# SmartHire working rules

## Product and architecture

- Work from these root specifications and existing detailed `docs/` contracts. Preserve Firebase/FastAPI identity/data boundaries and the feature-first Flutter structure.
- Prioritize complete acceptance journeys over commit counts. Target 2 November 2026; report risks honestly. No work-hour, daily commit-count or minimum-gap restrictions remain.
- Read/update the tracker for each coherent milestone. Never label mocked, pushed or merely configured work as live/accepted.

## Safety and security

- Preserve user changes; avoid overlapping checkout sessions. Run `python scripts/work_window.py` at session start and before commit.
- Derive identity from verified tokens and privileges from server-owned state. Enforce ownership, active-account checks, strict inputs and concurrency controls.
- Never commit/output credentials, private resumes or tokens. Keep operational secrets outside the repository; client project configuration is not authorization.
- Keep hosted profile saving disabled until authenticated persistence/isolation passes. Real administrator bootstrap requires explicit user approval.
- Review relevant authorization, session isolation, file validation, Firebase rules, dependencies and deployment settings. Fix material findings and retain evidence; do not claim a full audit from scanners.

## Efficient implementation

- Use targeted searches and precise patches; no whole-file rewrites for small edits. Do not load lockfiles, binary assets, build output or full logs into model context.
- Batch independent reads and related checks. Show at most ten relevant failure lines; keep progress/final reports concise.
- Avoid redundant polling, repeated passed suites and unnecessary agent delegation. Use the configured default model; no pinned override. Usage limits cannot be bypassed or guaranteed never to exhaust.
- Do not skip necessary validation to save tokens. Reversible documentation changes need link/content checks, not unrelated application test reruns.

## Git and delivery

- Retry tested unpushed commits first. Inspect diffs/secrets and run relevant required checks before push to main; no force pushes or empty/backdated commits.
- Repo-local author: Vishal Poute <159309295+vishalpoute@users.noreply.github.com>. No co-author trailer or claims of unassisted authorship.
- Wait for required CI success before API deployment. No deployment-only commits; preserve pushed code if hosting fails.
- Hosted Web releases use the existing external Firebase definition file, compiled assets and versioned main/bootstrap names. Verify actual served response/hash and record exact source separately for frontend and API.
- Automation notifications: completed pushed milestone, material failure or required action only. Unchanged checks stay quiet; stop completion automation only after all acceptance criteria pass.
