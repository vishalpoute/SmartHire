from datetime import UTC, datetime
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from fastapi.testclient import TestClient
from test_api import Verifier

from app.main import create_app
from app.profiles import FirestoreProfileStore, Profile, ProfileInput
from app.settings import Settings

NOW = datetime(2026, 10, 17, tzinfo=UTC)
BODY = {"display_name": "Demo Seeker", "headline": "Mobile developer", "skills": ["Dart"]}


class Store:
    def __init__(self):
        self.profiles = {}
        self.calls = []

    def get(self, uid):
        self.calls.append(uid)
        return self.profiles.get(uid)

    def put(self, uid, profile):
        self.calls.append(uid)
        self.profiles[uid] = Profile(uid=uid, updated_at=NOW, **profile.model_dump())
        return self.profiles[uid]


def client_for(store, uid="one", verified=True):
    return TestClient(
        create_app(
            Settings(),
            profile_store=store,
            token_verifier=Verifier({"uid": uid, "email_verified": verified}),
        )
    )


@pytest.mark.parametrize("method", ["get", "put"])
@pytest.mark.parametrize("authenticated,verified,status", [(False, False, 401), (True, False, 403)])
def test_profile_requires_verified_identity_before_accessing_store(
    method, authenticated, verified, status
):
    store = Store()
    with client_for(store, verified=verified) as client:
        response = client.request(
            method,
            "/api/v1/profile",
            json=BODY if method == "put" else None,
            headers={"Authorization": "Bearer test"} if authenticated else {},
        )
    assert response.status_code == status
    assert store.calls == []


def test_profile_is_private_and_owner_comes_from_verified_identity():
    store = Store()
    with client_for(store) as client:
        response = client.put(
            "/api/v1/profile?uid=two", json=BODY, headers={"Authorization": "Bearer test"}
        )
        assert response.status_code == 200
        assert response.json()["uid"] == "one"
        assert (
            client.get("/api/v1/profile", headers={"Authorization": "Bearer test"}).json()[
                "display_name"
            ]
            == "Demo Seeker"
        )
    with client_for(store, uid="two") as client:
        assert (
            client.get(
                "/api/v1/profile?uid=one", headers={"Authorization": "Bearer test"}
            ).status_code
            == 404
        )
    assert set(store.profiles) == {"one"}


@pytest.mark.parametrize(
    "extra", ["uid", "role", "roles", "recruiter_approved", "updated_at", "email_verified"]
)
def test_client_cannot_assign_ownership_privileges_or_server_metadata(extra):
    store = Store()
    with client_for(store) as client:
        response = client.put(
            "/api/v1/profile",
            json={**BODY, extra: "admin"},
            headers={"Authorization": "Bearer test"},
        )
    assert response.status_code == 422
    assert store.calls == []
    assert "admin" not in response.text


@pytest.mark.parametrize(
    "fields",
    [
        {"display_name": " "},
        {"display_name": "x" * 81},
        {"headline": "x" * 121},
        {"skills": [""]},
        {"skills": ["x" * 41]},
        {"skills": list(map(str, range(31)))},
        {"skills": [123]},
        {"skills": "Python"},
    ],
)
def test_invalid_fields_never_reach_storage(fields):
    store = Store()
    with client_for(store) as client:
        response = client.put(
            "/api/v1/profile", json={**BODY, **fields}, headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 422
    assert store.calls == []


def test_profile_normalizes_skills_without_inferring_matches_or_permissions():
    profile = ProfileInput(display_name="  Demo Seeker  ", skills=[" Dart ", "dart", "Python"])
    assert profile.display_name == "Demo Seeker"
    assert profile.skills == ["Dart", "Python"]


def test_unconfigured_datastore_fails_closed():
    with client_for(FirestoreProfileStore(Settings())) as client:
        response = client.get("/api/v1/profile", headers={"Authorization": "Bearer test"})
    assert response.status_code == 503
    assert response.json()["code"] == "profile_unavailable"


def test_firestore_adapter_escapes_uid_and_preserves_unrelated_server_fields(monkeypatch):
    document = Mock()
    document.set.return_value = SimpleNamespace(update_time=NOW)
    document.get.return_value = SimpleNamespace(
        exists=True,
        to_dict=lambda: {
            **BODY,
            "updated_at": NOW,
            "role": "admin",
            "uid": "spoofed",
        },
    )
    database = Mock()
    database.collection.return_value.document.return_value = document
    constructor = Mock(return_value=database)
    monkeypatch.setattr("app.profiles.firestore.Client", constructor)
    store = FirestoreProfileStore(Settings(firebase_project_id="demo-smarthire"))
    result = store.put("one/child", ProfileInput(**BODY))
    assert result.uid == "one/child"
    database.collection.assert_called_with("private_profiles")
    database.collection.return_value.document.assert_called_with("one%2Fchild")
    assert document.set.call_args.kwargs == {"merge": True, "timeout": 10, "retry": None}
    assert "role" not in document.set.call_args.args[0]
    result = store.get("one/child")
    assert result.uid == "one/child"
    assert "role" not in result.model_dump()
    assert constructor.call_count == 1


def test_firestore_outage_hides_credentials_and_profile_diagnostics(monkeypatch):
    monkeypatch.setattr(
        "app.profiles.firestore.Client", Mock(side_effect=ValueError("private credential details"))
    )
    with client_for(
        FirestoreProfileStore(Settings(firebase_project_id="demo-smarthire"))
    ) as client:
        response = client.put(
            "/api/v1/profile", json=BODY, headers={"Authorization": "Bearer test"}
        )
    assert response.status_code == 503
    assert "private" not in response.text
