import base64
import json
import tempfile
import unittest
from pathlib import Path

from Scripts.app_store_connect import generate_jwt


class GenerateJwtTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.key_path = Path(directory.name) / "AuthKey_TEST123.p8"
        # A throwaway EC P-256 private key generated solely for this test fixture.
        self.key_path.write_text(
            "-----BEGIN PRIVATE KEY-----\n"
            "MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgevZzL1gdAFr88hb2\n"
            "OF/2NxApJCzGCEDdfSp6VQO30hyhRANCAAQRWz+jn65BtOMvdyHKcvjBeBSDZH2r\n"
            "1RTwjmYSi9R/zpBnuQ4EiMnCqfMPWiZqB4QdbAd0E7oH50VpuZ1P087G\n"
            "-----END PRIVATE KEY-----\n",
            encoding="utf-8",
        )

    def test_jwt_has_three_segments_with_expected_header_and_payload(self):
        token = generate_jwt("KEY123", "ISSUER456", self.key_path)
        segments = token.split(".")
        self.assertEqual(len(segments), 3)

        def decode(segment: str) -> dict:
            padded = segment + "=" * (-len(segment) % 4)
            return json.loads(base64.urlsafe_b64decode(padded))

        header = decode(segments[0])
        payload = decode(segments[1])

        self.assertEqual(header, {"alg": "ES256", "kid": "KEY123", "typ": "JWT"})
        self.assertEqual(payload["iss"], "ISSUER456")
        self.assertEqual(payload["aud"], "appstoreconnect-v1")
        self.assertGreater(payload["exp"], payload["iat"])
        self.assertLessEqual(payload["exp"] - payload["iat"], 1200)


if __name__ == "__main__":
    unittest.main()
