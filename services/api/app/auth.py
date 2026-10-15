from threading import Lock
from typing import Annotated

import firebase_admin
from fastapi import Header, Request
from firebase_admin import auth, exceptions
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.errors import ApiError
from app.settings import Settings


class Identity(BaseModel):
    model_config = ConfigDict(strict=True)
    uid: str = Field(min_length=1, max_length=128)
    email: str | None = None
    email_verified: bool = False


class FirebaseTokenVerifier:
    """Verify signature, audience, issuer, expiry, revocation and disabled accounts."""

    def __init__(self, settings: Settings):
        self._settings = settings
        self._app = None
        self._lock = Lock()

    def verify(self, token: str) -> dict:
        if not self._settings.firebase_project_id:
            raise ApiError(503, "auth_unavailable", "Account verification is not configured.")
        try:
            with self._lock:
                if self._app is None:
                    # ADC stays in the server environment, never in source or Flutter assets.
                    self._app = firebase_admin.initialize_app(
                        options={
                            "projectId": self._settings.firebase_project_id,
                            "httpTimeout": 10,
                        },
                        name=f"smarthire-{id(self)}",
                    )
            return auth.verify_id_token(token, app=self._app, check_revoked=True)
        except (auth.InvalidIdTokenError, auth.RevokedIdTokenError, auth.UserDisabledError):
            raise ApiError(401, "invalid_token", "Sign in again to continue.") from None
        except (auth.CertificateFetchError, exceptions.FirebaseError):
            raise ApiError(
                503, "auth_unavailable", "Account verification is temporarily unavailable."
            ) from None
        except ApiError:
            raise
        except Exception:  # noqa: BLE001 - SDK/ADC failures must fail closed without diagnostics.
            # Includes missing/invalid ADC configuration. Never return SDK diagnostics or tokens.
            raise ApiError(
                503, "auth_unavailable", "Account verification is temporarily unavailable."
            ) from None


def require_identity(
    request: Request,
    authorization: Annotated[str | None, Header()] = None,
) -> Identity:
    if not authorization:
        raise ApiError(401, "authentication_required", "Sign in to continue.")
    parts = authorization.split()
    if len(parts) != 2 or parts[0].lower() != "bearer" or len(parts[1]) > 16384:
        raise ApiError(401, "invalid_token", "Provide a valid sign-in token.")
    claims = request.app.state.token_verifier.verify(parts[1])
    try:
        return Identity(
            uid=claims.get("uid"),
            email=claims.get("email"),
            email_verified=claims.get("email_verified", False),
        )
    except (ValidationError, AttributeError):
        raise ApiError(401, "invalid_token", "Sign in again to continue.") from None
