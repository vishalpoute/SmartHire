# SmartHire API

FastAPI service foundation. This service is tested locally; it is not yet deployed to Render or connected to the Flutter client.

## Local development

Use Python 3.11 or newer (validated with 3.14.7).

```sh
python -m venv .venv
# Activate .venv for your shell.
python -m pip install -r requirements.lock.txt
python -m pip install -e . --no-deps
python -m uvicorn app.main:app --reload --host 127.0.0.1
python -m pytest -q
python -m ruff check app tests
python -m ruff format --check app tests
```

Set environment variables from `.env.example` in the server process; the application does not automatically load that file. Use Application Default Credentials with permission to check Firebase accounts. Keep credentials outside Git and frontend assets. No credentials are needed for the isolated tests, which replace SDK calls with controlled responses.

## Endpoints

- `GET /health`: public liveness only. It does not test Firebase readiness.
- `GET /api/v1/me`: requires `Authorization: Bearer <Firebase ID token>`. Returns verified `uid`, optional `email`, and `email_verified`. The Admin SDK checks token validity, revocation and disabled accounts against the configured project. Query parameters cannot select another identity. This endpoint does not grant recruiter/admin roles.

Missing or invalid authentication returns 401; unavailable verification/configuration returns 503. Expected errors use `{code, message, requestId}` without SDK diagnostics. Responses include a UUID request ID and disable caching. CORS allows only explicitly configured origins; CORS does not replace authentication.

Unexpected request failures return the same envelope with a generic 500 message. Application error logs contain only the request ID and exception type, excluding exception messages, authorization headers and query strings. Configure infrastructure access logs separately to avoid recording sensitive request data. Allowed clients can read failure responses through CORS; untrusted origins receive no CORS grant. Method errors retain the HTTP `Allow` header.

Live Firebase token verification, emulator integration, live persistence and Render deployment remain pending. The Antideploy app serves only the Flutter preview.

## Private profile contract

`GET /api/v1/profile` and `PUT /api/v1/profile` require a verified Firebase email. Both select the owner from the verified token; they accept no owner or role parameter. GET returns 404 before onboarding. PUT is a full replacement of editable fields: `display_name` (2Ã¢â‚¬â€œ80 trimmed characters), `headline` (up to 120), `location` (up to 80), and `skills` (up to 30 strings, each 1Ã¢â‚¬â€œ40 characters). Skills are trimmed and deduplicated without assigning match scores. Omitted optional fields reset to empty values. Unknown fields, including roles, ownership, verification and timestamps, return 422. Responses include the server-selected UID and server write timestamp.

The Firestore adapter writes only editable fields plus `updated_at` into `private_profiles/{escaped_uid}`, merging so unrelated server-managed metadata is preserved. Reads expose only the profile response fields. Concurrent edits currently use last-write-wins behavior; no version precondition is implemented. Missing configuration and datastore failures return 503 without diagnostic details. HTTP CORS includes PUT for explicitly configured origins.

The client is lazy, uses server Application Default Credentials and explicit `FIREBASE_PROJECT_ID`, and limits individual Firestore calls to 10 seconds without automatic retries. Do not put server credentials into the Web build. Existing client Firestore rules stay deny-all. A live Firestore database, appropriately scoped server credentials and Render API hosting must be configured and verified before enabling profile editing in Flutter. No live datastore writes were performed by the isolated tests.

## Hosting

The root [Render blueprint](../../render.yaml) and [backend deployment runbook](../../docs/backend-deployment.md) describe the free service and remaining server configuration. The blueprint is prepared but has not been applied. Local startup returned health 200 and unauthenticated identity/profile 401 responses.

## Request size boundary

HTTP request bodies are limited to 64 KiB before JSON parsing or identity verification. Actual received bytes are counted even when Content-Length is missing or misleading. Oversized input returns a sanitized 413 with request tracing and configured CORS; malformed lengths return 400. This boundary currently applies to all API routes. Future resume upload endpoints need a separate bounded streaming policy. Rate limiting and slow-client protection remain separate deployment requirements.

## Profile throttling

Verified accounts share a limit of 60 profile reads/writes per 60-second fixed window per API process. Throttled requests return 429 with Retry-After and do not access Firestore. The bounded 4096-account table fails closed with 503 when full and expires inactive windows. Client-supplied forwarding headers cannot select a bucket. This is per-process protection, resets on restart, and does not replace edge rate limiting, distributed quotas, slow-client protection or limits on invalid-token verification.


## Server-owned account status

`GET /api/v1/account` returns the authenticated owner's server-owned `role`
(seeker/recruiter/admin), `account_status` (active/suspended), and
`recruiter_approved` boolean. These fields come from `users/{escaped_uid}` in
Firestore, never token role claims, query parameters, profile input, or a stored UID.
A missing document defaults to an active seeker with no recruiter approval. Malformed
server records and datastore failures return sanitized 503 responses. No client endpoint
can create privileged roles, approve recruiters, suspend accounts or edit this record.
Client Firestore rules remain deny-all; administrative mutation/auditing is a later milestone.

