"""Private company onboarding. Saving never assigns recruiter privileges."""

from datetime import datetime
from threading import Lock
from typing import Annotated, Literal
from urllib.parse import quote, urlsplit

from fastapi import APIRouter, Depends, Request
from google.cloud import firestore
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.auth import Identity
from app.errors import ApiError
from app.profiles import verified_identity


class CompanyInput(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid", str_strip_whitespace=True)
    name: str = Field(min_length=2, max_length=120)
    description: str = Field(default="", max_length=2000)
    location: str = Field(default="", max_length=80)
    website: str = Field(default="", max_length=500)

    @field_validator("website")
    @classmethod
    def validate_website(cls, value):
        if value:
            if any(character.isspace() or ord(character) < 32 for character in value):
                raise ValueError("Website must not contain whitespace or control characters.")
            parsed = urlsplit(value)
            if parsed.port == 0:
                raise ValueError("Website port must be valid.")
            if (
                parsed.scheme != "https"
                or not parsed.hostname
                or parsed.username
                or parsed.password
            ):
                raise ValueError("Website must be an HTTPS URL without credentials.")
        return value


class CompanyProfile(CompanyInput):
    owner_uid: str
    approval_status: Literal["pending", "approved", "rejected"]
    updated_at: datetime


class FirestoreCompanyStore:
    def __init__(self, settings):
        self.settings = settings
        self.client = None
        self.lock = Lock()

    def document(self, uid):
        if not self.settings.firebase_project_id:
            raise ValueError("Missing project")
        with self.lock:
            if self.client is None:
                self.client = firestore.Client(project=self.settings.firebase_project_id)
        return self.client.collection("company_profiles").document(quote(uid, safe=""))

    def get(self, uid):
        try:
            snapshot = self.document(uid).get(timeout=10, retry=None)
            if not snapshot.exists:
                return None
            data = snapshot.to_dict()
            fields = {key: data[key] for key in CompanyInput.model_fields if key in data}
            return CompanyProfile(
                owner_uid=uid,
                approval_status=data["approval_status"],
                updated_at=data["updated_at"],
                **fields,
            )
        except Exception:  # noqa: BLE001 - do not expose datastore or submitted company data.
            raise ApiError(
                503, "company_unavailable", "Company profile is temporarily unavailable."
            ) from None

    def put(self, uid, company):
        try:
            fields = company.model_dump()
            # Any company edit requires review again; preserve unrelated server metadata.
            result = self.document(uid).set(
                {**fields, "approval_status": "pending", "updated_at": firestore.SERVER_TIMESTAMP},
                merge=True,
                timeout=10,
                retry=None,
            )
            return CompanyProfile(
                owner_uid=uid, approval_status="pending", updated_at=result.update_time, **fields
            )
        except Exception:  # noqa: BLE001 - safe fail-closed storage boundary.
            raise ApiError(
                503, "company_unavailable", "Company profile is temporarily unavailable."
            ) from None


router = APIRouter(prefix="/api/v1/company", tags=["company"])


@router.get("", response_model=CompanyProfile)
def read_company(request: Request, identity: Annotated[Identity, Depends(verified_identity)]):
    company = request.app.state.company_store.get(identity.uid)
    if company is None:
        raise ApiError(404, "company_not_found", "Create your company profile to get started.")
    return company


@router.put("", response_model=CompanyProfile)
def save_company(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    company: CompanyInput,
):
    return request.app.state.company_store.put(identity.uid, company)
