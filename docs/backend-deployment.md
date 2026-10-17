# API hosting on Render

The root `render.yaml` defines one free Python Web service in Singapore with the API under `services/api`. No database, disk, paid instance or background worker is included. The start command binds Render's `PORT`, disables Uvicorn access logs to avoid collecting tokens or profile-related query strings, and uses `/health` for liveness. Deployment is configured to follow passing CI checks on main. The service definition has not yet been applied to an authenticated Render workspace.

Build: `python -m pip install -r requirements.lock.txt && python -m pip install . --no-deps`.

Start: `python -m uvicorn app.main:app --host 0.0.0.0 --port $PORT --no-access-log`.

The Python version matches the tested development runtime. The lock contains development checks too; no credentials are part of the build. CORS allows only the existing Antideploy origin. Keep the Flutter app on Antideploy and Firestore as the database.

## Secure configuration still required

Render sign-in currently requires GitHub authorization for vishalpoute. The permission screen asks to verify identity, read email addresses, know accessible resources and act on the user's behalf. Authorization is pending user approval; no access was granted by this work.

Configure server Application Default Credentials through Render's secret-file facility, then set `GOOGLE_APPLICATION_CREDENTIALS` to that file's mounted path. Use a dedicated least-privilege Google service identity with only the Firebase user lookups and Firestore operations needed by this API. Do not upload a personal ADC file or create broad Owner/Editor credentials. Credentials must never be included in Git, build arguments, frontend assets, screenshots, logs or chat. IAM approval, a live Firestore database and live token verification remain prerequisites for profile persistence.

A successful `/health` response means the process is running; it does not confirm identity or database readiness. Before connecting the Flutter editor, verify unauthenticated 401 responses, verified-email enforcement, two-account isolation, profile round trips, CORS behavior and safe failure handling on the actual hosted service. Record the actual URL and deployed Git SHA only after observing deployment success. No backend URL is live yet.

Official references: https://render.com/docs/deploy-fastapi and https://render.com/docs/blueprint-spec
