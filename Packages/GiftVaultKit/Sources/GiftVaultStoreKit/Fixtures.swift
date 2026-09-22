import Foundation
import GiftVaultKit
import GRDB

// Deterministic seed fixtures (issue #3).
//
// One fixed demo vault — people with ideas, one live occasion carrying a
// slot in every status, and ledger history — used by SwiftUI previews and
// the issue #4 UI tests. Every identifier is a *fixed* UUID (generated
// once below, never regenerated) and every date is a fixed calendar day,
// so snapshot-style UI tests get byte-identical data across runs.
//
// The seed bypasses the state machine deliberately: fixtures need slots
// resting in mid-timeline states simultaneously, which a live single
// session could not produce in one pass. The seeded `given` slots still
// carry their matching given-direction ledger rows, mirroring what
// `advanceSlot` would have written.

public enum GiftVaultFixtures {
    // Fixed identifiers — stable forever. Changing any of these is a
    // breaking change for UI tests that reference them.
    public static let personAvaID = uuid("7E5F2C1A-0000-4000-8000-000000000001")
    public static let personBenID = uuid("7E5F2C1A-0000-4000-8000-000000000002")
    public static let personCleoID = uuid("7E5F2C1A-0000-4000-8000-000000000003")
    public static let personDanaID = uuid("7E5F2C1A-0000-4000-8000-000000000004")
    public static let personEzraID = uuid("7E5F2C1A-0000-4000-8000-000000000005")

    public static let occasionID = uuid("7E5F2C1A-0000-4000-8000-000000000010")

    public static let ideaAvaBookID = uuid("7E5F2C1A-0000-4000-8000-000000000021")
    public static let ideaAvaScarfID = uuid("7E5F2C1A-0000-4000-8000-000000000022")
    public static let ideaBenVinylID = uuid("7E5F2C1A-0000-4000-8000-000000000023")
    public static let ideaCleoKnifeID = uuid("7E5F2C1A-0000-4000-8000-000000000024")
    public static let ideaDanaLampID = uuid("7E5F2C1A-0000-4000-8000-000000000025")
    public static let ideaEzraCandleID = uuid("7E5F2C1A-0000-4000-8000-000000000026")

    public static let slotAvaID = uuid("7E5F2C1A-0000-4000-8000-000000000031")
    public static let slotBenID = uuid("7E5F2C1A-0000-4000-8000-000000000032")
    public static let slotCleoID = uuid("7E5F2C1A-0000-4000-8000-000000000033")
    public static let slotDanaID = uuid("7E5F2C1A-0000-4000-8000-000000000034")
    public static let slotEzraID = uuid("7E5F2C1A-0000-4000-8000-000000000035")

    public static let ledgerGivenID = uuid("7E5F2C1A-0000-4000-8000-000000000041")
    public static let ledgerReceivedID = uuid("7E5F2C1A-0000-4000-8000-000000000042")

    public static func uuid(_ string: String) -> UUID {
        guard let id = UUID(uuidString: string) else {
            preconditionFailure("fixture UUID malformed: \(string)")
        }
        return id
    }

    private static func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate {
        guard let date = CalendarDate(year: y, month: m, day: d) else {
            preconditionFailure("invalid fixture date \(y)-\(m)-\(d)")
        }
        return date
    }

    /// The demo people (fixed ids).
    public static var people: [Person] {
        [
            Person(id: personAvaID, name: "Ava Chen",
                   birthday: day(1988, 3, 14)),
            Person(id: personBenID, name: "ben Ortiz",   // lowercase on purpose: exercises NOCASE sort
                   birthday: day(1992, 11, 2)),
            Person(id: personCleoID, name: "Cleo Dubois", birthday: nil),
            Person(id: personDanaID, name: "Dana Whitfield",
                   birthday: day(1975, 6, 30)),
            Person(id: personEzraID, name: "Ezra Park", birthday: nil),
        ]
    }

