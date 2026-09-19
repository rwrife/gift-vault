# Gift Vault — PLAN

## Scope

Local-first iPhone app for gift planning: people → per-person idea lists → occasions with per-person budgets and status → given/received ledger → private export/backup. Single device, single user in MVP. No network code at all.

### Out of scope (MVP)

Cloud sync, accounts, collaboration, contacts import, purchase links, OCR/barcode, recommendations, iPad-native layouts, shared household sync, finance reports.

## Architecture

```
gift-vault/
  GiftVault/                  # SwiftUI app target (iPhone-only)
    App/                      # entry point, commands, notification delegate
    Features/                 # People, Ideas, Occasions, Ledger, Backup views
    Layout/GiftWorkspaceLayout.swift   # THE dual-screen migration seam
  Packages/GiftVaultKit/      # pure Swift 6 package: domain + logic (Linux-testable)
    Models/    Occasions/ Statuses/ Ledger/ Export/
```

- **Domain layer (`GiftVaultKit`)**: `Person`, `GiftIdea`, `Occasion`, `OccasionSlot` (person × occasion with budget + status), `LedgerEntry` (given/received). Pure Swift value types + state machines; no UIKit/SwiftUI/Foundation networking imports. All rules (status transitions, budget arithmetic in integer cents, repeat-check matching) live here and are unit-tested on Linux CI.
- **Persistence**: GRDB/SQLite in app-private container; forward-only migrations; one JSON bundle export format (versioned) + CSV views.
- **UI**: SwiftUI, iPhone-first. `GiftWorkspaceLayout` selects single-pane vs (future) spanned board/detail; today it always resolves to single-pane. The occasion board (people × status matrix) is designed as one screen so a future dual-screen migration is layout-only.
- **Notifications**: local only (`UserNotifications`), scheduled from occasion dates; permission requested lazily.

## Technology choices

| Choice | Rationale |
|---|---|
| Swift 6 + SwiftUI | Tool-lab iOS convention; strict concurrency; iOS 26 SDK target. |
| GRDB/SQLite | Deterministic relational queries for ledger/analytics; file-based backup is trivial. |
| Pure-Swift Kit package | Domain logic testable on Linux CI without Xcode; keeps CI cheap. |
| No networking stack at all | Privacy contract enforced by construction + CI gate (no URLSession/socket symbols). |
| Xcode 26.0.1 (17A400), iOS SDK 26.0 | Pinned in `toolchain.json`; exact pin is an environment acceptance blocker on Apple CI. |

**Toolchain**: iOS 26 SDK or newer required (`toolchain.json`). iPhone-only: `TARGETED_DEVICE_FAMILY = 1` in every app-target configuration; native iPad support requires explicit user opt-in.

## Milestones (dependency order)

1. **Skeleton + CI** — Xcode project, GiftVaultKit package, Linux+macOS CI, iPhone-only guards, zero-network gate. (foundation)
2. **Domain layer** — models, status machine, budget math, repeat-match rules, with tests. (needs 1)
3. **Persistence** — GRDB store, migrations, seed/reference fixtures. (needs 2)
4. **Core workflow UI** — people + ideas CRUD, occasion board with status, ledger log. (needs 3)
5. **Polish + accessibility + notifications** — Dynamic Type, VoiceOver, occasion reminders. (needs 4)
6. **Backup/export/import** — JSON bundle, CSV views, restore flow. (needs 3; UI lands with 4/5)
7. **Release pipeline** — signing, App Store record, TestFlight upload via ASC secrets. (needs 1–6)

## Testing strategy

- **Host (Linux CI)**: `swift test` on GiftVaultKit — status transitions, budget arithmetic (integer cents), export/import round-trip, repeat matching.
- **Apple CI (macOS runner)**: exact Xcode-pin assertion, app build, launch smoke test (XCUITest), iPhone-only verification (config grep + built `UIDeviceFamily == [1]`), zero-network symbol scan.
- **Manual gates before release**: real-device smoke (no simulator-only claims), VoiceOver pass, notification permission flow. Device/TestFlight evidence is reported only when actually produced.

## Packaging / distribution

- App Store via TestFlight first: bundle `com.infinityball.giftvault` (registered in App Store Connect — `CREATED`).
- Signing/TestFlight automation uses repo Actions secrets by name: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID`. Values never appear in repo, logs, or issues.
- iPhone-only on App Store (UIDeviceFamily [1]); no iPad listing.

## Risks

| Risk | Mitigation |
|---|---|
| Dual-screen SDK never matures as expected | App ships fully useful single-screen; `GiftWorkspaceLayout` isolates the future change. |
| Exact Xcode pin absent on runners | Treat as environment blocker; never silently substitute. |
| Notification scheduling vs timezone/DST | Store occasion dates as calendar dates, compute locally, test around DST transitions in the kit. |
| Export format churn breaks restores | Versioned JSON bundle with migration + round-trip tests from v1 onward. |
| Scope creep toward shopping integration | Hard non-goal; CI zero-network gate makes it structurally impossible. |

## Non-goals (explicit)

No cloud, no accounts, no ads/analytics, no store links, no medical/financial advice, no iPad support without opt-in, no Android in MVP.
