"""Owner-scoped bookmarks; current visibility is always rechecked."""

import hashlib
from datetime import UTC, datetime
from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, Depends, Path, Query, Request
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from pydantic import BaseModel

from app.auth import Identity
from app.errors import ApiError
from app.jobs import JobDraftInput, PublicJob
from app.matching import ID_PATTERN, FirestoreMatchStore
from app.profiles import verified_identity
from app.resume_store import guarded


class SavedJob(BaseModel):
    id: str
    job_id: str
    saved_at: datetime
    job: PublicJob | None


class SavedJobPage(BaseModel):
    items: list[SavedJob]
    next_cursor: str | None = None


class FirestoreSavedJobStore(FirestoreMatchStore):
    def saved_collection(self):
        self.collection()
        return self.client.collection("saved_jobs")

    def seeker(self, transaction, uid):
        if self.account_record(transaction, uid).role != "seeker":
            raise ApiError(403, "seeker_required", "A seeker account is required.")

    def receipt(self, transaction, saved_id, data):
        try:
            current = self.available_job(transaction, data["job_id"])
            job = PublicJob(
                id=current.id,
                company_name=current.company_name,
                published_at=current.published_at,
                **{key: getattr(current, key) for key in JobDraftInput.model_fields},
            )
        except ApiError as error:
            if error.status != 404:
                raise
            job = None
        return SavedJob(id=saved_id, job_id=data["job_id"], saved_at=data["saved_at"], job=job)

    @guarded
    def save(self, uid, job_id):
        saved_id = hashlib.sha256((uid + "\0" + job_id).encode()).hexdigest()[:32]
        ref = self.saved_collection().document(saved_id)
        counter = self.client.collection("_saved_job_counts").document(quote(uid, safe=""))

        @firestore.transactional
        def write(transaction):
            self.seeker(transaction, uid)
            existing = ref.get(transaction=transaction, timeout=10, retry=None)
            if existing.exists:
                data = existing.to_dict()
                if data.get("owner_uid") != uid:
                    raise ValueError("Bookmark owner mismatch")
                return self.receipt(transaction, saved_id, data)
            count = counter.get(transaction=transaction, timeout=10, retry=None)
            total = count.to_dict()["count"] if count.exists else 0
            if total >= 100:
                raise ApiError(409, "saved_limit", "Remove a saved role before saving another.")
            data = {"owner_uid": uid, "job_id": job_id, "saved_at": datetime.now(UTC)}
            receipt = self.receipt(transaction, saved_id, data)
            if receipt.job is None:
                raise ApiError(404, "job_unavailable", "This job is unavailable.")
            transaction.create(ref, data)
            transaction.set(counter, {"count": total + 1})
            return receipt

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def remove(self, uid, job_id):
        saved_id = hashlib.sha256((uid + "\0" + job_id).encode()).hexdigest()[:32]
        ref = self.saved_collection().document(saved_id)
        counter = self.client.collection("_saved_job_counts").document(quote(uid, safe=""))

        @firestore.transactional
        def write(transaction):
            self.seeker(transaction, uid)
            existing = ref.get(transaction=transaction, timeout=10, retry=None)
            count = counter.get(transaction=transaction, timeout=10, retry=None)
            if existing.exists:
                if existing.to_dict().get("owner_uid") != uid:
                    raise ValueError("Bookmark owner mismatch")
                total = count.to_dict()["count"] if count.exists else 0
                transaction.delete(ref)
                transaction.set(counter, {"count": max(0, total - 1)})
            return {"job_id": job_id, "status": "removed"}

        return write(self.client.transaction(max_attempts=1))

    @guarded
    def list_saved(self, uid, cursor):
        collection = self.saved_collection()

        @firestore.transactional
        def read(transaction):
            self.seeker(transaction, uid)
            query = collection.where(filter=FieldFilter("owner_uid", "==", uid)).order_by(
                "__name__"
            )
            if cursor:
                query = query.start_after({"__name__": collection.document(cursor)})
            rows = query.limit(11).get(transaction=transaction, timeout=10, retry=None)
            items = []
            for row in rows[:10]:
                data = row.to_dict()
                if data.get("owner_uid") != uid:
                    raise ValueError("Bookmark owner mismatch")
                items.append(self.receipt(transaction, row.id, data))
            return SavedJobPage(items=items, next_cursor=rows[9].id if len(rows) > 10 else None)

        return read(self.client.transaction(max_attempts=1))


router = APIRouter(prefix="/api/v1/saved-jobs", tags=["saved jobs"])


@router.get("", response_model=SavedJobPage)
def list_saved_jobs(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    cursor: Annotated[str | None, Query(pattern=ID_PATTERN)] = None,
):
    return request.app.state.saved_job_store.list_saved(identity.uid, cursor)


@router.post("/{job_id}", response_model=SavedJob, status_code=201)
def save_job(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    job_id: Annotated[str, Path(pattern=ID_PATTERN)],
):
    return request.app.state.saved_job_store.save(identity.uid, job_id)


@router.delete("/{job_id}")
def remove_saved_job(
    request: Request,
    identity: Annotated[Identity, Depends(verified_identity)],
    job_id: Annotated[str, Path(pattern=ID_PATTERN)],
):
    return request.app.state.saved_job_store.remove(identity.uid, job_id)
