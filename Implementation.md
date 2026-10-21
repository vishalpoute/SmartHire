# SmartHire implementation process

Target: validated MVP by 2 November 2026. Follow [PRD.md](PRD.md), [TechSpec.md](TechSpec.md), [appflow.md](appflow.md), [Design.md](Design.md), [schem.md](schem.md), [tracker.md](tracker.md) and [rules.md](rules.md). Existing `docs/` contracts provide detailed behavior; reconcile contradictions explicitly rather than silently changing acceptance criteria.

## 1. Discovery

For each milestone identify the user outcome, existing implementation, acceptance checks and external dependencies. Inspect only relevant code/contracts. Confirm unresolved product decisions before irreversible scope changes. Record evidence and blockers in the tracker.

## 2. Design

Define screen states, API payloads, ownership/role checks, lifecycle/version rules and data retention before adding UI. Reuse the current visual theme and feature boundaries. Design failure/retry and account-switch behavior alongside the happy path.

## 3. Development sequence

1. Complete real owner-profile write/readback and two-account isolation; keep public saving gated meanwhile. Complete Android registration/configuration.
2. Deliver company onboarding, recruiter review UI and owned job publishing/closure on the existing API. Deploy the already-pushed review queue after CI and hosting verification.
3. Finish persisted discovery/filter behavior without fictional outage fallbacks.
4. Configure private file storage and durable parsing worker; implement upload validation, bounded parsing and skill confirmation.
5. Implement versioned matching and duplicate-safe application snapshots, seeker tracking and recruiter status changes.
6. Complete moderation/audit/deletion behavior, evaluation, Android/Web end-to-end checks and release evidence.

Make coherent changes with precise patches. Validate before committing/pushing; retry tested unpushed work before adding new work. Do not create deployment-only commits.

## 4. Testing and release

Test behavior and security boundaries: anonymous/owner/other-user/suspended/admin cases, malformed inputs, stale versions, session changes and datastore failures. Use focused checks while developing, then required relevant suite/lint checks before push. Do not repeat passing suites without changes or unresolved concerns.

Run real authenticated acceptance separately from mocks and isolated fixtures. Review secrets, authorization, upload handling, Firebase rules and dependencies; scanner success alone is not an audit. Deploy only after CI passes, verify actual served source and record frontend/API provenance separately.

## Tracking convention

Use `planned`, `in progress`, `implemented/tested`, `pushed`, `deployed`, and `accepted` precisely. A milestone is accepted only when its user journey and security gates have evidence. Update tracker and relevant detailed docs in the feature commit.
