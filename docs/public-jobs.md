# Public job discovery contract

`GET /api/v1/public/jobs?page_size=10&cursor=<last scanned ID>` returns `{items, next_cursor}` without login. Page size is 1–10; omit the cursor for the first page. Cursors are lowercase 32-character hexadecimal job IDs. They select a position, never a document path or a permission.

Ordering is ascending document ID, not recency or relevance. The server queries at most page_size + 1 published candidates and rechecks at most page_size candidate details. Current recruiter suspension/approval and company approval are checked with each job in a consistent transaction snapshot. Draft, closed and suspended jobs are hidden. Visibility can change between pages; pagination is not a snapshot of the entire collection.

Pages may be sparse or empty after moderation checks and still contain next_cursor. Continue until next_cursor is null; do not infer completion from items.length. The cursor advances past the last scanned candidate so hidden entries do not cause loops. Filtering, search and recency ordering remain pending.

`GET /api/v1/public/jobs/{id}` returns only job content, ID, published company name and publication time. Owner UIDs, private notes, server version and audit fields are excluded. Hidden and absent details return the same 404. Malformed parameters return 422; datastore failures return a safe 503. Responses use no-store to avoid serving cached moderation state.

Anonymous budgets are shared per process: 20 listing requests/minute and 120 detail requests/minute. Exhaustion returns 429 with Retry-After. These limits bound datastore work but one caller can consume the shared budget; distributed and edge abuse protection remain pending. A listing reads up to 11 query documents plus up to three documents for each of ten candidate checks. SDK document/query reads use ten-second timeouts without retries; transaction begin/commit retain SDK defaults.

Flutter still uses sample jobs. This backend contract is not evidence of completed discovery UI or authenticated recruiter publishing acceptance.
