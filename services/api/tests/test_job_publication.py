from unittest.mock import Mock

import pytest
from google.api_core.exceptions import Aborted
from test_jobs import BODY, JOB_ID, NOW, client_for

from app.errors import ApiError
from app.jobs import FirestoreJobStore, JobDraft, JobDraftInput, JobPublication, publication_changes
from app.settings import Settings


def fixtures():
    job = JobDraft(
        id=JOB_ID,
        recruiter_uid="one",
        company_owner_uid="one",
        status="draft",
        version=3,
        created_at=NOW,
        updated_at=NOW,
        **JobDraftInput(
            **{**BODY, "description": "Build a maintained Flutter application."}
        ).model_dump(),
    )
    account = {"role": "recruiter", "account_status": "active", "recruiter_approved": True}
    company = {"name": "Demo Company", "approval_status": "approved", "updated_at": NOW}
    return job.model_dump(exclude={"id"}), account, company


def test_publication_versions_and_snapshots_server_company_name():
    changes = publication_changes("one", JOB_ID, 3, *fixtures())
    assert changes["version"] == 4 and changes["status"] == "published"
    assert changes["company_name"] == "Demo Company"
    assert not {"recruiter_uid", "company_owner_uid", "created_at"} & changes.keys()


@pytest.mark.parametrize(
    "kind,fields,status",
    [
        ("job", {"recruiter_uid": "other"}, 404),
        ("job", {"company_owner_uid": "other"}, 503),
        ("job", {"status": "published"}, 409),
        ("job", {"version": 4}, 409),
        ("job", {"description": "short"}, 422),
        ("job", {"required_skills": []}, 422),
        ("job", {"preferred_skills": ["dart"]}, 422),
        ("job", {"work_mode": "onsite", "location": ""}, 422),
        ("account", {"account_status": "suspended"}, 403),
        ("account", {"role": "seeker"}, 403),
        ("account", {"recruiter_approved": False}, 403),
        ("company", {"approval_status": "pending"}, 403),
        ("company", {"approval_status": "rejected"}, 403),
    ],
)
def test_publication_policy_rejects_stale_incomplete_or_unapproved_state(kind, fields, status):
    job, account, company = fixtures()
    {"job": job, "account": account, "company": company}[kind].update(fields)
    if status == 503:
        with pytest.raises(ValueError):
            publication_changes("one", JOB_ID, 3, job, account, company)
    else:
        with pytest.raises(ApiError) as error:
            publication_changes("one", JOB_ID, 3, job, account, company)
        assert error.value.status == status


def setup_transaction(monkeypatch, job=None, account=None, company=None):
    data = fixtures()
    records = {
        "jobs": data[0] if job is None else job,
        "users": data[1] if account is None else account,
        "company_profiles": data[2] if company is None else company,
    }
    database, transaction = Mock(), Mock()
    refs = {}
    for collection, body in records.items():
        ref = Mock()
        ref.get.return_value = Mock(exists=True, to_dict=lambda body=body: body)
        refs[collection] = ref
    refs["audit_events"] = Mock()
    database.collection.side_effect = lambda name: Mock(document=Mock(return_value=refs[name]))
    database.transaction.return_value = transaction
    monkeypatch.setattr("app.jobs.firestore.Client", Mock(return_value=database))
    monkeypatch.setattr("app.jobs.firestore.transactional", lambda operation: operation)
    return (
        FirestoreJobStore(Settings(firebase_project_id="demo-smarthire")),
        database,
        transaction,
        refs,
    )


def test_transaction_reads_all_authorization_state_and_writes_one_audit(monkeypatch):
    store, database, transaction, refs = setup_transaction(monkeypatch)
    result = store.publish_owned("one", JOB_ID, 3)
    assert result.version == 4
    database.transaction.assert_called_once_with(max_attempts=1)
    for name in ["jobs", "users", "company_profiles"]:
        refs[name].get.assert_called_once_with(transaction=transaction, timeout=10, retry=None)
    transaction.update.assert_called_once()
    assert transaction.update.call_args.args[0] is refs["jobs"]
    transaction.create.assert_called_once()
    event = transaction.create.call_args.args[1]
    assert event["action"] == "job.published" and event["actor_uid"] == "one"
    assert event["job_id"] == JOB_ID and event["version"] == 4
    assert "description" not in event


def test_approval_revoked_between_http_precheck_and_transaction_blocks_every_write(monkeypatch):
    store, _, transaction, _ = setup_transaction(
        monkeypatch,
        account={"role": "recruiter", "recruiter_approved": False, "account_status": "active"},
    )
    # The outer API dependency sees approved state; the authoritative transaction does not.
    with client_for(store) as client:
        response = client.post(
            f"/api/v1/jobs/{JOB_ID}/publish",
            json={"expected_version": 3},
            headers={"Authorization": "Bearer test"},
        )
    assert response.status_code == 403
    transaction.update.assert_not_called()
    transaction.create.assert_not_called()


def test_sdk_exhausted_transaction_conflict_returns_safe_409(monkeypatch):
    store, _, _, _ = setup_transaction(monkeypatch)

    def decorator(operation):
        def execute(transaction):
            raise ValueError("private retry details") from Aborted("private datastore conflict")

        return execute

    monkeypatch.setattr("app.jobs.firestore.transactional", decorator)
    with pytest.raises(ApiError) as error:
        store.publish_owned("one", JOB_ID, 3)
    assert error.value.status == 409 and "private" not in error.value.message


@pytest.mark.parametrize(
    "body",
    [
        {},
        {"expected_version": "3"},
        {"expected_version": 0},
        {"expected_version": 3, "status": "published"},
    ],
)
def test_publication_command_cannot_supply_lifecycle_fields(body):
    jobs = Mock()
    with client_for(jobs) as client:
        assert (
            client.post(
                f"/api/v1/jobs/{JOB_ID}/publish",
                json=body,
                headers={"Authorization": "Bearer test"},
            ).status_code
            == 422
        )
    jobs.publish_owned.assert_not_called()


def test_http_publication_receipt_does_not_claim_a_client_timestamp():
    jobs = Mock()
    jobs.publish_owned.return_value = JobPublication(id=JOB_ID, version=4)
    with client_for(jobs) as client:
        response = client.post(
            f"/api/v1/jobs/{JOB_ID}/publish?recruiter_uid=other",
            json={"expected_version": 3},
            headers={"Authorization": "Bearer test"},
        )
    assert response.status_code == 200
    assert response.json() == {"id": JOB_ID, "status": "published", "version": 4}
    jobs.publish_owned.assert_called_once_with("one", JOB_ID, 3)