Both profile reads and writes now check server suspension after verified-email and rate
checks and before profile storage. Suspended users receive 403; they can still read their
own account status. Account-status reads share the existing per-account request budget.
These checks do not yet implement recruiter job publishing or admin moderation permissions.
Isolated tests verify the policy; successful live authenticated checks remain pending.


## Private company onboarding API

`GET/PUT /api/v1/company` select one private company profile per authenticated owner.
Both require verified email and an active server account, and share the account request
budget. GET returns 404 before onboarding. PUT accepts only `name` (2–120 trimmed
characters), `description` (up to 2000), `location` (up to 80), and optional `website`
(up to 500; HTTPS without embedded credentials, whitespace or invalid ports).
Website addresses are stored as text and never fetched by this API.

The server writes `company_profiles/{escaped_uid}` and a server timestamp. Each save
sets `approval_status` to pending, including edits to previously approved profiles;
privileged account roles/approval are never assigned by this endpoint. Reads expose only
company fields, approval status, owner and timestamp. Owner/status/role fields in input
are rejected. Client Firestore rules remain deny-all. This is private onboarding only:
company UI, moderation/audit mutations, and job publishing are not yet implemented.
Future publishing must check both server recruiter permission and current company approval;
an earlier approved account must not bypass review of an edited company profile.
Live authenticated company persistence remains unverified.


## Private recruiter job drafts

`POST /api/v1/jobs` creates a private draft with a generated ID, version 1 and server
timestamps. It requires verified email, an active server account whose role is recruiter
with recruiter approval, and that same owner's currently approved company profile. Token
role claims and client/query ownership fields cannot grant access. Every request shares
the bounded account request budget. Drafts accept a bounded title, description, location,
work mode, employment type and required/preferred skill lists; incomplete requirements are
allowed while drafting. Unknown lifecycle/ownership/version fields are rejected.

`GET /api/v1/jobs/{id}` reads only a verified active user's own draft. Missing and foreign
IDs both return 404. IDs must be 32 lowercase hex characters. Firestore writes use create
semantics, bounded calls and server timestamps; client Firestore rules remain deny-all.
The private record links to `company_owner_uid`; this is not the public listing contract.
A stable public company/listing representation must be defined before public browsing.

Closure and public discovery APIs are implemented separately below. A Flutter recruiter workspace
now supports drafts, owned listing, publication and closure; deployment and authenticated acceptance
remain pending. See `../../docs/recruiter-jobs.md`. Draft create/read/edit endpoints never publish implicitly. Publication must
recheck account/company approval atomically with the transition and validate complete
requirements; earlier approval must not bypass later suspension or company edits.
Live authenticated draft creation/ownership acceptance remains unverified.


### Conflict-safe draft edits

`PUT /api/v1/jobs/{id}` fully replaces editable draft fields and requires a strict positive
`expected_version`. Current recruiter and owned-company approval are checked again. The
server reads the owned draft, rejects non-draft state or a stale version with 409, and
increments the version itself. Missing/foreign jobs return 404. Ownership, creation time,
status and unrelated server metadata are preserved; omitted optional draft fields reset.

The write uses the read snapshot's Firestore update-time precondition in addition to the
application version check. A concurrent edit or lifecycle change cannot be silently
replaced: precondition failures return sanitized 409 and the caller must reload. Storage
calls remain bounded with automatic retries disabled. The concurrency regression test
simulates two writers against the installed SDK's write-precondition representation;
actual authenticated live edits remain unverified.

Official write-option contract: https://docs.cloud.google.com/python/docs/reference/firestore/latest/google.cloud.firestore_v1.document.DocumentReference#google_cloud_firestore_v1_document_DocumentReference_update


### Explicit publication

`POST /api/v1/jobs/{id}/publish` accepts only a strict positive `expected_version`.
A Firestore transaction reads the job, server account and owned company before writing;
it rechecks active recruiter approval, current company approval, ownership, draft status
and version in that same transaction. This prevents an earlier HTTP permission check
from authorizing a publish after approval changes. Required skills and a description of
at least 20 characters are mandatory; onsite/hybrid jobs need a location, and required
and preferred skills must not overlap. Missing/foreign jobs return 404, incomplete jobs
422, denied approval 403 and lifecycle/version conflicts 409.

One transaction changes status to published, increments the version, records server
publication/update timestamps and the reviewed company name, and creates a private
`audit_events` record containing action, actor UID, job ID, version and server timestamp.
No resume, description or credential is placed in the audit event. The receipt returns
only ID/status/version; owner reads retrieve server timestamps afterward. Logical
transaction attempts are limited to one, read calls use 10-second timeouts, and begin,
commit and rollback use the installed SDK's default RPC policy. On an uncertain network
outcome, reload the job before retrying. Failed authorization never queues a write.

Public discovery is implemented by the separate public listing endpoints, and the Flutter recruiter
workspace uses this explicit transition. Real authenticated publication remains unverified.
Official transaction contract: https://docs.cloud.google.com/python/docs/reference/firestore/latest/google.cloud.firestore_v1.transaction.Transaction

An isolated live datastore check also exercised this store under a nested nonpersonal readiness fixture: publication committed version 2 and server timestamps with exactly one audit event; a stale repeat returned 409. Root account/company/job collections and Firebase identities were not modified. This verifies datastore behavior, not authenticated HTTP publication or public discovery.
