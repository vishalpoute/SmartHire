# SmartHire product requirements

Owner: Vishal Poute. Target: validated Android/Web MVP by 2 November 2026. Status evidence lives in [tracker.md](tracker.md); planned features are not completion claims.

## Problem and users

Job seekers need a clear path from resume skills to suitable vacancies and application progress. Recruiters need controlled job publishing and explainable candidate comparisons. Administrators need permission-controlled recruiter review and moderation.

## Core features

| User | MVP capability |
| --- | --- |
| Visitor | Browse paginated published jobs and open shareable details |
| Seeker | Verified account, profile, private PDF/DOCX resume, correct extracted skills, review match explanations, apply and track/withdraw applications |
| Recruiter | Company onboarding and approval, owned job drafts/publishing/closure, applicants and permitted status changes |
| Administrator | Server-assigned access, approve/reject recruiters, moderate listings and inspect audit events |

Matching assists human review; it must not make automatic hiring decisions. Parsing failures produce an explicit unscored state. Defer chat, payments, scraping, video interviews, OCR and embeddings.

## Success criteria

- Google and email/password journeys work on supported platforms; protected writes require verified active accounts.
- Real authenticated profile save/reload succeeds, with two-account isolation demonstrated before public saving is enabled.
- Approved recruiters can publish and close owned jobs; anonymous discovery excludes drafts, closed jobs and ineligible publishers.
- Resume upload, parsing failure/retry and editable skill confirmation work without exposing private files.
- Applications prevent duplicates and retain job/resume version snapshots; only authorized parties can view or change them.
- Matching shows algorithm/source versions, evidence and missing skills; repeat inputs give reproducible results.
- Seeker, recruiter and admin acceptance journeys pass on Android/Web, with security findings resolved or explicitly accepted and deployment provenance recorded.
- Parser quality is measured on a consented evaluation set; record the measured results and agree numerical release thresholds before declaring parser acceptance.

No commit count or scanner result substitutes for these acceptance checks. Deadline risk must be reported; scope reductions require user agreement.
