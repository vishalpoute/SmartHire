# Matching and applications

## Explainable coverage

`POST /api/v1/jobs/{job_id}/match` takes an owned confirmed resume ID and its expected revision. An optional expected job version rejects stale previews. The server transaction rechecks the active seeker, source owner, current published job, approved recruiter and approved company. Unconfirmed/unscored parsing never becomes a zero match.

Algorithm `skill-coverage-v1` uses NFKC, case folding, collapsed whitespace and exact aliases from `skills-v1`. Substrings do not match: JavaScript is not Java and MySQL is not SQL. Canonically duplicate requirements count once. The percentage is matched required skills divided by distinct required skills, rounded deterministically to two decimals. Preferred evidence is separate and does not inflate coverage. No required skills yields an explicit unscored result with a null percentage. A confirmed empty skill set against nonempty requirements yields zero coverage.

Responses show the job/company, matched evidence mapping each requirement to a confirmed skill, missing required/preferred skills, algorithm/taxonomy/parser versions and exact job/resume/skill versions plus source hash. This is skill coverage for human review; it does not infer experience, assess overall suitability or decide hiring. Matching performs no writes and stores no raw document in its response.

## Submission and tracking

`POST /api/v1/jobs/{job_id}/applications` requires the reviewed resume revision and job version. It atomically creates one application per seeker/job, with a deterministic ID and audit entry. Identical interrupted retries return the existing application; another source for the same job returns conflict. Transactions recheck approval and source state, so closure or suspension cannot race an authorized new submission. Applying requires a completed profile and explicit UI consent.

The immutable snapshot contains public job fields, profile name/headline/location, confirmed skills and versioned matching evidence. It excludes email, raw extraction, signed URLs and the original private file. The source document may be erased without changing submitted evidence. Withdrawal retains application history and is not an erasure request. Account deletion/retention handling remains a separate unfinished acceptance requirement; do not claim complete deletion support.

`GET /api/v1/applications?scope=seeker|recruiter` provides ten rows per page, ordered by ID with a bounded cursor. The server derives the party from verified identity and current roles. `GET /api/v1/applications/{id}` uses the same checks. Recruiters need active approved status, an approved company and both current job ownership fields; closed jobs retain tracking access, but revoked approval removes candidate access. Other users receive unavailable responses.

`POST /api/v1/applications/{id}/status` requires the current application revision. Recruiters may move submitted to shortlisted/rejected, then shortlisted to hired/rejected. Rejection needs a reason. Seekers may withdraw submitted/shortlisted applications. Terminal states cannot change. Every successful transition atomically appends an audit; failed audits roll back the transition. There is no automatic shortlist, rejection or hire.

The Flutter flow allows confirmed-source selection, match review, submission consent, seeker tracking/withdrawal and recruiter evidence/decision review. It fences late callbacks on session changes, requires refresh after stale writes and uses explicit confirmations. Hosted `APPLICATIONS_API_ORIGIN` remains absent until real authenticated acceptance passes.

## Evidence and remaining acceptance

All 337 API tests and 163 Flutter tests pass. Ruff/Bandit and Flutter analysis pass. An isolated real Firestore fixture verified matching, duplicate-safe submission, party queries, foreign-owner rejection, immutable snapshots after source deletion, stale transitions, recruiter revocation, three atomic audit entries and cleanup. These SDK checks do not impersonate Firebase users and do not establish authenticated HTTP or hosted acceptance. A real seeker/recruiter journey, deployed origin checks and Android validation remain required.
