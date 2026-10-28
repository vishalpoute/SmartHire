import copy

import pytest

from app.errors import ApiError
from app.moderation import FirestoreModerationStore, ModerationCommand
from app.settings import Settings
from tests.test_matching import JOB_ID, match_fixture


def moderation_fixture(monkeypatch):
    bundle = match_fixture(monkeypatch)
    bundle.database.data[("users", "one")] = {"role": "admin", "account_status": "active"}
    store = FirestoreModerationStore(Settings(firebase_project_id="fixture"))
    store.client = bundle.database
    bundle.app.state.moderation_store = store
    bundle.moderation = store
    return bundle


def test_suspension_and_restore_draft_are_versioned_and_audited(monkeypatch):
    bundle = moderation_fixture(monkeypatch)
    assert bundle.moderation.jobs("one", "published", None).items[0].id == JOB_ID
    first = bundle.moderation.moderate(
        "one",
        JOB_ID,
        ModerationCommand(expected_version=2, action="suspend", reason="Fixture moderation reason"),
    )
    assert first.status == "suspended" and first.version == 3
    assert bundle.moderation.jobs("one", "published", None).items == []
    assert bundle.moderation.jobs("one", "suspended", None).items[0].version == 3
    with pytest.raises(ApiError) as error:
        bundle.moderation.moderate(
            "one",
            JOB_ID,
            ModerationCommand(
                expected_version=2, action="restore_draft", reason="Fixture stale reason"
            ),
        )
    assert error.value.status == 409
    second = bundle.moderation.moderate(
        "one",
        JOB_ID,
        ModerationCommand(
            expected_version=3, action="restore_draft", reason="Fixture restored for review"
        ),
    )
    assert second.status == "draft" and second.version == 4
    audits = bundle.moderation.audits("one", None)
    assert len(audits.items) == 2
    assert {row.action for row in audits.items} == {"job.suspend", "job.restore_draft"}


@pytest.mark.parametrize(
    "account", [{}, {"role": "recruiter"}, {"role": "admin", "account_status": "suspended"}]
)
def test_server_state_required_for_every_admin_operation(monkeypatch, account):
    bundle = moderation_fixture(monkeypatch)
    bundle.database.data[("users", "one")] = account
    for operation in [
        lambda: bundle.moderation.jobs("one", "published", None),
        lambda: bundle.moderation.audits("one", None),
        lambda: bundle.moderation.moderate(
            "one",
            JOB_ID,
            ModerationCommand(expected_version=2, action="suspend", reason="Fixture reason"),
        ),
    ]:
        with pytest.raises(ApiError) as error:
            operation()
        assert error.value.status == 403
    assert bundle.database.writes == []


def test_audit_allowlist_and_atomic_rollback(monkeypatch):
    bundle = moderation_fixture(monkeypatch)
    data = bundle.database.data[("jobs", JOB_ID)]
    bundle.database.data[("audit_events", "c" * 32)] = {
        "action": "fixture",
        "actor_uid": "one",
        "created_at": data["created_at"],
        "raw_text": "Never expose this",
        "secret": "fixture-private",
    }
    value = bundle.moderation.audits("one", None).model_dump()
    assert "raw_text" not in str(value) and "fixture-private" not in str(value)
    from tests.resume_fixtures import Transaction

    original = Transaction.create

    def fail(transaction, ref, value):
        if ref.key[0] == "audit_events":
            raise RuntimeError("Fixture failure")
        return original(transaction, ref, value)

    monkeypatch.setattr(Transaction, "create", fail)
    before = copy.deepcopy(bundle.database.data)
    with pytest.raises(ApiError):
        bundle.moderation.moderate(
            "one",
            JOB_ID,
            ModerationCommand(expected_version=2, action="suspend", reason="Fixture reason"),
        )
    assert bundle.database.data == before


def test_http_rejects_injection_and_requires_admin(monkeypatch):
    bundle = moderation_fixture(monkeypatch)
    headers = {"Authorization": "Bearer one"}
    assert bundle.client.get("/api/v1/admin/jobs", headers=headers).status_code == 200
    assert (
        bundle.client.get("/api/v1/admin/jobs", headers={"Authorization": "Bearer two"}).status_code
        == 403
    )
    assert bundle.client.get("/api/v1/admin/audit-events").status_code == 401
    path = f"/api/v1/admin/jobs/{JOB_ID}/moderation"
    command = {"expected_version": 2, "action": "suspend", "reason": "Fixture reason"}
    for change in [
        {"actor_uid": "one"},
        {"reason": " "},
        {"action": "publish"},
        {"expected_version": True},
    ]:
        assert (
            bundle.client.post(path, headers=headers, json={**command, **change}).status_code == 422
        )
