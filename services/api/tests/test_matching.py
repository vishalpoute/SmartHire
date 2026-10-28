from datetime import UTC, datetime
from types import SimpleNamespace

import pytest

from app.errors import ApiError
from app.matching import FirestoreMatchStore, MatchInput, calculate_match
from app.settings import Settings
from tests.resume_fixtures import fixture_app

JOB_ID = "a" * 32
RESUME_ID = "b" * 32


def match_fixture(monkeypatch):
    bundle = fixture_app(monkeypatch)
    now = datetime.now(UTC)
    bundle.database.data[("users", "recruiter")] = {
        "role": "recruiter",
        "account_status": "active",
        "recruiter_approved": True,
    }
    bundle.database.data[("company_profiles", "recruiter")] = {
        "name": "Fixture company",
        "description": "",
        "location": "",
        "website": "",
        "approval_status": "approved",
        "updated_at": now,
    }
    bundle.database.data[("jobs", JOB_ID)] = {
        "title": "Fixture job",
        "required_skills": ["Python", "Flutter", "SQL"],
        "preferred_skills": ["Docker"],
        "status": "published",
        "version": 2,
        "recruiter_uid": "recruiter",
        "company_owner_uid": "recruiter",
        "company_name": "Fixture company",
        "created_at": now,
        "updated_at": now,
        "published_at": now,
    }
    bundle.database.data[("resumes", RESUME_ID)] = {
        "owner_uid": "one",
        "version": 1,
        "revision": 4,
        "extension": "pdf",
        "size": 20,
        "sha256": "c" * 64,
        "parse_status": "confirmed",
        "confirmed_skills": ["Python", "Docker"],
        "skills_version": 1,
        "parser_version": "fixture-parser-v1",
        "created_at": now,
        "updated_at": now,
        "text": "Private text never returned",
    }
    store = FirestoreMatchStore(Settings(firebase_project_id="fixture"))
    store.client = bundle.database
    bundle.app.state.match_store = store
    bundle.match_store = store
    return bundle


def command(**changes):
    return {"resume_id": RESUME_ID, "expected_resume_revision": 4, **changes}


def test_match_returns_reproducible_versions_and_evidence_without_private_text(monkeypatch):
    bundle = match_fixture(monkeypatch)
    first = bundle.client.post(
        f"/api/v1/jobs/{JOB_ID}/match", headers={"Authorization": "Bearer one"}, json=command()
    )
    assert first.status_code == 200
    value = first.json()
    assert value["score"] == 33.33
    assert value["required_evidence"] == [{"skill": "Python", "confirmed_skill": "Python"}]
    assert value["preferred_evidence"] == [{"skill": "Docker", "confirmed_skill": "Docker"}]
    assert value["missing_required"] == ["Flutter", "SQL"]
    assert value["job_version"] == 2 and value["skills_version"] == 1
    assert value["algorithm_version"] == "skill-coverage-v1"
    assert not {"text", "owner_uid", "storage_path", "recruiter_uid"} & value.keys()
    assert (
        bundle.client.post(
            f"/api/v1/jobs/{JOB_ID}/match", headers={"Authorization": "Bearer one"}, json=command()
        ).json()
        == value
    )
    assert bundle.database.writes == []


@pytest.mark.parametrize(
    "changes,status",
    [
        ({"resume_id": "d" * 32}, 404),
        ({"expected_resume_revision": 3}, 409),
        ({"expected_job_version": 1}, 409),
        ({"owner_uid": "two"}, 422),
        ({"score": 100}, 422),
        ({"expected_resume_revision": True}, 422),
    ],
)
def test_match_rejects_foreign_stale_and_injected_inputs(monkeypatch, changes, status):
    bundle = match_fixture(monkeypatch)
    assert (
        bundle.client.post(
            f"/api/v1/jobs/{JOB_ID}/match",
            headers={"Authorization": "Bearer one"},
            json=command(**changes),
        ).status_code
        == status
    )


def test_other_owner_gets_same_unavailable_and_anonymous_rejected(monkeypatch):
    bundle = match_fixture(monkeypatch)
    assert (
        bundle.client.post(
            f"/api/v1/jobs/{JOB_ID}/match", headers={"Authorization": "Bearer two"}, json=command()
        ).status_code
        == 404
    )
    assert bundle.client.post(f"/api/v1/jobs/{JOB_ID}/match", json=command()).status_code == 401


@pytest.mark.parametrize(
    "target,changes,status",
    [
        (("users", "one"), {"account_status": "suspended"}, 403),
        (("users", "one"), {"role": "admin"}, 403),
        (("users", "recruiter"), {"account_status": "suspended"}, 404),
        (("users", "recruiter"), {"recruiter_approved": False}, 404),
        (("company_profiles", "recruiter"), {"approval_status": "pending"}, 404),
        (("jobs", JOB_ID), {"status": "closed"}, 404),
        (("jobs", JOB_ID), {"company_owner_uid": "other"}, 404),
        (("resumes", RESUME_ID), {"parse_status": "parsed"}, 409),
    ],
)
def test_match_rechecks_source_and_permissions_inside_transaction(
    monkeypatch, target, changes, status
):
    bundle = match_fixture(monkeypatch)
    bundle.database.data.setdefault(target, {}).update(changes)
    assert (
        bundle.client.post(
            f"/api/v1/jobs/{JOB_ID}/match", headers={"Authorization": "Bearer one"}, json=command()
        ).status_code
        == status
    )


def test_exact_aliases_unicode_and_duplicate_requirements_have_no_substring_matches():
    job = SimpleNamespace(
        title="Fixture job",
        company_name="Fixture company",
        id=JOB_ID,
        version=2,
        required_skills=["React", "reactjs", "Java", "SQL", "C++"],
        preferred_skills=[],
    )
    resume = SimpleNamespace(
        id=RESUME_ID,
        version=1,
        revision=4,
        sha256="c" * 64,
        skills_version=1,
        parser_version="fixture",
        parse_status="confirmed",
        confirmed_skills=["ＲＥＡＣＴ．ＪＳ", "JavaScript", "MySQL", "c++"],
    )
    result = calculate_match(job, resume)
    assert result.score == 50
    assert result.missing_required == ["Java", "SQL"]
    assert len(result.required_evidence) == 2
    resume.confirmed_skills = []
    assert calculate_match(job, resume).score == 0
    job.required_skills = []
    result = calculate_match(job, resume)
    assert result.status == "unscored" and result.score is None
    assert result.unscored_reason == "no_required_skills"
    resume.parse_status = "unscored"
    with pytest.raises(ApiError):
        calculate_match(job, resume)


def test_store_detects_suspension_even_if_http_account_check_is_stale(monkeypatch):
    bundle = match_fixture(monkeypatch)
    bundle.database.data[("users", "one")] = {"account_status": "suspended"}
    with pytest.raises(ApiError) as error:
        bundle.match_store.match("one", JOB_ID, MatchInput(**command()))
    assert error.value.status == 403
