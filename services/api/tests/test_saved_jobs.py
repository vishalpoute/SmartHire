import copy

import pytest

from app.errors import ApiError
from app.saved_jobs import FirestoreSavedJobStore
from app.settings import Settings
from tests.test_matching import JOB_ID, match_fixture


def saved_fixture(monkeypatch):
    bundle = match_fixture(monkeypatch)
    store = FirestoreSavedJobStore(Settings(firebase_project_id="fixture"))
    store.client = bundle.database
    bundle.app.state.saved_job_store = store
    bundle.saved = store
    return bundle


def test_saved_roles_persist_idempotently_and_are_owner_scoped(monkeypatch):
    bundle = saved_fixture(monkeypatch)
    first = bundle.saved.save("one", JOB_ID)
    assert bundle.saved.save("one", JOB_ID) == first
    assert bundle.saved.list_saved("one", None).items == [first]
    assert bundle.saved.list_saved("two", None).items == []
    assert bundle.database.data[("_saved_job_counts", "one")]["count"] == 1
    assert "owner_uid" not in first.model_dump()
    bundle.saved.remove("two", JOB_ID)
    assert bundle.saved.list_saved("one", None).items == [first]
    bundle.saved.remove("one", JOB_ID)
    bundle.saved.remove("one", JOB_ID)
    assert bundle.saved.list_saved("one", None).items == []
    assert bundle.database.data[("_saved_job_counts", "one")]["count"] == 0


def test_hidden_roles_keep_removable_bookmark_without_exposing_job(monkeypatch):
    bundle = saved_fixture(monkeypatch)
    bundle.saved.save("one", JOB_ID)
    bundle.database.data[("users", "recruiter")]["recruiter_approved"] = False
    first = bundle.saved.list_saved("one", None).items[0]
    assert first.job is None and first.job_id == JOB_ID
    assert bundle.saved.save("one", JOB_ID).job is None
    with pytest.raises(ApiError) as error:
        bundle.saved.save("two", JOB_ID)
    assert error.value.status == 404
    bundle.saved.remove("one", JOB_ID)
    assert bundle.saved.list_saved("one", None).items == []


def test_saved_limit_and_suspended_account_are_rechecked_transactionally(monkeypatch):
    bundle = saved_fixture(monkeypatch)
    bundle.database.data[("_saved_job_counts", "one")] = {"count": 100}
    with pytest.raises(ApiError) as error:
        bundle.saved.save("one", JOB_ID)
    assert error.value.status == 409
    bundle.database.data[("users", "one")] = {"account_status": "suspended"}
    for operation in [
        lambda: bundle.saved.save("one", JOB_ID),
        lambda: bundle.saved.remove("one", JOB_ID),
        lambda: bundle.saved.list_saved("one", None),
    ]:
        with pytest.raises(ApiError) as error:
            operation()
        assert error.value.status == 403


def test_saved_query_is_bounded_and_cursor_advances(monkeypatch):
    bundle = saved_fixture(monkeypatch)
    first = bundle.saved.save("one", JOB_ID)
    original = bundle.database.data[("saved_jobs", first.id)]
    for index in range(12):
        bundle.database.data[("saved_jobs", f"{index:032x}")] = copy.deepcopy(original)
    first = bundle.saved.list_saved("one", None)
    second = bundle.saved.list_saved("one", first.next_cursor)
    assert len(first.items) == 10 and len(second.items) == 3
    assert not {item.id for item in first.items} & {item.id for item in second.items}
    assert bundle.database.limits[-2:] == [11, 11]


def test_http_saved_auth_and_safe_path_validation(monkeypatch):
    bundle = saved_fixture(monkeypatch)
    headers = {"Authorization": "Bearer one"}
    assert bundle.client.post(f"/api/v1/saved-jobs/{JOB_ID}", headers=headers).status_code == 201
    assert len(bundle.client.get("/api/v1/saved-jobs", headers=headers).json()["items"]) == 1
    assert bundle.client.delete(f"/api/v1/saved-jobs/{JOB_ID}", headers=headers).json() == {
        "job_id": JOB_ID,
        "status": "removed",
    }
    assert bundle.client.get("/api/v1/saved-jobs").status_code == 401
    assert bundle.client.get("/api/v1/saved-jobs?cursor=bad", headers=headers).status_code == 422
    assert bundle.client.post("/api/v1/saved-jobs/invalid", headers=headers).status_code == 422
