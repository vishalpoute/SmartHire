"""Recruiter-owned jobs with versioned draft editing and guarded publication."""

from datetime import datetime
from threading import Lock
from typing import Annotated, Literal
from urllib.parse import quote
from uuid import uuid4

from fastapi import APIRouter, Depends, Path, Query, Request
from google.api_core.exceptions import Aborted, Conflict, FailedPrecondition, NotFound
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.accounts import Account, active_account
from app.auth import Identity
from app.companies import CompanyInput, CompanyProfile
from app.errors import ApiError
from app.profiles import ProfileInput, verified_identity


class JobDraftInput(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", str_strip_whitespace=True)
    title: str = Field(min_length=2, max_length=120)
    description: str = Field(default="", max_length=12000)
    location: str = Field(default="", max_length=80)
    work_mode: Literal["remote", "hybrid", "onsite"] = "onsite"
    employment_type: Literal["full_time", "part_time", "contract", "internship"] = "full_time"
    required_skills: list[str] = Field(default_factory=list, max_length=30)
    preferred_skills: list[str] = Field(default_factory=list, max_length=30)

    @field_validator("required_skills", "preferred_skills")
    @classmethod
    def clean_skills(cls, values):
        return ProfileInput.clean_skills(values)


class PublicJob(JobDraftInput):
    """Explicit allowlist: owner identifiers and private lifecycle metadata stay private."""

    id: str
    company_name: str
    published_at: datetime


class PublicJobPage(BaseModel):
    items: list[PublicJob]
    next_cursor: str | None = None


class JobDraftUpdate(JobDraftInput):
    expected_version: int = Field(ge=1, le=2147483647)


class JobDraft(JobDraftInput):
    id: str
    recruiter_uid: str
    company_owner_uid: str
    status: Literal["draft", "published", "closed", "suspended"]
    version: int = Field(ge=1)
    created_at: datetime
    updated_at: datetime
    published_at: datetime | None = None
    company_name: str | None = None


class JobVersionInput(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    expected_version: int = Field(ge=1, le=2147483647)


class OwnedJobPage(BaseModel):
    items: list[JobDraft]
    next_cursor: str | None = None


class JobClosure(BaseModel):
    id: str
    status: Literal["closed"] = "closed"
    version: int


class JobPublication(BaseModel):
    id: str
    status: Literal["published"] = "published"
    version: int


def publication_changes(uid, job_id, expected_version, job_data, account_data, company_data):
    if not job_data or job_data.get("recruiter_uid") != uid:
        raise ApiError(404, "job_not_found", "Job is unavailable.")
    job = JobDraft(
        id=job_id,
        **{key: job_data[key] for key in JobDraft.model_fields if key != "id" and key in job_data},
    )
    if job.company_owner_uid != uid:
        raise ValueError("Company owner mismatch")
    account = Account(
        uid=uid,
        **{
            key: account_data[key]
            for key in ("role", "account_status", "recruiter_approved")
            if key in account_data
        },
    )
    if account.account_status != "active":
        raise ApiError(403, "account_suspended", "This account is suspended.")
    if account.role != "recruiter" or not account.recruiter_approved:
        raise ApiError(403, "recruiter_approval_required", "Recruiter approval is required.")
    if not company_data:
        raise ApiError(403, "company_approval_required", "An approved company is required.")
    company = CompanyProfile(
        owner_uid=uid,
        **{
            key: company_data[key]
            for key in (*CompanyInput.model_fields, "approval_status", "updated_at")
            if key in company_data
        },
    )
    if company.approval_status != "approved":
        raise ApiError(403, "company_approval_required", "An approved company is required.")
    if job.status != "draft" or job.version != expected_version:
        raise ApiError(409, "job_version_conflict", "Job changed. Reload before publishing.")
    overlaps = set(map(str.casefold, job.required_skills)) & set(
        map(str.casefold, job.preferred_skills)
    )
    if (
        len(job.description) < 20
        or not job.required_skills
        or overlaps
        or (job.work_mode != "remote" and not job.location)
    ):
        raise ApiError(
            422,
            "job_incomplete",
            "Complete the job description, skills and location before publishing.",
        )
    return {
        "status": "published",
        "version": job.version + 1,
        "company_name": company.name,
        "published_at": firestore.SERVER_TIMESTAMP,
        "updated_at": firestore.SERVER_TIMESTAMP,
    }


def closure_changes(uid, job_id, expected_version, job_data, account_data, company_data):
    # Closing removes availability, so revoked recruiter/company approval must not
    # prevent an active owner from withdrawing their own published vacancy.
    if not job_data or job_data.get("recruiter_uid") != uid:
        raise ApiError(404, "job_not_found", "Job is unavailable.")
    job = JobDraft(
        id=job_id,
        **{key: job_data[key] for key in JobDraft.model_fields if key != "id" and key in job_data},
    )
    if job.company_owner_uid != uid:
        raise ValueError("Company owner mismatch")
    account = Account(
        uid=uid,
        **{
            key: account_data[key]
            for key in ("role", "account_status", "recruiter_approved")
            if key in account_data
        },
    )
    if account.account_status != "active":
        raise ApiError(403, "account_suspended", "This account is suspended.")
    if job.status != "published" or job.version != expected_version:
        raise ApiError(409, "job_version_conflict", "Job changed. Reload before closing.")
    return {
        "status": "closed",
        "version": job.version + 1,
        "updated_at": firestore.SERVER_TIMESTAMP,
    }


class FirestoreJobStore:
    def __init__(self, settings):
        self.settings = settings
        self.client = None
        self.lock = Lock()

    def collection(self):
        if not self.settings.firebase_project_id:
            raise ValueError("Missing project")
        with self.lock:
            if self.client is None:
                self.client = firestore.Client(project=self.settings.firebase_project_id)
        return self.client.collection("jobs")

    def get_public(self, job_id):
        try:
            job_ref = self.collection().document(job_id)

            @firestore.transactional
            def read(transaction):
                snapshot = job_ref.get(transaction=transaction, timeout=10, retry=None)
                data = snapshot.to_dict() if snapshot.exists else None
                if not data or data.get("status") != "published":
                    return None
                job = JobDraft(
                    id=job_id,
                    **{
                        key: data[key]
                        for key in JobDraft.model_fields
                        if key != "id" and key in data
                    },
                )
                if job.recruiter_uid != job.company_owner_uid:
                    raise ValueError("Company owner mismatch")
                owner_key = quote(job.recruiter_uid, safe="")
                account = (
                    self.client.collection("users")
                    .document(owner_key)
                    .get(transaction=transaction, timeout=10, retry=None)
                )
                company = (
                    self.client.collection("company_profiles")
                    .document(owner_key)
                    .get(transaction=transaction, timeout=10, retry=None)
                )
                if not account.exists or not company.exists:
                    return None
                account_data, company_data = account.to_dict(), company.to_dict()
                owner = Account(
                    uid=job.recruiter_uid,
                    **{
                        key: account_data[key]
                        for key in ("role", "account_status", "recruiter_approved")
                        if key in account_data
                    },
                )
                if (
                    owner.account_status != "active"
                    or owner.role != "recruiter"
                    or not owner.recruiter_approved
                ):
                    return None
                reviewed_company = CompanyProfile(
                    owner_uid=job.recruiter_uid,
                    **{
                        key: company_data[key]
                        for key in (*CompanyInput.model_fields, "approval_status", "updated_at")
                        if key in company_data
                    },
                )
                if reviewed_company.approval_status != "approved":
                    return None
                if job.published_at is None or not job.company_name:
                    raise ValueError("Missing publication metadata")
                return PublicJob(
                    id=job_id,
                    company_name=job.company_name,
                    published_at=job.published_at,
                    **{key: getattr(job, key) for key in JobDraftInput.model_fields},
                )

            return read(self.client.transaction(max_attempts=1))
        except Exception:  # noqa: BLE001 - no private record details in public failures.
            raise ApiError(503, "jobs_unavailable", "Jobs are temporarily unavailable.") from None

    def list_public(self, page_size, cursor=None):
        try:
            collection = self.collection()
            query = collection.where(filter=FieldFilter("status", "==", "published")).order_by(
                "__name__"
            )
            if cursor is not None:
                query = query.start_after({"__name__": collection.document(cursor)})
            candidates = list(query.limit(page_size + 1).get(timeout=10, retry=None))
            scanned = candidates[:page_size]
            # Recheck visibility, including current moderation, for each bounded candidate.
            # Sparse/empty pages can have a continuation; never scan an unbounded set
            # to fill a page after approval revocations.
            items = []
            for candidate in scanned:
                job = self.get_public(candidate.id)
                if job is not None:
                    items.append(job)
            return PublicJobPage(
                items=items,
                next_cursor=scanned[-1].id if len(candidates) > page_size else None,
            )
        except ApiError:
            raise
        except Exception:  # noqa: BLE001 - query/index diagnostics stay private.
            raise ApiError(503, "jobs_unavailable", "Jobs are temporarily unavailable.") from None

    def create(self, uid, draft):
        try:
            document = self.collection().document(uuid4().hex)
            fields = draft.model_dump()
            result = document.create(
                {
                    **fields,
                    "recruiter_uid": uid,
                    "company_owner_uid": uid,
                    "status": "draft",
                    "version": 1,
                    "created_at": firestore.SERVER_TIMESTAMP,
                    "updated_at": firestore.SERVER_TIMESTAMP,
                },
                timeout=10,
                retry=None,
            )
            return JobDraft(
                id=document.id,
                status="draft",
                version=1,
                recruiter_uid=uid,
                company_owner_uid=uid,
                created_at=result.update_time,
                updated_at=result.update_time,
                **fields,
            )
        except Exception:  # noqa: BLE001 - no input or datastore diagnostics in errors.
            raise ApiError(
                503, "jobs_unavailable", "Job drafts are temporarily unavailable."
            ) from None

    def list_owned(self, uid, page_size=10, cursor=None):
        try:
            if not 1 <= page_size <= 20:
                raise ValueError("Invalid page size")
            if cursor is not None and (
                len(cursor) != 32 or any(char not in "0123456789abcdef" for char in cursor)
            ):
                raise ValueError("Invalid cursor")
            collection = self.collection()
            account_ref = self.client.collection("users").document(quote(uid, safe=""))
            query = collection.where(filter=FieldFilter("recruiter_uid", "==", uid)).order_by(
                "__name__"
            )
            if cursor is not None:
                query = query.start_after({"__name__": collection.document(cursor)})

            @firestore.transactional
            def read(transaction):
                account = account_ref.get(transaction=transaction, timeout=10, retry=None)
                if (
                    not account.exists
                    or account.to_dict().get("account_status", "active") != "active"
                ):
                    raise ApiError(403, "account_inactive", "An active account is required.")
                candidates = list(
                    query.limit(page_size + 1).get(transaction=transaction, timeout=10, retry=None)
                )
                items = []
                for document in candidates[:page_size]:
                    if len(document.id) != 32 or any(
                        char not in "0123456789abcdef" for char in document.id
                    ):
                        raise ValueError("Invalid stored job ID")
                    data = document.to_dict()
                    if data.get("recruiter_uid") != uid or data.get("company_owner_uid") != uid:
                        raise ValueError("Job ownership mismatch")
                    items.append(
                        JobDraft(
                            id=document.id,
                            **{
                                key: data[key]
                                for key in JobDraft.model_fields
                                if key != "id" and key in data
                            },
                        )
                    )
                return OwnedJobPage(
                    items=items,
                    next_cursor=items[-1].id if len(candidates) > page_size else None,
                )

            return read(self.client.transaction(max_attempts=1))
        except ApiError:
            raise
        except Exception:  # noqa: BLE001 - hide private job and datastore diagnostics.
            raise ApiError(
                503, "jobs_unavailable", "Your jobs are temporarily unavailable."
            ) from None

    def get_owned(self, uid, job_id):
        try:
            snapshot = self.collection().document(job_id).get(timeout=10, retry=None)
            if not snapshot.exists:
                return None
            data = snapshot.to_dict()
            if data.get("recruiter_uid") != uid:
                return None
            if data.get("company_owner_uid") != uid:
                raise ValueError("Company owner mismatch")
            # Return a fixed contract; unrelated server metadata must stay private.
            fields = {
                key: data[key] for key in JobDraft.model_fields if key != "id" and key in data
            }
            return JobDraft(id=job_id, **fields)
        except Exception:  # noqa: BLE001 - safe failure without leaking document contents.
            raise ApiError(
                503, "jobs_unavailable", "Job drafts are temporarily unavailable."
            ) from None

    def update_owned(self, uid, job_id, draft):
        try:
            document = self.collection().document(job_id)
            snapshot = document.get(timeout=10, retry=None)
            data = snapshot.to_dict() if snapshot.exists else None
            if data is None or data.get("recruiter_uid") != uid:
                raise ApiError(404, "job_not_found", "Job draft is unavailable.")
            if data.get("status") != "draft":
                raise ApiError(409, "job_not_editable", "Only draft jobs can be edited here.")
            if data.get("company_owner_uid") != uid:
                raise ValueError("Company owner mismatch")
            current = JobDraft(
                id=job_id,
                **{key: data[key] for key in JobDraft.model_fields if key != "id" and key in data},
            )
            if current.version != draft.expected_version:
                raise ApiError(409, "job_version_conflict", "Job changed. Reload before editing.")
            fields = draft.model_dump(exclude={"expected_version"})
            version = current.version + 1
            # The version check alone is insufficient: another writer can race this read.
            # Firestore must atomically assert that the read snapshot is still current.
            if snapshot.update_time is None:
                raise ValueError("Missing snapshot precondition")
            result = document.update(
                {**fields, "version": version, "updated_at": firestore.SERVER_TIMESTAMP},
                option=firestore.LastUpdateOption(snapshot.update_time),
                timeout=10,
                retry=None,
            )
            return JobDraft(
                id=job_id,
                recruiter_uid=uid,
                company_owner_uid=uid,
                status="draft",
                version=version,
                created_at=current.created_at,
                updated_at=result.update_time,
                **fields,
            )
        except ApiError:
            raise
        except (Conflict, FailedPrecondition, NotFound):
            raise ApiError(
                409, "job_version_conflict", "Job changed. Reload before editing."
            ) from None
        except Exception:  # noqa: BLE001 - hide submitted data and SDK diagnostics.
            raise ApiError(
                503, "jobs_unavailable", "Job drafts are temporarily unavailable."
            ) from None

    def publish_owned(self, uid, job_id, expected_version):
        return self._transition_owned(uid, job_id, expected_version, closing=False)

    def close_owned(self, uid, job_id, expected_version):
        return self._transition_owned(uid, job_id, expected_version, closing=True)

    def _transition_owned(self, uid, job_id, expected_version, *, closing):
        try:
            job_ref = self.collection().document(job_id)
            owner_key = quote(uid, safe="")
            account_ref = self.client.collection("users").document(owner_key)
            company_ref = self.client.collection("company_profiles").document(owner_key)
            audit_ref = self.client.collection("audit_events").document(uuid4().hex)

            @firestore.transactional
            def publish(transaction):
                # All authorization and job reads share the transaction snapshot.
                job = job_ref.get(transaction=transaction, timeout=10, retry=None)
                account = account_ref.get(transaction=transaction, timeout=10, retry=None)
                company = (
                    None
                    if closing
                    else company_ref.get(transaction=transaction, timeout=10, retry=None)
                )
                policy = closure_changes if closing else publication_changes
                changes = policy(
                    uid,
                    job_id,
                    expected_version,
                    job.to_dict() if job.exists else None,
                    account.to_dict() if account.exists else {},
                    company.to_dict() if company is not None and company.exists else None,
                )
                transaction.update(job_ref, changes)
                transaction.create(
                    audit_ref,
                    {
                        "action": "job.closed" if closing else "job.published",
                        "actor_uid": uid,
                        "job_id": job_id,
                        "version": changes["version"],
                        "created_at": firestore.SERVER_TIMESTAMP,
                    },
                )
                receipt = JobClosure if closing else JobPublication
                return receipt(id=job_id, version=changes["version"])

            # No automatic transaction re-execution: clients must reload stale versions.
            return publish(self.client.transaction(max_attempts=1))
        except ApiError:
            raise
        except (Aborted, Conflict, FailedPrecondition, NotFound):
            raise ApiError(
                409, "job_version_conflict", "Job changed. Reload before retrying."
            ) from None
        except ValueError as error:
            if isinstance(error.__cause__, Aborted):
                raise ApiError(
                    409, "job_version_conflict", "Job changed. Reload before retrying."
                ) from None
            raise ApiError(
                503, "jobs_unavailable", "Job transition is temporarily unavailable."
            ) from None
        except Exception:  # noqa: BLE001 - fail closed without record or credential details.
            raise ApiError(
                503, "jobs_unavailable", "Job transition is temporarily unavailable."
            ) from None


def approved_recruiter(request: Request, identity: Annotated[Identity, Depends(verified_identity)]):
    account = active_account(request, identity)
    if account.role != "recruiter" or not account.recruiter_approved:
        raise ApiError(403, "recruiter_approval_required", "Recruiter approval is required.")
    company = request.app.state.company_store.get(identity.uid)
    if (
        company is None
        or company.owner_uid != identity.uid
        or company.approval_status != "approved"
    ):
        raise ApiError(403, "company_approval_required", "An approved company profile is required.")
    return identity


router = APIRouter(prefix="/api/v1/jobs", tags=["jobs"])
JobId = Annotated[str, Path(pattern=r"^[a-f0-9]{32}$")]


@router.get("", response_model=OwnedJobPage)
def list_owned_jobs(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    page_size: Annotated[int, Query(ge=1, le=20)] = 10,
    cursor: Annotated[str | None, Query(pattern=r"^[a-f0-9]{32}$", max_length=32)] = None,
):
    return request.app.state.job_store.list_owned(identity.uid, page_size, cursor)


@router.post("", response_model=JobDraft, status_code=201)
def create_draft(
    request: Request,
    identity: Annotated[Identity, Depends(approved_recruiter)],
    draft: JobDraftInput,
):
    return request.app.state.job_store.create(identity.uid, draft)


@router.get("/{job_id}", response_model=JobDraft)
def read_owned_draft(
    request: Request, job_id: JobId, identity: Annotated[Identity, Depends(verified_identity)]
):
    job = request.app.state.job_store.get_owned(identity.uid, job_id)
    if job is None:
        raise ApiError(404, "job_not_found", "Job draft is unavailable.")
    return job


@router.put("/{job_id}", response_model=JobDraft)
def update_owned_draft(
    request: Request,
    job_id: JobId,
    identity: Annotated[Identity, Depends(approved_recruiter)],
    draft: JobDraftUpdate,
):
    return request.app.state.job_store.update_owned(identity.uid, job_id, draft)


@router.post("/{job_id}/publish", response_model=JobPublication)
def publish_owned_job(
    request: Request,
    job_id: JobId,
    identity: Annotated[Identity, Depends(approved_recruiter)],
    command: JobVersionInput,
):
    return request.app.state.job_store.publish_owned(identity.uid, job_id, command.expected_version)


@router.post("/{job_id}/close", response_model=JobClosure)
def close_owned_job(
    request: Request,
    job_id: JobId,
    identity: Annotated[Identity, Depends(verified_identity)],
    command: JobVersionInput,
):
    return request.app.state.job_store.close_owned(identity.uid, job_id, command.expected_version)


public_router = APIRouter(prefix="/api/v1/public/jobs", tags=["public jobs"])


@public_router.get("/{job_id}", response_model=PublicJob)
def read_public_job(request: Request, job_id: JobId):
    # One shared process budget bounds anonymous datastore work without trusting
    # caller-controlled IP headers or retaining anonymous identifiers.
    try:
        request.app.state.public_job_limiter.check("public-job-details")
    except ApiError as error:
        raise ApiError(
            error.status,
            "jobs_busy",
            "Jobs are busy. Please retry shortly.",
            retry_after=error.retry_after,
        ) from None
    job = request.app.state.job_store.get_public(job_id)
    if job is None:
        raise ApiError(404, "job_not_found", "Job is unavailable.")
    return job


@public_router.get("", response_model=PublicJobPage)
def list_public_jobs(
    request: Request,
    page_size: Annotated[int, Query(ge=1, le=10)] = 10,
    cursor: Annotated[str | None, Query(pattern=r"^[a-f0-9]{32}$")] = None,
):
    try:
        request.app.state.public_job_list_limiter.check("public-job-list")
    except ApiError as error:
        raise ApiError(
            error.status,
            "jobs_busy",
            "Jobs are busy. Please retry shortly.",
            retry_after=error.retry_after,
        ) from None
    return request.app.state.job_store.list_public(page_size, cursor)
