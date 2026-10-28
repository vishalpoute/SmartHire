from datetime import UTC, datetime, timedelta
from unittest.mock import Mock

import pytest
from resume_fixtures import fixture_app

from app.accounts import Account
from app.resume_parser import ParseResult
from app.resumes import ParseOutcome
from app.skill_taxonomy import suggest_skills

HEADERS = {"Authorization": "Bearer one"}
OTHER = {"Authorization": "Bearer two"}
COMMAND = {"upload_id": "a" * 32, "extension": "pdf", "size": 100, "sha256": "b" * 64}


def upload(bundle, headers=HEADERS, command=None):
    response = bundle.client.post("/api/v1/resumes", headers=headers, json=command or COMMAND)
    assert response.status_code == 201
    return response.json()["resume"]


def queued(bundle):
    resume = upload(bundle)
    response = bundle.client.post(
        f"/api/v1/resumes/{resume['id']}/finalize",
        headers=HEADERS,
        json={"expected_revision": resume["revision"]},
    )
    assert response.status_code == 200
    return response.json()


def test_initialization_is_owner_bound_idempotent_and_budgeted(monkeypatch):
    bundle = fixture_app(monkeypatch)
    first = upload(bundle)
    assert upload(bundle)["id"] == first["id"]
    assert upload(bundle, OTHER)["id"] != first["id"]
    changed = bundle.client.post(
        "/api/v1/resumes", headers=HEADERS, json={**COMMAND, "sha256": "c" * 64}
    )
    assert changed.status_code == 409
    assert len([key for key in bundle.database.data if key[0] == "resumes"]) == 2
    assert all(key[0] != "users" for key in bundle.database.writes)


