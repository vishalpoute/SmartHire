from types import SimpleNamespace
from unittest.mock import Mock
from urllib.parse import quote

import pytest
from test_recruiter_review import ADMIN, COMPANY, client_for

from app.errors import ApiError
from app.recruiter_review import FirestoreRecruiterReviewStore, RecruiterReviewPage
from app.settings import Settings


def queue_store(monkeypatch, ids, actor=None):
    database, transaction, account_ref, collection, query = [Mock() for _ in range(5)]
    account_ref.get.return_value = Mock(
        exists=True, to_dict=lambda: ADMIN if actor is None else actor
    )
    database.collection.side_effect = lambda name: (
        Mock(document=Mock(return_value=account_ref)) if name == "users" else collection
    )
    database.transaction.return_value = transaction
    collection.where.return_value = query
    query.order_by.return_value = query
    query.start_after.return_value = query
    query.limit.return_value = query
    query.get.return_value = [
        SimpleNamespace(
            id=value,
            to_dict=lambda: {**COMPANY, "owner_uid": "spoofed", "internal_note": "private note"},
        )
        for value in ids
    ]
    monkeypatch.setattr("app.recruiter_review.firestore.Client", Mock(return_value=database))
    monkeypatch.setattr("app.recruiter_review.firestore.transactional", lambda operation: operation)
    return (
        FirestoreRecruiterReviewStore(Settings(firebase_project_id="demo-smarthire")),
        query,
        collection,
        transaction,
        account_ref,
    )


def test_queue_is_bounded_and_decodes_owner_from_path_not_record(monkeypatch):
    uid = "applicant/path%name"
    store, query, collection, transaction, account = queue_store(
        monkeypatch, [quote(uid, safe=""), "next"]
    )
    page = store.pending("reviewer", 1, "before/path")
    assert page.items[0].owner_uid == uid and page.next_cursor == uid
    assert "private note" not in page.model_dump_json() and "spoofed" not in page.model_dump_json()
    collection.document.assert_called_once_with("before%2Fpath")
    query.start_after.assert_called_once_with({"__name__": collection.document.return_value})
    query.limit.assert_called_once_with(2)
    query.get.assert_called_once_with(transaction=transaction, timeout=10, retry=None)
    account.get.assert_called_once_with(transaction=transaction, timeout=10, retry=None)
    transaction.set.assert_not_called()
    transaction.update.assert_not_called()
    transaction.create.assert_not_called()


@pytest.mark.parametrize("ids", [[], ["one"], ["one", "two"]])
def test_terminal_queue_page_has_no_cursor(monkeypatch, ids):
    store, query, _, _, _ = queue_store(monkeypatch, ids)
    page = store.pending("reviewer", 2)
    assert len(page.items) == len(ids) and page.next_cursor is None
    query.start_after.assert_not_called()


def test_admin_revocation_race_prevents_queue_read(monkeypatch):
    store, query, _, _, _ = queue_store(monkeypatch, ["private"], actor={"role": "seeker"})
    with client_for(store) as client:
        response = client.get(
            "/api/v1/admin/recruiter-reviews", headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 403
    query.get.assert_not_called()


@pytest.mark.parametrize(
    "options", [{"role": "seeker"}, {"role": "recruiter"}, {"suspended": True}, {"verified": False}]
)
def test_queue_denies_nonadmins_before_storage(options):
    store = Mock()
    with client_for(store, **options) as client:
        assert (
            client.get(
                "/api/v1/admin/recruiter-reviews", headers={"Authorization": "Bearer test"}
            ).status_code
            == 403
        )
    store.pending.assert_not_called()


@pytest.mark.parametrize(
    "query", ["page_size=0", "page_size=21", "cursor=", "cursor=" + "x" * 129, "cursor=%00"]
)
def test_bad_queue_parameters_never_read_storage(query):
    store = Mock()
    with client_for(store) as client:
        assert (
            client.get(
                "/api/v1/admin/recruiter-reviews?" + query, headers={"Authorization": "Bearer test"}
            ).status_code
            == 422
        )
    store.pending.assert_not_called()


def test_queue_http_selects_actor_from_token_and_requires_login():
    store = Mock()
    store.pending.return_value = RecruiterReviewPage(items=[])
    with client_for(store) as client:
        assert client.get("/api/v1/admin/recruiter-reviews").status_code == 401
        response = client.get(
            "/api/v1/admin/recruiter-reviews?page_size=2&actor_uid=other",
            headers={"Authorization": "Bearer test"},
        )
    assert response.json() == {"items": [], "next_cursor": None}
    assert response.headers["cache-control"] == "no-store"
    store.pending.assert_called_once_with("reviewer", 2, None)


@pytest.mark.parametrize("key", ["bad%path", "bad/path", "x" * 129])
def test_corrupt_document_keys_fail_closed(monkeypatch, key):
    store, _, _, _, _ = queue_store(monkeypatch, [key])
    with pytest.raises(ApiError) as error:
        store.pending("reviewer", 2)
    assert error.value.status == 503


def test_queue_failure_does_not_reveal_index_or_company_details(monkeypatch):
    store, query, _, _, _ = queue_store(monkeypatch, [])
    query.get.side_effect = RuntimeError("private query credentials")
    with client_for(store) as client:
        response = client.get(
            "/api/v1/admin/recruiter-reviews", headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 503 and "credential" not in response.text
