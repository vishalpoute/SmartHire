# SmartHire API

FastAPI service foundation. This service is tested locally; it is not yet deployed to Render or connected to the Flutter client.

## Local development

Use Python 3.11 or newer (validated with 3.14.7).

```sh
python -m venv .venv
# Activate .venv for your shell.
python -m pip install -r requirements.lock.txt
python -m pip install -e . --no-deps
python -m uvicorn app.main:app --reload --host 127.0.0.1
python -m pytest -q
python -m ruff check app tests
python -m ruff format --check app tests
```

Set environment variables from `.env.example` in the server process; the application does not automatically load that file. Use Application Default Credentials with permission to check Firebase accounts. Keep credentials outside Git and frontend assets. No credentials are needed for the isolated tests, which replace SDK calls with controlled responses.

## Endpoints

- `GET /health`: public liveness only. It does not test Firebase readiness.
- `GET /api/v1/me`: requires `Authorization: Bearer <Firebase ID token>`. Returns verified `uid`, optional `email`, and `email_verified`. The Admin SDK checks token validity, revocation and disabled accounts against the configured project. Query parameters cannot select another identity. This endpoint does not grant recruiter/admin roles.

Missing or invalid authentication returns 401; unavailable verification/configuration returns 503. Expected errors use `{code, message, requestId}` without SDK diagnostics. Responses include a UUID request ID and disable caching. CORS allows only explicitly configured origins; CORS does not replace authentication.

Unexpected request failures return the same envelope with a generic 500 message. Application error logs contain only the request ID and exception type, excluding exception messages, authorization headers and query strings. Configure infrastructure access logs separately to avoid recording sensitive request data. Allowed clients can read failure responses through CORS; untrusted origins receive no CORS grant. Method errors retain the HTTP `Allow` header.

Live Firebase token verification, emulator integration, permission policies, profiles and Render deployment remain pending. The Antideploy app serves only the Flutter preview.
