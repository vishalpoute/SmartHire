import pytest
from fastapi.testclient import TestClient
from test_api import Verifier
from test_profiles import Accounts, Store

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
        Settings(allowed_origins=["https://example.com"]),
        token_verifier=Verifier({"uid": "one", "email_verified": True}),
        profile_store=store,
        account_store=Accounts(),
    )
    api.state.profile_limiter = ProfileRateLimiter(limit=1)
    with TestClient(api) as client:
        headers = {"Authorization": "Bearer test"}
        assert client.get("/api/v1/profile", headers=headers).status_code == 404
        response = client.get(
            "/api/v1/profile",
            headers={**headers, "X-Forwarded-For": "spoofed", "Origin": "https://example.com"},
        )
        assert response.status_code == 429
        assert int(response.headers["Retry-After"]) >= 1
        assert "Retry-After" in response.headers["Access-Control-Expose-Headers"]
        assert response.json()["requestId"] == response.headers["X-Request-ID"]
        assert client.get("/health").status_code == 200
    assert store.calls == ["one"]


def test_concurrent_requests_share_one_account_budget():
    from concurrent.futures import ThreadPoolExecutor

    limiter = ProfileRateLimiter(limit=10)

    def request(_):
        try:
            limiter.check("one")
            return 200
        except ApiError as error:
            return error.status

    with ThreadPoolExecutor(max_workers=16) as pool:
        statuses = list(pool.map(request, range(100)))
    assert statuses.count(200) == 10
    assert statuses.count(429) == 90
