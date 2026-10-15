from unittest.mock import Mock

import pytest
from firebase_admin import auth

from app.auth import FirebaseTokenVerifier
from app.errors import ApiError
from app.settings import Settings


def test_sdk_checks_revocation_and_uses_the_explicit_project(monkeypatch):
    application = object()
    initialize = Mock(return_value=application)
    verify = Mock(return_value={"uid": "demo"})
    monkeypatch.setattr("app.auth.firebase_admin.initialize_app", initialize)
    monkeypatch.setattr("app.auth.auth.verify_id_token", verify)
    verifier = FirebaseTokenVerifier(Settings(firebase_project_id="demo-smarthire"))
    assert verifier.verify("test-token")["uid"] == "demo"
    verifier.verify("another-token")
    assert initialize.call_count == 1
    assert initialize.call_args.kwargs["options"]["projectId"] == "demo-smarthire"
    verify.assert_called_with("another-token", app=application, check_revoked=True)


@pytest.mark.parametrize(
    "sdk_error",
    [
        auth.InvalidIdTokenError("invalid"),
        auth.RevokedIdTokenError("revoked"),
        auth.UserDisabledError("disabled"),
    ],
)
def test_invalid_expired_or_disabled_tokens_are_unauthorized(monkeypatch, sdk_error):
    monkeypatch.setattr("app.auth.firebase_admin.initialize_app", Mock(return_value=object()))
    monkeypatch.setattr("app.auth.auth.verify_id_token", Mock(side_effect=sdk_error))
    verifier = FirebaseTokenVerifier(Settings(firebase_project_id="demo-smarthire"))
    with pytest.raises(ApiError) as result:
        verifier.verify("test-token")
    assert result.value.status == 401
    assert "test-token" not in result.value.message


def test_unavailable_credentials_are_not_reported_as_an_invalid_user(monkeypatch):
    monkeypatch.setattr(
        "app.auth.firebase_admin.initialize_app",
        Mock(side_effect=ValueError("private credential diagnostic")),
    )
    with pytest.raises(ApiError) as result:
        FirebaseTokenVerifier(Settings(firebase_project_id="demo-smarthire")).verify("test-token")
    assert result.value.status == 503
    assert "private" not in result.value.message
