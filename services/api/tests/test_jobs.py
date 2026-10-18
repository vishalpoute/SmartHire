from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from test_api import Verifier

from app.accounts import Account
from app.companies import CompanyProfile
from app.errors import ApiError
from app.jobs import FirestoreJobStore, JobDraft, JobDraftInput, JobDraftUpdate
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


def firestore_edit_store(monkeypatch, **changes):
    document = Mock()
    data = JobDraft(
        id=JOB_ID,
        recruiter_uid="one",
        company_owner_uid="one",
        status="draft",
        version=1,
        created_at=NOW,
        updated_at=NOW,
        **JobDraftInput(**BODY).model_dump(),
    ).model_dump(exclude={"id"})
    data.update(changes)
    document.get.return_value = SimpleNamespace(exists=True, update_time=NOW, to_dict=lambda: data)
    document.update.return_value = SimpleNamespace(update_time=NOW)
    database = Mock()
    database.collection.return_value.document.return_value = document
    monkeypatch.setattr("app.jobs.firestore.Client", Mock(return_value=database))
    return FirestoreJobStore(Settings(firebase_project_id="demo-smarthire")), document


def test_owned_draft_edit_increments_version_and_preserves_server_metadata(monkeypatch):
    from google.cloud.firestore_v1.types import Write

    store, document = firestore_edit_store(monkeypatch)
    result = store.update_owned(
        "one", JOB_ID, JobDraftUpdate(title="Updated role", expected_version=1)
    )
    assert result.title == "Updated role" and result.version == 2
    assert result.created_at == NOW and result.recruiter_uid == "one"
    payload = document.update.call_args.args[0]
    assert payload["version"] == 2 and payload["description"] == ""
    assert (
        not {"recruiter_uid", "company_owner_uid", "created_at", "status", "expected_version"}
        & payload.keys()
    )
    kwargs = document.update.call_args.kwargs
    assert kwargs["timeout"] == 10 and kwargs["retry"] is None
    write = Write()
    kwargs["option"].modify_write(write)
    assert write.current_document.update_time == NOW


@pytest.mark.parametrize(
    "changes,status",
    [
        ({"recruiter_uid": "other"}, 404),
        ({"status": "published"}, 409),
        ({"version": 2}, 409),
        ({"version": "1"}, 503),
        ({"company_owner_uid": "other"}, 503),
    ],
)
def test_stale_foreign_or_noneditable_draft_never_writes(monkeypatch, changes, status):
    store, document = firestore_edit_store(monkeypatch, **changes)
    with pytest.raises(ApiError) as error:
        store.update_owned("one", JOB_ID, JobDraftUpdate(title="Updated role", expected_version=1))
    assert error.value.status == status
    document.update.assert_not_called()


def test_concurrent_firestore_edits_allow_only_one_snapshot_to_commit(monkeypatch):
    from concurrent.futures import ThreadPoolExecutor
    from datetime import timedelta
    from threading import Barrier, Lock

    from google.api_core.exceptions import FailedPrecondition
    from google.cloud.firestore_v1.types import Write

    store, _ = firestore_edit_store(monkeypatch)
    initial = JobDraft(
        id=JOB_ID,
        recruiter_uid="one",
        company_owner_uid="one",
        status="draft",
        version=1,
        created_at=NOW,
        updated_at=NOW,
        **JobDraftInput(**BODY).model_dump(),
    ).model_dump(exclude={"id"})
    state = {"data": initial, "time": NOW}
    barrier, lock = Barrier(2), Lock()

    class Document:
        def get(self, **kwargs):
            with lock:
                data, timestamp = dict(state["data"]), state["time"]
            barrier.wait(timeout=5)
            return SimpleNamespace(exists=True, update_time=timestamp, to_dict=lambda: data)

        def update(self, data, option, **kwargs):
            write = Write()
            option.modify_write(write)
            with lock:
                if write.current_document.update_time != state["time"]:
                    raise FailedPrecondition("Concurrent write")
                state["time"] += timedelta(seconds=1)
                state["data"].update(data)
                state["data"]["updated_at"] = state["time"]
                return SimpleNamespace(update_time=state["time"])

    store.client = Mock()
    store.client.collection.return_value.document.return_value = Document()

    def edit(title):
        try:
            return store.update_owned(
                "one", JOB_ID, JobDraftUpdate(title=title, expected_version=1)
            ).version
        except ApiError as error:
            return error.status

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(edit, ["First editor", "Second editor"]))
    assert sorted(results) == [2, 409]
    assert state["data"]["version"] == 2


@pytest.mark.parametrize(
    "options",
    [
        {"role": "seeker"},
        {"approved": False},
        {"company_status": "pending"},
        {"suspended": True},
        {"verified": False},
    ],
)
def test_http_draft_edit_requires_current_recruiter_and_company_approval(options):
    jobs = Jobs()
    with client_for(jobs, **options) as client:
        assert (
            client.put(
                f"/api/v1/jobs/{JOB_ID}",
                json={**BODY, "expected_version": 1},
                headers={"Authorization": "Bearer test"},
            ).status_code
            == 403
        )
    assert jobs.calls == []


@pytest.mark.parametrize(
    "fields",
    [
        {},
        {"expected_version": 0},
        {"expected_version": "1"},
        {"expected_version": 1, "recruiter_uid": "other"},
    ],
)
def test_edit_version_is_required_strict_and_cannot_select_owner(fields):
    jobs = Jobs()
    with client_for(jobs) as client:
        assert (
            client.put(
                f"/api/v1/jobs/{JOB_ID}",
                json={**BODY, **fields},
                headers={"Authorization": "Bearer test"},
            ).status_code
            == 422
        )
    assert jobs.calls == []


def test_http_owned_draft_edit_uses_authenticated_uid(monkeypatch):
    store, _ = firestore_edit_store(monkeypatch)
    with client_for(store) as client:
        response = client.put(
            f"/api/v1/jobs/{JOB_ID}?recruiter_uid=other",
            json={**BODY, "expected_version": 1},
            headers={"Authorization": "Bearer test"},
        )
    assert response.status_code == 200
    assert response.json()["version"] == 2 and response.json()["recruiter_uid"] == "one"
