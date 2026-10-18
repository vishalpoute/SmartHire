"""Manual live acceptance check using two consenting, disposable verified accounts.

Tokens are read with getpass, held in memory, and never logged or written.
No account is created, impersonated or marked verified by this tool.
"""

import argparse
import getpass
import json
import sys
import warnings
from urllib.error import HTTPError
from urllib.parse import quote, urlsplit
from urllib.request import HTTPRedirectHandler, Request, build_opener
from uuid import uuid4


class CheckFailed(Exception):
    pass


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


class Api:
    def __init__(self, origin):
        parsed = urlsplit(origin)
        if (
            parsed.scheme != "https"
            or not parsed.hostname
            or parsed.username
            or parsed.password
            or parsed.query
            or parsed.fragment
            or parsed.path not in ("", "/")
        ):
            raise CheckFailed("Use an HTTPS API origin without a path or credentials.")
        self.origin = origin.rstrip("/")
        self.opener = build_opener(NoRedirects())

    def call(self, method, path, token, body=None):
        headers = {
            "Authorization": "Bearer " + token,
            "Content-Type": "application/json",
        }
        data = None if body is None else json.dumps(body).encode()
        request = Request(self.origin + path, data=data, headers=headers, method=method)
        try:
            response = self.opener.open(request, timeout=30)
        except HTTPError as error:
            response = error
        except Exception:  # noqa: BLE001 - suppress transport diagnostics containing tokens.
            raise CheckFailed(
                "Network check failed; no credential diagnostics recorded."
            ) from None
        with response:
            status = response.code
            raw = response.read(65537)
        if len(raw) > 65536:
            raise CheckFailed("API response exceeded the acceptance-check limit.")
        try:
            payload = json.loads(raw)
        except (ValueError, UnicodeError):
            raise CheckFailed("API did not return a JSON response.") from None
        return status, payload


def require(condition, message):
    if not condition:
        raise CheckFailed(message)


def verify(api, tokens, allow_write=False):
    identities = []
    for token in tokens:
        status, identity = api.call("GET", "/api/v1/me", token)
        require(
            status == 200 and isinstance(identity, dict),
            "Identity verification failed.",
        )
        require(
            identity.get("email_verified") is True,
            "Both accounts must verify their email.",
        )
        require(
            isinstance(identity.get("uid"), str) and identity["uid"],
            "Missing verified UID.",
        )
        identities.append(identity["uid"])
    require(identities[0] != identities[1], "Use two different accounts.")
    marker = uuid4().hex
    if allow_write:
        for i, token in enumerate(tokens):
            body = {
                "display_name": f"SmartHire acceptance account {i + 1}",
                "headline": "Disposable integration check " + marker,
                "location": "",
                "skills": ["Dart"],
            }
            status, saved = api.call("PUT", "/api/v1/profile", token, body)
            require(
                status == 200 and saved.get("uid") == identities[i],
                "Owner write failed.",
            )
            require(
                saved.get("display_name") == body["display_name"],
                "Write response mismatch.",
            )
    for i, token in enumerate(tokens):
        other = identities[1 - i]
        # Query and privilege-field attempts must not select or modify the other owner.
        status, profile = api.call(
            "GET", "/api/v1/profile?uid=" + quote(other, safe=""), token
        )
        require(status in (200, 404), "Profile read failed.")
        if allow_write:
            require(status == 200, "Saved profile could not be read back.")
            require(
                profile.get("headline") == "Disposable integration check " + marker,
                "Current write marker was not persisted.",
            )
            require(
                profile.get("display_name") == f"SmartHire acceptance account {i + 1}",
                "Persisted profile content mismatch.",
            )
        if status == 200:
            require(
                profile.get("uid") == identities[i], "Cross-account profile disclosure."
            )
        status, _ = api.call(
            "PUT",
            "/api/v1/profile",
            token,
            {"display_name": "Rejected escalation", "uid": other, "role": "admin"},
        )
        require(status == 422, "Ownership/role injection was not rejected.")
    return "PASS: two verified identities and owner isolation" + (
        "; live writes/readbacks verified."
        if allow_write
        else "; persistence writes NOT tested."
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origin", required=True)
    parser.add_argument(
        "--write-disposable-profiles",
        action="store_true",
        help="Replace both disposable test profiles; no automatic deletion or rollback",
    )
    args = parser.parse_args()
    try:
        api = Api(args.origin)
        print("Destination:", api.origin)
        if args.write_disposable_profiles:
            require(
                input(
                    "This replaces TWO disposable profiles. Type REPLACE to continue: "
                )
                == "REPLACE",
                "Write check cancelled.",
            )
        require(
            sys.stdin.isatty(),
            "Run interactively in a terminal; piped tokens are refused.",
        )
        warnings.simplefilter("error", getpass.GetPassWarning)
        tokens = [
            getpass.getpass(f"Fresh Firebase ID token for account {i + 1}: ")
            for i in range(2)
        ]
        require(all(tokens), "Two fresh ID tokens are required.")
        print(verify(api, tokens, args.write_disposable_profiles))
    except CheckFailed as error:
        print("FAIL:", str(error))
        return 1
    except Exception:  # noqa: BLE001 - never print response or credential diagnostics.
        print("FAIL: unexpected check error; credentials and response data suppressed.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
