# Live discovery and saved roles

Public listing accepts bounded `search` (80 characters), `work_mode` (remote/hybrid/onsite) and `employment_type` (full_time/part_time/contract/internship). Search requires every case-insensitive whitespace-separated term to appear in the public role title, company, location or skill fields. Filters combine with AND. Description/private ownership fields are not searched. This is bounded substring discovery, not ranked full-text search.

The existing status/name query scans at most the requested page size (maximum ten) plus one lookahead. Every scanned result rechecks current approval/visibility before filtering. Sparse and empty pages may have a cursor; clients must continue rather than conclude that no matching roles exist. Cursor progress follows scanned candidates, never only matching items. No unbounded fill scan or new composite index is introduced. Flutter submits filters explicitly, resets pagination when they change, preserves filters during further pages and discards stale results from previous queries.

Saved roles use the verified active seeker's identity. `POST /api/v1/saved-jobs/{job_id}` persists a bookmark and is idempotent. New saves require current public job visibility; an atomic per-owner counter limits bookmarks to 100. `DELETE` is owner-selected and idempotent. `GET /api/v1/saved-jobs` returns ten owned bookmarks and a stable cursor. There is no client-supplied owner field. Recruiter/admin accounts cannot use seeker bookmarks.

Visibility is rechecked for each bookmark. Closed, hidden or approval-revoked jobs return a removable bookmark with `job: null`; private job fields are never exposed. A foreign owner cannot remove or list another owner's bookmarks. Firestore stores only owner UID, job ID and saved timestamp; no resume, token or copied job description is retained. Account cleanup must include bookmarks and `_saved_job_counts`.

The Flutter account screen opens persisted saved roles. Available job details can open a save action when `SAVED_JOBS_API_ORIGIN` is configured. Session changes clear private state and fence late responses. Hosted authenticated origins remain disabled until real owner/two-account acceptance. Sample-job session bookmarks remain explicitly separate from this API-backed feature.

Validation: all 344 API tests and 171 Flutter tests pass; analysis, Ruff and Bandit pass. Isolated live Firestore checks verified idempotence, party isolation, removal and fixture cleanup. These checks do not establish authenticated HTTP or hosted acceptance.
