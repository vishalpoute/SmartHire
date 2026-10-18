from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from test_api import Verifier
from test_profiles import Store

from app.accounts import Account, FirestoreAccountStore
from app.main import create_app
from app.settings import Settings


class Accounts:
    def __init__(self, account):
        self.account = account
        self.calls = []

    def get(self, uid):
        self.calls.append(uid)
        return self.account


def app_for(accounts, profiles=None):
    return create_app(
        Settings(),
        account_store=accounts,
        profile_store=profiles or Store(),
        token_verifier=Verifier(
            {"uid": "one", "email_verified": True, "role": "admin", "recruiter_approved": True}
        ),
    )


def test_account_is_selected_by_token_and_role_claims_cannot_escalate():
    accounts = Accounts(Account(uid="one"))
    with TestClient(app_for(accounts)) as client:
        response = client.get(
            "/api/v1/account?uid=other&role=admin", headers={"Authorization": "Bearer test"}
        )
        assert response.status_code == 200
        assert response.json() == {
            "uid": "one",
            "role": "seeker",
            "account_status": "active",
            "recruiter_approved": False,
        }
        assert (
            client.put(
                "/api/v1/account", json={"role": "admin"}, headers={"Authorization": "Bearer test"}
            ).status_code
            == 405
        )
    assert accounts.calls == ["one"]


def test_unauthenticated_account_request_does_not_read_store():
    accounts = Accounts(Account(uid="one"))
    with TestClient(app_for(accounts)) as client:
        assert client.get("/api/v1/account").status_code == 401
    assert accounts.calls == []


@pytest.mark.parametrize("method", ["GET", "PUT"])
def test_suspended_account_cannot_read_or_change_profiles(method):
    accounts = Accounts(Account(uid="one", account_status="suspended"))
    profiles = Store()
    with TestClient(app_for(accounts, profiles)) as client:
        response = client.request(
            method,
            "/api/v1/profile",
            headers={"Authorization": "Bearer test"},
            json={"display_name": "Demo seeker"} if method == "PUT" else None,
        )
        assert response.status_code == 403
        assert response.json()["code"] == "account_suspended"
        # Own status remains readable for an eventual suspension/appeal screen.
        assert (
            client.get("/api/v1/account", headers={"Authorization": "Bearer test"}).json()[
                "account_status"
            ]
            == "suspended"
        )
    assert profiles.calls == []


def test_mismatched_account_store_owner_fails_closed():
    with TestClient(app_for(Accounts(Account(uid="other", role="admin")))) as client:
        for path in ["/api/v1/account", "/api/v1/profile"]:
            response = client.get(path, headers={"Authorization": "Bearer test"})
            assert response.status_code == 503
            assert "other" not in response.text


@pytest.mark.parametrize(
    "data",
    [
        None,
        {"role": "superadmin"},
        {"recruiter_approved": "true"},
        {"account_status": "unexpected"},
    ],
)
def test_invalid_server_account_data_fails_closed_without_sdk_details(monkeypatch, data):
    document = Mock()
    document.get.return_value = SimpleNamespace(exists=True, to_dict=lambda: data)
    database = Mock()
    database.collection.return_value.document.return_value = document
    monkeypatch.setattr("app.accounts.firestore.Client", Mock(return_value=database))
    store = FirestoreAccountStore(Settings(firebase_project_id="demo-smarthire"))
    with TestClient(app_for(store)) as client:
        response = client.get("/api/v1/account", headers={"Authorization": "Bearer test"})
        assert response.status_code == 503
        assert "superadmin" not in response.text


def test_missing_record_defaults_to_seeker_and_server_uid_cannot_override_owner(monkeypatch):
    document = Mock()
    document.get.return_value = SimpleNamespace(exists=False)
    database = Mock()
    database.collection.return_value.document.return_value = document
    constructor = Mock(return_value=database)
    monkeypatch.setattr("app.accounts.firestore.Client", constructor)
    store = FirestoreAccountStore(Settings(firebase_project_id="demo-smarthire"))
    assert store.get("one/child") == Account(uid="one/child")
    database.collection.assert_called_with("users")
    database.collection.return_value.document.assert_called_with("one%2Fchild")
    document.get.assert_called_with(timeout=10, retry=None)
    document.get.return_value = SimpleNamespace(
        exists=True,
        to_dict=lambda: {"uid": "other", "role": "recruiter", "recruiter_approved": False},
    )
    assert store.get("one").uid == "one"
    assert constructor.call_count == 1


def test_account_store_outage_does_not_reach_profile_storage(monkeypatch):
    monkeypatch.setattr(
        "app.accounts.firestore.Client",
        Mock(side_effect=ValueError("private credential diagnostics")),
    )
    profiles = Store()
    store = FirestoreAccountStore(Settings(firebase_project_id="demo-smarthire"))
    with TestClient(app_for(store, profiles)) as client:
        response = client.get("/api/v1/profile", headers={"Authorization": "Bearer test"})
        assert response.status_code == 503
        assert "private" not in response.text
    assert profiles.calls == []
