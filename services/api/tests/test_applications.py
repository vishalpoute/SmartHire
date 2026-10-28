import copy

import pytest

from app.applications import ApplyInput, FirestoreApplicationStore
from app.errors import ApiError
from app.settings import Settings
from tests.test_matching import JOB_ID, RESUME_ID, command, match_fixture

HEADERS = {"Authorization": "Bearer one"}


def applications_fixture(monkeypatch):
    bundle = match_fixture(monkeypatch)
    bundle.database.data[("private_profiles", "one")] = {
        "display_name": "Fixture seeker",
        "headline": "Fixture headline",
        "location": "Fixture city",
        "skills": ["Unconfirmed profile skill"],
        "email": "never-return-this@example.invalid",
    }
    store = FirestoreApplicationStore(Settings(firebase_project_id="fixture"))
    store.client = bundle.database
    bundle.app.state.application_store = store
    bundle.applications = store
    return bundle


def submit(bundle, **changes):
    return bundle.client.post(
        f"/api/v1/jobs/{JOB_ID}/applications",
        headers=HEADERS,
        json=command(expected_job_version=2, **changes),
    )


def test_submission_pins_versions_is_duplicate_safe_and_minimizes_data(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    response = submit(bundle)
    assert response.status_code == 201
    value = response.json()
    assert value["status"] == "submitted" and value["revision"] == 1
    assert value["candidate"]["skills"] == ["Python", "Docker"]
    assert value["match"]["resume_version"] == 1
    assert value["match"]["job_version"] == value["job"]["version"] == 2
    assert value["job"]["title"] == "Fixture job"
    assert not {"seeker_uid", "recruiter_uid", "email", "text"} & value.keys()
    assert "never-return-this" not in response.text and "Private text" not in response.text
    assert submit(bundle).json() == value
    assert len([key for key in bundle.database.data if key[0] == "applications"]) == 1
    assert len([key for key in bundle.database.data if key[0] == "audit_events"]) == 1
    bundle.database.data[("resumes", RESUME_ID)] = {"parse_status": "deleted"}
    bundle.database.data[("jobs", JOB_ID)]["status"] = "closed"
    bundle.database.data[("private_profiles", "one")]["display_name"] = "Changed"
    assert bundle.client.get(f"/api/v1/applications/{value['id']}", headers=HEADERS).json() == value
    assert submit(bundle).json() == value
    assert submit(bundle, resume_id="d" * 32).status_code == 409


def test_seeker_tracking_foreign_owner_and_scope_isolation(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    assert bundle.client.get("/api/v1/applications", headers=HEADERS).json()["items"] == [value]
    other = {"Authorization": "Bearer two"}
    assert bundle.client.get("/api/v1/applications", headers=other).json()["items"] == []
    assert (
        bundle.client.get(f"/api/v1/applications/{value['id']}", headers=other).status_code == 404
    )
    assert (
        bundle.client.get("/api/v1/applications?scope=recruiter", headers=HEADERS).status_code
        == 403
    )
    assert bundle.client.get("/api/v1/applications").status_code == 401
    assert (
        bundle.client.get("/api/v1/applications?cursor=foreign/path", headers=HEADERS).status_code
        == 422
    )


def test_recruiter_transitions_are_versioned_and_audited(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    application_id = value["id"]
    current = bundle.applications.get_application("recruiter", application_id)
    from app.applications import ApplicationChange

    def transition(status, revision, reason=""):
        return bundle.applications.transition(
            "recruiter",
            application_id,
            ApplicationChange(status=status, expected_revision=revision, reason=reason),
        )

    with pytest.raises(ApiError) as error:
        transition("hired", 1)
    assert error.value.status == 409
    shortlisted = transition("shortlisted", current.revision)
    assert shortlisted.status == "shortlisted" and shortlisted.revision == 2
    with pytest.raises(ApiError) as error:
        transition("rejected", 1, "Fixture reason")
    assert error.value.status == 409
    hired = transition("hired", 2)
    assert hired.status == "hired" and hired.revision == 3
    with pytest.raises(ApiError):
        transition("rejected", 3, "Fixture reason")
    assert len([key for key in bundle.database.data if key[0] == "audit_events"]) == 3


def test_withdrawal_cannot_hire_and_terminal_states_cannot_change(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    path = f"/api/v1/applications/{value['id']}/status"
    assert (
        bundle.client.post(
            path, headers=HEADERS, json={"status": "hired", "expected_revision": 1}
        ).status_code
        == 409
    )
    result = bundle.client.post(
        path, headers=HEADERS, json={"status": "withdrawn", "expected_revision": 1}
    )
    assert result.status_code == 200 and result.json()["status"] == "withdrawn"
    assert (
        bundle.client.post(
            path, headers=HEADERS, json={"status": "withdrawn", "expected_revision": 2}
        ).status_code
        == 409
    )
    assert (
        bundle.client.post(
            path,
            headers={"Authorization": "Bearer two"},
            json={"status": "withdrawn", "expected_revision": 2},
        ).status_code
        == 404
    )


@pytest.mark.parametrize(
    "target,changes",
    [
        (("users", "recruiter"), {"recruiter_approved": False}),
        (("users", "recruiter"), {"account_status": "suspended"}),
        (("company_profiles", "recruiter"), {"approval_status": "pending"}),
        (("jobs", JOB_ID), {"company_owner_uid": "other"}),
    ],
)
def test_recruiter_candidate_access_revoked_with_server_state(monkeypatch, target, changes):
    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    bundle.database.data[target].update(changes)
    with pytest.raises(ApiError):
        bundle.applications.get_application("recruiter", value["id"])
    with pytest.raises(ApiError):
        bundle.applications.list_applications("recruiter", "recruiter", None)


def test_submission_requires_profile_fresh_confirmed_source_and_no_client_privileges(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    bundle.database.data.pop(("private_profiles", "one"))
    assert submit(bundle).status_code == 409
    assert not any(key[0] == "applications" for key in bundle.database.data)
    assert submit(bundle, expected_resume_revision=2).status_code == 409
    assert submit(bundle, recruiter_uid="one").status_code == 422
    assert submit(bundle, status="hired").status_code == 422
    body = command(expected_job_version=2)
    body.pop("expected_job_version")
    assert (
        bundle.client.post(
            f"/api/v1/jobs/{JOB_ID}/applications", headers=HEADERS, json=body
        ).status_code
        == 422
    )


def test_rejection_requires_reason_and_audit_failure_rolls_back(monkeypatch):
    from app.applications import ApplicationChange

    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    with pytest.raises(ApiError) as error:
        bundle.applications.transition(
            "recruiter", value["id"], ApplicationChange(status="rejected", expected_revision=1)
        )
    assert error.value.status == 422
    before = copy.deepcopy(bundle.database.data)

    def fail(*args):
        raise RuntimeError("Fixture audit failure")

    monkeypatch.setattr(bundle.applications, "audit", fail)
    with pytest.raises(ApiError) as error:
        bundle.applications.transition(
            "recruiter",
            value["id"],
            ApplicationChange(status="rejected", reason="Fixture reason", expected_revision=1),
        )
    assert error.value.status == 503 and bundle.database.data == before


def test_bounded_party_query_and_cursor(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    original = bundle.database.data[("applications", value["id"])]
    for index in range(12):
        bundle.database.data[("applications", f"{index:032x}")] = copy.deepcopy(original)
    first = bundle.applications.list_applications("one", "seeker", None)
    second = bundle.applications.list_applications("one", "seeker", first.next_cursor)
    assert len(first.items) == 10 and len(second.items) == 3
    assert not {row.id for row in first.items} & {row.id for row in second.items}
    assert second.next_cursor is None and bundle.database.limits[-2:] == [11, 11]


def test_transaction_rechecks_seeker_suspension(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    bundle.database.data[("users", "one")] = {"account_status": "suspended"}
    with pytest.raises(ApiError) as error:
        bundle.applications.submit("one", JOB_ID, ApplyInput(**command(expected_job_version=2)))
    assert error.value.status == 403


def test_terminal_application_removal_clears_snapshots_and_prevents_reapplication(monkeypatch):
    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    path = f"/api/v1/applications/{value['id']}"
    assert (
        bundle.client.post(
            path + "/delete", headers=HEADERS, json={"expected_revision": 1}
        ).status_code
        == 409
    )
    assert (
        bundle.client.post(
            path + "/status", headers=HEADERS, json={"expected_revision": 1, "status": "withdrawn"}
        ).status_code
        == 200
    )
    assert (
        bundle.client.post(
            path + "/delete", headers=HEADERS, json={"expected_revision": 1}
        ).status_code
        == 409
    )
    assert (
        bundle.client.post(
            path + "/delete", headers={"Authorization": "Bearer two"}, json={"expected_revision": 2}
        ).status_code
        == 404
    )
    result = bundle.client.post(path + "/delete", headers=HEADERS, json={"expected_revision": 2})
    assert result.json() == {"id": value["id"], "status": "deleted"}
    data = bundle.database.data[("applications", value["id"])]
    assert set(data) == {"status", "deleted_at"}
    assert bundle.client.get(path, headers=HEADERS).status_code == 404
    assert bundle.client.get("/api/v1/applications", headers=HEADERS).json()["items"] == []
    assert submit(bundle).status_code == 409
    assert ("resumes", RESUME_ID) in bundle.database.data


def test_recruiter_cannot_erase_candidate_application(monkeypatch):
    from app.applications import DeleteApplication

    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    with pytest.raises(ApiError) as error:
        bundle.applications.delete_application(
            "recruiter", value["id"], DeleteApplication(expected_revision=1)
        )
    assert error.value.status == 403
    assert bundle.applications.get_application("one", value["id"]).status == "submitted"


def test_removal_audit_failure_preserves_snapshot(monkeypatch):
    from app.applications import ApplicationChange, DeleteApplication

    bundle = applications_fixture(monkeypatch)
    value = submit(bundle).json()
    bundle.applications.transition(
        "one", value["id"], ApplicationChange(expected_revision=1, status="withdrawn")
    )
    before = copy.deepcopy(bundle.database.data)

    def fail(*args):
        raise RuntimeError("Fixture audit failure")

    monkeypatch.setattr(bundle.applications, "audit", fail)
    with pytest.raises(ApiError):
        bundle.applications.delete_application(
            "one", value["id"], DeleteApplication(expected_revision=2)
        )
    assert bundle.database.data == before
