from unittest.mock import Mock

import pytest
from test_job_publication import fixtures, setup_transaction
from test_jobs import JOB_ID, client_for

from app.errors import ApiError
from app.jobs import JobClosure, closure_changes


def published_fixture():
    job, account, company = fixtures()
    job["status"] = "published"
    return job, account, company


def test_active_owner_can_close_after_recruiter_or_company_approval_is_revoked():
    job, account, _ = published_fixture()
    account.update(role="seeker", recruiter_approved=False)
    changes = closure_changes("one", JOB_ID, 3, job, account, None)
    assert changes["status"] == "closed" and changes["version"] == 4
    assert set(changes) == {"status", "version", "updated_at"}


@pytest.mark.parametrize(
    "changes,status",
    [
        ({"recruiter_uid": "other"}, 404),
        ({"status": "draft"}, 409),
        ({"status": "closed"}, 409),
        ({"status": "suspended"}, 409),
        ({"version": 4}, 409),
    ],
)
def test_foreign_stale_or_nonpublished_jobs_cannot_close(changes, status):
    job, account, company = published_fixture()
    job.update(changes)
    with pytest.raises(ApiError) as error:
        closure_changes("one", JOB_ID, 3, job, account, company)
    assert error.value.status == status


def test_suspension_race_blocks_transaction_and_audit(monkeypatch):
    job, account, _ = published_fixture()
    account["account_status"] = "suspended"
    store, _, transaction, _ = setup_transaction(monkeypatch, job=job, account=account)
    with client_for(store) as client:
        response = client.post(
            f"/api/v1/jobs/{JOB_ID}/close",
            json={"expected_version": 3},
            headers={"Authorization": "Bearer test"},
        )
    assert response.status_code == 403
    transaction.update.assert_not_called()
    transaction.create.assert_not_called()


def test_closure_transaction_preserves_content_and_audits_atomically(monkeypatch):
    job, _, _ = published_fixture()
    store, database, transaction, refs = setup_transaction(monkeypatch, job=job)
    result = store.close_owned("one", JOB_ID, 3)
    assert result == JobClosure(id=JOB_ID, version=4)
    database.transaction.assert_called_once_with(max_attempts=1)
    for collection in ["jobs", "users"]:
        refs[collection].get.assert_called_once_with(
            transaction=transaction, timeout=10, retry=None
        )
    refs["company_profiles"].get.assert_not_called()
    transaction.update.assert_called_once()
    assert transaction.update.call_args.args[1]["status"] == "closed"
    transaction.create.assert_called_once()
    event = transaction.create.call_args.args[1]
    assert event["action"] == "job.closed" and event["actor_uid"] == "one"
    assert "description" not in event


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"expected_version": "3"},
        {"expected_version": 0},
        {"expected_version": 3, "status": "closed"},
    ],
)
def test_closure_command_is_strict(body):
    jobs = Mock()
    with client_for(jobs) as client:
        assert (
            client.post(
                f"/api/v1/jobs/{JOB_ID}/close", json=body, headers={"Authorization": "Bearer test"}
            ).status_code
            == 422
        )
    jobs.close_owned.assert_not_called()


def test_http_close_uses_token_owner_even_without_current_approval():
    jobs = Mock()
    jobs.close_owned.return_value = JobClosure(id=JOB_ID, version=4)
    with client_for(jobs, role="seeker", approved=False, company_status=None) as client:
        response = client.post(
            f"/api/v1/jobs/{JOB_ID}/close?recruiter_uid=other",
            json={"expected_version": 3},
            headers={"Authorization": "Bearer test"},
        )
        assert response.json() == {"id": JOB_ID, "status": "closed", "version": 4}
        assert (
            client.post(f"/api/v1/jobs/{JOB_ID}/close", json={"expected_version": 3}).status_code
            == 401
        )
    jobs.close_owned.assert_called_once_with("one", JOB_ID, 3)
