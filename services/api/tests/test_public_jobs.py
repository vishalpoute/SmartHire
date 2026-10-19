from unittest.mock import Mock

import pytest
from test_job_publication import fixtures, setup_transaction
from test_jobs import JOB_ID, NOW, client_for

from app.errors import ApiError


def published_fixture():
    job, account, company = fixtures()
    job.update(status="published", published_at=NOW, company_name="Demo Company")
    job["private_note"] = "never public"
    return job, account, company


def test_public_detail_needs_no_login_and_never_exposes_owners(monkeypatch):
    job, _, _ = published_fixture()
    store, database, transaction, refs = setup_transaction(monkeypatch, job=job)
    with client_for(store) as client:
        response = client.get(f"/api/v1/public/jobs/{JOB_ID}")
    assert response.status_code == 200
    body = response.json()
    assert body["company_name"] == "Demo Company" and body["id"] == JOB_ID
    assert set(body) == {
        "id",
        "company_name",
        "published_at",
        "title",
        "description",
        "location",
        "work_mode",
        "employment_type",
        "required_skills",
        "preferred_skills",
    }
    assert "never public" not in response.text
    assert response.headers["cache-control"] == "no-store"
    database.transaction.assert_called_once_with(max_attempts=1)
    for collection in ["jobs", "users", "company_profiles"]:
        refs[collection].get.assert_called_once_with(
            transaction=transaction, timeout=10, retry=None
        )
    transaction.update.assert_not_called()
    transaction.create.assert_not_called()


@pytest.mark.parametrize(
    "kind,changes",
    [
        ("job", {"status": "draft"}),
        ("job", {"status": "closed"}),
        ("job", {"status": "suspended"}),
        ("account", {"account_status": "suspended"}),
        ("account", {"role": "seeker"}),
        ("account", {"recruiter_approved": False}),
        ("company", {"approval_status": "pending"}),
        ("company", {"approval_status": "rejected"}),
    ],
)
def test_public_visibility_tracks_current_moderation(monkeypatch, kind, changes):
    job, account, company = published_fixture()
    {"job": job, "account": account, "company": company}[kind].update(changes)
    store, _, _, _ = setup_transaction(monkeypatch, job=job, account=account, company=company)
    with client_for(store) as client:
        response = client.get(f"/api/v1/public/jobs/{JOB_ID}")
    assert response.status_code == 404
    assert response.json()["message"] == "Job is unavailable."


@pytest.mark.parametrize("missing", ["jobs", "users", "company_profiles"])
def test_missing_records_do_not_publish_partial_data(monkeypatch, missing):
    job, _, _ = published_fixture()
    store, _, _, refs = setup_transaction(monkeypatch, job=job)
    refs[missing].get.return_value.exists = False
    assert store.get_public(JOB_ID) is None


@pytest.mark.parametrize(
    "changes",
    [
        {"company_owner_uid": "different"},
        {"published_at": None},
        {"company_name": None},
        {"version": "bad"},
    ],
)
def test_corrupt_public_records_fail_closed(monkeypatch, changes):
    job, _, _ = published_fixture()
    job.update(changes)
    store, _, _, _ = setup_transaction(monkeypatch, job=job)
    with pytest.raises(ApiError) as error:
        store.get_public(JOB_ID)
    assert error.value.status == 503
    assert "different" not in error.value.message


def test_datastore_outage_does_not_expose_diagnostics(monkeypatch):
    job, _, _ = published_fixture()
    store, _, _, refs = setup_transaction(monkeypatch, job=job)
    refs["users"].get.side_effect = RuntimeError("private credentials")
    with client_for(store) as client:
        response = client.get(f"/api/v1/public/jobs/{JOB_ID}")
    assert response.status_code == 503 and "credentials" not in response.text


def test_invalid_id_cannot_select_a_firestore_path():
    store = Mock()
    with client_for(store) as client:
        assert client.get("/api/v1/public/jobs/not-a-document").status_code == 422
    store.get_public.assert_not_called()


def test_shared_anonymous_budget_bounds_reads_and_exposes_retry():
    store = Mock()
    store.get_public.return_value = None
    with client_for(store) as client:
        client.app.state.public_job_limiter.limit = 1
        assert client.get(f"/api/v1/public/jobs/{JOB_ID}").status_code == 404
        response = client.get(
            f"/api/v1/public/jobs/{JOB_ID}", headers={"X-Forwarded-For": "forged-address"}
        )
        assert response.status_code == 429 and int(response.headers["retry-after"]) >= 1
        assert response.json()["code"] == "jobs_busy"
    store.get_public.assert_called_once_with(JOB_ID)
