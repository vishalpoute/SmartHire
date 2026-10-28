"""Reproducible skill coverage; never a hiring decision or inferred qualification."""

import unicodedata
from typing import Annotated, Literal
from urllib.parse import quote

from fastapi import APIRouter, Depends, Path, Request
from google.cloud import firestore
from pydantic import BaseModel, ConfigDict, Field

from app.accounts import Account
from app.auth import Identity
from app.companies import CompanyInput, CompanyProfile
from app.errors import ApiError
from app.jobs import JobDraft
from app.profiles import verified_identity
from app.resume_store import FirestoreResumeStore, guarded, snapshot
from app.skill_taxonomy import ALIASES, TAXONOMY_VERSION

ALGORITHM_VERSION = "skill-coverage-v1"
ID_PATTERN = r"^[0-9a-f]{32}$"


def normalize(value):
    return " ".join(unicodedata.normalize("NFKC", value).casefold().split())


CANONICAL = {
    normalize(alias): normalize(name) for name, aliases in ALIASES.items() for alias in aliases
}


def skill_key(value):
    value = normalize(value)
    return CANONICAL.get(value, value)


class MatchInput(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    resume_id: str = Field(pattern=ID_PATTERN)
    expected_resume_revision: int = Field(ge=1, le=2147483647)
    expected_job_version: int | None = Field(default=None, ge=1, le=2147483647)


class SkillEvidence(BaseModel):
    skill: str
    confirmed_skill: str


class MatchResult(BaseModel):
    algorithm_version: str = ALGORITHM_VERSION
    taxonomy_version: str = TAXONOMY_VERSION
    job_id: str
    job_title: str
    company_name: str
    job_version: int
    resume_id: str
    resume_version: int
    resume_revision: int
    resume_sha256: str
    skills_version: int
    parser_version: str
    status: Literal["scored", "unscored"]
    score: float | None
    unscored_reason: Literal["no_required_skills"] | None = None
    required_evidence: list[SkillEvidence]
    preferred_evidence: list[SkillEvidence]
    missing_required: list[str]
    missing_preferred: list[str]


def calculate_match(job, resume):
    if resume.parse_status != "confirmed":
        raise ApiError(
            409, "skills_confirmation_required", "Confirm resume skills before matching."
        )
    skills = {}
    for value in resume.confirmed_skills:
        skills.setdefault(skill_key(value), value)

    def compare(values):
        evidence, missing, seen = [], [], set()
        for value in values:
            key = skill_key(value)
            if key in seen:
                continue
            seen.add(key)
            if key in skills:
                evidence.append(SkillEvidence(skill=value, confirmed_skill=skills[key]))
            else:
                missing.append(value)
        return evidence, missing

    required, missing_required = compare(job.required_skills)
    preferred, missing_preferred = compare(job.preferred_skills)
    count = len(required) + len(missing_required)
    # Integer rounding gives stable percentages without platform float tie behavior.
    score = ((len(required) * 10000 + count // 2) // count) / 100 if count else None
    return MatchResult(
        job_id=job.id,
        job_title=job.title,
        company_name=job.company_name,
        job_version=job.version,
        resume_id=resume.id,
        resume_version=resume.version,
        resume_revision=resume.revision,
        resume_sha256=resume.sha256,
        skills_version=resume.skills_version,
        parser_version=resume.parser_version,
        status="scored" if count else "unscored",
        score=score,
        unscored_reason=None if count else "no_required_skills",
        required_evidence=required,
        preferred_evidence=preferred,
        missing_required=missing_required,
        missing_preferred=missing_preferred,
    )


class FirestoreMatchStore(FirestoreResumeStore):
    def account_record(self, transaction, uid):
        record = (
            self.client.collection("users")
            .document(quote(uid, safe=""))
            .get(transaction=transaction, timeout=10, retry=None)
        )
        data = record.to_dict() if record.exists else {}
        account = Account(
            uid=uid,
            **{
                key: data[key]
                for key in ("role", "account_status", "recruiter_approved")
                if key in data
            },
        )
        if account.account_status != "active":
            raise ApiError(403, "account_inactive", "An active account is required.")
        return account

    def available_job(self, transaction, job_id):
        record = (
            self.client.collection("jobs")
            .document(job_id)
            .get(transaction=transaction, timeout=10, retry=None)
        )
        data = record.to_dict() if record.exists else None
        unavailable = ApiError(404, "job_unavailable", "This job is unavailable.")
        if not data or data.get("status") != "published":
            raise unavailable
        job = JobDraft(
            id=job_id,
            **{key: data[key] for key in JobDraft.model_fields if key != "id" and key in data},
        )
        if (
            job.recruiter_uid != job.company_owner_uid
            or not job.published_at
            or not job.company_name
        ):
            raise unavailable
        try:
            owner = self.account_record(transaction, job.recruiter_uid)
        except ApiError as error:
            if error.status == 403:
                raise unavailable from None
            raise
        company = (
            self.client.collection("company_profiles")
            .document(quote(job.company_owner_uid, safe=""))
            .get(transaction=transaction, timeout=10, retry=None)
        )
        if owner.role != "recruiter" or not owner.recruiter_approved or not company.exists:
            raise unavailable
        data = company.to_dict()
        profile = CompanyProfile(
            owner_uid=job.company_owner_uid,
            **{
                key: data[key]
                for key in (*CompanyInput.model_fields, "approval_status", "updated_at")
                if key in data
            },
        )
        if profile.approval_status != "approved":
            raise unavailable
        return job

    def inputs(self, transaction, uid, job_id, command):
        actor = self.account_record(transaction, uid)
        if actor.role != "seeker":
            raise ApiError(403, "seeker_required", "A seeker account is required.")
        ref = self.collection().document(command.resume_id)
        resume = snapshot(command.resume_id, self.owned(transaction, uid, ref))
        job = self.available_job(transaction, job_id)
        if resume.revision != command.expected_resume_revision or (
            command.expected_job_version is not None and job.version != command.expected_job_version
        ):
            raise ApiError(
                409, "sources_changed", "Job or resume changed. Refresh before retrying."
            )
        return job, resume

    @guarded
    def match(self, uid, job_id, command):
        self.collection()  # Initialize the shared Firestore client before starting the transaction.

        @firestore.transactional
        def read(transaction):
            return calculate_match(*self.inputs(transaction, uid, job_id, command))

        return read(self.client.transaction(max_attempts=1))


router = APIRouter(prefix="/api/v1/jobs", tags=["matching"])


@router.post("/{job_id}/match", response_model=MatchResult)
def match_resume(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    job_id: Annotated[str, Path(pattern=ID_PATTERN)],
    command: MatchInput,
):
    return request.app.state.match_store.match(identity.uid, job_id, command)
