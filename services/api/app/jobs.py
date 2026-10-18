"""Private recruiter-owned job drafts; publishing is a separate future transition."""

from datetime import datetime
from threading import Lock
from typing import Annotated, Literal
from uuid import uuid4

from fastapi import APIRouter, Depends, Path, Request
from google.api_core.exceptions import Conflict, FailedPrecondition, NotFound
from google.cloud import firestore
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.accounts import active_account
from app.auth import Identity
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


class JobDraftUpdate(JobDraftInput):
    expected_version: int = Field(ge=1, le=2147483647)


class JobDraft(JobDraftInput):
    id: str
    recruiter_uid: str
    company_owner_uid: str
    status: Literal["draft"]
    version: int = Field(ge=1)
    created_at: datetime
    updated_at: datetime


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
