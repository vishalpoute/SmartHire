"""Server-authorized listing moderation and bounded audit inspection."""

from datetime import UTC, datetime
from typing import Annotated, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, Path, Query, Request
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.auth import Identity
from app.errors import ApiError
from app.jobs import JobDraft, OwnedJobPage
from app.matching import ID_PATTERN, FirestoreMatchStore
from app.profiles import verified_identity
from app.resume_store import guarded


class ModerationCommand(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", str_strip_whitespace=True)
    expected_version: int = Field(ge=1, le=2147483647)
    action: Literal["suspend", "restore_draft"]
    reason: str = Field(min_length=3, max_length=500)

    @field_validator("reason")
    @classmethod
    def valid_reason(cls, value):
        if any(ord(char) < 32 and char not in "\n\t" for char in value):
            raise ValueError("Control characters are not allowed")
        return value


class ModerationReceipt(BaseModel):
    id: str
    status: Literal["suspended", "draft"]
    version: int


class AuditEntry(BaseModel):
    id: str
    action: str = Field(max_length=80)
    actor_uid: str = Field(max_length=128)
    target_uid: str | None = Field(default=None, max_length=128)
    target_id: str | None = Field(default=None, max_length=128)
    job_id: str | None = Field(default=None, max_length=32)
    version: int | None = None
    reason: str = Field(default="", max_length=500)
    created_at: datetime


class AuditPage(BaseModel):
    items: list[AuditEntry]
    next_cursor: str | None = None


class FirestoreModerationStore(FirestoreMatchStore):
    def administrator(self, transaction, uid):
        if self.account_record(transaction, uid).role != "admin":
            raise ApiError(403, "admin_required", "Administrator access is required.")

    @guarded
    def jobs(self, uid, status, cursor):
        self.collection()
        collection = self.client.collection("jobs")

        @firestore.transactional
        def read(transaction):
            self.administrator(transaction, uid)
            query = collection.where(filter=FieldFilter("status", "==", status)).order_by(
                "__name__"
            )
            if cursor:
                query = query.start_after({"__name__": collection.document(cursor)})
            rows = query.limit(11).get(transaction=transaction, timeout=10, retry=None)
            return OwnedJobPage(
                items=[
                    JobDraft(
                        id=row.id,
                        **{
                            key: row.to_dict()[key]
                            for key in JobDraft.model_fields
                            if key != "id" and key in row.to_dict()
                        },
                    )
                    for row in rows[:10]
                ],
                next_cursor=rows[9].id if len(rows) > 10 else None,
            )

        return read(self.client.transaction(max_attempts=1))

    @guarded
    def moderate(self, uid, job_id, command):
        self.collection()
        ref = self.client.collection("jobs").document(job_id)

        @firestore.transactional
        def write(transaction):
            self.administrator(transaction, uid)
            record = ref.get(transaction=transaction, timeout=10, retry=None)
            if not record.exists:
                raise ApiError(404, "job_unavailable", "This job is unavailable.")
            data = record.to_dict()
            expected = "published" if command.action == "suspend" else "suspended"
            if data.get("version") != command.expected_version or data.get("status") != expected:
                raise ApiError(409, "job_changed", "Job changed. Refresh before retrying.")
            status = "suspended" if command.action == "suspend" else "draft"
            changes = {
                "status": status,
                "version": data["version"] + 1,
                "updated_at": datetime.now(UTC),
            }
            transaction.update(ref, changes)
            transaction.create(
                self.client.collection("audit_events").document(uuid4().hex),
                {
                    "action": "job." + command.action,
                    "actor_uid": uid,
                    "job_id": job_id,
                    "reason": command.reason,
                    "version": changes["version"],
                    "created_at": datetime.now(UTC),
                },
            )
            return ModerationReceipt(id=job_id, status=status, version=changes["version"])

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def audits(self, uid, cursor):
        self.collection()
        collection = self.client.collection("audit_events")

        @firestore.transactional
        def read(transaction):
            self.administrator(transaction, uid)
            query = collection.order_by("__name__")
            if cursor:
                query = query.start_after({"__name__": collection.document(cursor)})
            rows = query.limit(21).get(transaction=transaction, timeout=10, retry=None)
            return AuditPage(
                items=[
                    AuditEntry(
                        id=row.id,
                        **{
                            key: row.to_dict()[key]
                            for key in AuditEntry.model_fields
                            if key != "id" and key in row.to_dict()
                        },
                    )
                    for row in rows[:20]
                ],
                next_cursor=rows[19].id if len(rows) > 20 else None,
            )

        return read(self.client.transaction(max_attempts=1))


router = APIRouter(prefix="/api/v1/admin", tags=["moderation"])


@router.get("/jobs", response_model=OwnedJobPage)
def moderation_jobs(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    status: Literal["published", "suspended"] = "published",
    cursor: Annotated[str | None, Query(pattern=ID_PATTERN)] = None,
):
    return request.app.state.moderation_store.jobs(identity.uid, status, cursor)


@router.post("/jobs/{job_id}/moderation", response_model=ModerationReceipt)
def moderate_job(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    job_id: Annotated[str, Path(pattern=ID_PATTERN)],
    command: ModerationCommand,
):
    return request.app.state.moderation_store.moderate(identity.uid, job_id, command)


@router.get("/audit-events", response_model=AuditPage)
def audit_events(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    cursor: Annotated[str | None, Query(pattern=ID_PATTERN)] = None,
):
    return request.app.state.moderation_store.audits(identity.uid, cursor)
