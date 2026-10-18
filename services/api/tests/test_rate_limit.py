import pytest
from fastapi.testclient import TestClient
from test_api import Verifier
from test_profiles import Store

from app.errors import ApiError
from app.main import create_app
from app.rate_limit import ProfileRateLimiter
from app.settings import Settings


def test_identity_buckets_are_separate_and_expire_at_boundary():
    now = [0.0]
    limiter = ProfileRateLimiter(limit=1, clock=lambda: now[0])
    limiter.check("one")
    with pytest.raises(ApiError) as error:
        limiter.check("one")
    assert error.value.status == 429
    assert error.value.retry_after == 60
    limiter.check("two")
    now[0] = 60.0
    limiter.check("one")


def test_capacity_is_bounded_and_fails_closed_until_expiration():
    now = [0.0]
    limiter = ProfileRateLimiter(max_accounts=2, clock=lambda: now[0])
    limiter.check("one")
    limiter.check("two")
    with pytest.raises(ApiError) as error:
        limiter.check("three")
    assert error.value.status == 503
    assert len(limiter.accounts) == 2
    now[0] = 61
    limiter.check("three")
    assert len(limiter.accounts) == 1


def test_throttled_requests_never_reach_profile_store_and_return_retry_after():
    store = Store()
    api = create_app(
        Settings(),
        token_verifier=Verifier({"uid": "one", "email_verified": True}),
        profile_store=store,
    )
    api.state.profile_limiter = ProfileRateLimiter(limit=1)
    with TestClient(api) as client:
        headers = {"Authorization": "Bearer test"}
        assert client.get("/api/v1/profile", headers=headers).status_code == 404
        response = client.get("/api/v1/profile", headers={**headers, "X-Forwarded-For": "spoofed"})
        assert response.status_code == 429
        assert int(response.headers["Retry-After"]) >= 1
        assert response.json()["requestId"] == response.headers["X-Request-ID"]
        assert client.get("/health").status_code == 200
    assert store.calls == ["one"]
