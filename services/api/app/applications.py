"""Duplicate-safe applications with immutable evidence and party-scoped transitions."""

import hashlib
from datetime import UTC, datetime
from typing import Annotated, Literal
from urllib.parse import quote
from uuid import uuid4

from fastapi import APIRouter, Depends, Path, Query, Request
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.auth import Identity
from app.errors import ApiError
from app.jobs import JobDraftInput
from app.matching import ID_PATTERN, FirestoreMatchStore, MatchInput, MatchResult, calculate_match
from app.profiles import ProfileInput, verified_identity
from app.resume_store import guarded


class ApplyInput(MatchInput):
    expected_job_version: int = Field(ge=1, le=2147483647)


class ApplicationChange(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", str_strip_whitespace=True)
    expected_revision: int = Field(ge=1, le=2147483647)
    status: Literal["shortlisted", "rejected", "hired", "withdrawn"]
    reason: str = Field(default="", max_length=500)

    @field_validator("reason")
    @classmethod
    def valid_reason(cls, value):
        if any(ord(char) < 32 and char not in "\n\t" for char in value):
            raise ValueError("Control characters are not allowed")
        return value


class ApplicationJob(JobDraftInput):
    id: str
    version: int
    company_name: str


class CandidateSnapshot(ProfileInput):
    """Only explicitly submitted profile/skills; never email, raw text or a signed URL."""


class ApplicationRecord(BaseModel):
    id: str
    job: ApplicationJob
    candidate: CandidateSnapshot
    match: MatchResult
    revision: int
    status: Literal["submitted", "shortlisted", "rejected", "hired", "withdrawn"]
    reason: str = ""
    submitted_at: datetime
    updated_at: datetime


class ApplicationPage(BaseModel):
    items: list[ApplicationRecord]
    next_cursor: str | None = None


def application_record(application_id, data):
    return ApplicationRecord(
        id=application_id,
        **{key: data[key] for key in ApplicationRecord.model_fields if key != "id" and key in data},
    )


class FirestoreApplicationStore(FirestoreMatchStore):
    def application_collection(self):
        self.collection()
        return self.client.collection("applications")

    def party(self, transaction, uid, data):
        actor = self.account_record(transaction, uid)
        if data.get("seeker_uid") == uid and actor.role == "seeker":
            return "seeker"
        unavailable = ApiError(404, "application_unavailable", "This application is unavailable.")
        if data.get("recruiter_uid") != uid or actor.role != "recruiter":
            raise unavailable
        # Company edits/revoked approval also revoke access to candidate snapshots.
        company = (
            self.client.collection("company_profiles")
            .document(quote(uid, safe=""))
            .get(transaction=transaction, timeout=10, retry=None)
        )
        job = (
            self.client.collection("jobs")
            .document(data["job"]["id"])
            .get(transaction=transaction, timeout=10, retry=None)
        )
        if not actor.recruiter_approved or not company.exists or not job.exists:
            raise unavailable
        if (
            company.to_dict().get("approval_status") != "approved"
            or job.to_dict().get("recruiter_uid") != uid
            or job.to_dict().get("company_owner_uid") != uid
        ):
            raise unavailable
        return "recruiter"

    @guarded
    def submit(self, uid, job_id, command):
        application_id = hashlib.sha256((uid + "\0" + job_id).encode()).hexdigest()[:32]
        ref = self.application_collection().document(application_id)

        @firestore.transactional
        def write(transaction):
            existing = ref.get(transaction=transaction, timeout=10, retry=None)
            if existing.exists:
                data = existing.to_dict()
                self.party(transaction, uid, data)
                # Retrying an interrupted identical request never creates another application.
                match = application_record(application_id, data).match
                if (
                    match.resume_id == command.resume_id
                    and match.resume_revision == command.expected_resume_revision
                    and match.job_version == command.expected_job_version
                ):
                    return application_record(application_id, data)
                raise ApiError(409, "already_applied", "You already applied to this job.")
            job, resume = self.inputs(transaction, uid, job_id, command)
            match = calculate_match(job, resume)
            if job.recruiter_uid == uid:
                raise ApiError(403, "own_job", "You cannot apply to your own job.")
            profile = (
                self.client.collection("private_profiles")
                .document(quote(uid, safe=""))
                .get(transaction=transaction, timeout=10, retry=None)
            )
            if not profile.exists:
                raise ApiError(409, "profile_required", "Complete your profile before applying.")
            data = profile.to_dict()
            candidate = CandidateSnapshot(
                **{
                    key: data[key]
                    for key in ProfileInput.model_fields
                    if key in data and key != "skills"
                },
                skills=resume.confirmed_skills,
            )
            now = datetime.now(UTC)
            receipt = ApplicationRecord(
                id=application_id,
                job=ApplicationJob(
                    id=job.id,
                    version=job.version,
                    company_name=job.company_name,
                    **{key: getattr(job, key) for key in JobDraftInput.model_fields},
                ),
                candidate=candidate,
                match=match,
                revision=1,
                status="submitted",
                submitted_at=now,
                updated_at=now,
            )
            transaction.create(
                ref,
                {
                    **receipt.model_dump(exclude={"id"}),
                    "seeker_uid": uid,
                    "recruiter_uid": job.recruiter_uid,
                },
            )
            self.audit(transaction, uid, application_id, "submitted", "")
            return receipt

        return write(self.client.transaction(max_attempts=1))

    def audit(self, transaction, uid, application_id, status, reason):
        transaction.create(
            self.client.collection("audit_events").document(uuid4().hex),
            {
                "actor_uid": uid,
                "action": "application." + status,
                "target_id": application_id,
                "reason": reason,
                "created_at": datetime.now(UTC),
            },
        )

    @guarded
    def get_application(self, uid, application_id):
        ref = self.application_collection().document(application_id)

        @firestore.transactional
        def read(transaction):
            record = ref.get(transaction=transaction, timeout=10, retry=None)
            if not record.exists:
                raise ApiError(404, "application_unavailable", "This application is unavailable.")
            data = record.to_dict()
            self.party(transaction, uid, data)
            return application_record(application_id, data)

        return read(self.client.transaction(max_attempts=1))

    @guarded
    def list_applications(self, uid, scope, cursor):
        collection = self.application_collection()

        @firestore.transactional
        def read(transaction):
            actor = self.account_record(transaction, uid)
            if actor.role != scope:
                raise ApiError(403, "role_required", "This application view is unavailable.")
            query = collection.where(
                filter=FieldFilter(
                    "seeker_uid" if scope == "seeker" else "recruiter_uid", "==", uid
                )
            ).order_by("__name__")
            if cursor:
                query = query.start_after({"__name__": collection.document(cursor)})
            rows = query.limit(11).get(transaction=transaction, timeout=10, retry=None)
            items = []
            for row in rows[:10]:
                data = row.to_dict()
                self.party(transaction, uid, data)
                items.append(application_record(row.id, data))
            return ApplicationPage(items=items, next_cursor=rows[9].id if len(rows) > 10 else None)

        return read(self.client.transaction(max_attempts=1))

    @guarded
    def transition(self, uid, application_id, command):
        ref = self.application_collection().document(application_id)

        @firestore.transactional
        def write(transaction):
            record = ref.get(transaction=transaction, timeout=10, retry=None)
            if not record.exists:
                raise ApiError(404, "application_unavailable", "This application is unavailable.")
            data = record.to_dict()
            party = self.party(transaction, uid, data)
            current = application_record(application_id, data)
            if current.revision != command.expected_revision:
                raise ApiError(
                    409, "application_changed", "Application changed. Refresh before retrying."
                )
            allowed = {
                "submitted": {"shortlisted", "rejected"},
                "shortlisted": {"hired", "rejected"},
            }
            permitted = (
                (current.status in ("submitted", "shortlisted") and command.status == "withdrawn")
                if party == "seeker"
                else command.status in allowed.get(current.status, set())
            )
            if not permitted:
                raise ApiError(409, "invalid_transition", "This application action is unavailable.")
            if command.status == "rejected" and not command.reason:
                raise ApiError(422, "reason_required", "A reason is required for rejection.")
            changes = {
                "status": command.status,
                "reason": command.reason,
                "revision": current.revision + 1,
                "updated_at": datetime.now(UTC),
            }
            transaction.update(ref, changes)
            self.audit(transaction, uid, application_id, command.status, command.reason)
            return application_record(application_id, {**data, **changes})

        return write(self.client.transaction(max_attempts=1))


router = APIRouter(prefix="/api/v1", tags=["applications"])


@router.post("/jobs/{job_id}/applications", response_model=ApplicationRecord, status_code=201)
def submit_application(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    job_id: Annotated[str, Path(pattern=ID_PATTERN)],
    command: ApplyInput,
):
    return request.app.state.application_store.submit(identity.uid, job_id, command)


@router.get("/applications", response_model=ApplicationPage)
def list_applications(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    scope: Literal["seeker", "recruiter"] = "seeker",
    cursor: Annotated[str | None, Query(pattern=ID_PATTERN)] = None,
):
    return request.app.state.application_store.list_applications(identity.uid, scope, cursor)


@router.get("/applications/{application_id}", response_model=ApplicationRecord)
def get_application(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    application_id: Annotated[str, Path(pattern=ID_PATTERN)],
):
    return request.app.state.application_store.get_application(identity.uid, application_id)


@router.post("/applications/{application_id}/status", response_model=ApplicationRecord)
def change_application(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    application_id: Annotated[str, Path(pattern=ID_PATTERN)],
    command: ApplicationChange,
):
    return request.app.state.application_store.transition(identity.uid, application_id, command)
