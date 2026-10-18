from datetime import datetime
from threading import Lock
from typing import Annotated, Protocol
from urllib.parse import quote

from fastapi import APIRouter, Depends, Request
from google.cloud import firestore
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.accounts import active_account
from app.auth import Identity, require_identity
from app.errors import ApiError
from app.settings import Settings


class ProfileInput(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    display_name: str = Field(min_length=2, max_length=80)
    headline: str = Field(default="", max_length=120)
    location: str = Field(default="", max_length=80)
    skills: list[str] = Field(default_factory=list, max_length=30)

    @field_validator("skills")
    @classmethod
    def clean_skills(cls, values: list[str]) -> list[str]:
        result = []
        seen = set()
        for value in values:
            value = value.strip()
            if not value or len(value) > 40:
                raise ValueError("Skills must contain between 1 and 40 characters.")
            if value.casefold() not in seen:
                result.append(value)
                seen.add(value.casefold())
        return result


class Profile(ProfileInput):
    uid: str
    updated_at: datetime


class ProfileStore(Protocol):
    def get(self, uid: str) -> Profile | None: ...
    def put(self, uid: str, profile: ProfileInput) -> Profile: ...


class FirestoreProfileStore:
    def __init__(self, settings: Settings):
        self._settings = settings
        self._client = None
        self._lock = Lock()

    def _document(self, uid: str):
        if not self._settings.firebase_project_id:
            raise ApiError(503, "profile_unavailable", "Profile storage is not configured.")
        with self._lock:
            if self._client is None:
                self._client = firestore.Client(project=self._settings.firebase_project_id)
        # A signed custom UID must never become extra Firestore path segments.
        return self._client.collection("private_profiles").document(quote(uid, safe=""))

    def get(self, uid: str) -> Profile | None:
        try:
            snapshot = self._document(uid).get(timeout=10, retry=None)
            if not snapshot.exists:
                return None
            data = snapshot.to_dict()
            fields = {key: data[key] for key in ProfileInput.model_fields if key in data}
            return Profile(uid=uid, updated_at=data["updated_at"], **fields)
        except ApiError:
            raise
        except Exception:  # noqa: BLE001 - do not expose datastore/credential diagnostics.
            raise ApiError(
                503, "profile_unavailable", "Profile storage is temporarily unavailable."
            ) from None

    def put(self, uid: str, profile: ProfileInput) -> Profile:
        try:
            data = profile.model_dump()
            result = self._document(uid).set(
                {**data, "updated_at": firestore.SERVER_TIMESTAMP},
                merge=True,
                timeout=10,
                retry=None,
            )
            return Profile(uid=uid, updated_at=result.update_time, **data)
        except ApiError:
            raise
        except Exception:  # noqa: BLE001 - fail closed without leaking profile or SDK data.
            raise ApiError(
                503, "profile_unavailable", "Profile storage is temporarily unavailable."
            ) from None


def verified_identity(
    request: Request, identity: Annotated[Identity, Depends(require_identity)]
) -> Identity:
    if not identity.email_verified:
        raise ApiError(
            403, "email_verification_required", "Verify your email before using your profile."
        )
    request.app.state.profile_limiter.check(identity.uid)
    active_account(request, identity)
    return identity


router = APIRouter(prefix="/api/v1/profile", tags=["profile"])


@router.get("", response_model=Profile)
def read_profile(request: Request, identity: Annotated[Identity, Depends(verified_identity)]):
    profile = request.app.state.profile_store.get(identity.uid)
    if profile is None:
        raise ApiError(404, "profile_not_found", "Complete your profile to get started.")
    return profile


@router.put("", response_model=Profile)
def save_profile(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    profile: ProfileInput,
):
    return request.app.state.profile_store.put(identity.uid, profile)
