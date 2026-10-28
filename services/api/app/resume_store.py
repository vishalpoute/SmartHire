"""Transactional resume ownership, upload budgets and durable processing leases."""

import hashlib
import re
from datetime import UTC, datetime, timedelta
from threading import Lock
from urllib.parse import quote
from uuid import uuid4

from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter

from app.errors import ApiError
from app.resumes import ParseOutcome, ResumePage, ResumeSnapshot


def snapshot(resume_id, data):
    return ResumeSnapshot(
        id=resume_id,
        **{key: data[key] for key in ResumeSnapshot.model_fields if key != "id" and key in data},
    )


def require_owned(uid, data):
    if not data or data.get("owner_uid") != uid:
        raise ApiError(404, "resume_unavailable", "Resume is unavailable.")


def require_revision(data, expected):
    if data["revision"] != expected:
        raise ApiError(409, "resume_changed", "This resume changed. Reload before retrying.")


def require_uploadable(data, now):
    if data["parse_status"] != "uploading" or now - data["created_at"] > timedelta(minutes=15):
        raise ApiError(
            409, "upload_expired", "Start a new upload; this upload is no longer available."
        )


def guarded(operation):
    def call(*args, **kwargs):
        try:
            return operation(*args, **kwargs)
        except ApiError:
            raise
        except Exception:  # noqa: BLE001 - never expose private records or datastore diagnostics.
            raise ApiError(
                503, "resumes_unavailable", "Resumes are temporarily unavailable."
            ) from None

    return call


