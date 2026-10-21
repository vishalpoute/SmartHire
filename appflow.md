# SmartHire application flow

## Entry and identity

Visitor → job discovery → job detail. Sign in/register/reset are reachable without losing the intended destination. Firebase sign-in → account summary → verification gate for protected changes. Sign-out/account switch clears private state and discards late responses from the previous session.

## Seeker journey

Account → profile overview → editor → save/reload → resume manager → upload progress → processing status → extracted-skill review → confirm skills → discovery → job detail/match explanation → application confirmation → application list/detail → withdraw where permitted.

Public profile saving stays disabled until authenticated persistence/isolation acceptance passes. Resume/application screens are planned, not currently delivered. Application submission must identify the resume/job versions being used.

## Recruiter journey

Account → company editor → pending approval/status → approved recruiter dashboard → owned jobs → draft editor → publish confirmation → published job → applicants → candidate detail/evidence → shortlist/reject/hire → close job.

Pending/rejected/suspended states explain permitted next actions. Company edits reset approval to pending. Conflicting job edits require refresh without silently overwriting newer versions.

## Administrator journey

Server-authorized account → pending company queue → company review → approve/reject with reason → refreshed queue and audit outcome. Moderation and audit screens follow. Users cannot register themselves as administrators; bootstrap needs explicit approval.

## Experience requirements

- Web: adaptive sidebar/workspace where useful; mobile: single-column navigation and touch-friendly controls.
- Every data screen: loading, true empty state, safe error and actionable retry. Never replace an API outage with fictional listings.
- Forms: inline validation, preserved drafts after failure, duplicate-submit prevention and explicit unsaved-change navigation handling.
- Use accessible labels, keyboard focus, readable contrast and status text alongside color. Test narrow and desktop layouts.
- Resume parse failure offers retry/replacement; unscored candidates are distinct from zero-match candidates.
- Deep links must handle missing/hidden jobs safely and recheck access when opened.
