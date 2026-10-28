# SmartHire technical specification

## Stack and boundaries

| Layer | Choice |
| --- | --- |
| Android/Web client | Flutter, Dart, Material 3; feature-first data/domain/presentation folders |
| State and navigation | BLoC/Cubit and existing routing; repository injection without duplicate state systems |
| HTTP | Dio, bounded timeouts, cancellation and safe structured errors |
| Authentication | Firebase Authentication: Google and email/password with email verification |
| API | Python, FastAPI, Pydantic, Firebase Admin/Firestore SDK |
| Database | Cloud Firestore; server-controlled authorization and protected mutations |
| Resume files | Existing free private Antideploy S3-compatible bucket; Firebase/Firestore remain identity and metadata boundaries |
| Parsing | Bounded isolated PDF/DOCX parser, versioned taxonomy suggestions, explicit confirmation and persisted processing leases; approved free dependencies |
| Hosting | Existing Antideploy compiled Web preview and free Render FastAPI with in-process worker; processing pauses during free-service sleep |
| Validation | Flutter tests/analyzer, pytest, Ruff, Bandit, dependency review and emulator/integration acceptance |

## Configuration and keys

- Firebase project: `smarthire-dev-99f32`. Client Firebase configuration identifies the project; it is not authorization.
- Server identity uses a dedicated service account through a Render secret file and `GOOGLE_APPLICATION_CREDENTIALS`. Never place its private key in Flutter, Git, logs or chat.
- Client release configuration is outside Git at `C:/Users/visha/Documents/Codex/2026-10-13/c/work/firebase/web-dev.json`. Build hosted releases with `--dart-define-from-file` pointing there.
- `PUBLIC_JOBS_API_ORIGIN` selects the live anonymous job API. Keep hosted `PROFILE_API_ORIGIN` absent until real profile acceptance passes.
- Antideploy credentials remain outside Git and output; Render deployment uses the existing authorized service. No paid parsing/LLM API key is required by this design.
- Future services require explicit configuration documentation; never invent credentials or silently substitute backend services.

## API and security

Firebase ID tokens go to FastAPI over HTTPS. Verify signature, project audience/issuer, expiry and revocation; derive ownership from verified UID. Read roles/account status from server-owned records, never request bodies or client role claims. Recheck authorization inside sensitive transactions.

Existing API groups cover account, private profile/company, owned job lifecycle, anonymous published jobs and admin recruiter review. Queue pagination is bounded to 20; public job pages to 10. Use optimistic versions and atomic audit writes for lifecycle changes. See existing `docs/` endpoint contracts for exact payloads.

Keep client Firestore/Storage rules restrictive. Current direct client access is denied; any future scoped reads/uploads require tested rules before enablement. Current process-local throttles do not provide distributed abuse protection. Exact CORS origins, body limits, safe errors and private response caching controls remain required.

## Deployment

Deploy only compiled Web output, including renderer assets, with versioned main/bootstrap filenames. Verify host status and actual served response/hash. Record frontend and API source separately; GitHub push alone does not mean live. Consult the official hosting contract when deploying and retain pushed code if hosting fails.
