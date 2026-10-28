# SmartHire data schema

Firestore uses collections/documents, not SQL tables. Names below distinguish implemented records from proposed additions. API snake_case names take precedence over older conceptual camelCase examples.

## Implemented collections

| Collection / key | Main data | Relations and access |
| --- | --- | --- |
| `users/{encoded_uid}` | role, account_status, recruiter_approved | Firebase UID identity; server-owned permissions; missing account defaults to an unapproved seeker |
| `private_profiles/{encoded_uid}` | display_name, headline, location, skills, updated_at | One private profile per authenticated owner |
| `company_profiles/{encoded_uid}` | name, description, location, website, approval_status, updated_at | One owned company profile per UID in current MVP; edits reset approval |
| `jobs/{32hex_id}` | recruiter_uid, company_owner_uid, title, description, location, work_mode, employment_type, required_skills, preferred_skills, status, version, timestamps, published company_name | Many jobs per recruiter/company; public API returns an allowlist only |
| `audit_events/{generated_id}` | actor/action/target metadata, reason where applicable, server timestamp | Private server writes; atomically accompanies review/publication/closure |
| `resumes/{32hex_id}` | owner_uid, immutable extension/size/SHA-256, revision, parse_status, extracted/confirmed skills, skills_version, parser_version, safe error_code, private text and worker lease | Owner-only API allowlist omits text/leases; deleted IDs retain only a minimal tombstone |
| `_resume_upload_limits/{scope_day}` | count | Atomic UTC daily upload budget per owner/global; no client access |
| `applications/{32hex_id}` | seeker_uid/recruiter_uid, immutable job/candidate/match snapshots, revision, status/reason, submitted_at/updated_at | Unique seeker/job; verified party access and atomic audited transitions |
| `saved_jobs/{32hex_id}` | owner_uid, job_id, saved_at | Unique owner/job bookmark; API always rechecks current visibility |
| `_saved_job_counts/{encoded_uid}` | count | Atomic maximum 100 saved roles per seeker; server-only |

`encoded_uid` means percent-encoding the opaque UID using the existing server convention, not changing identity. Never accept another owner's UID from an editable payload.

## Proposed collections: finalize contracts before implementation

| Collection | Data and relationship |
| --- | --- |
| `match_results/{id}` | Future saved comparisons; previews currently read-only and submitted evidence embedded immutably in applications |
| `processing_tasks/{id}` | Future generic tasks; resume processing already stores attempts/leases on its resume record |

A seeker has many resumes/applications; a job has many applications; each application pins one resume version and job version. Matching results reference those exact inputs. Replacing a current resume must not change historical applications.

## Handling and integrity

- Server timestamps, strict field allowlists, size/type bounds and explicit lifecycle transitions; no client writes to roles, scores or audits.
- Job lifecycle: draft → published → closed; suspended is reserved for moderation. Approval changes affect current public visibility.
- Implemented application lifecycle: submitted → shortlisted/rejected; shortlisted → hired/rejected; seeker withdrawal from submitted/shortlisted. Terminal states cannot change. Transactions append audit entries atomically.
- Use transactions/preconditions for duplicate applications and version conflicts. No implicit cascading deletion: define retention, ownership and file cleanup together before enabling deletion.
- Keep raw resume text/private files separate from recruiter-readable application snapshots. Recruiter access must be tied to an authorized application.
- Public pagination currently orders by document ID, not recency. Add filters/indexes only alongside tested query contracts; document required indexes in Firebase configuration.
- Deny direct client access until narrowly scoped rules and two-account tests pass. Do not treat knowledge of a document ID as authorization.
