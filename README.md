# Gift Vault

**Local-first iPhone gift planner: capture ideas per person as you hear them, manage occasions with budgets, and log what was given or received — no accounts, no cloud.**

## Overview

Gift Vault is a private, offline-first iPhone app for people who give gifts. It keeps three things organized for you:

1. **Wishlists per person** — capture a gift idea the moment you hear it ("Sarah mentioned she likes pour-over coffee"), tied to a contact, with notes, price hints, and where you saw it.
2. **Occasions** — birthdays, holidays, weddings, anniversaries — each with the people involved, a per-person budget, and a status timeline (idea → chosen → bought → wrapped → given).
3. **Given/received history** — what you gave whom, when, for what occasion, and what you received, so "what did I already get Alex?" is a two-second lookup.

Everything lives on your device. There is no account, no server, no analytics, and no network access at all.

## Motivation

Gift-giving ideas are forgettable: a friend mentions a hobby once, a partner hints at something in March for a December birthday. Existing solutions are social networks, shopping affiliates, or cloud wishlists tied to retail accounts. People who want a *private* memory for ideas and a simple budget/status tracker for occasions have nothing local-first. Gift Vault fills that gap with plain, deterministic record-keeping.

## Target users

- Adults managing gift-giving for family and friend circles (5–30 people).
- Households that coordinate gift-giving and want exportable, user-owned records.
- Privacy-conscious users who refuse retail-account wishlists.

## Concrete use cases

- At dinner, someone mentions a book series; open Gift Vault, add one idea to their list in under 10 seconds.
- In November, open the "Holiday 2026" occasion, see each person's budget, and move shortlists through chosen/bought/given states.
- Before a birthday, check given-history for that person to avoid repeats.
- After receiving a gift, log the giver and item so thank-you notes and future reciprocity are easy.
- Export everything to CSV/JSON for your own backup or to share a shopping list with your partner (file export only — no sharing accounts).

## How to use (intended end-to-end workflow)

1. Create people (name, optional birthday date).
2. Add ideas to each person over time — note, optional price estimate, optional link-free "where I saw it" text.
3. Create occasions; attach the people involved; set a per-person budget.
4. For each occasion + person, mark one idea as *chosen*; update status as you buy, wrap, and give.
5. When the occasion passes, the ledger records what was given; ideas you didn't use stay on the wishlist for next time.
6. Back up any time via the built-in export (private JSON bundle) and restore on a new phone.

## MVP feature list

- People list with quick-add and optional birthday (no contacts permission required; manual entry).
- Per-person idea lists with note, price hint, created date, and freeform source note.
- Occasions with attached people, per-person budget, and status states (`idea`, `chosen`, `bought`, `wrapped`, `given`) tracked per person-slot.
- Given/received ledger: date, person, occasion (optional), item description, optional value.
- Repeat-check: shows past gifts to a person when adding a new choice.
- Private full-data export (JSON + CSV) and import/restore; user-owned files.
- Local notifications for upcoming occasions (opt-in permission).
- Accessibility: Dynamic Type, VoiceOver-annotated lists, full contrast, large tap targets.

## Non-goals

- No purchase links, store scraping, affiliate links, or barcode/OCR scanning.
- No cloud sync, accounts, social sharing, or collaborative editing in MVP.
- No contacts-library access (manual people entries; a later import is opt-in per record).
- No spending/finance tracking beyond the gift budget fields.
- No recommendations, AI suggestions, or registry features.
- No shared household sync in MVP (export/airdrop a file instead).

## iPhone Duo dual-screen design target

The dual-screen experience is a **documented design target with a migration path**, not a current dependency:

- **Folded / current iPhone shape:** single-pane iPhone app — browse a person's ideas, or run an occasion checklist.
- **Unfolded design target:** persistent *plan board* on one screen (occasion × person status matrix) while the other shows the selected person's idea list and budget editor — the canonical master/detail span that gift planning naturally wants.
- **Build shape (SDK gap):** native fold APIs are not yet available, so Gift Vault scaffolds and ships as a **standard iPhone app with iPad support disabled by default** (`TARGETED_DEVICE_FAMILY = 1`, built `UIDeviceFamily == [1]`). All dual-screen layouts route through a single `GiftWorkspaceLayout` seam so a future native migration changes one file, never the data layer. Native iPad/tablet layouts require explicit user opt-in and are deferred.

## Privacy, permissions, and data storage

- **Zero network:** the app makes no network requests; CI enforces a zero-network gate (empty allowlist).
- **Storage:** local SQLite (GRDB) in app-private storage; ideas, occasions, and ledger entries never leave the device except via exports the user initiates.
- **Permissions:** only Notifications (opt-in). No contacts, no camera, no location.
- **Export/backup:** user-exported JSON bundle (restorable) and CSV views via the system share sheet; exports are plain files the user owns.
- **No analytics, no tracking, no third-party SDKs.**

## Health & legal limits

Gift Vault is a personal record-keeping tool. It gives no financial advice; budget fields are user-entered reminders, not spending recommendations.

## Current status

Scaffold complete: documentation and issue backlog only. No Xcode project, builds, tests, device evidence, or TestFlight binary exists yet. See `PLAN.md` for milestones.

- Bundle ID: `com.infinityball.giftvault` — App Store Connect registration: **CREATED** (verified this run).
- iOS signing/TestFlight will use the repository Actions secrets (`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `ASC_TEAM_ID` — names only; values are never stored in this repository).

## Development quickstart (planned)

- Xcode 26.0.1 (17A400) with iOS SDK 26.0, Swift 6 language mode (see `toolchain.json`).
- SwiftUI app target + pure-Swift `GiftVaultKit` package (Linux-testable domain logic).
- CI: Linux `swift test` for the package + macOS build/launch checks; iPhone-only enforcement (`TARGETED_DEVICE_FAMILY = 1` pre-build grep, post-build `UIDeviceFamily == [1]` check); zero-network gate.
- iPhone-only: native iPad support is disabled by default and requires explicit user opt-in.