class FirestoreResumeStore:
    def __init__(self, settings):
        self.settings = settings
        self.client = None
        self.lock = Lock()

    def collection(self):
        if not self.settings.firebase_project_id:
            raise ValueError("Missing project")
        with self.lock:
            if self.client is None:
                self.client = firestore.Client(project=self.settings.firebase_project_id)
        return self.client.collection("resumes")

    def account(self, transaction, uid):
        account = (
            self.client.collection("users")
            .document(quote(uid, safe=""))
            .get(transaction=transaction, timeout=10, retry=None)
        )
        if account.exists and account.to_dict().get("account_status", "active") != "active":
            raise ApiError(403, "account_inactive", "An active account is required.")

    def owned(self, transaction, uid, ref):
        self.account(transaction, uid)
        record = ref.get(transaction=transaction, timeout=10, retry=None)
        data = record.to_dict() if record.exists else None
        require_owned(uid, data)
        return data

    @guarded
    def create(self, uid, command):
        resume_id = hashlib.sha256((uid + "\0" + command.upload_id).encode()).hexdigest()[:32]
        ref = self.collection().document(resume_id)
        now = datetime.now(UTC)
        day = now.strftime("%Y%m%d")
        limits = self.client.collection("_resume_upload_limits")
        owner_limit = limits.document(hashlib.sha256(uid.encode()).hexdigest() + "-" + day)
        global_limit = limits.document("global-" + day)

        @firestore.transactional
        def write(transaction):
            self.account(transaction, uid)
            old = ref.get(transaction=transaction, timeout=10, retry=None)
            if old.exists:
                data = old.to_dict()
                if data.get("parse_status") == "deleted":
                    raise ApiError(
                        409, "upload_expired", "Start a new upload for a removed resume."
                    )
                require_owned(uid, data)
                if any(
                    data[key] != getattr(command, key) for key in ("extension", "size", "sha256")
                ):
                    raise ApiError(
                        409, "upload_changed", "Start a new upload for a different file."
                    )
                if data["parse_status"] == "uploading":
                    require_uploadable(data, now)
                return snapshot(resume_id, data)
            counters = [
                ref.get(transaction=transaction, timeout=10, retry=None)
                for ref in (owner_limit, global_limit)
            ]
            counts = [item.to_dict().get("count", 0) if item.exists else 0 for item in counters]
            if any(type(value) is not int or value < 0 for value in counts):
                raise ValueError("Invalid upload budget")
            if counts[0] >= 5 or counts[1] >= 100:
                raise ApiError(
                    429, "upload_budget", "Today's upload budget is reached. Try tomorrow."
                )
            data = {
                "owner_uid": uid,
                "version": 1,
                "revision": 1,
                "extension": command.extension,
                "size": command.size,
                "sha256": command.sha256,
                "parse_status": "uploading",
                "extracted_skills": [],
                "confirmed_skills": None,
                "skills_version": 0,
                "created_at": now,
                "updated_at": now,
                "attempts": 0,
            }
            transaction.create(ref, data)
            for limit, count in zip((owner_limit, global_limit), counts, strict=True):
                transaction.set(limit, {"count": count + 1, "day": day})
            return snapshot(resume_id, data)

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def get_owned(self, uid, resume_id):
        ref = self.collection().document(resume_id)

        @firestore.transactional
        def read(transaction):
            return snapshot(resume_id, self.owned(transaction, uid, ref))

        return read(self.client.transaction(max_attempts=1))

    @guarded
    def list_owned(self, uid, cursor=None):
        collection = self.collection()
        query = collection.where(filter=FieldFilter("owner_uid", "==", uid)).order_by("__name__")
        if cursor is not None:
            query = query.start_after({"__name__": collection.document(cursor)})

        @firestore.transactional
        def read(transaction):
            self.account(transaction, uid)
            records = list(query.limit(11).get(transaction=transaction, timeout=10, retry=None))
            items = []
            for record in records[:10]:
                data = record.to_dict()
                require_owned(uid, data)
                items.append(snapshot(record.id, data))
            return ResumePage(items=items, next_cursor=items[-1].id if len(records) > 10 else None)

        return read(self.client.transaction(max_attempts=1))

    def mutate(self, uid, resume_id, change):
        ref = self.collection().document(resume_id)

        @firestore.transactional
        def write(transaction):
            data = self.owned(transaction, uid, ref)
            changes = change(data)
            changes.update(revision=data["revision"] + 1, updated_at=datetime.now(UTC))
            transaction.update(ref, changes)
            return snapshot(resume_id, {**data, **changes})

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def uploadable(self, uid, resume_id):
        value = self.get_owned(uid, resume_id)
        require_uploadable(value.model_dump(), datetime.now(UTC))
        return value

    @guarded
    def queue(self, uid, resume_id, expected):
        def change(data):
            require_revision(data, expected)
            require_uploadable(data, datetime.now(UTC))
            return {"parse_status": "queued", "error_code": None}

        return self.mutate(uid, resume_id, change)

    @guarded
    def confirm(self, uid, resume_id, command):
        def change(data):
            require_revision(data, command.expected_revision)
            if data["parse_status"] not in ("parsed", "confirmed"):
                raise ApiError(409, "resume_unscored", "A successfully parsed resume is required.")
            return {
                "parse_status": "confirmed",
                "confirmed_skills": command.skills,
                "skills_version": data["skills_version"] + 1,
            }

        return self.mutate(uid, resume_id, change)

    @guarded
    def retry(self, uid, resume_id, expected):
        def change(data):
            require_revision(data, expected)
            if (
                data["parse_status"] != "unscored"
                or data.get("attempts", 0) >= 3
                or data.get("error_code") not in ("resource_limit", "storage_unavailable")
            ):
                raise ApiError(
                    409, "retry_unavailable", "Upload a new text PDF or DOCX to continue."
                )
            return {"parse_status": "queued", "error_code": None}

        return self.mutate(uid, resume_id, change)

    @guarded
    def mark_deleting(self, uid, resume_id, expected):
        def change(data):
            require_revision(data, expected)
            return {
                "parse_status": "deleting",
                "text": None,
                "extracted_skills": [],
                "confirmed_skills": None,
                "lease_token": firestore.DELETE_FIELD,
                "lease_until": firestore.DELETE_FIELD,
            }

        return self.mutate(uid, resume_id, change)

    @guarded
    def finish_delete(self, uid, resume_id):
        ref = self.collection().document(resume_id)

        @firestore.transactional
        def write(transaction):
            record = ref.get(transaction=transaction, timeout=10, retry=None)
            if not record.exists:
                return
            data = record.to_dict()
            if data.get("parse_status") == "deleted":
                return
            require_owned(uid, data)
            if data["parse_status"] != "deleting":
                raise ApiError(409, "resume_changed", "Resume deletion was not requested.")
            transaction.set(ref, {"parse_status": "deleted", "deleted_at": datetime.now(UTC)})

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def expire_upload(self, resume_id):
        ref = self.collection().document(resume_id)

        @firestore.transactional
        def write(transaction):
            record = ref.get(transaction=transaction, timeout=10, retry=None)
            if not record.exists:
                return False
            data = record.to_dict()
            now = datetime.now(UTC)
            if data["parse_status"] != "uploading" or now - data["created_at"] <= timedelta(
                minutes=15
            ):
                return False
            transaction.update(
                ref,
                {
                    "parse_status": "deleting",
                    "text": None,
                    "confirmed_skills": None,
                    "extracted_skills": [],
                    "revision": data["revision"] + 1,
                    "updated_at": now,
                },
            )
            return True

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def candidates(self):
        collection = self.collection()
        result = []
        for status in ("deleting", "queued", "processing", "uploading"):
            result.extend(
                collection.where(filter=FieldFilter("parse_status", "==", status))
                .order_by("__name__")
                .limit(5)
                .get(timeout=10, retry=None)
            )
        return [(record.id, record.to_dict()) for record in result]

    @guarded
    def claim(self, resume_id):
        ref = self.collection().document(resume_id)
        now = datetime.now(UTC)

        @firestore.transactional
        def write(transaction):
            record = ref.get(transaction=transaction, timeout=10, retry=None)
            if not record.exists:
                return None
            data = record.to_dict()
            if data["parse_status"] not in ("queued", "processing"):
                return None
            try:
                self.account(transaction, data["owner_uid"])
            except ApiError as error:
                if error.status != 403:
                    raise
                transaction.update(
                    ref,
                    {
                        "parse_status": "unscored",
                        "error_code": "account_inactive",
                        "text": None,
                        "extracted_skills": [],
                        "revision": data["revision"] + 1,
                        "updated_at": now,
                        "lease_token": firestore.DELETE_FIELD,
                        "lease_until": firestore.DELETE_FIELD,
                    },
                )
                return None
            if data["parse_status"] == "processing" and data.get("lease_until", now) > now:
                return None
            if data.get("attempts", 0) >= 3:
                transaction.update(
                    ref,
                    {
                        "parse_status": "unscored",
                        "error_code": "resource_limit",
                        "text": None,
                        "extracted_skills": [],
                        "revision": data["revision"] + 1,
                        "updated_at": now,
                        "lease_token": firestore.DELETE_FIELD,
                        "lease_until": firestore.DELETE_FIELD,
                    },
                )
                return None
            changes = {
                "parse_status": "processing",
                "lease_token": uuid4().hex,
                "lease_until": now + timedelta(seconds=90),
                "attempts": data.get("attempts", 0) + 1,
                "revision": data["revision"] + 1,
                "updated_at": now,
            }
            transaction.update(ref, changes)
            return {**data, **changes, "id": resume_id}

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def finish(self, resume_id, lease, result):
        if not isinstance(lease, str) or not re.fullmatch(r"[0-9a-f]{32}", lease):
            return False
        result = ParseOutcome.model_validate(result).model_dump()
        ref = self.collection().document(resume_id)

        @firestore.transactional
        def write(transaction):
            record = ref.get(transaction=transaction, timeout=10, retry=None)
            if not record.exists:
                return False
            data = record.to_dict()
            if data.get("lease_token") != lease or data["parse_status"] != "processing":
                return False
            self.account(transaction, data["owner_uid"])
            transaction.update(
                ref,
                {
                    **result,
                    "lease_token": firestore.DELETE_FIELD,
                    "lease_until": firestore.DELETE_FIELD,
                    "revision": data["revision"] + 1,
                    "updated_at": datetime.now(UTC),
                },
            )
            return True

        return write(self.client.transaction(max_attempts=1))
