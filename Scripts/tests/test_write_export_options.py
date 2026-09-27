import plistlib
import tempfile
import unittest
from pathlib import Path

from Scripts.write_export_options import write_export_options


class WriteExportOptionsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.path = Path(directory.name) / "ExportOptions.plist"

    def test_writes_xcode26_upload_payload(self):
        write_export_options(self.path, "TEAM123")
        with self.path.open("rb") as handle:
            payload = plistlib.load(handle)
        self.assertEqual(
            payload,
            {
                "destination": "upload",
                "manageAppVersionAndBuildNumber": False,
                "method": "app-store-connect",
                "signingStyle": "automatic",
                "teamID": "TEAM123",
                "uploadMethod": "app-store-connect",
            },
        )

    def test_rejects_blank_team_id(self):
        with self.assertRaisesRegex(SystemExit, "team ID"):
            write_export_options(self.path, "  ")


if __name__ == "__main__":
    unittest.main()
