# Recruiter review API

POST /api/v1/admin/recruiter-reviews accepts target_uid, decision (approved or rejected), expected_company_updated_at (the pending company timestamp including timezone), and reason (3-500 characters). Only a verified, active user with a server-assigned admin role can call it; token role claims do not grant access. This endpoint cannot create administrators or restore suspended users.

The transaction rechecks the acting administrator, target account and pending company. Self-review, administrator targets and suspended targets are rejected. A stale company timestamp or already reviewed request returns 409; reload the submitted company before retrying. The transaction updates company approval and its server timestamp, merges recruiter_approved into the account (assigning only recruiter on approval), and creates a private audit event containing the actor, target, decision and reason. Rejection does not remove unrelated roles or account metadata. A subsequent company edit resets review to pending as before.

The response contains only target_uid and decision. It does not echo the private review reason or claim a client timestamp. Document reads use ten-second timeouts without retry; transaction begin/commit retain SDK defaults. Transaction conflicts require a reload rather than automatic re-execution.

Administrative bootstrap, a pending-request queue and review UI remain pending. No administrator role or real recruiter approval was assigned while implementing this endpoint. Actual authenticated administrator review has not been verified. SDK integration validation uses nonpersonal nested _deployment_checks fixtures only, isolated from application collections and Firebase identities.
