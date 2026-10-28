"""Nonpersonal transactional fixtures; never usable as production authentication."""

import copy
from types import SimpleNamespace
from urllib.parse import quote

from fastapi.testclient import TestClient
from google.cloud import firestore

from app.accounts import Account
from app.errors import ApiError
from app.main import create_app
from app.resume_storage import ResumeStorageFailure, UploadTicket
from app.resume_store import FirestoreResumeStore
from app.resume_worker import ResumeWorker
from app.settings import Settings


class Document:
    def __init__(self, database, collection, name):
        self.database, self.collection, self.id = database, collection, name
        self.key = (collection, name)

    def get(self, transaction=None, **options):
        if transaction is not None:
            assert not transaction.wrote, "Firestore reads must precede writes"
        data = copy.deepcopy(self.database.data.get(self.key))
        return SimpleNamespace(
            id=self.id, exists=data is not None, to_dict=lambda: copy.deepcopy(data)
        )


class Query:
    def __init__(self, database, collection, condition=None):
        self.database, self.collection, self.condition = database, collection, condition
        self.cursor = None
        self.bound = 100

    def order_by(self, field):
        assert field == "__name__"
        return self

    def start_after(self, values):
        self.cursor = values["__name__"].id
        return self

    def limit(self, value):
        self.bound = value
        self.database.limits.append(value)
        return self

    def get(self, transaction=None, **options):
        if transaction is not None:
            assert not transaction.wrote
        result = []
        for collection, name in sorted(self.database.data):
            if collection != self.collection or (self.cursor is not None and name <= self.cursor):
                continue
            data = self.database.data[(collection, name)]
            if (
                self.condition is not None
                and data.get(self.condition.field_path) != self.condition.value
            ):
                continue
            result.append(Document(self.database, collection, name).get(transaction))
        return result[: self.bound]


class Collection:
    def __init__(self, database, name):
        self.database, self.name = database, name

    def document(self, name):
        return Document(self.database, self.name, name)

    def where(self, *, filter):
        assert filter.op_string == "=="
        return Query(self.database, self.name, filter)

    def order_by(self, field):
        return Query(self.database, self.name).order_by(field)


class Transaction:
    def __init__(self, database):
        self.database, self.wrote = database, False

    def create(self, ref, data):
        assert ref.key not in self.database.data
        self.set(ref, data)

    def set(self, ref, data):
        self.wrote = True
        self.database.data[ref.key] = copy.deepcopy(data)
        self.database.writes.append(ref.key)

    def update(self, ref, changes):
        assert ref.key in self.database.data
        value = copy.deepcopy(self.database.data[ref.key])
        for key, change in changes.items():
            if change is firestore.DELETE_FIELD:
                value.pop(key, None)
            else:
                value[key] = change
        self.set(ref, value)

    def delete(self, ref):
        self.wrote = True
        self.database.data.pop(ref.key, None)
        self.database.writes.append(ref.key)


class Database:
    def __init__(self):
        self.data, self.writes, self.limits = {}, [], []

    def collection(self, name):
        return Collection(self, name)

    def transaction(self, *, max_attempts):
        assert max_attempts == 1
        return Transaction(self)


def transactional(operation):
    def execute(transaction):
        before = copy.deepcopy(transaction.database.data)
        try:
            return operation(transaction)
        except Exception:
            transaction.database.data = before
            raise

    return execute


class FixtureVerifier:
    def verify(self, token):
        if token not in ("one", "two"):
            raise ApiError(401, "invalid_token", "Please sign in again.")
        return {"uid": token, "email_verified": True}


class Accounts:
    def __init__(self, database):
        self.database = database

    def get(self, uid):
        data = self.database.data.get(("users", quote(uid, safe="")), {})
        return Account(uid=uid, account_status=data.get("account_status", "active"))


class Storage:
    def __init__(self):
        self.tickets, self.deleted = [], []
        self.failure = None

    def upload_ticket(self, uid, resume_id, extension, size, sha256):
        self.tickets.append((uid, resume_id, extension, size, sha256))
        return UploadTicket("https://storage.example.com/nonpersonal-fixture", {})

    def download_verified(self, *args):
        if self.failure:
            raise ResumeStorageFailure(self.failure)
        return b"nonpersonal fixture"

    def erase(self, *args):
        if self.failure:
            raise ResumeStorageFailure(self.failure)
        self.deleted.append(args)


def fixture_app(monkeypatch, *, storage_enabled=True):
    database = Database()
    monkeypatch.setattr("app.resume_store.firestore.transactional", transactional)
    store = FirestoreResumeStore(Settings(firebase_project_id="nonpersonal-fixture"))
    store.client = database
    storage = Storage() if storage_enabled else None
    worker = ResumeWorker(store, storage) if storage is not None else None
    accounts = Accounts(database)
    app = create_app(
        Settings(),
        token_verifier=FixtureVerifier(),
        account_store=accounts,
        resume_store=store,
        resume_storage=storage,
        resume_worker=worker,
    )
    return SimpleNamespace(
        database=database,
        store=store,
        storage=storage,
        worker=worker,
        accounts=accounts,
        client=TestClient(app),
        app=app,
    )
