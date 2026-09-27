#!/usr/bin/env python3
"""Write Xcode 26 App Store Connect upload export options."""

from __future__ import annotations

import plistlib
import sys
from pathlib import Path


def write_export_options(path: Path, team_id: str) -> None:
    if not team_id.strip():
        raise SystemExit("team ID must not be empty")
    payload = {
        "destination": "upload",
        "manageAppVersionAndBuildNumber": False,
        "method": "app-store-connect",
        "signingStyle": "automatic",
        "teamID": team_id,
        "uploadMethod": "app-store-connect",
    }
    with path.open("wb") as handle:
        plistlib.dump(payload, handle)


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: write_export_options.py <output-path> <team-id>", file=sys.stderr)
        sys.exit(2)
    write_export_options(Path(sys.argv[1]), sys.argv[2])


if __name__ == "__main__":
    main()
