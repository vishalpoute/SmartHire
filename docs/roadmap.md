# Delivery roadmap

Current target: validated MVP by 2 November 2026. See [delivery plan](delivery-plan.md) for sequencing and security gates. Daily commit quotas and minimum spacing were removed at the user's request on 18 October.

## Completed

- [x] Android/Web scaffold and feature-first project structure
- [x] Shared Material theme and adaptive discovery layout
- [x] Repository-backed job search, work-mode filters, session bookmarks and job details
- [x] Initial domain/widget checks and Flutter CI
- [x] Named routes, responsive sign-in/register/reset previews and form validation
- [x] Firebase dependency/bootstrap boundary, example client configuration and restrictive emulator rule scaffold
- [x] Firebase authentication repository and tested session/action state, ready for form integration
- [x] Conditional account-form integration, session summary, verification refresh and sign-out with controlled UI tests
- [x] FastAPI liveness and protected identity endpoint, fail-closed Firebase token adapter and isolated API tests
- [x] Sanitized unexpected API failures with request tracing, safe outage responses and preserved HTTP/CORS behavior

- [x] Job discovery sorting and filter reset that preserves saved jobs and view selection

- [x] Dedicated role detail routes with copyable Web links, session saves and unavailable/retry states

- [x] Firebase Spark development project and Web app registration, email/password provider and preview domain configured

- [x] Web Google sign-in action, safe popup/cancellation feedback and controlled regression tests; live Google completion requires user verification

- [x] Protected profile overview route that hides identity on sign-out or session failure; persistent onboarding remains pending

- [x] Private profile API contract and Firestore adapter with verified-email/ownership checks and isolated persistence/validation tests (live deployment pending)

- [x] Free Render API service blueprint and hosting runbook; local startup smoke check passed, Render service live with health 200/protected routes 401; dedicated server credentials installed and Firestore readiness verified; authenticated profile persistence remains pending

- [x] Immutable Flutter profile payload/response contract, editor field validation and malformed-response checks; editor and authenticated persistence remain pending

- [x] Profile load/save state with draft-preserving failure/retry, duplicate-submit protection and reset/late-response isolation; HTTP adapter and editor integration remain pending

- [x] Responsive profile editor component with validation, save feedback and preserved failed edits; route wiring and authenticated API integration remain pending

- [x] Dio profile API adapter with bounded requests, session/ownership checks and safe errors; live Firebase token provider and editor route integration remain pending

- [x] Firebase profile token provider bound to the signed-in owner, with refreshed tokens, verification checks and account-change rejection; editor routing and live persistence remain pending

- [x] Protected editor route with verification gate, initial-load retry and session-scoped disposal; live saving remains disabled until server identity and persistence are verified

- [x] Profile-editor unsaved-edit back-navigation confirmation with explicit discard and saved-state reset; browser reload/tab closure protection remains out of scope

- [x] API request-byte limit before JSON/auth processing, including chunked and misleading-length regression coverage

- [x] Bounded per-process verified-account profile throttling with Retry-After; edge/distributed abuse controls remain pending

## Next milestones

1. Register Android and verify successful live authentication, Google completion and local emulator/rules behavior.
2. Add persistent profile onboarding with scoped data rules and server permission checks.
3. Verify API authentication with the live Firebase project, then add permission checks and Render deployment.
4. Seeker profiles, company profiles and server-managed recruiter approval.
5. Firestore job repository, scoped rules, indexes and job publishing.
6. Private resume upload, durable parsing tasks and skill confirmation.
7. Versioned skill-match scoring with evidence and missing skills.
8. Applications, resume snapshots and recruiter status management.
9. Admin moderation, audit events and deletion workflows.
10. Parser evaluation, performance profiling, production deployment and portfolio demo.

Each milestone can span several commits. Prefer a small verified feature over an arbitrary file count. Do not publish unfinished features as completed.

## Integration prerequisites

Firebase development/production project IDs and client configuration, Storage billing setup, and Render deployment access will be needed before live integration. Request them at the appropriate milestone. Never put service-account credentials in a client or repository.

Security follow-up: concurrent profile requests share one account budget; browser clients can read Retry-After on throttled responses. Authenticated live profile saving remains disabled pending verification.

- Backend CI runs pinned Bandit static analysis on application code; all workflows request read-only repository contents permission. This complements authorization tests and manual review.

- Credential-safe manual two-account live profile checker added, with explicit disposable-profile write consent and regression checks; real authenticated acceptance remains pending.

- Server-owned account status endpoint and suspension checks before profile access, with fail-closed datastore handling and role-claim/ownership escalation tests. Live authenticated account/profile checks remain pending; no administrative mutation interface exists yet.

- Private company onboarding GET/PUT API with owner-selected documents, verified/active-account checks, bounded fields, safe datastore errors and review reset on edits. Isolated contract/security tests pass; company UI, moderation and live authenticated persistence remain pending.

- Profile client now distinguishes suspended accounts, email-verification requirements, generic access denial and throttling with fixed safe messages; server diagnostics remain hidden.