def test_missing_and_foreign_records_share_unavailable_response(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = upload(bundle)
    foreign = bundle.client.get(f"/api/v1/resumes/{resume['id']}", headers=OTHER)
    missing = bundle.client.get("/api/v1/resumes/" + "0" * 32, headers=OTHER)
    assert foreign.status_code == missing.status_code == 404
    assert foreign.json()["message"] == missing.json()["message"]
    response = bundle.client.get("/api/v1/resumes", headers=OTHER)
    assert response.json()["items"] == [] and response.headers["cache-control"] == "no-store"


@pytest.mark.parametrize(
    "change",
    [
        {"owner_uid": "two"},
        {"role": "admin"},
        {"storage_key": "foreign/key"},
        {"extension": "exe"},
        {"size": True},
        {"sha256": "invalid"},
    ],
)
def test_upload_rejects_forged_fields_and_bad_types(monkeypatch, change):
    bundle = fixture_app(monkeypatch)
    response = bundle.client.post("/api/v1/resumes", headers=HEADERS, json={**COMMAND, **change})
    assert response.status_code == 422 and not bundle.database.data
    assert not bundle.storage.tickets


def test_unconfigured_storage_rejects_before_metadata_creation(monkeypatch):
    bundle = fixture_app(monkeypatch, storage_enabled=False)
    response = bundle.client.post("/api/v1/resumes", headers=HEADERS, json=COMMAND)
    assert response.status_code == 503 and not bundle.database.data


def test_suspension_between_http_and_transaction_check_prevents_write(monkeypatch):
    bundle = fixture_app(monkeypatch)

    def suspend(uid):
        bundle.database.data[("users", uid)] = {"account_status": "suspended"}
        return Account(uid=uid)

    bundle.accounts.get = suspend
    response = bundle.client.post("/api/v1/resumes", headers=HEADERS, json=COMMAND)
    assert response.status_code == 403
    assert not [key for key in bundle.database.data if key[0] == "resumes"]


def test_owner_upload_budget_is_atomic_and_retries_do_not_consume_it(monkeypatch):
    bundle = fixture_app(monkeypatch)
    for index in range(5):
        upload(bundle, command={**COMMAND, "upload_id": f"{index:032x}"})
    upload(bundle, command={**COMMAND, "upload_id": f"{0:032x}"})
    response = bundle.client.post(
        "/api/v1/resumes", headers=HEADERS, json={**COMMAND, "upload_id": "f" * 32}
    )
    assert response.status_code == 429
    assert len([key for key in bundle.database.data if key[0] == "resumes"]) == 5


def test_worker_extracts_suggestions_without_confirming_or_disclosing_private_fields(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = queued(bundle)
    monkeypatch.setattr(
        "app.resume_worker.extract_resume",
        lambda *args: ParseResult("parsed", text="Flutter Python JavaScript private fixture"),
    )
    assert bundle.worker.process_one()
    value = bundle.client.get(f"/api/v1/resumes/{resume['id']}", headers=HEADERS).json()
    assert value["parse_status"] == "parsed" and value["confirmed_skills"] is None
    assert value["extracted_skills"] == ["Flutter", "Python", "JavaScript"]
    assert not {"text", "owner_uid", "lease_token", "lease_until", "storage_key"} & value.keys()
    confirmed = bundle.client.put(
        f"/api/v1/resumes/{resume['id']}/skills",
        headers=HEADERS,
        json={"expected_revision": value["revision"], "skills": ["Flutter", " flutter ", "Python"]},
    )
    assert confirmed.status_code == 200
    assert confirmed.json()["skills_version"] == 1
    assert confirmed.json()["confirmed_skills"] == ["Flutter", "Python"]
    stale = bundle.client.put(
        f"/api/v1/resumes/{resume['id']}/skills",
        headers=HEADERS,
        json={"expected_revision": value["revision"], "skills": ["Wrong stale input"]},
    )
    assert stale.status_code == 409


def test_unscored_documents_cannot_be_confirmed_or_retried_indefinitely(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = queued(bundle)
    monkeypatch.setattr(
        "app.resume_worker.extract_resume",
        lambda *args: ParseResult("unscored", error_code="empty_text"),
    )
    bundle.worker.process_one()
    value = bundle.store.get_owned("one", resume["id"])
    assert value.parse_status == "unscored" and value.confirmed_skills is None
    command = {"expected_revision": value.revision}
    assert (
        bundle.client.put(
            f"/api/v1/resumes/{value.id}/skills",
            headers=HEADERS,
            json={**command, "skills": ["Cannot silently score"]},
        ).status_code
        == 409
    )
    assert (
        bundle.client.post(
            f"/api/v1/resumes/{value.id}/retry", headers=HEADERS, json=command
        ).status_code
        == 409
    )


def test_storage_failure_stays_unscored_and_retry_preserves_attempt_budget(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = queued(bundle)
    bundle.storage.failure = "storage_unavailable"
    bundle.worker.process_one()
    value = bundle.store.get_owned("one", resume["id"])
    assert value.error_code == "storage_unavailable"
    response = bundle.client.post(
        f"/api/v1/resumes/{value.id}/retry",
        headers=HEADERS,
        json={"expected_revision": value.revision},
    )
    assert response.status_code == 200 and response.json()["parse_status"] == "queued"
    assert bundle.database.data[("resumes", value.id)]["attempts"] == 1


def test_old_lease_cannot_overwrite_new_processing_or_delete(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = queued(bundle)
    first = bundle.store.claim(resume["id"])
    assert bundle.store.claim(resume["id"]) is None
    bundle.database.data[("resumes", resume["id"])]["lease_until"] = datetime.now(UTC) - timedelta(
        seconds=1
    )
    second = bundle.store.claim(resume["id"])
    outcome = {"parse_status": "parsed", "text": "Nonpersonal current text"}
    assert not bundle.store.finish(resume["id"], first["lease_token"], outcome)
    current = bundle.store.get_owned("one", resume["id"])
    bundle.store.mark_deleting("one", current.id, current.revision)
    assert not bundle.store.finish(resume["id"], second["lease_token"], outcome)
    bundle.store.finish_delete("one", resume["id"])
    assert not bundle.store.finish(resume["id"], second["lease_token"], outcome)


def test_exhausted_processing_clears_content_and_advances_revision(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = queued(bundle)
    data = bundle.database.data[("resumes", resume["id"])]
    data.update(attempts=3, text="stale text", extracted_skills=["Python"])
    revision = data["revision"]
    assert bundle.store.claim(resume["id"]) is None
    current = bundle.database.data[("resumes", resume["id"])]
    assert current["parse_status"] == "unscored"
    assert current["error_code"] == "resource_limit"
    assert current["revision"] == revision + 1
    assert current["text"] is None and current["extracted_skills"] == []


def test_missing_or_malformed_lease_cannot_finish_processing(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = queued(bundle)
    bundle.store.claim(resume["id"])
    data = bundle.database.data[("resumes", resume["id"])]
    data.pop("lease_token")
    for lease in (None, "", "invalid", 123):
        assert not bundle.store.finish(resume["id"], lease, {"parse_status": "parsed"})
    assert data["parse_status"] == "processing"


def test_expired_upload_cleanup_works_for_suspended_owner(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = upload(bundle)
    data = bundle.database.data[("resumes", resume["id"])]
    data["created_at"] = datetime.now(UTC) - timedelta(minutes=16)
    bundle.database.data[("users", "one")] = {"account_status": "suspended"}
    assert bundle.worker.process_one()
    assert bundle.database.data[("resumes", resume["id"])]["parse_status"] == "deleted"
    assert "owner_uid" not in bundle.database.data[("resumes", resume["id"])]
    assert bundle.storage.deleted == [("one", resume["id"], "pdf")]


def test_delete_clears_content_before_storage_and_survives_failure(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = upload(bundle)
    bundle.database.data[("resumes", resume["id"])]["text"] = "private fixture"
    bundle.storage.failure = "storage_unavailable"
    response = bundle.client.post(
        f"/api/v1/resumes/{resume['id']}/delete",
        headers=HEADERS,
        json={"expected_revision": resume["revision"]},
    )
    assert response.json()["status"] == "deleting"
    assert bundle.database.data[("resumes", resume["id"])]["text"] is None
    bundle.storage.failure = None
    bundle.worker.process_one()
    assert bundle.database.data[("resumes", resume["id"])]["parse_status"] == "deleted"
    assert set(bundle.database.data[("resumes", resume["id"])]) == {"parse_status", "deleted_at"}


def test_worker_result_cannot_assign_confirmed_skills_or_change_ownership():
    with pytest.raises(ValueError):
        ParseOutcome.model_validate({"parse_status": "confirmed", "confirmed_skills": ["Flutter"]})
    with pytest.raises(ValueError):
        ParseOutcome.model_validate(
            {"parse_status": "parsed", "text": "fixture", "owner_uid": "other"}
        )


def test_removed_resume_id_cannot_be_reused_for_new_content(monkeypatch):
    bundle = fixture_app(monkeypatch)
    resume = upload(bundle)
    removed = bundle.client.post(
        f"/api/v1/resumes/{resume['id']}/delete",
        headers=HEADERS,
        json={"expected_revision": resume["revision"]},
    )
    assert removed.json()["status"] == "deleted"
    replay = bundle.client.post(
        "/api/v1/resumes", headers=HEADERS, json={**COMMAND, "sha256": "c" * 64}
    )
    assert replay.status_code == 409
    assert bundle.client.get(f"/api/v1/resumes/{resume['id']}", headers=HEADERS).status_code == 404
    assert bundle.client.get("/api/v1/resumes", headers=HEADERS).json()["items"] == []


def test_taxonomy_suggestions_do_not_match_java_inside_javascript():
    assert suggest_skills("JavaScript PostgreSQL C++ C# Fast API") == [
        "FastAPI",
        "JavaScript",
        "C++",
        "C#",
        "PostgreSQL",
    ]


def test_resume_routes_require_identity_and_cursor_validation(monkeypatch):
    bundle = fixture_app(monkeypatch)
    assert bundle.client.get("/api/v1/resumes").status_code == 401
    assert bundle.client.get("/api/v1/resumes?cursor=../bad", headers=HEADERS).status_code == 422
    assert bundle.client.get("/api/v1/resumes/invalid", headers=HEADERS).status_code == 422


def test_worker_lifecycle_is_managed_by_application_lifespan(monkeypatch):
    bundle = fixture_app(monkeypatch)
    worker = Mock()
    bundle.app.state.resume_worker = worker
    with bundle.client:
        worker.start.assert_called_once()
        worker.stop.assert_not_called()
    worker.stop.assert_called_once()
