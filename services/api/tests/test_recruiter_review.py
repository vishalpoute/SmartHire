from datetime import UTC, datetime, timedelta
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from test_api import Verifier

from app.accounts import Account
from app.errors import ApiError
from app.main import create_app
from app.recruiter_review import FirestoreRecruiterReviewStore, RecruiterReview, review_policy
from app.settings import Settings

NOW = datetime(2026, 10, 20, tzinfo=UTC)
BODY = {
    "target_uid": "applicant",
    "decision": "approved",
    "expected_company_updated_at": NOW.isoformat(),
    "reason": "Company reviewed",
}
ADMIN = {"role": "admin", "account_status": "active"}
COMPANY = {"name": "Company", "approval_status": "pending", "updated_at": NOW}


def client_for(store, role="admin", suspended=False, verified=True):
    accounts = Mock()
    accounts.get.return_value = Account(
        uid="reviewer", role=role, account_status="suspended" if suspended else "active"
    )
    return TestClient(
        create_app(
            Settings(),
            account_store=accounts,
            recruiter_review_store=store,
            token_verifier=Verifier(
                {"uid": "reviewer", "email_verified": verified, "role": "admin"}
            ),
        )
    )


@pytest.mark.parametrize("decision", ["approved", "rejected"])
def test_policy_can_only_assign_recruiter_approval(decision):
    command = RecruiterReview(**{**BODY, "decision": decision})
    changes = review_policy("reviewer", command, ADMIN, {}, COMPANY)
    assert changes["recruiter_approved"] == (decision == "approved")
    assert changes.get("role") == ("recruiter" if decision == "approved" else None)
    assert "account_status" not in changes


@pytest.mark.parametrize(
    "actor,target,company,status",
    [
        ({"role": "seeker"}, {}, COMPANY, 403),
        ({"role": "admin", "account_status": "suspended"}, {}, COMPANY, 403),
        (ADMIN, {"role": "admin"}, COMPANY, 403),
        (ADMIN, {"account_status": "suspended"}, COMPANY, 403),
        (ADMIN, {}, None, 404),
        (ADMIN, {}, {**COMPANY, "approval_status": "approved"}, 409),
        (ADMIN, {}, {**COMPANY, "approval_status": "rejected"}, 409),
        (ADMIN, {}, {**COMPANY, "updated_at": NOW + timedelta(seconds=1)}, 409),
    ],
)
def test_policy_rejects_unauthorized_or_stale_reviews(actor, target, company, status):
    with pytest.raises(ApiError) as error:
        review_policy("reviewer", RecruiterReview(**BODY), actor, target, company)
    assert error.value.status == status


def test_admin_cannot_review_self():
    command = RecruiterReview(**{**BODY, "target_uid": "reviewer"})
    with pytest.raises(ApiError) as error:
        review_policy("reviewer", command, ADMIN, {}, COMPANY)
    assert error.value.code == "self_review_forbidden"


def setup_store(monkeypatch, actor=None):
    database, transaction = Mock(), Mock()
    refs = {name: Mock() for name in ["reviewer", "applicant", "company", "audit"]}
    for key, data in [
        ("reviewer", ADMIN if actor is None else actor),
        ("applicant", {}),
        ("company", COMPANY),
    ]:
        refs[key].get.return_value = Mock(exists=True, to_dict=lambda data=data: data)
    database.collection.side_effect = lambda name: Mock(
        document=Mock(
            side_effect=(lambda uid: refs[uid])
            if name == "users"
            else (lambda uid: refs["company" if name == "company_profiles" else "audit"])
        )
    )
    database.transaction.return_value = transaction
    monkeypatch.setattr("app.recruiter_review.firestore.Client", Mock(return_value=database))
    monkeypatch.setattr("app.recruiter_review.firestore.transactional", lambda operation: operation)
    return (
        FirestoreRecruiterReviewStore(Settings(firebase_project_id="demo-smarthire")),
        transaction,
        refs,
    )


def test_review_atomically_updates_approval_and_private_audit(monkeypatch):
    store, transaction, refs = setup_store(monkeypatch)
    receipt = store.review("reviewer", RecruiterReview(**BODY))
    assert receipt.model_dump() == {"target_uid": "applicant", "decision": "approved"}
    for name in ["reviewer", "applicant", "company"]:
        refs[name].get.assert_called_once_with(transaction=transaction, timeout=10, retry=None)
    transaction.set.assert_called_once()
    assert transaction.set.call_args.kwargs == {"merge": True}
    assert transaction.set.call_args.args[1]["role"] == "recruiter"
    transaction.update.assert_called_once()
    assert transaction.update.call_args.args[1]["approval_status"] == "approved"
    event = transaction.create.call_args.args[1]
    assert event["action"] == "recruiter.approved" and event["reason"] == BODY["reason"]
    assert "reason" not in receipt.model_dump()


def test_revoked_admin_between_http_precheck_and_transaction_writes_nothing(monkeypatch):
    store, transaction, _ = setup_store(monkeypatch, actor={"role": "seeker"})
    with client_for(store) as client:
        response = client.post(
            "/api/v1/admin/recruiter-reviews", json=BODY, headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 403
    transaction.set.assert_not_called()
    transaction.update.assert_not_called()
    transaction.create.assert_not_called()


@pytest.mark.parametrize(
    "options", [{"role": "seeker"}, {"role": "recruiter"}, {"suspended": True}, {"verified": False}]
)
def test_role_claims_cannot_bypass_server_admin_gate(options):
    store = Mock()
    with client_for(store, **options) as client:
        assert (
            client.post(
                "/api/v1/admin/recruiter-reviews",
                json=BODY,
                headers={"Authorization": "Bearer test"},
            ).status_code
            == 403
        )
    store.review.assert_not_called()


@pytest.mark.parametrize(
    "changes",
    [
        {"decision": "admin"},
        {"role": "admin"},
        {"reason": "x"},
        {"reason": "x" * 501},
        {"target_uid": ""},
        {"expected_company_updated_at": "2026-10-20T00:00:00"},
    ],
)
def test_invalid_review_never_reaches_store(changes):
    store = Mock()
    with client_for(store) as client:
        assert (
            client.post(
                "/api/v1/admin/recruiter-reviews",
                json={**BODY, **changes},
                headers={"Authorization": "Bearer test"},
            ).status_code
            == 422
        )
    store.review.assert_not_called()


def test_sdk_failure_is_safe_and_missing_login_cannot_review(monkeypatch):
    store, _, refs = setup_store(monkeypatch)
    refs["company"].get.side_effect = RuntimeError("private credentials")
    with client_for(store) as client:
        assert client.post("/api/v1/admin/recruiter-reviews", json=BODY).status_code == 401
        response = client.post(
            "/api/v1/admin/recruiter-reviews", json=BODY, headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 503 and "credential" not in response.text
