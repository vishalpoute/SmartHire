from typing import Annotated
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.auth import FirebaseTokenVerifier, Identity, require_identity
from app.errors import ApiError
from app.settings import Settings


def create_app(settings: Settings | None = None, *, token_verifier=None) -> FastAPI:
    settings = settings or Settings.from_environment()
    api = FastAPI(title="SmartHire API", version="0.1.0")
    api.state.token_verifier = token_verifier or FirebaseTokenVerifier(settings)
    if settings.allowed_origins:
        api.add_middleware(
            CORSMiddleware,
            allow_origins=list(settings.allowed_origins),
            allow_methods=["GET"],
            allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
            expose_headers=["X-Request-ID"],
        )

    @api.middleware("http")
    async def request_context(request: Request, call_next):
        supplied = request.headers.get("X-Request-ID", "")
        try:
            request.state.request_id = str(UUID(supplied))
        except ValueError:
            request.state.request_id = str(uuid4())
        response = await call_next(request)
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
        return error_response(request, error.status, error.code, error.message)

    @api.exception_handler(RequestValidationError)
    async def handle_validation_error(request: Request, error: RequestValidationError):
        # Validation details can include submitted values; do not echo them.
        return error_response(request, 422, "validation_error", "Check the request fields.")

    @api.exception_handler(HTTPException)
    async def handle_http_error(request: Request, error: HTTPException):
        return error_response(
            request, error.status_code, "request_error", "This request is unavailable."
        )

    @api.get("/health")
    def health():
        # Liveness only: success does not claim Firebase or a database is ready.
        return {"status": "ok", "service": "smarthire-api"}

    @api.get("/api/v1/me", response_model=Identity)
    def me(identity: Annotated[Identity, Depends(require_identity)]):
        return identity

    return api


app = create_app()
