"""Bound request bytes before framework JSON parsing or authentication work."""

from uuid import uuid4

from starlette.responses import JSONResponse

MAX_BODY_BYTES = 64 * 1024


class RequestBodyLimit:
    def __init__(self, app, max_bytes=MAX_BODY_BYTES):
        self.app = app
        self.max_bytes = max_bytes

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        headers = dict(scope.get("headers", []))
        declared = headers.get(b"content-length")
        if declared is not None:
            try:
                length = int(declared)
                if length < 0:
                    raise ValueError
            except ValueError:
                await self.reject(scope, receive, send, 400, "invalid_content_length")
                return
            if length > self.max_bytes:
                await self.reject(scope, receive, send, 413, "request_too_large")
                return
        body = bytearray()
        size = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            size += len(message.get("body", b""))
            if size > self.max_bytes:
                await self.reject(scope, receive, send, 413, "request_too_large")
                return
            body.extend(message.get("body", b""))
            if not message.get("more_body", False):
                break
        replayed = False

        async def replay():
            nonlocal replayed
            if not replayed:
                replayed = True
                return {"type": "http.request", "body": bytes(body), "more_body": False}
            return await receive()

        await self.app(scope, replay, send)

    @staticmethod
    async def reject(scope, receive, send, status, code):
        response = JSONResponse(
            status_code=status,
            content={
                "code": code,
                "message": "Request exceeds the size limit."
                if status == 413
                else "Invalid request length.",
                "requestId": scope.get("state", {}).get("request_id", str(uuid4())),
            },
        )
        await response(scope, receive, send)
