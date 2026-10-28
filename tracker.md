# SmartHire delivery tracker

Baseline: 21 October 2026. Target: 2 November 2026. This file records evidence, not inferred completion; deployment entries below are last verified observations.

| Milestone | Status / evidence | Remaining acceptance |
| --- | --- | --- |
| Flutter scaffold/theme/auth | Pushed; Google Web login manually confirmed by user on 18 October | Android setup and complete platform journeys |
| Private profile | API/client/editor implemented and tested; hosted saving gated | Real owner save/reload and two-account isolation |
| Company and owned job lifecycle | API implemented/tested, including approval checks and transactions | Client workflows and authenticated end-to-end proof |
| Public discovery/detail | Live bounded search/mode/employment filters and owner-persisted saved roles implemented; 344 API/171 Flutter tests and isolated Firestore bookmark checks pass | Deploy latest client/API and populated real-account acceptance |
| Admin recruiter review | POST deployed at API source `88853e4`; isolated transaction proof; Flutter queue/decision screen locally tested | Explicit administrator bootstrap, UI deployment and real admin acceptance |
| Pending review queue | Pushed `330deb2`; 243 API tests, Ruff/Bandit clean; all three remote CI checks passed | Render deployment, authenticated queue acceptance and review UI |
| Private resumes/parsing | Owner API, durable leases, explicit skill confirmation/deletion and Flutter screen implemented; 305 API tests plus two lease regressions and 150 Flutter tests pass; real storage/Firestore fixture verified | Render secret import and deployed worker, authenticated isolation and consented parser evaluation |
| Matching/applications | Versioned coverage, immutable duplicate-safe applications, tracking/withdrawal and recruiter decisions implemented; 337 API/163 Flutter tests and real isolated Firestore checks pass | Deployment, real authenticated parties and Android journeys |
| Moderation/deletion/final release | Admin moderation/audit and terminal history removal implemented; 353 API/177 Flutter tests, analysis/Ruff/Bandit/Web build and isolated live Firestore checks pass | Deployment, real administrator/Android/Web acceptance, parser evaluation and security review |

## Deployment baseline

- Preview: https://smarthire-vishalpoute.antideploy.app — frontend source `d6592f6dc359e8a45154152206b13d41987bab42`; actual index, versioned bootstrap and main JavaScript SHA-256 hashes matched on 28 October. Authenticated feature origins remain absent pending real acceptance.
- API: https://smarthire-api-ep83.onrender.com — verified source `d6592f6dc359e8a45154152206b13d41987bab42`, Render deploy `dep-dbgnk36gekts738e3jjg` live. OpenAPI verified owned job listing and review queue. A later CORS request timed out; it is not evidence of resume deployment.
- Known preview scanner result: one low missing-security-headers finding; do not describe the release as finding-free.

## Priority and blockers

Next: deploy the resume workflow after CI and private secret import; implement matching/applications and finish authenticated profile/isolation acceptance. Independent implementation can continue while browser-only acceptance is blocked; do not enable gated saving prematurely.

Required decisions/dependencies: explicit named administrator approval and real authenticated acceptance access. Free private storage is provisioned; secrets require secure import into the existing free Render service. Its in-process worker persists leases but pauses during free-service sleep. Google popup limitations in the automated browser are not evidence of login failure or persistence success.

Deadline risk: core resume/application/matching and cross-platform acceptance remain open. Reassess against acceptance outcomes each milestone; report slippage without removing scope silently.

## Current implementation progress

- Admin moderation now provides bounded published/suspended listings, reasoned versioned suspension/restore-to-draft and allowlisted audit inspection. Every request rechecks server-owned administrator access. Terminal application history may be removed by its seeker with explicit confirmation; snapshots and party identifiers are erased, replay markers and accountability audits retained, and original resumes remain separate. Real administrator bootstrap remains unperformed. See `docs/moderation-audit.md` and `docs/matching-applications.md`.

- Discovery now submits search/work-mode/employment filters to the real API with bounded sparse-page continuation and stale-query fencing. Saved roles persist under server-selected ownership with idempotent save/remove, an atomic 100-role limit and safe unavailable-job placeholders. Real Firestore bookmark isolation/removal passed with cleanup. See `docs/discovery-saved-jobs.md`.

- Matching/application workflows now pin job/resume/skill/parser/algorithm versions, show exact evidence/missing skills, distinguish unscored from zero coverage and require explicit submission/decisions. Duplicate application and status/audit writes are atomic. Revoked recruiter approval removes candidate access. Private originals are never shared. Isolated real Firestore ownership/query/snapshot/stale-write/revocation checks passed and fixtures were cleaned. See `docs/matching-applications.md`; hosted and authenticated acceptance remain pending.

- Private resumes now include bounded selection/upload, immutable source checks, persisted worker leases/recovery, editable taxonomy suggestions, explicit skill confirmation and deletion with replay protection. Firebase tokens never go to S3. Owner isolation, stale versions, suspension races and pending cleanup have tests. Live nonpersonal S3/Firestore verification passed and cleaned its fixtures; this does not replace real authenticated HTTP acceptance. Flutter analysis, release Web build, Ruff and Bandit passed. See `docs/private-resumes.md`.

- Company onboarding now includes the owner-bound API adapter, verified-session route, editable company form, validation, retry, pending-review receipts, unsaved-change protection and session reset. On 27 October, all 95 Flutter tests passed (including 18 focused company checks), full Flutter analysis was clean and diff whitespace checks passed. Live owner write/readback and two-account isolation remain unverified; hosted saving remains gated. This milestone has not been deployed.
- The eight root specifications now guide implementation alongside the detailed existing contracts.
- Recruiter job management now supports private draft creation/editing, owned-list recovery, explicit publication and closure with server versions, unsaved-change confirmation and session cleanup. Owned listing rechecks the active account and both ownership fields transactionally. Validation: 256 API tests, Ruff/Bandit, all 126 Flutter tests (16 focused job checks), clean analysis and release Web build. Isolated live Firestore query/cursor, two-owner isolation and suspension checks passed with fixture cleanup. No deployment or authenticated recruiter acceptance is claimed. See `docs/recruiter-jobs.md`.
- Administrator recruiter review now has a verified-session queue and reasoned approval/rejection screen, bounded pagination, stale-write reloads and private-state cleanup on session changes. On 27 October, 15 new focused tests and all 110 Flutter tests passed; analysis was clean. No administrator bootstrap, real approval or UI deployment is claimed. See `docs/recruiter-review.md`.
- Local graphify memory index built on 22 October with 1,150 nodes and 2,216 edges; all 26 documents were covered and extraction cached. Binary assets excluded. Derived navigation has 129 dangling references and 285 collapsed same-endpoint edges; verify source. Benchmark estimates 31.6x less query context, not measured account usage. Generated outputs stay ignored. Tracker changes after indexing require incremental refresh.

## Update format

For each completed milestone record source commit, pushed status, checks actually run, deployment source/status and remaining acceptance. Keep operational secrets and detailed private records outside Git. Do not add routine heartbeat entries or duplicate unchanged results.
