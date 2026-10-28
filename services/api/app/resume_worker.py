"""Recoverable Firestore leases; extraction is bounded and private storage is immutable."""

import logging
from datetime import UTC, datetime, timedelta
from threading import Event, Thread

from app.errors import ApiError
from app.resume_parser import extract_resume
from app.resume_storage import ResumeStorageFailure
from app.skill_taxonomy import TAXONOMY_VERSION, suggest_skills

logger = logging.getLogger("smarthire.resume_worker")


class ResumeWorker:
    def __init__(self, store, storage):
        self.store, self.storage = store, storage
        self.stopped, self.signal = Event(), Event()
        self.thread = None

    def start(self):
        if self.thread is None:
            self.thread = Thread(target=self.run, name="resume-worker", daemon=True)
            self.thread.start()

    def wake(self):
        self.signal.set()

    def stop(self):
        self.stopped.set()
        self.signal.set()
        if self.thread is not None:
            self.thread.join(timeout=2)

    def run(self):
        backoff = 30
        while not self.stopped.is_set():
            try:
                worked = self.process_one()
                backoff = 30
                if worked:
                    continue
            except Exception as error:  # noqa: BLE001 - no record IDs, URLs, text or exception messages.
                logger.warning("resume_worker_unavailable error_type=%s", type(error).__name__)
                backoff = min(backoff * 2, 3600)
            self.signal.wait(backoff)
            self.signal.clear()

    def process_one(self):
        for resume_id, data in self.store.candidates():
            if self.stopped.is_set():
                return False
            owner, kind = data["owner_uid"], data["extension"]
            status = data["parse_status"]
            if status == "uploading" and datetime.now(UTC) - data["created_at"] > timedelta(
                minutes=15
            ):
                if not self.store.expire_upload(resume_id):
                    continue
                status = "deleting"
            if status == "deleting":
                self.storage.erase(owner, resume_id, kind)
                self.store.finish_delete(owner, resume_id)
                return True
            if status not in ("queued", "processing"):
                continue
            claimed = self.store.claim(resume_id)
            if claimed is None:
                continue
            owner, kind = claimed["owner_uid"], claimed["extension"]
            try:
                content = self.storage.download_verified(
                    owner, resume_id, kind, claimed["size"], claimed["sha256"]
                )
                result = extract_resume(content, kind)
                outcome = {
                    "parse_status": "parsed" if result.status == "parsed" else "unscored",
                    "text": result.text,
                    "error_code": result.error_code,
                    "parser_version": result.parser_version,
                    "taxonomy_version": TAXONOMY_VERSION,
                    "extracted_skills": suggest_skills(result.text) if result.text else [],
                }
            except ResumeStorageFailure as error:
                outcome = {
                    "parse_status": "unscored",
                    "error_code": error.code,
                    "taxonomy_version": TAXONOMY_VERSION,
                }
            try:
                self.store.finish(resume_id, claimed["lease_token"], outcome)
            except ApiError as error:
                if error.status != 403:
                    raise
                # Suspension raced extraction; discard the result. Lease recovery records inactivity.
            return True
        return False
