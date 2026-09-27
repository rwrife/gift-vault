#!/usr/bin/env python3
"""Verify that an iOS app Info.plist conforms to the project contract."""

from __future__ import annotations

import json
import plistlib
import sys
from pathlib import Path


def verify_app_plist(plist_path: Path, expected_bundle_id: str) -> None:
    if not plist_path.is_file():
        raise SystemExit(f"Info.plist not found at {plist_path}")

    with plist_path.open("rb") as handle:
        data = plistlib.load(handle)

    bundle_id = data.get("CFBundleIdentifier")
    if bundle_id != expected_bundle_id:
        raise SystemExit(
            f"CFBundleIdentifier mismatch: expected {expected_bundle_id!r}, "
            f"found {bundle_id!r}"
        )

    device_family = data.get("UIDeviceFamily")
    if device_family != [1]:
        raise SystemExit(
            f"iPhone-only contract violated: UIDeviceFamily must be [1], "
            f"found {device_family!r}"
        )

    print(f"Verified {plist_path}: bundle_id={bundle_id} UIDeviceFamily={device_family}")


def main() -> None:
    if len(sys.argv) != 3:
        print("usage: verify_archive_plist.py <path-to-Info.plist> <expected-bundle-id>", file=sys.stderr)
        sys.exit(2)

    verify_app_plist(Path(sys.argv[1]), sys.argv[2])


if __name__ == "__main__":
    main()
