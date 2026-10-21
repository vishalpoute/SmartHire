"""Server-assigned administrators review companies without trusting role claims."""

from datetime import datetime
from threading import Lock
from typing import Annotated, Literal
from urllib.parse import quote, unquote
from uuid import uuid4

from fastapi import APIRouter, Depends, Query, Request
from google.api_core.exceptions import Aborted, Conflict, FailedPrecondition, NotFound
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.accounts import Account, active_account
from app.auth import Identity
from app.companies import CompanyInput, CompanyProfile
from app.errors import ApiError
from app.profiles import verified_identity


class RecruiterReview(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    target_uid: str = Field(min_length=1, max_length=128)
    decision: Literal["approved", "rejected"]
    expected_company_updated_at: str = Field(min_length=20, max_length=40)
    reason: str = Field(min_length=3, max_length=500)

    @field_validator("target_uid", "reason")
    @classmethod
    def no_control_characters(cls, value):
        if any(ord(char) < 32 or ord(char) == 127 for char in value):
            raise ValueError("Control characters are not allowed")
        if not value.strip():
            raise ValueError("Value must not be blank")
        return value

    @field_validator("expected_company_updated_at")
    @classmethod
    def aware_timestamp(cls, value):
        timestamp = datetime.fromisoformat(value)
        if timestamp.tzinfo is None:
            raise ValueError("Timezone is required")
        return value


class RecruiterReviewReceipt(BaseModel):
    target_uid: str
    decision: Literal["approved", "rejected"]


class RecruiterReviewPage(BaseModel):
    items: list[CompanyProfile]
    next_cursor: str | None = None


def account_from(uid, data):
    return Account(
        uid=uid,
        **{
            key: data[key]
            for key in ("role", "account_status", "recruiter_approved")
            if key in data
        },
    )


def review_policy(actor_uid, command, actor_data, target_data, company_data):
    actor = account_from(actor_uid, actor_data)
    if actor.role != "admin" or actor.account_status != "active":
        raise ApiError(403, "admin_required", "Administrator access is required.")
    if actor_uid == command.target_uid:
        raise ApiError(403, "self_review_forbidden", "You cannot review your own request.")
    target = account_from(command.target_uid, target_data)
    if target.role == "admin" or target.account_status != "active":
        raise ApiError(403, "review_forbidden", "This account cannot be reviewed here.")
    if not company_data:
        raise ApiError(404, "company_not_found", "Company request is unavailable.")
    company = CompanyProfile(
        owner_uid=command.target_uid,
        **{
            key: company_data[key]
            for key in (*CompanyInput.model_fields, "approval_status", "updated_at")
            if key in company_data
        },
    )
    if company.approval_status != "pending" or company.updated_at != datetime.fromisoformat(
        command.expected_company_updated_at
    ):
        raise ApiError(409, "review_conflict", "Company changed. Reload before reviewing.")
    return {
        "recruiter_approved": command.decision == "approved",
        **({"role": "recruiter"} if command.decision == "approved" else {}),
    }


class FirestoreRecruiterReviewStore:
    def __init__(self, settings):
        self.settings = settings
        self.client = None
        self.lock = Lock()

    def pending(self, actor_uid, page_size, cursor=None):
        try:
            if not self.settings.firebase_project_id:
                raise ValueError("Missing project")
            with self.lock:
                if self.client is None:
                    self.client = firestore.Client(project=self.settings.firebase_project_id)
            actor_ref = self.client.collection("users").document(quote(actor_uid, safe=""))
            collection = self.client.collection("company_profiles")
            query = collection.where(
                filter=FieldFilter("approval_status", "==", "pending")
            ).order_by("__name__")
            if cursor is not None:
                query = query.start_after({"__name__": collection.document(quote(cursor, safe=""))})

            @firestore.transactional
            def read(transaction):
                snapshot = actor_ref.get(transaction=transaction, timeout=10, retry=None)
                actor = account_from(actor_uid, snapshot.to_dict() if snapshot.exists else {})
                if actor.role != "admin" or actor.account_status != "active":
                    raise ApiError(403, "admin_required", "Administrator access is required.")
                candidates = list(
                    query.limit(page_size + 1).get(transaction=transaction, timeout=10, retry=None)
                )
                items = []
                for document in candidates[:page_size]:
                    owner_uid = unquote(document.id, errors="strict")
                    if (
                        not owner_uid
                        or len(owner_uid) > 128
                        or quote(owner_uid, safe="") != document.id
                    ):
                        raise ValueError("Invalid owner document key")
                    data = document.to_dict()
                    company = CompanyProfile(
                        owner_uid=owner_uid,
                        **{
                            key: data[key]
                            for key in (*CompanyInput.model_fields, "approval_status", "updated_at")
                            if key in data
                        },
                    )
                    if company.approval_status != "pending":
                        raise ValueError("Unexpected review state")
                    items.append(company)
                return RecruiterReviewPage(
                    items=items,
                    next_cursor=items[-1].owner_uid if len(candidates) > page_size else None,
                )

            return read(self.client.transaction(max_attempts=1))
        except ApiError:
            raise
        except Exception:  # noqa: BLE001 - hide company and query diagnostics.
            raise ApiError(
                503, "review_unavailable", "Review queue is temporarily unavailable."
            ) from None

    def review(self, actor_uid, command):
        try:
            if not self.settings.firebase_project_id:
                raise ValueError("Missing project")
            with self.lock:
                if self.client is None:
                    self.client = firestore.Client(project=self.settings.firebase_project_id)
            actor_ref = self.client.collection("users").document(quote(actor_uid, safe=""))
            target_ref = self.client.collection("users").document(
                quote(command.target_uid, safe="")
            )
            company_ref = self.client.collection("company_profiles").document(
                quote(command.target_uid, safe="")
            )
            audit_ref = self.client.collection("audit_events").document(uuid4().hex)

            @firestore.transactional
            def apply(transaction):
                actor = actor_ref.get(transaction=transaction, timeout=10, retry=None)
                target = target_ref.get(transaction=transaction, timeout=10, retry=None)
                company = company_ref.get(transaction=transaction, timeout=10, retry=None)
                changes = review_policy(
                    actor_uid,
                    command,
                    actor.to_dict() if actor.exists else {},
                    target.to_dict() if target.exists else {},
                    company.to_dict() if company.exists else None,
                )
                transaction.set(
                    target_ref, {**changes, "updated_at": firestore.SERVER_TIMESTAMP}, merge=True
                )
                transaction.update(
                    company_ref,
                    {"approval_status": command.decision, "updated_at": firestore.SERVER_TIMESTAMP},
                )
                transaction.create(
                    audit_ref,
                    {
                        "action": "recruiter." + command.decision,
                        "actor_uid": actor_uid,
                        "target_uid": command.target_uid,
                        "reason": command.reason,
                        "created_at": firestore.SERVER_TIMESTAMP,
                    },
                )
                return RecruiterReviewReceipt(
                    target_uid=command.target_uid, decision=command.decision
                )

            return apply(self.client.transaction(max_attempts=1))
        except ApiError:
            raise
        except (Aborted, Conflict, FailedPrecondition, NotFound):
            raise ApiError(
                409, "review_conflict", "Request changed. Reload before reviewing."
            ) from None
        except ValueError as error:
            if isinstance(error.__cause__, Aborted):
                raise ApiError(
                    409, "review_conflict", "Request changed. Reload before reviewing."
                ) from None
            raise ApiError(
                503, "review_unavailable", "Review is temporarily unavailable."
            ) from None
        except Exception:  # noqa: BLE001 - no identity, review notes or SDK details in errors.
            raise ApiError(
                503, "review_unavailable", "Review is temporarily unavailable."
            ) from None


def administrator(request: Request, identity: Annotated[Identity, Depends(verified_identity)]):
    if active_account(request, identity).role != "admin":
        raise ApiError(403, "admin_required", "Administrator access is required.")
    return identity


router = APIRouter(prefix="/api/v1/admin/recruiter-reviews", tags=["administrator"])


@router.post("", response_model=RecruiterReviewReceipt)
def review_recruiter(
    request: Request,
    identity: Annotated[Identity, Depends(administrator)],
    command: RecruiterReview,
):
    return request.app.state.recruiter_review_store.review(identity.uid, command)


@router.get("", response_model=RecruiterReviewPage)
def pending_recruiters(
    request: Request,
    identity: Annotated[Identity, Depends(administrator)],
    page_size: Annotated[int, Query(ge=1, le=20)] = 10,
    cursor: Annotated[
        str | None, Query(min_length=1, max_length=128, pattern=r"^[^\x00-\x1f\x7f]+$")
    ] = None,
):
    return request.app.state.recruiter_review_store.pending(identity.uid, page_size, cursor)
