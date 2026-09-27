#!/usr/bin/env python3
"""Append TestFlight evidence to GitHub step summary markdown."""

from __future__ import annotations

import json
import sys
from pathlib import Path


def append_summary(evidence_path: Path, summary_path: Path) -> None:
    with evidence_path.open(encoding="utf-8") as handle:
        evidence = json.load(handle)
    with summary_path.open("a", encoding="utf-8") as summary:
        summary.write("### TestFlight upload evidence\n")
        summary.write(f"- App Store Connect: {evidence['app_store_connect_url']}\n")
        summary.write(f"- Build ID: {evidence['build_id']}\n")
        summary.write(f"- MARKETING_VERSION: {evidence['marketing_version']}\n")
        summary.write(f"- CURRENT_PROJECT_VERSION: {evidence['current_project_version']}\n")
        summary.write(f"- Processing state: {evidence['processing_state']}\n")


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: write_summary_from_evidence.py <evidence-json> <summary-path>", file=sys.stderr)
        sys.exit(2)
    append_summary(Path(sys.argv[1]), Path(sys.argv[2]))


if __name__ == "__main__":
    main()
