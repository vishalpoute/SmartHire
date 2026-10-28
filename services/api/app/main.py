import logging
from contextlib import asynccontextmanager
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

from app.accounts import FirestoreAccountStore
from app.accounts import router as account_router
from app.applications import FirestoreApplicationStore
from app.applications import router as application_router
from app.auth import FirebaseTokenVerifier, Identity, require_identity
from app.body_limit import RequestBodyLimit
from app.companies import FirestoreCompanyStore
from app.companies import router as company_router
from app.errors import ApiError
from app.jobs import FirestoreJobStore
from app.jobs import public_router as public_job_router
from app.jobs import router as job_router
from app.matching import FirestoreMatchStore
from app.matching import router as match_router
from app.profiles import FirestoreProfileStore
from app.profiles import router as profile_router
from app.rate_limit import ProfileRateLimiter
from app.recruiter_review import FirestoreRecruiterReviewStore
from app.recruiter_review import router as recruiter_review_router
from app.resume_storage import ResumeStorageFailure, S3ResumeStorage
from app.resume_store import FirestoreResumeStore
from app.resume_worker import ResumeWorker
from app.resumes import router as resume_router
from app.saved_jobs import FirestoreSavedJobStore
from app.saved_jobs import router as saved_job_router
from app.settings import Settings

logger = logging.getLogger("smarthire.api")


def create_app(
    settings: Settings | None = None,
    *,
    token_verifier=None,
    profile_store=None,
    account_store=None,
    company_store=None,
    job_store=None,
    recruiter_review_store=None,
    resume_store=None,
    resume_storage=None,
    resume_worker=None,
    match_store=None,
    application_store=None,
    saved_job_store=None,
) -> FastAPI:
    settings = settings or Settings.from_environment()

    @asynccontextmanager
    async def lifespan(api):
        worker = api.state.resume_worker
        if worker is not None:
            worker.start()
        try:
            yield
        finally:
            if worker is not None:
                worker.stop()

    api = FastAPI(title="SmartHire API", version="0.1.0", lifespan=lifespan)
    api.state.token_verifier = token_verifier or FirebaseTokenVerifier(settings)
    api.state.profile_limiter = ProfileRateLimiter()
    api.state.public_job_limiter = ProfileRateLimiter(limit=120, max_accounts=1)
    api.state.public_job_list_limiter = ProfileRateLimiter(limit=20, max_accounts=1)
    api.state.profile_store = profile_store or FirestoreProfileStore(settings)
    api.state.account_store = account_store or FirestoreAccountStore(settings)
    api.state.company_store = company_store or FirestoreCompanyStore(settings)
    api.state.job_store = job_store or FirestoreJobStore(settings)
    api.state.resume_store = resume_store or FirestoreResumeStore(settings)
    api.state.match_store = match_store or FirestoreMatchStore(settings)
    api.state.application_store = application_store or FirestoreApplicationStore(settings)
    api.state.saved_job_store = saved_job_store or FirestoreSavedJobStore(settings)
    api.state.resume_storage = resume_storage
    if resume_storage is None and settings.resume_uploads_enabled:
        try:
            api.state.resume_storage = S3ResumeStorage.from_environment()
        except ResumeStorageFailure:
            logger.warning("resume_storage_not_configured")
    api.state.resume_worker = resume_worker
    if (
        resume_worker is None
        and settings.resume_worker_enabled
        and api.state.resume_storage is not None
    ):
        api.state.resume_worker = ResumeWorker(api.state.resume_store, api.state.resume_storage)
    api.state.recruiter_review_store = recruiter_review_store or FirestoreRecruiterReviewStore(
        settings
    )
    api.include_router(recruiter_review_router)
    api.include_router(resume_router)
    api.include_router(match_router)
    api.include_router(application_router)
    api.include_router(saved_job_router)
    api.include_router(job_router)
    api.include_router(public_job_router)
    api.include_router(company_router)
    api.include_router(account_router)
    api.include_router(profile_router)
    api.add_middleware(RequestBodyLimit)
    if settings.allowed_origins:
        api.add_middleware(
            CORSMiddleware,
            allow_origins=list(settings.allowed_origins),
            allow_methods=["GET", "PUT", "POST"],
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
