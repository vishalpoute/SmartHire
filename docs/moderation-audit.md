# Listing moderation and audit inspection

Every operation derives the actor from a verified token and rechecks the active server-owned administrator role inside its transaction. No client field or authentication provider claim grants administrator access. Bootstrap of a real administrator still needs explicit approval of a named target; fixture administrators are isolated test records only.

`GET /api/v1/admin/jobs?status=published|suspended` returns up to ten jobs and a stable document-ID cursor. `POST /api/v1/admin/jobs/{id}/moderation` requires `expected_version`, `action` and a 3–500 character reason. Suspension is allowed only from published; restore is allowed only from suspended and returns the job to draft. Both increment its version and atomically append an audit entry. Stale/invalid transitions fail without writes. Restoration never republishes a listing; the owner must pass current approval checks and explicitly publish again.

Existing public visibility and new-application checks exclude suspended listings. Existing application history remains available to its authorized parties; moderation does not rewrite previously submitted evidence. This listing-moderation feature does not grant administrators unrestricted access to raw private resumes.

`GET /api/v1/admin/audit-events` returns at most twenty allowlisted records per page: action, actor/target identifiers, reason, version and creation time. Records are ordered by document ID, not chronology. Unknown datastore fields and diagnostics are excluded. Audit events have no client mutation route. Deployment-specific errors remain generic.

The Flutter administrator screen separates published/suspended views and audit inspection. Every decision requires a reason and explicit confirmation. Stale decisions require refresh; authorization loss clears private records and sign-out fences late responses. Hosted `MODERATION_API_ORIGIN` remains absent until real administrator acceptance.

Focused tests cover server-role checks, suspension, restoration, stale versions, audit allowlisting/rollback, strict input rejection, client receipts, narrow/desktop layouts, explicit decisions and account cleanup. Full validation and real administrator acceptance are tracked separately in `tracker.md`.
