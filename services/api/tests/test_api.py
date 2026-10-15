from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient

from app.errors import ApiError
from app.main import create_app
from app.settings import Settings


class Verifier:
    def __init__(self, claims=None, error=None):
        self.claims = claims or {"uid": "seeker-one", "email_verified": False}
        self.error = error
        self.received = []

    def verify(self, token):
        self.received.append(token)
        if self.error:
            raise self.error
        return self.claims


def test_health_does_not_require_firebase_configuration():
    with TestClient(create_app(Settings())) as client:
        response = client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"


@pytest.mark.parametrize("authorization", [None, "Basic test", "Bearer", "Bearer one two"])
def test_missing_or_malformed_identity_is_rejected_before_verification(authorization):
    verifier = Verifier()
    with TestClient(create_app(Settings(), token_verifier=verifier)) as client:
        headers = {"Authorization": authorization} if authorization else {}
        response = client.get("/api/v1/me", headers=headers)
        assert response.status_code == 401
        assert response.headers["WWW-Authenticate"] == "Bearer"
        assert verifier.received == []
        assert response.json()["requestId"] == response.headers["X-Request-ID"]


def test_me_identity_comes_from_verified_claims_not_query_parameters():
    verifier = Verifier({"uid": "seeker-one", "email": "demo@example.com", "email_verified": True})
    with TestClient(create_app(Settings(), token_verifier=verifier)) as client:
        response = client.get(
            "/api/v1/me?uid=another-user", headers={"Authorization": "Bearer test"}
        )
        assert response.json() == {
            "uid": "seeker-one",
            "email": "demo@example.com",
            "email_verified": True,
        }
        assert verifier.received == ["test"]
        assert response.headers["Cache-Control"] == "no-store"


@pytest.mark.parametrize(
    "claims",
    [{"email": "demo@example.com"}, {"uid": ""}, {"uid": "demo", "email_verified": "true"}],
)
def test_invalid_verified_claim_shapes_cannot_create_an_identity(claims):
    with TestClient(create_app(Settings(), token_verifier=Verifier(claims))) as client:
        response = client.get("/api/v1/me", headers={"Authorization": "Bearer test"})
        assert response.status_code == 401


def test_revoked_identity_cannot_access_the_account_endpoint():
    verifier = Verifier(error=ApiError(401, "invalid_token", "Sign in again to continue."))
    with TestClient(create_app(Settings(), token_verifier=verifier)) as client:
        response = client.get("/api/v1/me", headers={"Authorization": "Bearer revoked-test"})
        assert response.status_code == 401
        assert "revoked-test" not in response.text


def test_missing_server_configuration_fails_closed():
    with TestClient(create_app(Settings())) as client:
        response = client.get("/api/v1/me", headers={"Authorization": "Bearer test"})
        assert response.status_code == 503
        assert response.json()["code"] == "auth_unavailable"


def test_request_ids_are_safe_and_traceable():
    with TestClient(create_app(Settings())) as client:
        request_id = str(uuid4())
        response = client.get("/health", headers={"X-Request-ID": request_id})
        assert response.headers["X-Request-ID"] == request_id
        response = client.get("/health", headers={"X-Request-ID": "untrusted-diagnostic"})
        assert str(UUID(response.headers["X-Request-ID"])) == response.headers["X-Request-ID"]


def test_cors_only_allows_the_configured_preview():
    origin = "https://smarthire-vishalpoute.antideploy.app"
    with TestClient(create_app(Settings(allowed_origins=(origin,)))) as client:
        headers = {
            "Origin": origin,
            "Access-Control-Request-Method": "GET",
            "Access-Control-Request-Headers": "authorization",
        }
        response = client.options("/api/v1/me", headers=headers)
        assert response.headers["Access-Control-Allow-Origin"] == origin
        headers["Origin"] = "https://untrusted.example"
        response = client.options("/api/v1/me", headers=headers)
        assert response.status_code == 400
        assert "Access-Control-Allow-Origin" not in response.headers


def test_unknown_paths_use_the_error_envelope():
    with TestClient(create_app(Settings())) as client:
        response = client.get("/unknown")
        assert response.status_code == 404
        assert response.json()["code"] == "request_error"


def test_wildcard_cors_environment_is_rejected(monkeypatch):
    monkeypatch.setenv("ALLOWED_ORIGINS", "*")
    with pytest.raises(ValueError):
        Settings.from_environment()
