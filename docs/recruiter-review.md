# Recruiter review API

POST /api/v1/admin/recruiter-reviews accepts target_uid, decision (approved or rejected), expected_company_updated_at (the pending company timestamp including timezone), and reason (3-500 characters). Only a verified, active user with a server-assigned admin role can call it; token role claims do not grant access. This endpoint cannot create administrators or restore suspended users.

The transaction rechecks the acting administrator, target account and pending company. Self-review, administrator targets and suspended targets are rejected. A stale company timestamp or already reviewed request returns 409; reload the submitted company before retrying. The transaction updates company approval and its server timestamp, merges recruiter_approved into the account (assigning only recruiter on approval), and creates a private audit event containing the actor, target, decision and reason. Rejection does not remove unrelated roles or account metadata. A subsequent company edit resets review to pending as before.

The response contains only target_uid and decision. It does not echo the private review reason or claim a client timestamp. Document reads use ten-second timeouts without retry; transaction begin/commit retain SDK defaults. Transaction conflicts require a reload rather than automatic re-execution.

GET /api/v1/admin/recruiter-reviews returns pending company submissions in document-ID order. page_size defaults to 10 (maximum 20); pass next_cursor as cursor for the next page. The transaction rechecks the active administrator before querying, reads at most page_size + 1 submissions, and returns only company profile fields and the owner UID derived from the document path. Private metadata is excluded; malformed records fail closed. Responses are not cached.

Queue authorization, pagination, cursor validation, malformed records and safe errors are covered by regression tests; the API suite passes 243 tests. Authenticated queue acceptance remains unverified. Administrative bootstrap remains pending. No administrator role or real recruiter approval was assigned while implementing these endpoints. Actual authenticated administrator review has not been verified. SDK integration validation of the approval transaction uses nonpersonal nested _deployment_checks fixtures only, isolated from application collections and Firebase identities.

## Flutter review screen

The `/admin/recruiter-reviews` route is available from Manage account. A verified Firebase session is required before creating its repository. Configure the HTTPS API origin through `REVIEW_API_ORIGIN`; without it, the screen reports that reviews are unavailable. This definition does not grant administrator access: the server authorizes every queue read and decision from its own account record.

The screen loads ten submissions per page, displays company details, and requires a 3–500 character reason before approval or rejection. Decisions include the submitted company version; the client cannot assign administrators or override server review policy. Every failed write clears the visible queue and requires an explicit reload because the server may already have committed. Authorization/read failures also clear private records. Sign-out and account changes dispose the screen and discard late responses. The reason is neither logged nor retained after a successful decision or session change.

Local validation on 27 October: 15 new API-contract/security/widget tests passed, including narrow/desktop layouts, stale decisions and late-response isolation; the full Flutter suite passed 110 tests and analysis was clean. Real administrator acceptance and deployment remain separate requirements.
