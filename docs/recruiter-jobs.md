# Recruiter job workspace

The Flutter `/recruiter/jobs` route is available from Manage account. Configure an HTTPS origin with `RECRUITER_JOBS_API_ORIGIN`; otherwise the feature reports that it is unavailable. Verified Firebase identity is required before creating a repository. Server account and company approval checks remain authoritative for all writes.

Recruiters can create private drafts, reopen an owned job from the paginated list or by ID, edit draft fields, publish a complete saved draft, and close a published vacancy. Publishing and closing require explicit confirmation. Unsaved edits block publication and require confirmation before leaving or loading another job. Server receipts must match the expected owner, job ID, lifecycle and version. No operation publishes implicitly.

Save failures preserve edits and disable further writes until the current record is reloaded. A failed create may already have committed; use Load my jobs to recover the record before creating another draft. There is no automatic write retry or claim of exactly-once creation. Successful transitions are followed by an owner read to obtain the current server record. Account changes dispose private state; authorization failures clear loaded job fields and lists.

## Owned-job listing API

`GET /api/v1/jobs` returns an `items` array of the existing private JobDraft contract and `next_cursor`. `page_size` defaults to 10 and is bounded to 1–20; `cursor` must be a 32-character lowercase hexadecimal job ID. Results are ordered by document ID. The query is constrained to the verified token owner's recruiter UID. Client owner/query parameters cannot change ownership.

The read transaction rechecks the account is present and active, reads at most page_size + 1 jobs, validates both recruiter and company ownership, and returns only explicitly defined fields. Missing/revoked accounts cannot read the list even if the earlier HTTP account check succeeded. Malformed/foreign stored records and query errors fail closed with a safe response. Client Firestore rules remain deny-all. Listing remains available to an active former recruiter so they can retrieve and close a previously published vacancy without requiring fresh company approval.

The frontend requests ten rows at a time and rejects malformed, duplicate, foreign-owner and non-advancing pages. This endpoint must be deployed before enabling the list in a hosted frontend. An isolated live Firestore check passed for the actual query/cursor, two fixture owners, field allowlisting and suspension; the nonpersonal nested `_deployment_checks` records were removed afterward, and root application collections were untouched. Authenticated HTTP two-account isolation remains unverified.

## Local validation

On 27 October, all 256 API tests passed, including 13 new list security/contract checks. Ruff and Bandit checks passed. All 126 Flutter tests passed, analysis was clean, and the release Web build succeeded using the external Firebase definition file. Sixteen focused Flutter tests cover create/edit/list/publish/close, malformed receipts, owner checks, stale writes, explicit confirmations, phone/desktop layouts and late-response isolation. Live recruiter acceptance, deployment and populated public discovery remain separate release requirements.
