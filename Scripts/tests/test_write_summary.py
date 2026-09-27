import json
import tempfile
import unittest
from pathlib import Path

from Scripts.write_summary_from_evidence import append_summary


class WriteSummaryTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.temp = Path(directory.name)
        self.evidence_path = self.temp / "evidence.json"
        self.summary_path = self.temp / "summary.md"

    def test_appends_markdown_table_rows(self):
        self.evidence_path.write_text(
            json.dumps(
                {
                    "app_store_connect_url": "https://appstoreconnect.apple.com/apps/123/testflight/ios",
                    "build_id": "BUILD-456",
                    "marketing_version": "0.2.0",
                    "current_project_version": "7",
                    "processing_state": "VALID",
                }
            ),
            encoding="utf-8",
        )
        append_summary(self.evidence_path, self.summary_path)
        content = self.summary_path.read_text(encoding="utf-8")
        self.assertIn("TestFlight upload evidence", content)
        self.assertIn("BUILD-456", content)
        self.assertIn("0.2.0", content)
        self.assertIn("VALID", content)


if __name__ == "__main__":
    unittest.main()
