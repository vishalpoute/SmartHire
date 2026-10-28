import hashlib
import io
from unittest.mock import Mock

import pytest

from app.resume_storage import MAX_BYTES, ResumeStorageFailure, S3ResumeStorage

OWNER = "fixture-owner"
RESUME = "a" * 32
DATA = b"nonpersonal storage fixture"
HASH = hashlib.sha256(DATA).hexdigest()


def storage():
    client = Mock()
    client.generate_presigned_url.return_value = "https://storage.example.com/signed-fixture"
    return S3ResumeStorage(client, "private-fixture"), client


def test_owner_keys_do_not_use_client_path_or_raw_identity():
    store, _ = storage()
    key = store.key("owner/../private", RESUME, "pdf")
    assert key.startswith("resumes/") and ".." not in key and "private" not in key
    assert key != store.key("other", RESUME, "pdf")
    with pytest.raises(ResumeStorageFailure):
        store.key(OWNER, "../other", "pdf")


def test_upload_is_short_lived_size_bound_and_create_only():
    store, client = storage()
    ticket = store.upload_ticket(OWNER, RESUME, "pdf", len(DATA), HASH)
    arguments = client.generate_presigned_url.call_args.kwargs
    assert arguments["ExpiresIn"] == 60 and arguments["HttpMethod"] == "PUT"
    assert arguments["Params"]["ContentLength"] == len(DATA)
    assert arguments["Params"]["IfNoneMatch"] == "*"
    assert ticket.headers["If-None-Match"] == "*"
    assert HASH == arguments["Params"]["Metadata"]["sha256"]
    assert "signed-fixture" not in repr(ticket)


@pytest.mark.parametrize(
    "size,digest", [(0, HASH), (MAX_BYTES + 1, HASH), (True, HASH), (1, "bad")]
)
def test_invalid_upload_does_not_create_a_signed_capability(size, digest):
    store, client = storage()
    with pytest.raises(ResumeStorageFailure):
        store.upload_ticket(OWNER, RESUME, "pdf", size, digest)
    client.generate_presigned_url.assert_not_called()


def test_download_checks_actual_bytes_hash_and_closes_stream():
    store, client = storage()
    client.head_object.return_value = {
        "ContentLength": len(DATA),
        "ContentType": "application/pdf",
        "Metadata": {"sha256": HASH},
    }
    body = io.BytesIO(DATA)
    client.get_object.return_value = {"Body": body}
    assert store.download_verified(OWNER, RESUME, "pdf", len(DATA), HASH) == DATA
    assert body.closed


def test_head_metadata_is_not_a_substitute_for_content_integrity():
    store, client = storage()
    client.head_object.return_value = {
        "ContentLength": len(DATA),
        "ContentType": "application/pdf",
        "Metadata": {"sha256": HASH},
    }
    body = io.BytesIO(b"x" * len(DATA))
    client.get_object.return_value = {"Body": body}
    with pytest.raises(ResumeStorageFailure) as error:
        store.download_verified(OWNER, RESUME, "pdf", len(DATA), HASH)
    assert error.value.code == "object_mismatch" and body.closed


def test_wrong_size_or_mime_is_rejected_before_downloading():
    store, client = storage()
    client.head_object.return_value = {"ContentLength": MAX_BYTES + 1}
    with pytest.raises(ResumeStorageFailure):
        store.download_verified(OWNER, RESUME, "pdf", len(DATA), HASH)
    client.get_object.assert_not_called()


def test_sdk_diagnostics_are_private_and_delete_is_owner_scoped():
    store, client = storage()
    client.head_object.side_effect = RuntimeError("private SDK URL and credentials")
    with pytest.raises(ResumeStorageFailure) as error:
        store.download_verified(OWNER, RESUME, "pdf", len(DATA), HASH)
    assert error.value.code == "storage_unavailable"
    store.delete(OWNER, RESUME, "pdf")
    client.delete_object.assert_called_once_with(
        Bucket="private-fixture", Key=store.key(OWNER, RESUME, "pdf")
    )


def test_erasure_removes_content_but_reserves_create_only_object_key():
    store, client = storage()
    store.erase(OWNER, RESUME, "pdf")
    options = client.put_object.call_args.kwargs
    assert options["Key"] == store.key(OWNER, RESUME, "pdf")
    assert options["Body"] == b"" and options["ContentLength"] == 0
    assert options["Metadata"] == {"deleted": "true"}
    client.delete_object.assert_not_called()
