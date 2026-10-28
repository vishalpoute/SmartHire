# SmartHire delivery tracker

Baseline: 21 October 2026. Target: 2 November 2026. This file records evidence, not inferred completion; deployment entries below are last verified observations.

| Milestone | Status / evidence | Remaining acceptance |
| --- | --- | --- |
| Flutter scaffold/theme/auth | Pushed; Google Web login manually confirmed by user on 18 October | Android setup and complete platform journeys |
| Private profile | API/client/editor implemented and tested; hosted saving gated | Real owner save/reload and two-account isolation |
| Company and owned job lifecycle | API implemented/tested, including approval checks and transactions | Client workflows and authenticated end-to-end proof |
| Public discovery/detail | Frontend `0f70596` deployed; 77 Flutter tests at that milestone; actual empty API-backed state verified | Live filtering/saving and populated-job acceptance |
| Admin recruiter review | POST deployed at API source `88853e4`; isolated transaction proof; Flutter queue/decision screen locally tested | Explicit administrator bootstrap, UI deployment and real admin acceptance |
| Pending review queue | Pushed `330deb2`; 243 API tests, Ruff/Bandit clean; all three remote CI checks passed | Render deployment, authenticated queue acceptance and review UI |
| Private resumes/parsing | Free private bucket and bounded offline parser/storage adapters verified with nonpersonal fixtures; 282 API tests pass | Owner API/UI, durable worker integration, authenticated isolation and consented parser evaluation |
| Matching/applications | Planned | Versioned evidence, snapshots, duplicate prevention and status workflows |
| Moderation/deletion/final release | Partial foundations | UI, retention/cleanup contracts, Android/Web acceptance and security review |

## Deployment baseline

- Preview: https://smarthire-vishalpoute.antideploy.app — frontend source `d6592f6dc359e8a45154152206b13d41987bab42`; actual index, versioned bootstrap and main JavaScript SHA-256 hashes matched on 28 October. Authenticated feature origins remain absent pending real acceptance.
- API: https://smarthire-api-ep83.onrender.com — last verified source `88853e484449f3361abd82415949cddc8875302e`.
- Queue source `330deb2f5d5590e97d58453230da72fd4672180d` is pushed but not verified deployed: Render browser navigation repeatedly timed out. Preserve the pushed work and retry hosting independently.
- Known preview scanner result: one low missing-security-headers finding; do not describe the release as finding-free.

## Priority and blockers

Next: deploy the queue, then complete authenticated profile/isolation acceptance and company/recruiter UI. Independent implementation can continue while browser-only acceptance is blocked; do not enable gated saving prematurely.

Required decisions/dependencies: explicit approval before real admin role assignment; private Storage billing/configuration and durable worker hosting; real authenticated acceptance access. Google popup limitations in the automated browser are not evidence of login failure or persistence success.

Deadline risk: core resume/application/matching and cross-platform acceptance remain open. Reassess against acceptance outcomes each milestone; report slippage without removing scope silently.

## Current implementation progress

- Company onboarding now includes the owner-bound API adapter, verified-session route, editable company form, validation, retry, pending-review receipts, unsaved-change protection and session reset. On 27 October, all 95 Flutter tests passed (including 18 focused company checks), full Flutter analysis was clean and diff whitespace checks passed. Live owner write/readback and two-account isolation remain unverified; hosted saving remains gated. This milestone has not been deployed.
- The eight root specifications now guide implementation alongside the detailed existing contracts.
- Recruiter job management now supports private draft creation/editing, owned-list recovery, explicit publication and closure with server versions, unsaved-change confirmation and session cleanup. Owned listing rechecks the active account and both ownership fields transactionally. Validation: 256 API tests, Ruff/Bandit, all 126 Flutter tests (16 focused job checks), clean analysis and release Web build. Isolated live Firestore query/cursor, two-owner isolation and suspension checks passed with fixture cleanup. No deployment or authenticated recruiter acceptance is claimed. See `docs/recruiter-jobs.md`.
- Administrator recruiter review now has a verified-session queue and reasoned approval/rejection screen, bounded pagination, stale-write reloads and private-state cleanup on session changes. On 27 October, 15 new focused tests and all 110 Flutter tests passed; analysis was clean. No administrator bootstrap, real approval or UI deployment is claimed. See `docs/recruiter-review.md`.
- Local graphify memory index built on 22 October with 1,150 nodes and 2,216 edges; all 26 documents were covered and extraction cached. Binary assets excluded. Derived navigation has 129 dangling references and 285 collapsed same-endpoint edges; verify source. Benchmark estimates 31.6x less query context, not measured account usage. Generated outputs stay ignored. Tracker changes after indexing require incremental refresh.

## Update format

For each completed milestone record source commit, pushed status, checks actually run, deployment source/status and remaining acceptance. Keep operational secrets and detailed private records outside Git. Do not add routine heartbeat entries or duplicate unchanged results.
