import asyncio

import pytest
from fastapi.testclient import TestClient

from app.body_limit import MAX_BODY_BYTES, RequestBodyLimit
from app.main import create_app
from app.settings import Settings


def test_oversized_body_is_rejected_before_auth_with_cors_and_safe_headers():
    class Verifier:
        def verify(self, token):
            raise AssertionError("Must not verify oversized input")

    with TestClient(
        create_app(Settings(allowed_origins=("https://client.example",)), token_verifier=Verifier())
    ) as client:
        response = client.put(
            "/api/v1/profile",
            content=b"x" * (MAX_BODY_BYTES + 1),
            headers={
                "Authorization": "Bearer test",
                "Origin": "https://client.example",
            },
        )
    assert response.status_code == 413
    assert response.json()["code"] == "request_too_large"
    assert response.json()["requestId"] == response.headers["X-Request-ID"]
    assert response.headers["Cache-Control"] == "no-store"
    assert response.headers["Access-Control-Allow-Origin"] == "https://client.example"


@pytest.mark.parametrize("declared", [None, b"0"])
def test_chunked_or_underdeclared_body_still_has_actual_byte_limit(declared):
    async def run():
        called = False
        messages = iter(
            [
                {"type": "http.request", "body": b"a" * 40, "more_body": True},
                {"type": "http.request", "body": b"b" * 30, "more_body": False},
            ]
        )
        sent = []

        async def receive():
            return next(messages)

        async def send(message):
            sent.append(message)

        async def app(scope, receive, send):
            nonlocal called
            called = True

        scope = {
            "type": "http",
            "headers": [] if declared is None else [(b"content-length", declared)],
        }
        await RequestBodyLimit(app, max_bytes=64)(scope, receive, send)
        assert not called
        assert sent[0]["status"] == 413

    asyncio.run(run())


def test_exact_limit_is_replayed_without_modifying_body():
    async def run():
        original = {"type": "http.request", "body": b"a" * 64, "more_body": False}

        async def receive():
            return original

        async def app(scope, replay, send):
            assert await replay() == original

        async def send(message):
            raise AssertionError("Unexpected rejection")

        await RequestBodyLimit(app, max_bytes=64)({"type": "http", "headers": []}, receive, send)

    asyncio.run(run())


@pytest.mark.parametrize("length", ["-1", "not-a-number"])
def test_invalid_content_length_is_safe_400(length):
    with TestClient(create_app(Settings())) as client:
        response = client.put("/api/v1/profile", content=b"{}", headers={"Content-Length": length})
    assert response.status_code == 400
    assert response.json()["code"] == "invalid_content_length"
