from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from test_api import Verifier
from test_profiles import Accounts

from app.accounts import Account
from app.companies import CompanyInput, CompanyProfile, FirestoreCompanyStore
from app.main import create_app
from app.settings import Settings

NOW = datetime(2026, 10, 18, tzinfo=UTC)
BODY = {"name": "Demo Company", "description": "Software team", "website": "https://example.com"}


class Companies:
    def __init__(self):
        self.data = {}
        self.calls = []

    def get(self, uid):
        self.calls.append(uid)
        return self.data.get(uid)

    def put(self, uid, body):
        self.calls.append(uid)
        self.data[uid] = CompanyProfile(
            owner_uid=uid, approval_status="pending", updated_at=NOW, **body.model_dump()
        )
        return self.data[uid]


def client_for(store, uid="one", verified=True, accounts=None):
    return TestClient(
        create_app(
            Settings(),
            company_store=store,
            account_store=accounts or Accounts(),
            token_verifier=Verifier({"uid": uid, "email_verified": verified}),
        )
    )


def test_company_is_private_and_token_owns_the_write():
    store = Companies()
    with client_for(store) as client:
        headers = {"Authorization": "Bearer test"}
        assert client.get("/api/v1/company", headers=headers).status_code == 404
        response = client.put("/api/v1/company?owner_uid=other", json=BODY, headers=headers)
        assert response.status_code == 200
        assert response.json()["owner_uid"] == "one"
        assert response.json()["approval_status"] == "pending"
        assert client.get("/api/v1/company", headers=headers).json()["name"] == "Demo Company"
    with client_for(store, uid="other") as client:
        assert client.get("/api/v1/company?owner_uid=one", headers=headers).status_code == 404
    assert set(store.data) == {"one"}


@pytest.mark.parametrize(
    "extra", ["owner_uid", "uid", "approval_status", "role", "recruiter_approved", "updated_at"]
)
def test_company_input_cannot_assign_ownership_or_privileges(extra):
    store = Companies()
    with client_for(store) as client:
        response = client.put(
            "/api/v1/company",
            json={**BODY, extra: "admin"},
            headers={"Authorization": "Bearer test"},
        )
    assert response.status_code == 422
    assert store.calls == []
    assert "admin" not in response.text


@pytest.mark.parametrize(
    "fields",
    [
        {"name": " "},
        {"name": "x" * 121},
        {"description": "x" * 2001},
        {"website": "http://example.com"},
        {"website": "https://user:password@example.com"},
        {"website": "javascript:alert(1)"},
        {"website": "https://example.com:invalid"},
        {"website": "https://exa mple.com"},
    ],
)
def test_invalid_company_fields_do_not_reach_storage(fields):
    store = Companies()
    with client_for(store) as client:
        response = client.put(
            "/api/v1/company", json={**BODY, **fields}, headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 422
    assert store.calls == []


@pytest.mark.parametrize("method", ["GET", "PUT"])
def test_company_requires_verified_email_and_active_account(method):
    store = Companies()
    with client_for(store, verified=False) as client:
        assert (
            client.request(
                method,
                "/api/v1/company",
                json=BODY if method == "PUT" else None,
                headers={"Authorization": "Bearer test"},
            ).status_code
            == 403
        )
    accounts = Mock()
    accounts.get.return_value = Account(uid="one", account_status="suspended")
    with client_for(store, accounts=accounts) as client:
        assert (
            client.request(
                method,
                "/api/v1/company",
                json=BODY if method == "PUT" else None,
                headers={"Authorization": "Bearer test"},
            ).status_code
            == 403
        )
    assert store.calls == []


def test_firestore_save_resets_approval_without_granting_roles(monkeypatch):
    document = Mock()
    document.set.return_value = SimpleNamespace(update_time=NOW)
    document.get.return_value = SimpleNamespace(
        exists=True,
        to_dict=lambda: {
            **BODY,
            "approval_status": "approved",
            "updated_at": NOW,
            "owner_uid": "spoofed",
            "role": "admin",
        },
    )
    database = Mock()
    database.collection.return_value.document.return_value = document
    monkeypatch.setattr("app.companies.firestore.Client", Mock(return_value=database))
    store = FirestoreCompanyStore(Settings(firebase_project_id="demo-smarthire"))
    assert store.get("one").approval_status == "approved"
    result = store.put("one/child", CompanyInput(**BODY))
    assert result.owner_uid == "one/child"
    assert result.approval_status == "pending"
    data = document.set.call_args.args[0]
    assert data["approval_status"] == "pending"
    assert "role" not in data and "owner_uid" not in data
    assert document.set.call_args.kwargs == {"merge": True, "timeout": 10, "retry": None}
    database.collection.return_value.document.assert_called_with("one%2Fchild")
    database.collection.assert_called_with("company_profiles")


def test_company_outage_is_safe(monkeypatch):
    monkeypatch.setattr(
        "app.companies.firestore.Client", Mock(side_effect=ValueError("private key"))
    )
    with client_for(
        FirestoreCompanyStore(Settings(firebase_project_id="demo-smarthire"))
    ) as client:
        response = client.put(
            "/api/v1/company", json=BODY, headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 503
    assert "private" not in response.text
