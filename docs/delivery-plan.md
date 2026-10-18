# Fifteen-day MVP delivery target

Target: 2 November 2026, measured from 18 October. This is a delivery goal, not a guarantee; report blocking dependencies and acceptance failures promptly. Commit counts do not measure completion. Use the configured default agent/model without pinning an override.

| Dates | Deliverable and exit check |
| --- | --- |
| 18-20 October | Verify live sign-in and owner-scoped profile persistence; register Android; test restrictive rules and two-account isolation. |
| 21-23 October | Seeker/company profiles, server-assigned recruiter approval and owned job publishing; persisted discovery with pagination. |
| 24-26 October | Private PDF/DOCX upload, bounded parsing tasks, extraction failure recovery and editable skill confirmation. |
| 27-29 October | Explainable versioned matching, application snapshots, seeker tracking and recruiter status workflow. |
| 30 October-2 November | Admin moderation, deletion/audit behavior, parser evaluation, Android/Web end-to-end checks, security fixes, deployment and demo. |

Security gates: verify token revocation and email checks, owner/role authorization, restrictive client rules, upload limits/type validation, safe parsing, secrets handling, dependency vulnerabilities and safe error responses. Record actual evidence and residual risks. Review the deployed frontend and API separately. Never replace Firebase/FastAPI with the preview host's data or identity services.

First blocker: authenticated profile API round trips and successful Google login remain unverified. Resume storage billing/configuration and durable worker hosting may require user input. Keep credentials and private operational records outside this public repository. Defer extra polish before cutting acceptance criteria; any scope reduction requires user agreement.
