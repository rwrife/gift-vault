# Bootstrap evidence (issue #1)

Honest split between what was verified on the Linux executor host and what
only the pinned macOS CI can prove. Updated when the exact-head CI run goes
green.

## Host-verified (Linux executor, 2026-09-20)

- Helper unit tests: `python3 -m unittest discover -s Scripts/tests` — **21 tests, all passing** (pin loader, simulator selection retry/flush, bounded boot/retry/teardown paths).
- Pure-Swift package on the CI Linux image: `docker run … swift:6.2-noble swift test` — **5 swift-testing tests passed** in `Packages/GiftVaultKit` (contract bounds, integer-cent budget type, five-state status pipeline order, ledger vocabulary). This is domain-package behavior evidence on Linux; it is **not** iOS build evidence.
- `bash -n` clean on `Scripts/ci.sh` and `Scripts/check_zero_network.sh`; workflow YAML, toolchain.json, scheme XML, and workspace XML all parse.
- `TARGETED_DEVICE_FAMILY = 1` present in exactly 4 target-level build configurations; zero `1,2` occurrences anywhere in `project.pbxproj`.
- Zero-network gate: PASS locally (empty allowlist; no URLSession/socket/Network symbols in `App/`, `UITests/`, `Packages/`).
- Bundle id `com.infinityball.giftvault` (app) / `…giftvault.uitests` (UI-test target) in all six target configurations.

## CI-pending (requires the pinned macOS runner; no claim made here)

- Exact measured Xcode pin 26.0.1 / 17A400 / iPhoneOS SDK 26.0 (acceptance blocker if absent — `Scripts/select_xcode.py` fails the run rather than substituting).
- App build and `UIDeviceFamily == [1]` post-build verification on the built simulator bundle.
- Launch XCUITest smoke (`bootstrap.home` identifier + static texts) — launch-only evidence, not a UI journey.
- `xcrun swift test` of GiftVaultKit on Apple silicon macOS.

## Not claimed anywhere

No device run, no signed archive, no TestFlight upload, no iPad behavior.
