# API hosting on Render

The root `render.yaml` defines one free Python Web service in Singapore with the API under `services/api`. No database, disk, paid instance or background worker is included. The start command binds Render's `PORT`, disables Uvicorn access logs to avoid collecting tokens or profile-related query strings, and uses `/health` for liveness. Deployment is configured to follow passing CI checks on main. A matching free service was created through the Render dashboard after user-approved GitHub authorization. The YAML is a reproducible definition; it is not a connected Blueprint instance.

Build: `python -m pip install -r requirements.lock.txt && python -m pip install . --no-deps`.

Start: `python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT --no-access-log`.

The Python version matches the tested development runtime. The lock contains development checks too; no credentials are part of the build. CORS allows only the existing Antideploy origin. Keep the Flutter app on Antideploy and Firestore as the database.

## Secure configuration still required

Render GitHub sign-in for vishalpoute was authorized by the user and verified. The service uses the public repository source.

Configure server Application Default Credentials through Render's secret-file facility, then set `GOOGLE_APPLICATION_CREDENTIALS` to that file's mounted path. Use a dedicated least-privilege Google service identity with only the Firebase user lookups and Firestore operations needed by this API. Do not upload a personal ADC file or create broad Owner/Editor credentials. Credentials must never be included in Git, build arguments, frontend assets, screenshots, logs or chat. IAM approval, a live Firestore database and live token verification remain prerequisites for profile persistence.

A successful `/health` response means the process is running; it does not confirm identity or database readiness. Before connecting the Flutter editor, verify unauthenticated 401 responses, verified-email enforcement, two-account isolation, profile round trips, CORS behavior and safe failure handling on the actual hosted service. Record the actual URL and deployed Git SHA only after observing deployment success. The API is live at https://smarthire-api-ep83.onrender.com from commit `972a159`. Render reported Live, `/health` returned 200, and unauthenticated identity/profile requests returned 401. Server credentials and authenticated persistence are still unconfigured/unverified.

Official references: https://render.com/docs/deploy-fastapi and https://render.com/docs/blueprint-spec

## Flutter editor connection

The protected `/profile/edit` route is available from the account profile. Without `PROFILE_API_ORIGIN`, verified users see a saving-unavailable state. Only enable this HTTPS origin build definition after server credentials, verified-user requests and profile isolation have passed on the live API. Keep it absent from the current hosted client configuration until then. The session-bound repository refreshes Firebase tokens, rejects ownership changes and is disposed with its editor route. Tests inject repositories without making live profile writes.


## Manual two-account acceptance check

Keep hosted profile saves disabled until real authenticated API writes and reads pass.
Use two consenting, disposable development accounts with verified email and fresh Firebase
ID tokens. Do not mint impersonation tokens or change verification flags to bypass this gate.

Run `python scripts/verify_live_profiles.py --origin https://YOUR-API-ORIGIN` in an
interactive terminal. Tokens are entered with hidden prompts, held in memory, and never
written to a report. Never paste tokens into chat, command arguments, source or CI logs.
The default checks identity and owner isolation without replacing editable profiles;
malformed ownership/role writes must return 422. It does not prove persistence.

Add `--write-disposable-profiles` only for disposable accounts: after typing REPLACE,
it replaces both editable profiles with clearly identified integration fixtures, reads them
back, and checks cross-account owner selection and privilege injection rejection. It leaves
the fixtures in place; it performs no deletion or rollback. Redirects are refused so bearer
tokens cannot follow a redirect to another destination. Network calls have a 30-second
per-call timeout and responses are bounded. Output contains only pass/fail diagnostics,
without tokens, account IDs, emails or profile contents. A local test of this checker is not
live acceptance evidence; record the actual deployed source and live result separately.