    /// The demo wishlist (fixed ids).
    public static var ideas: [GiftIdea] {
        [
            GiftIdea(id: ideaAvaBookID, personID: personAvaID,
                     note: "Cookbook: seasonal preserving",
                     priceHintCents: 4_500, sourceText: "corner bookshop window",
                     createdOn: day(2026, 1, 8)),
            GiftIdea(id: ideaAvaScarfID, personID: personAvaID,
                     note: "Wool scarf, moss green",
                     priceHintCents: 8_900, sourceText: nil,
                     createdOn: day(2026, 2, 2)),
            GiftIdea(id: ideaBenVinylID, personID: personBenID,
                     note: "Repress jazz vinyl box set",
                     priceHintCents: 6_200, sourceText: "mentioned at dinner",
                     createdOn: day(2026, 1, 20)),
            GiftIdea(id: ideaCleoKnifeID, personID: personCleoID,
                     note: "Paring knife, hand-forged",
                     priceHintCents: 7_500, sourceText: "craft fair flyer",
                     createdOn: day(2026, 3, 1)),
            GiftIdea(id: ideaDanaLampID, personID: personDanaID,
                     note: "Desk lamp with warm dimmer",
                     priceHintCents: nil, sourceText: nil,   // no price hint: unknown-price state
                     createdOn: day(2026, 2, 14)),
            GiftIdea(id: ideaEzraCandleID, personID: personEzraID,
                     note: "Soy candle trio, cedar",
                     priceHintCents: 3_100, sourceText: "made by a friend",
                     createdOn: day(2026, 3, 21)),
        ]
    }

    /// The one live occasion: Dana's birthday, 2026-10-04.
    public static var occasion: Occasion {
        Occasion(id: occasionID, name: "Dana's birthday", date: day(2026, 10, 4))
    }

    /// One slot per status across the state machine (fixed ids).
    public static var slots: [OccasionSlot] {
        [
            OccasionSlot(id: slotAvaID, occasionID: occasionID, personID: personAvaID,
                         budgetCents: 5_000, status: .idea, chosenIdeaID: nil),
            OccasionSlot(id: slotBenID, occasionID: occasionID, personID: personBenID,
                         budgetCents: 7_000, status: .chosen, chosenIdeaID: ideaBenVinylID),
            OccasionSlot(id: slotCleoID, occasionID: occasionID, personID: personCleoID,
                         budgetCents: 9_000, status: .bought, chosenIdeaID: ideaCleoKnifeID),
            OccasionSlot(id: slotEzraID, occasionID: occasionID, personID: personEzraID,
                         budgetCents: 4_000, status: .wrapped, chosenIdeaID: ideaEzraCandleID),
            OccasionSlot(id: slotDanaID, occasionID: occasionID, personID: personDanaID,
                         budgetCents: 12_000, status: .given, chosenIdeaID: ideaDanaLampID),
        ]
    }

    /// Demo ledger history: the row the `given` slot implies, plus one
    /// received row (the `given` side comes only from slot transitions).
    public static var ledgerEntries: [LedgerEntry] {
        [
            LedgerEntry(
                id: ledgerGivenID,
                direction: .given, date: day(2026, 10, 4), personID: personDanaID,
                occasionID: occasionID, itemDescription: "Desk lamp with warm dimmer",
                valueCents: nil
            ),
            LedgerEntry(
                id: ledgerReceivedID,
                direction: .received, date: day(2026, 4, 12), personID: personAvaID,
                occasionID: nil, itemDescription: "Handmade candles", valueCents: 2_400
            ),
        ]
    }

    /// Seed the demo vault into `store` inside one transaction. Idempotent:
    /// re-seeding upserts the same fixed rows.
    public static func seed(into store: GiftVaultStore) throws {
        try store.writer.write { db in
            for person in people { try PersonRecord(person).save(db) }
            for idea in ideas { try GiftIdeaRecord(idea).save(db) }
            try OccasionRecord(occasion).save(db)
            for slot in slots { try OccasionSlotRecord(slot).save(db) }
            for entry in ledgerEntries { try LedgerEntryRecord(entry).save(db) }
        }
    }
}
