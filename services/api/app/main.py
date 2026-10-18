import logging
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.accounts import FirestoreAccountStore
from app.accounts import router as account_router
from app.auth import FirebaseTokenVerifier, Identity, require_identity
from app.body_limit import RequestBodyLimit
from app.errors import ApiError
from app.profiles import FirestoreProfileStore
from app.profiles import router as profile_router
from app.rate_limit import ProfileRateLimiter
from app.settings import Settings

logger = logging.getLogger("smarthire.api")


def create_app(
    settings: Settings | None = None, *, token_verifier=None, profile_store=None, account_store=None
) -> FastAPI:
    settings = settings or Settings.from_environment()
    api = FastAPI(title="SmartHire API", version="0.1.0")
    api.state.token_verifier = token_verifier or FirebaseTokenVerifier(settings)
    api.state.profile_limiter = ProfileRateLimiter()
    api.state.profile_store = profile_store or FirestoreProfileStore(settings)
    api.state.account_store = account_store or FirestoreAccountStore(settings)
    api.include_router(account_router)
    api.include_router(profile_router)
    api.add_middleware(RequestBodyLimit)
    if settings.allowed_origins:
        api.add_middleware(
            CORSMiddleware,
            allow_origins=list(settings.allowed_origins),
            allow_methods=["GET", "PUT"],
            allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
            expose_headers=["X-Request-ID", "Retry-After"],
        )

    @api.middleware("http")
    async def request_context(request: Request, call_next):
        supplied = request.headers.get("X-Request-ID", "")
        try:
            request.state.request_id = str(UUID(supplied))
        except ValueError:
            request.state.request_id = str(uuid4())
        try:
            response = await call_next(request)
        except Exception as error:  # noqa: BLE001 - sanitize unexpected failures at the HTTP boundary.
            # Exception messages, URLs and headers can contain credentials or personal data.
            logger.error(
                "request_failed request_id=%s error_type=%s",
                request.state.request_id,
                type(error).__name__,
            )
            response = error_response(request, 500, "internal_error", "Please try again later.")
            origin = request.headers.get("Origin")
            if origin in settings.allowed_origins:
                response.headers["Access-Control-Allow-Origin"] = origin
                response.headers["Access-Control-Expose-Headers"] = "X-Request-ID"
                response.headers["Vary"] = "Origin"
        response.headers["X-Request-ID"] = request.state.request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        return response

    def error_response(request: Request, status: int, code: str, message: str):
        return JSONResponse(
            status_code=status,
            content={"code": code, "message": message, "requestId": request.state.request_id},
            headers={"WWW-Authenticate": "Bearer"} if status == 401 else {},
        )

    @api.exception_handler(ApiError)
    async def handle_api_error(request: Request, error: ApiError):
        response = error_response(request, error.status, error.code, error.message)
        if error.retry_after is not None:
            response.headers["Retry-After"] = str(error.retry_after)
        return response

    @api.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, error: RequestValidationError):
        # Validation details can include submitted values; do not echo them.
        return error_response(request, 422, "validation_error", "Check the request fields.")

    @api.exception_handler(HTTPException)
    async def handle_http_error(request: Request, error: HTTPException):
        response = error_response(
            request, error.status_code, "request_error", "This request is unavailable."
        )
        # Preserve protocol-required headers, without forwarding arbitrary diagnostic headers.
        if error.headers and "Allow" in error.headers:
            response.headers["Allow"] = error.headers["Allow"]
        return response

    @api.get("/health")
    def health():
        # Liveness only: success does not claim Firebase or a database is ready.
        return {"status": "ok", "service": "smarthire-api"}

    @api.get("/api/v1/me", response_model=Identity)
    def me(identity: Annotated[Identity, Depends(require_identity)]):
        return identity

    return api


app = create_app()
