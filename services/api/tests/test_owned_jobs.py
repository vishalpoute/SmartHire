from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from test_jobs import JOB_ID, NOW, client_for

from app.errors import ApiError
from app.jobs import FirestoreJobStore, JobDraft, OwnedJobPage
from app.settings import Settings


def stored_job(**changes):
    return {
        "title": "Private developer job",
        "recruiter_uid": "one",
        "company_owner_uid": "one",
        "status": "draft",
        "version": 1,
        "created_at": NOW,
        "updated_at": NOW,
        "internal_note": "private server metadata",
        **changes,
    }


def owned_store(monkeypatch, ids, data=None, account_status="active", exists=True):
    database, transaction, account, collection, query = [Mock() for _ in range(5)]
    account.get.return_value = Mock(
        exists=exists, to_dict=lambda: {"account_status": account_status}
    )
    database.collection.side_effect = lambda name: (
        Mock(document=Mock(return_value=account)) if name == "users" else collection
    )
    database.transaction.return_value = transaction
    collection.where.return_value = query
    query.order_by.return_value = query
    query.start_after.return_value = query
    query.limit.return_value = query
    query.get.return_value = [
        SimpleNamespace(id=value, to_dict=lambda: stored_job() if data is None else data)
        for value in ids
    ]
    monkeypatch.setattr("app.jobs.firestore.Client", Mock(return_value=database))
    monkeypatch.setattr("app.jobs.firestore.transactional", lambda operation: operation)
    return (
        FirestoreJobStore(Settings(firebase_project_id="demo-smarthire")),
        query,
        collection,
        transaction,
        account,
    )


def test_owned_page_is_bounded_owner_filtered_and_allowlisted(monkeypatch):
    store, query, collection, transaction, account = owned_store(monkeypatch, [JOB_ID, "b" * 32])
    page = store.list_owned("one", 1, "0" * 32)
    assert page.items[0].id == JOB_ID and page.next_cursor == JOB_ID
    assert "private server metadata" not in page.model_dump_json()
    owner_filter = collection.where.call_args.kwargs["filter"]
    assert (owner_filter.field_path, owner_filter.op_string, owner_filter.value) == (
        "recruiter_uid",
        "==",
        "one",
    )
    query.limit.assert_called_once_with(2)
    query.start_after.assert_called_once_with({"__name__": collection.document.return_value})
    collection.document.assert_called_once_with("0" * 32)
    query.get.assert_called_once_with(transaction=transaction, timeout=10, retry=None)
    account.get.assert_called_once_with(transaction=transaction, timeout=10, retry=None)
    transaction.set.assert_not_called()
    transaction.update.assert_not_called()
    transaction.create.assert_not_called()


def test_empty_owned_page_has_no_cursor(monkeypatch):
    store, *_ = owned_store(monkeypatch, [])
    assert store.list_owned("one").model_dump() == {"items": [], "next_cursor": None}


@pytest.mark.parametrize(
    "changes",
    [
        {"recruiter_uid": "other"},
        {"company_owner_uid": "other"},
        {"version": 0},
        {"status": "arbitrary"},
    ],
)
def test_owned_page_fails_closed_on_foreign_or_malformed_record(monkeypatch, changes):
    store, *_ = owned_store(monkeypatch, [JOB_ID], stored_job(**changes))
    with pytest.raises(ApiError) as error:
        store.list_owned("one")
    assert error.value.status == 503
    assert "other" not in error.value.message


@pytest.mark.parametrize("exists,status", [(False, "active"), (True, "suspended")])
def test_account_rechecked_transactionally_before_query(monkeypatch, exists, status):
    store, query, *_ = owned_store(monkeypatch, [JOB_ID], exists=exists, account_status=status)
    with pytest.raises(ApiError) as error:
        store.list_owned("one")
    assert error.value.status == 403
    query.get.assert_not_called()


def test_datastore_error_has_safe_response(monkeypatch):
    store, query, *_ = owned_store(monkeypatch, [JOB_ID])
    query.get.side_effect = RuntimeError("private server metadata")
    with pytest.raises(ApiError) as error:
        store.list_owned("one")
    assert error.value.status == 503
    assert "private" not in error.value.message


def test_endpoint_derives_owner_from_identity_and_bounds_pagination():
    jobs = Mock()
    jobs.list_owned.return_value = OwnedJobPage(
        items=[
            JobDraft(
                id=JOB_ID,
                **{key: value for key, value in stored_job().items() if key != "internal_note"},
            )
        ]
    )
    client = client_for(jobs, role="seeker", approved=False)
    response = client.get(
        "/api/v1/jobs?uid=other&page_size=1&cursor=" + "0" * 32,
        headers={"Authorization": "Bearer valid"},
    )
    assert response.status_code == 200
    jobs.list_owned.assert_called_once_with("one", 1, "0" * 32)
    assert response.headers["cache-control"] == "no-store"
    for query in ["page_size=0", "page_size=21", "cursor=invalid", "cursor=" + "a" * 33]:
        assert (
            client.get(
                "/api/v1/jobs?" + query, headers={"Authorization": "Bearer valid"}
            ).status_code
            == 422
        )


@pytest.mark.parametrize(
    "settings,status",
    [
        ({"verified": False}, 403),
        ({"suspended": True}, 403),
    ],
)
def test_endpoint_denies_unverified_or_suspended_accounts(settings, status):
    jobs = Mock()
    response = client_for(jobs, **settings).get(
        "/api/v1/jobs", headers={"Authorization": "Bearer valid"}
    )
    assert response.status_code == status
    jobs.list_owned.assert_not_called()


def test_endpoint_requires_authentication():
    jobs = Mock()
    assert client_for(jobs).get("/api/v1/jobs").status_code == 401
    jobs.list_owned.assert_not_called()
