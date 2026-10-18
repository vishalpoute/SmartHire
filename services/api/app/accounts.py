"""Server-owned account permissions; client claims cannot assign application roles."""

from threading import Lock
from typing import Annotated, Literal
from urllib.parse import quote

from fastapi import APIRouter, Depends, Request
from google.cloud import firestore
from pydantic import BaseModel, ConfigDict

from app.auth import Identity, require_identity
from app.errors import ApiError


class Account(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    uid: str
    role: Literal["seeker", "recruiter", "admin"] = "seeker"
    account_status: Literal["active", "suspended"] = "active"
    recruiter_approved: bool = False


class FirestoreAccountStore:
    def __init__(self, settings):
        self.settings = settings
        self.client = None
        self.lock = Lock()

    def get(self, uid):
        try:
            if not self.settings.firebase_project_id:
                raise ValueError("Missing project")
            with self.lock:
                if self.client is None:
                    self.client = firestore.Client(project=self.settings.firebase_project_id)
            snapshot = (
                self.client.collection("users")
                .document(quote(uid, safe=""))
                .get(timeout=10, retry=None)
            )
            if not snapshot.exists:
                # A missing server record grants only ordinary seeker access.
                return Account(uid=uid)
            data = snapshot.to_dict()
            fields = {
                key: data[key]
                for key in ("role", "account_status", "recruiter_approved")
                if key in data
            }
            return Account(uid=uid, **fields)
        except Exception:  # noqa: BLE001 - fail closed without datastore/credential details.
            raise ApiError(
                503, "account_unavailable", "Account access is temporarily unavailable."
            ) from None


def active_account(request: Request, identity: Identity):
    account = request.app.state.account_store.get(identity.uid)
    if account.uid != identity.uid:
        raise ApiError(503, "account_unavailable", "Account access is temporarily unavailable.")
    if account.account_status != "active":
        raise ApiError(403, "account_suspended", "This account is suspended.")
    return account


router = APIRouter(prefix="/api/v1/account", tags=["account"])


@router.get("", response_model=Account)
def read_account(request: Request, identity: Annotated[Identity, Depends(require_identity)]):
    # Users can inspect their own suspension/approval state; no mutation endpoint exists.
    request.app.state.profile_limiter.check(identity.uid)
    account = request.app.state.account_store.get(identity.uid)
    if account.uid != identity.uid:
        raise ApiError(503, "account_unavailable", "Account access is temporarily unavailable.")
    return account
