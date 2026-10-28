"""Verified owner resume workflow; private content never appears in public responses."""

from datetime import datetime
from typing import Annotated, Literal

from fastapi import APIRouter, Depends, Path, Query, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.auth import Identity
from app.errors import ApiError
from app.profiles import ProfileInput, verified_identity
from app.resume_parser import MAX_BYTES, MAX_TEXT, PARSER_VERSION
from app.resume_storage import ResumeStorageFailure

ResumeId = Annotated[str, Path(pattern=r"^[a-f0-9]{32}$", max_length=32)]


class ResumeUpload(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    upload_id: str = Field(pattern=r"^[a-f0-9]{32}$", max_length=32)
    extension: Literal["pdf", "docx"]
    size: int = Field(ge=1, le=MAX_BYTES)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$", max_length=64)


class ResumeVersion(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    expected_revision: int = Field(ge=1, le=2147483647)


class ConfirmResumeSkills(ResumeVersion):
    skills: list[str] = Field(max_length=30)

    @field_validator("skills")
    @classmethod
    def checked_skills(cls, values):
        if any(any(ord(char) < 32 or ord(char) == 127 for char in value) for value in values):
            raise ValueError("Control characters are not allowed")
        return ProfileInput.clean_skills(values)


class ResumeSnapshot(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    id: str = Field(pattern=r"^[a-f0-9]{32}$", max_length=32)
    version: int = Field(ge=1)
    revision: int = Field(ge=1)
    extension: Literal["pdf", "docx"]
    size: int = Field(ge=1, le=MAX_BYTES)
    sha256: str = Field(pattern=r"^[a-f0-9]{64}$", max_length=64)
    parse_status: Literal[
        "uploading", "queued", "processing", "parsed", "unscored", "confirmed", "deleting"
    ]
    extracted_skills: list[str] = Field(default_factory=list, max_length=30)
    confirmed_skills: list[str] | None = Field(default=None, max_length=30)
    skills_version: int = Field(default=0, ge=0)
    parser_version: str | None = None
    taxonomy_version: str | None = None
    error_code: (
        Literal[
            "unsupported_type",
            "size_limit",
            "invalid_document",
            "encrypted_pdf",
            "empty_text",
            "resource_limit",
            "storage_unavailable",
            "object_mismatch",
            "invalid_object",
            "account_inactive",
        ]
        | None
    ) = None
    created_at: datetime
    updated_at: datetime

    @field_validator("extracted_skills", "confirmed_skills")
    @classmethod
    def valid_skills(cls, values):
        return None if values is None else ConfirmResumeSkills.checked_skills(values)

    @field_validator("created_at", "updated_at")
    @classmethod
    def aware_dates(cls, value):
        if value.tzinfo is None:
            raise ValueError("A timezone is required")
        return value

    @model_validator(mode="after")
    def confirmed_source(self):
        if self.parse_status == "confirmed" and (
            self.confirmed_skills is None or self.skills_version < 1 or not self.parser_version
        ):
            raise ValueError("Confirmed skills need a parsed source and version")
        return self


class ParseOutcome(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    parse_status: Literal["parsed", "unscored"]
    text: str | None = Field(default=None, max_length=MAX_TEXT)
    extracted_skills: list[str] = Field(default_factory=list, max_length=30)
    parser_version: str = PARSER_VERSION
    taxonomy_version: str | None = None
    error_code: (
        Literal[
            "unsupported_type",
            "size_limit",
            "invalid_document",
            "encrypted_pdf",
            "empty_text",
            "resource_limit",
            "storage_unavailable",
            "object_mismatch",
            "invalid_object",
            "account_inactive",
        ]
        | None
    ) = None

    @model_validator(mode="after")
    def consistent(self):
        if self.parse_status == "parsed" and (not self.text or self.error_code is not None):
            raise ValueError("A parsed result needs text and no error")
        if self.parse_status == "unscored" and (
            self.text is not None or self.extracted_skills or self.error_code is None
        ):
            raise ValueError("An unscored result must not contain extracted content")
        return self


class ResumePage(BaseModel):
    items: list[ResumeSnapshot]
    next_cursor: str | None = None


class ResumeUploadReceipt(BaseModel):
    resume: ResumeSnapshot
    upload_url: str | None = None
    upload_headers: dict[str, str] = Field(default_factory=dict)
    expires_in: int = 0


def private_storage(request):
    storage = request.app.state.resume_storage
    if storage is None:
        raise ApiError(503, "resumes_unavailable", "Private resume uploads are not available yet.")
    return storage


def ticket_response(request, uid, resume):
    if resume.parse_status != "uploading":
        return ResumeUploadReceipt(resume=resume)
    try:
        ticket = private_storage(request).upload_ticket(
            uid, resume.id, resume.extension, resume.size, resume.sha256
        )
    except ResumeStorageFailure:
        raise ApiError(
            503, "resumes_unavailable", "Private resume uploads are temporarily unavailable."
        ) from None
    return ResumeUploadReceipt(
        resume=resume,
        upload_url=ticket.url,
        upload_headers=ticket.headers,
        expires_in=ticket.expires_in,
    )


router = APIRouter(prefix="/api/v1/resumes", tags=["private resumes"])


@router.post("", response_model=ResumeUploadReceipt, status_code=201)
def begin_resume_upload(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    command: ResumeUpload,
):
    private_storage(request)
    resume = request.app.state.resume_store.create(identity.uid, command)
    return ticket_response(request, identity.uid, resume)


@router.get("", response_model=ResumePage)
def owned_resumes(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    cursor: Annotated[str | None, Query(pattern=r"^[a-f0-9]{32}$", max_length=32)] = None,
):
    from app.resume_storage import valid_hex

    if cursor is not None and not valid_hex(cursor, 32):
        raise ApiError(422, "validation_error", "Check the resume page.")
    return request.app.state.resume_store.list_owned(identity.uid, cursor)


@router.get("/{resume_id}", response_model=ResumeSnapshot)
def read_resume(
    request: Request, resume_id: ResumeId, identity: Annotated[Identity, Depends(verified_identity)]
):
    return request.app.state.resume_store.get_owned(identity.uid, resume_id)


@router.post("/{resume_id}/upload-ticket", response_model=ResumeUploadReceipt)
def refresh_resume_ticket(
    request: Request, resume_id: ResumeId, identity: Annotated[Identity, Depends(verified_identity)]
):
    resume = request.app.state.resume_store.uploadable(identity.uid, resume_id)
    return ticket_response(request, identity.uid, resume)


@router.post("/{resume_id}/finalize", response_model=ResumeSnapshot)
def finalize_resume(
    request: Request,
    resume_id: ResumeId,
    identity: Annotated[Identity, Depends(verified_identity)],
    command: ResumeVersion,
):
    private_storage(request)
    value = request.app.state.resume_store.queue(identity.uid, resume_id, command.expected_revision)
    if request.app.state.resume_worker is not None:
        request.app.state.resume_worker.wake()
    return value


@router.put("/{resume_id}/skills", response_model=ResumeSnapshot)
def confirm_resume_skills(
    request: Request,
    resume_id: ResumeId,
    identity: Annotated[Identity, Depends(verified_identity)],
    command: ConfirmResumeSkills,
):
    return request.app.state.resume_store.confirm(identity.uid, resume_id, command)


@router.post("/{resume_id}/retry", response_model=ResumeSnapshot)
def retry_resume(
    request: Request,
    resume_id: ResumeId,
    identity: Annotated[Identity, Depends(verified_identity)],
    command: ResumeVersion,
):
    private_storage(request)
    value = request.app.state.resume_store.retry(identity.uid, resume_id, command.expected_revision)
    if request.app.state.resume_worker is not None:
        request.app.state.resume_worker.wake()
    return value


@router.post("/{resume_id}/delete")
def delete_resume(
    request: Request,
    resume_id: ResumeId,
    identity: Annotated[Identity, Depends(verified_identity)],
    command: ResumeVersion,
):
    storage = private_storage(request)
    resume = request.app.state.resume_store.mark_deleting(
        identity.uid, resume_id, command.expected_revision
    )
    try:
        storage.erase(identity.uid, resume_id, resume.extension)
        request.app.state.resume_store.finish_delete(identity.uid, resume_id)
    except ResumeStorageFailure:
        return {"id": resume_id, "status": "deleting"}
    return {"id": resume_id, "status": "deleted"}
