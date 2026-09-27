import plistlib
import tempfile
import unittest
from pathlib import Path

from Scripts.verify_archive_plist import verify_app_plist


class VerifyArchivePlistTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.temp = Path(directory.name)

    def write_plist(self, payload: dict) -> Path:
        path = self.temp / "Info.plist"
        with path.open("wb") as handle:
            plistlib.dump(payload, handle)
        return path

    def test_accepts_expected_bundle_id_and_iphone_family(self):
        path = self.write_plist(
            {
                "CFBundleIdentifier": "com.infinityball.giftvault",
                "UIDeviceFamily": [1],
            }
        )
        verify_app_plist(path, "com.infinityball.giftvault")

    def test_rejects_mismatched_bundle_id(self):
        path = self.write_plist(
            {
                "CFBundleIdentifier": "com.infinityball.other",
                "UIDeviceFamily": [1],
            }
        )
        with self.assertRaisesRegex(SystemExit, "CFBundleIdentifier mismatch"):
            verify_app_plist(path, "com.infinityball.giftvault")

    def test_rejects_non_iphone_device_family(self):
        path = self.write_plist(
            {
                "CFBundleIdentifier": "com.infinityball.giftvault",
                "UIDeviceFamily": [1, 2],
            }
        )
        with self.assertRaisesRegex(SystemExit, "UIDeviceFamily"):
            verify_app_plist(path, "com.infinityball.giftvault")


if __name__ == "__main__":
    unittest.main()
