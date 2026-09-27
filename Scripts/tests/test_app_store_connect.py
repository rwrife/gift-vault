import base64
import json
import tempfile
import unittest
from pathlib import Path

from Scripts.app_store_connect import _der_ecdsa_to_raw, generate_jwt


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

        # JWS ES256 requires raw 32-byte R + 32-byte S, not OpenSSL's DER
        # sequence. This exact defect caused App Store Connect HTTP 401 in
        # release run 36299096969 after the upload itself succeeded.
        signature_segment = segments[2]
        padded = signature_segment + "=" * (-len(signature_segment) % 4)
        signature = base64.urlsafe_b64decode(padded)
        self.assertEqual(len(signature), 64)
        self.assertNotEqual(signature[:1], b"\x30")

    def test_der_ecdsa_to_raw_pads_and_strips_sign_prefix(self):
        r = b"\x00\x80" + b"\x11" * 31
        s = b"\x7f" + b"\x22" * 31
        der_payload = b"\x02" + bytes([len(r)]) + r + b"\x02" + bytes([len(s)]) + s
        der = b"\x30" + bytes([len(der_payload)]) + der_payload

        raw = _der_ecdsa_to_raw(der)

        self.assertEqual(len(raw), 64)
        self.assertEqual(raw[:32], b"\x80" + b"\x11" * 31)
        self.assertEqual(raw[32:], s)


if __name__ == "__main__":
    unittest.main()
