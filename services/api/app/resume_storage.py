"""Private S3 access; object keys are derived from verified owners, never client paths."""

import hashlib
import hmac
import os
from dataclasses import dataclass
from urllib.parse import urlsplit

import boto3
from botocore.config import Config

from app.resume_parser import MAX_BYTES

MIME_TYPES = {
    "pdf": "application/pdf",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
}


class ResumeStorageFailure(Exception):
    def __init__(self, code="storage_unavailable"):
        self.code = code


@dataclass(frozen=True, repr=False)
class UploadTicket:
    url: str
    headers: dict[str, str]
    expires_in: int = 60


def valid_hex(value, length):
    return (
        isinstance(value, str)
        and len(value) == length
        and all(char in "0123456789abcdef" for char in value)
    )


class S3ResumeStorage:
    def __init__(self, client, bucket, *, prefix="resumes"):
        if not bucket or not prefix or prefix.startswith("/") or ".." in prefix.split("/"):
            raise ValueError("Invalid private storage configuration")
        self.client, self.bucket, self.prefix = client, bucket, prefix

    @classmethod
    def from_environment(cls):
        required = (
            "AWS_ACCESS_KEY_ID",
            "AWS_SECRET_ACCESS_KEY",
            "AWS_ENDPOINT_URL_S3",
            "AWS_REGION",
            "BUCKET_NAME",
        )
        if not all(os.environ.get(key) for key in required):
            raise ResumeStorageFailure()
        endpoint = urlsplit(os.environ["AWS_ENDPOINT_URL_S3"])
        if (
            endpoint.scheme != "https"
            or not endpoint.hostname
            or endpoint.username
            or endpoint.password
            or endpoint.query
            or endpoint.fragment
            or endpoint.path not in ("", "/")
        ):
            raise ResumeStorageFailure()
        client = boto3.client(
            "s3",
            endpoint_url=os.environ["AWS_ENDPOINT_URL_S3"],
            aws_access_key_id=os.environ["AWS_ACCESS_KEY_ID"],
            aws_secret_access_key=os.environ["AWS_SECRET_ACCESS_KEY"],
            region_name=os.environ["AWS_REGION"],
            config=Config(
                signature_version="s3v4",
                s3={"addressing_style": "path"},
                connect_timeout=5,
                read_timeout=15,
                retries={"total_max_attempts": 1},
                request_checksum_calculation="when_required",
                response_checksum_validation="when_required",
            ),
        )
        return cls(client, os.environ["BUCKET_NAME"])

    def key(self, owner_uid, resume_id, extension):
        if (
            not isinstance(owner_uid, str)
            or not 1 <= len(owner_uid) <= 128
            or not valid_hex(resume_id, 32)
            or extension not in MIME_TYPES
        ):
            raise ResumeStorageFailure("invalid_object")
        owner = hashlib.sha256(owner_uid.encode()).hexdigest()
        return f"{self.prefix}/{owner}/{resume_id}/source.{extension}"

    def upload_ticket(self, owner_uid, resume_id, extension, size, sha256):
        if type(size) is not int or not 1 <= size <= MAX_BYTES or not valid_hex(sha256, 64):
            raise ResumeStorageFailure("invalid_object")
        key = self.key(owner_uid, resume_id, extension)
        try:
            url = self.client.generate_presigned_url(
                "put_object",
                Params={
                    "Bucket": self.bucket,
                    "Key": key,
                    "ContentType": MIME_TYPES[extension],
                    "ContentLength": size,
                    "Metadata": {"sha256": sha256},
                    "IfNoneMatch": "*",
                },
                ExpiresIn=60,
                HttpMethod="PUT",
            )
            return UploadTicket(
                url,
                {
                    "Content-Type": MIME_TYPES[extension],
                    "x-amz-meta-sha256": sha256,
                    "If-None-Match": "*",
                },
            )
        except Exception:  # noqa: BLE001 - signed URLs and credentials must never enter diagnostics.
            raise ResumeStorageFailure() from None

    def download_verified(self, owner_uid, resume_id, extension, size, sha256):
        key = self.key(owner_uid, resume_id, extension)
        if type(size) is not int or not 1 <= size <= MAX_BYTES or not valid_hex(sha256, 64):
            raise ResumeStorageFailure("invalid_object")
        body = None
        try:
            head = self.client.head_object(Bucket=self.bucket, Key=key)
            if (
                head.get("ContentLength") != size
                or head.get("ContentType") != MIME_TYPES[extension]
                or head.get("Metadata", {}).get("sha256") != sha256
            ):
                raise ResumeStorageFailure("object_mismatch")
            response = self.client.get_object(Bucket=self.bucket, Key=key)
            body = response["Body"]
            data = body.read(MAX_BYTES + 1)
            if len(data) != size or not hmac.compare_digest(
                hashlib.sha256(data).hexdigest(), sha256
            ):
                raise ResumeStorageFailure("object_mismatch")
            return data
        except ResumeStorageFailure:
            raise
        except Exception:  # noqa: BLE001 - do not expose private paths, URLs or SDK errors.
            raise ResumeStorageFailure() from None
        finally:
            if body is not None:
                body.close()

    def erase(self, owner_uid, resume_id, extension):
        """Erase content but reserve the key so an old create-only upload cannot resurrect it."""
        key = self.key(owner_uid, resume_id, extension)
        try:
            self.client.put_object(
                Bucket=self.bucket,
                Key=key,
                Body=b"",
                ContentLength=0,
                ContentType="application/octet-stream",
                Metadata={"deleted": "true"},
            )
        except Exception:  # noqa: BLE001 - no credential or object diagnostics.
            raise ResumeStorageFailure() from None

    def delete(self, owner_uid, resume_id, extension):
        """Physical object cleanup for isolated fixtures; owner deletion uses erase()."""
        key = self.key(owner_uid, resume_id, extension)
        try:
            self.client.delete_object(Bucket=self.bucket, Key=key)
        except Exception:  # noqa: BLE001 - no credential or object diagnostics.
            raise ResumeStorageFailure() from None
