from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from test_api import Verifier

from app.accounts import Account
from app.companies import CompanyProfile
from app.jobs import FirestoreJobStore, JobDraft, JobDraftInput
from app.main import create_app
from app.settings import Settings

NOW = datetime(2026, 10, 18, tzinfo=UTC)
JOB_ID = "a" * 32
BODY = {"title": "Flutter Developer", "work_mode": "remote", "required_skills": [" Dart ", "dart"]}


class Jobs:
    def __init__(self):
        self.data = {}
        self.calls = []

    def create(self, uid, draft):
        self.calls.append(("create", uid))
        job = JobDraft(
            id=JOB_ID,
            status="draft",
            version=1,
            recruiter_uid=uid,
            company_owner_uid=uid,
            created_at=NOW,
            updated_at=NOW,
            **draft.model_dump(),
        )
        self.data[JOB_ID] = job
        return job

    def get_owned(self, uid, job_id):
        self.calls.append(("get", uid))
        job = self.data.get(job_id)
        return job if job and job.recruiter_uid == uid else None


def client_for(
    jobs,
    uid="one",
    role="recruiter",
    approved=True,
    company_status="approved",
    verified=True,
    suspended=False,
):
    accounts = Mock()
    accounts.get.return_value = Account(
        uid=uid,
        role=role,
        recruiter_approved=approved,
        account_status="suspended" if suspended else "active",
    )
    companies = Mock()
    companies.get.return_value = (
        None
        if company_status is None
        else CompanyProfile(
            owner_uid=uid, name="Demo company", approval_status=company_status, updated_at=NOW
        )
    )
    return TestClient(
        create_app(
            Settings(),
            account_store=accounts,
            company_store=companies,
            job_store=jobs,
            token_verifier=Verifier(
                {
                    "uid": uid,
                    "email_verified": verified,
                    "role": "recruiter",
                    "recruiter_approved": True,
                }
            ),
        )
    )


def test_approved_recruiter_creates_private_owned_normalized_draft():
    jobs = Jobs()
    with client_for(jobs) as client:
        headers = {"Authorization": "Bearer test"}
        response = client.post("/api/v1/jobs?recruiter_uid=other", json=BODY, headers=headers)
        assert response.status_code == 201
        data = response.json()
        assert data["recruiter_uid"] == data["company_owner_uid"] == "one"
        assert data["status"] == "draft" and data["version"] == 1
        assert data["required_skills"] == ["Dart"]
        assert client.get(f"/api/v1/jobs/{JOB_ID}", headers=headers).json() == data
    with client_for(jobs, uid="other") as client:
        assert (
            client.get(f"/api/v1/jobs/{JOB_ID}?recruiter_uid=one", headers=headers).status_code
            == 404
        )


@pytest.mark.parametrize(
    "options",
    [
        {"role": "seeker"},
        {"role": "admin"},
        {"approved": False},
        {"company_status": "pending"},
        {"company_status": "rejected"},
        {"company_status": None},
        {"verified": False},
        {"suspended": True},
    ],
)
def test_unapproved_or_inactive_callers_cannot_create_drafts(options):
    jobs = Jobs()
    with client_for(jobs, **options) as client:
        response = client.post("/api/v1/jobs", json=BODY, headers={"Authorization": "Bearer test"})
        assert response.status_code == 403
    assert jobs.calls == []


@pytest.mark.parametrize(
    "extra", ["id", "recruiter_uid", "company_owner_uid", "status", "version", "created_at"]
)
def test_client_cannot_assign_draft_ownership_or_lifecycle(extra):
    jobs = Jobs()
    with client_for(jobs) as client:
        response = client.post(
            "/api/v1/jobs",
            json={**BODY, extra: "spoofed"},
            headers={"Authorization": "Bearer test"},
        )
        assert response.status_code == 422
        assert "spoofed" not in response.text
    assert jobs.calls == []


@pytest.mark.parametrize(
    "fields",
    [
        {"title": " "},
        {"title": "x" * 121},
        {"description": "x" * 12001},
        {"work_mode": "unknown"},
        {"employment_type": "unknown"},
        {"required_skills": ["x"] * 31},
        {"required_skills": [""]},
        {"preferred_skills": [12]},
    ],
)
def test_invalid_draft_never_reaches_storage(fields):
    jobs = Jobs()
    with client_for(jobs) as client:
        assert (
            client.post(
                "/api/v1/jobs", json={**BODY, **fields}, headers={"Authorization": "Bearer test"}
            ).status_code
            == 422
        )
    assert jobs.calls == []


def test_missing_auth_and_invalid_ids_do_not_reach_storage():
    jobs = Jobs()
    with client_for(jobs) as client:
        assert client.post("/api/v1/jobs", json=BODY).status_code == 401
        assert (
            client.get(
                "/api/v1/jobs/not-a-valid-id", headers={"Authorization": "Bearer test"}
            ).status_code
            == 422
        )
    assert jobs.calls == []


def test_firestore_create_uses_generated_id_and_server_metadata(monkeypatch):
    document = Mock(id=JOB_ID)
    document.create.return_value = SimpleNamespace(update_time=NOW)
    database = Mock()
    database.collection.return_value.document.return_value = document
    monkeypatch.setattr("app.jobs.firestore.Client", Mock(return_value=database))
    store = FirestoreJobStore(Settings(firebase_project_id="demo-smarthire"))
    result = store.create("one", JobDraftInput(**BODY))
    assert result.status == "draft" and result.version == 1
    assert result.id == JOB_ID
    data = document.create.call_args.args[0]
    assert data["recruiter_uid"] == data["company_owner_uid"] == "one"
    assert data["status"] == "draft" and data["version"] == 1
    assert document.create.call_args.kwargs == {"timeout": 10, "retry": None}
    document.get.return_value = SimpleNamespace(
        exists=True,
        to_dict=lambda: {
            **result.model_dump(exclude={"id"}),
            "internal_note": "private diagnostics",
        },
    )
    assert store.get_owned("one", JOB_ID).id == JOB_ID
    assert store.get_owned("other", JOB_ID) is None
    database.collection.assert_called_with("jobs")


def test_datastore_failure_is_safe(monkeypatch):
    monkeypatch.setattr(
        "app.jobs.firestore.Client", Mock(side_effect=ValueError("private credentials"))
    )
    jobs = FirestoreJobStore(Settings(firebase_project_id="demo-smarthire"))
    with client_for(jobs) as client:
        response = client.post("/api/v1/jobs", json=BODY, headers={"Authorization": "Bearer test"})
        assert response.status_code == 503
        assert "private" not in response.text


@pytest.mark.parametrize("options", [{"verified": False}, {"suspended": True}])
def test_private_job_reads_require_verified_active_identity(options):
    jobs = Jobs()
    with client_for(jobs, **options) as client:
        assert (
            client.get(
                f"/api/v1/jobs/{JOB_ID}", headers={"Authorization": "Bearer test"}
            ).status_code
            == 403
        )
    assert jobs.calls == []
