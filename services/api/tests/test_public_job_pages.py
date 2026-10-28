from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from test_jobs import JOB_ID, NOW, client_for

from app.errors import ApiError
from app.jobs import FirestoreJobStore, PublicJob, PublicJobFilters, PublicJobPage
from app.settings import Settings


def listing_store(monkeypatch, ids):
    database, collection, query = Mock(), Mock(), Mock()
    database.collection.return_value = collection
    collection.where.return_value = query
    query.order_by.return_value = query
    query.start_after.return_value = query
    query.limit.return_value = query
    query.get.return_value = [SimpleNamespace(id=value) for value in ids]
    monkeypatch.setattr("app.jobs.firestore.Client", Mock(return_value=database))
    store = FirestoreJobStore(Settings(firebase_project_id="demo-smarthire"))
    store.get_public = Mock(
        side_effect=lambda value: PublicJob(
            id=value, title="Public fixture", company_name="Company", published_at=NOW
        )
    )
    return store, collection, query


def test_bounded_query_returns_stable_continuation_without_reading_extra_detail(monkeypatch):
    ids = ["1" * 32, "2" * 32, "3" * 32]
    store, collection, query = listing_store(monkeypatch, ids)
    page = store.list_public(2, JOB_ID)
    assert [job.id for job in page.items] == ids[:2] and page.next_cursor == ids[1]
    assert store.get_public.call_count == 2
    query.limit.assert_called_once_with(3)
    query.order_by.assert_called_once_with("__name__")
    query.start_after.assert_called_once_with({"__name__": collection.document.return_value})
    collection.document.assert_called_with(JOB_ID)
    query.get.assert_called_once_with(timeout=10, retry=None)
    condition = collection.where.call_args.kwargs["filter"]
    assert condition.field_path == "status" and condition.value == "published"


def test_hidden_candidates_produce_sparse_page_with_progress_not_unbounded_scans(monkeypatch):
    ids = ["1" * 32, "2" * 32, "3" * 32]
    store, _, query = listing_store(monkeypatch, ids)
    store.get_public.return_value = None
    store.get_public.side_effect = None
    page = store.list_public(2)
    assert page.items == [] and page.next_cursor == ids[1]
    assert store.get_public.call_count == 2
    query.get.assert_called_once()
    query.start_after.assert_not_called()


@pytest.mark.parametrize("ids", [[], ["1" * 32], ["1" * 32, "2" * 32]])
def test_last_or_empty_page_has_no_continuation(monkeypatch, ids):
    store, _, _ = listing_store(monkeypatch, ids)
    page = store.list_public(2)
    assert len(page.items) == len(ids) and page.next_cursor is None


def test_filters_keep_bounded_cursor_progress_on_empty_matching_page(monkeypatch):
    ids = ["1" * 32, "2" * 32, "3" * 32]
    store, _, query = listing_store(monkeypatch, ids)
    page = store.list_public(2, filters=PublicJobFilters(search="not present"))
    assert page.items == [] and page.next_cursor == ids[1]
    assert store.get_public.call_count == 2
    query.limit.assert_called_once_with(3)


def test_search_terms_and_modes_are_combined_without_description_or_owner_leak():
    job = PublicJob(
        id=JOB_ID,
        title="Flutter engineer",
        company_name="Fixture company",
        location="Pune",
        description="Hidden search token",
        required_skills=["Dart"],
        work_mode="remote",
        employment_type="internship",
        published_at=NOW,
    )
    assert PublicJobFilters(
        search=" DART pune ", work_mode="remote", employment_type="internship"
    ).accepts(job)
    assert not PublicJobFilters(search="Hidden").accepts(job)
    assert not PublicJobFilters(search="Flutter missing").accepts(job)
    assert not PublicJobFilters(work_mode="onsite").accepts(job)
    assert not PublicJobFilters(employment_type="full_time").accepts(job)


def test_query_failure_never_returns_partial_data_or_index_diagnostics(monkeypatch):
    store, _, query = listing_store(monkeypatch, [])
    query.get.side_effect = RuntimeError("private index url")
    with pytest.raises(ApiError) as error:
        store.list_public(2)
    assert error.value.status == 503 and "index" not in error.value.message


@pytest.mark.parametrize(
    "query",
    [
        "page_size=0",
        "page_size=11",
        "page_size=bad",
        "cursor=../private_profiles",
        "cursor=",
        "cursor=" + "A" * 32,
    ],
)
def test_invalid_pagination_never_reaches_storage(query):
    store = Mock()
    with client_for(store) as client:
        assert client.get("/api/v1/public/jobs?" + query).status_code == 422
    store.list_public.assert_not_called()


def test_public_page_and_shared_budget_require_no_identity():
    store = Mock()
    store.list_public.return_value = PublicJobPage(items=[])
    with client_for(store) as client:
        client.app.state.public_job_list_limiter.limit = 1
        response = client.get("/api/v1/public/jobs?page_size=2&cursor=" + JOB_ID)
        assert response.status_code == 200 and response.json() == {"items": [], "next_cursor": None}
        throttled = client.get("/api/v1/public/jobs", headers={"X-Forwarded-For": "spoofed"})
        assert throttled.status_code == 429 and int(throttled.headers["retry-after"]) >= 1
    store.list_public.assert_called_once_with(2, JOB_ID)
