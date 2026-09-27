#!/usr/bin/env python3
"""App Store Connect API client helper for TestFlight poll and localization update."""

from __future__ import annotations

import argparse
import base64
import json
import subprocess
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path


def generate_jwt(key_id: str, issuer_id: str, key_path: Path) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": now,
        "exp": now + 1200,
        "aud": "appstoreconnect-v1",
    }

    def b64url(data: bytes) -> str:
        return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")

    unsigned = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(payload).encode())}"
    # Sign using openssl
    proc = subprocess.run(
        ["openssl", "dgst", "-binary", "-sha256", "-sign", str(key_path)],
        input=unsigned.encode("utf-8"),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=True,
    )
    signature = b64url(proc.stdout)
    return f"{unsigned}.{signature}"


def api_request(method: str, url: str, token: str, payload: dict | None = None) -> dict:
    req = urllib.request.Request(
        url,
        data=json.dumps(payload).encode("utf-8") if payload is not None else None,
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/json",
        },
        method=method,
    )
    with urllib.request.urlopen(req) as resp:
        body = resp.read()
        if not body:
            return {}
        return json.loads(body.decode("utf-8"))


def get_app_id(bundle_id: str, token: str) -> str:
    query = urllib.parse.urlencode({"filter[bundleId]": bundle_id, "limit": 1})
    url = f"https://api.appstoreconnect.apple.com/v1/apps?{query}"
    data = api_request("GET", url, token).get("data", [])
    if not data:
        raise RuntimeError(f"No app found in App Store Connect with bundleId: {bundle_id}")
    return str(data[0]["id"])


def poll_build(app_id: str, marketing_version: str, build_version: str, token_factory) -> tuple[str, str]:
    query = urllib.parse.urlencode({
        "filter[app]": app_id,
        "filter[preReleaseVersion.version]": marketing_version,
        "filter[version]": build_version,
        "sort": "-uploadedDate",
        "limit": 1,
    })
    url = f"https://api.appstoreconnect.apple.com/v1/builds?{query}"

    for attempt in range(1, 81):
        token = token_factory()
        try:
            data = api_request("GET", url, token).get("data", [])
        except Exception as error:
            print(f"Attempt {attempt}/80: API query error: {error}", file=sys.stderr)
            time.sleep(30)
            continue

        if not data:
            print(f"Attempt {attempt}/80: Build {marketing_version} ({build_version}) not visible yet...", file=sys.stderr)
            time.sleep(30)
            continue

        build = data[0]
        build_id = str(build["id"])
        state = (build.get("attributes", {}) or {}).get("processingState", "")
        print(f"Attempt {attempt}/80: Build {build_id} processingState={state}", file=sys.stderr)

        if state in ("VALID", "COMPLETE"):
            return build_id, state
        if state in ("FAILED", "INVALID"):
            raise RuntimeError(f"Build {build_id} entered terminal failure state: {state}")

        time.sleep(30)

    raise TimeoutError(f"Build {marketing_version} ({build_version}) did not finish processing within 40 minutes.")


def set_release_notes(build_id: str, release_notes: str, token_factory) -> None:
    token = token_factory()
    query = urllib.parse.urlencode({
        "filter[build]": build_id,
        "filter[locale]": "en-US",
        "limit": 1,
    })
    url = f"https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations?{query}"
    data = api_request("GET", url, token).get("data", [])

    if data:
        loc_id = data[0]["id"]
        patch_url = f"https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations/{loc_id}"
        patch_payload = {
            "data": {
                "id": loc_id,
                "type": "betaBuildLocalizations",
                "attributes": {
                    "whatsNew": release_notes,
                },
            }
        }
        api_request("PATCH", patch_url, token, patch_payload)
        print(f"Updated release notes for localization {loc_id}")
    else:
        post_url = "https://api.appstoreconnect.apple.com/v1/betaBuildLocalizations"
        post_payload = {
            "data": {
                "type": "betaBuildLocalizations",
                "attributes": {
                    "locale": "en-US",
                    "whatsNew": release_notes,
                },
                "relationships": {
                    "build": {
                        "data": {
                            "type": "builds",
                            "id": build_id,
                        }
                    }
                },
            }
        }
        api_request("POST", post_url, token, post_payload)
        print(f"Created release notes for build {build_id}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--current-project-version", required=True)
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--key-path", type=Path, required=True)
    parser.add_argument("--notes-file", type=Path, required=True)
    parser.add_argument("--evidence-out", type=Path, required=True)
    args = parser.parse_args()

    token_factory = lambda: generate_jwt(args.key_id, args.issuer_id, args.key_path)

    print("Fetching App Store Connect app ID...", file=sys.stderr)
    app_id = get_app_id(args.bundle_id, token_factory())
    print(f"Found app ID: {app_id}", file=sys.stderr)

    print(f"Polling build status for version {args.marketing_version} ({args.current_project_version})...", file=sys.stderr)
    build_id, final_state = poll_build(app_id, args.marketing_version, args.current_project_version, token_factory)

    notes_text = args.notes_file.read_text(encoding="utf-8")
    if notes_text.strip():
        print(f"Setting TestFlight release notes on build {build_id}...", file=sys.stderr)
        set_release_notes(build_id, notes_text, token_factory)

    asc_url = f"https://appstoreconnect.apple.com/apps/{app_id}/testflight/ios"
    evidence = {
        "bundle_id": args.bundle_id,
        "marketing_version": args.marketing_version,
        "current_project_version": args.current_project_version,
        "app_id": app_id,
        "build_id": build_id,
        "processing_state": final_state,
        "app_store_connect_url": asc_url,
    }
    args.evidence_out.write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    print(f"Release evidence written to {args.evidence_out}")


if __name__ == "__main__":
    main()
