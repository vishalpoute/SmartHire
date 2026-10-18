import unittest

from verify_live_profiles import Api, CheckFailed, NoRedirects, verify


class FakeApi:
    def __init__(self, cross_owner=False, accept_role=False, same_identity=False):
        self.profiles = {}
        self.cross_owner = cross_owner
        self.accept_role = accept_role
        self.same_identity = same_identity
        self.writes = 0

    def call(self, method, path, token, body=None):
        uid = "one" if self.same_identity else token
        if path == "/api/v1/me":
            return 200, {"uid": uid, "email_verified": True}
        if method == "PUT":
            if "role" in body:
                return (200 if self.accept_role else 422), {}
            self.writes += 1
            self.profiles[uid] = {**body, "uid": uid}
            return 200, self.profiles[uid]
        if self.cross_owner:
            return 200, {"uid": "two" if uid == "one" else "one"}
        return (200, self.profiles[uid]) if uid in self.profiles else (404, {})


class LiveProfileChecks(unittest.TestCase):
    def test_read_only_default_never_writes_editable_profiles(self):
        api = FakeApi()
        self.assertIn("NOT tested", verify(api, ["one", "two"]))
        self.assertEqual(api.writes, 0)

    def test_explicit_write_checks_two_persisted_profiles(self):
        api = FakeApi()
        self.assertIn("readbacks verified", verify(api, ["one", "two"], True))
        self.assertEqual(api.writes, 2)

    def test_cross_account_disclosure_and_privilege_acceptance_fail(self):
        for api in [
            FakeApi(cross_owner=True),
            FakeApi(accept_role=True),
            FakeApi(same_identity=True),
        ]:
            with self.subTest(api=api), self.assertRaises(CheckFailed):
                verify(api, ["one", "two"])

    def test_unsafe_destinations_are_rejected_before_credentials(self):
        for origin in [
            "http://example.com",
            "https://user:pass@example.com",
            "https://example.com/path",
            "https://example.com?token=x",
            "https://example.com#fragment",
        ]:
            with self.subTest(origin=origin), self.assertRaises(CheckFailed):
                Api(origin)

    def test_transport_failure_never_echoes_token_or_sdk_details(self):
        from unittest.mock import Mock

        api = Api("https://example.com")
        api.opener = Mock()
        api.opener.open.side_effect = RuntimeError(
            "private bearer and transport details"
        )
        with self.assertRaises(CheckFailed) as result:
            api.call("GET", "/api/v1/me", "private-token")
        self.assertNotIn("private", str(result.exception))
        self.assertEqual(api.opener.open.call_args.kwargs["timeout"], 30)

    def test_redirect_cannot_forward_bearer_to_another_destination(self):
        self.assertIsNone(
            NoRedirects().redirect_request(
                None, None, 302, "", {}, "https://another.example"
            )
        )


if __name__ == "__main__":
    unittest.main()
