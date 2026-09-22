import Foundation
import GRDB
import Testing
@testable import GiftVaultKit
@testable import GiftVaultStoreKit

// Issue #3 store tests. Every mutation path on the store gets at least one
// test: person/idea/occasion/slot/ledger CRUD, FK enforcement, atomic
// state-machine transitions with ledger side effects, migration
// idempotency, budget CHECK constraints, and the deterministic fixture
// seed. All run on Linux CI against the system SQLite.

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate {
    guard let date = CalendarDate(year: y, month: m, day: d) else {
        preconditionFailure("invalid test date \(y)-\(m)-\(d)")
    }
    return date
}

private func makeStore() throws -> GiftVaultStore {
    try GiftVaultStore.inMemory()
}

// MARK: - Migrations

@Suite("Migrations")
struct MigrationTests {
    @Test("Fresh database applies v1 and reports it applied")
    func freshDatabaseMigrates() throws {
        let store = try makeStore()
        #expect(try store.appliedMigrations() == ["v1"])
    }

    @Test("Re-running migrations is a no-op (forward-only)")
    func migrateIsIdempotent() throws {
        let store = try makeStore()
        try store.migrate()
        try store.migrate()
        #expect(try store.appliedMigrations() == ["v1"])
    }

    @Test("v1 schema has exactly the five domain tables")
    func schemaTablesExist() throws {
        let store = try makeStore()
        let tables = try store.reader.read { db in
            try Set(String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table'
                  AND name NOT LIKE 'sqlite_%'
                  AND name <> 'grdb_migrations'
                """))
        }
        #expect(tables == ["person", "occasion", "gift_idea", "occasion_slot", "ledger_entry"])
    }

    @Test("No REAL columns exist anywhere — money is integer cents only")
    func noFloatingPointColumns() throws {
        let store = try makeStore()
        let realColumns: [String] = try store.reader.read { db in
            var found: [String] = []
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                  AND name <> 'grdb_migrations'
                """)
            for table in tables {
                let columns = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
                for column in columns {
                    let type: String = column["type"]
                    if type.uppercased().contains("REAL") || type.uppercased().contains("FLOAT")
                        || type.uppercased().contains("DOUBLE") {
                        found.append("\(table).\(column["name"])")
                    }
                }
            }
            return found
        }
        #expect(realColumns.isEmpty)
    }
}

// MARK: - People CRUD

@Suite("People CRUD")
struct PeopleTests {
    @Test("Save, fetch, list, and delete a person (round-trip fidelity)")
    func personRoundTrip() throws {
        let store = try makeStore()
        let person = Person(name: "Ava Chen", birthday: day(1988, 3, 14))
        try store.savePerson(person)

        let fetched = try #require(try store.person(id: person.id))
        #expect(fetched == person)

        try store.savePerson(Person(id: GiftVaultFixtures.personBenID, name: "ben Ortiz"))
        let names = try store.allPeople().map(\.name)
        #expect(names == ["Ava Chen", "ben Ortiz"])  // NOCASE sort

        try store.deletePerson(id: person.id)
        #expect(try store.person(id: person.id) == nil)
    }

    @Test("Person without birthday round-trips as nil")
    func optionalBirthday() throws {
        let store = try makeStore()
        let person = Person(name: "No Birthday")
        try store.savePerson(person)
        #expect(try store.person(id: person.id)?.birthday == nil)
    }

    @Test("Save twice upserts instead of duplicating")
    func upsert() throws {
        let store = try makeStore()
        var person = Person(name: "Old Name")
        try store.savePerson(person)
        person.name = "New Name"
        try store.savePerson(person)
        #expect(try store.recordCounts().people == 1)
        #expect(try store.person(id: person.id)?.name == "New Name")
    }

    @Test("Deleting a person cascades to ideas, slots, and ledger rows")
    func cascadeDelete() throws {
        let store = try makeStore()
        let person = Person(name: "Cascade")
        try store.savePerson(person)
        let occasion = Occasion(name: "Some Day", date: day(2026, 12, 25))
        try store.saveOccasion(occasion)
        try store.saveIdea(GiftIdea(personID: person.id, note: "trinket", createdOn: day(2026, 1, 1)))
        try store.saveSlot(OccasionSlot(occasionID: occasion.id, personID: person.id, budgetCents: 100))
        try store.saveLedgerEntry(LedgerEntry(direction: .received, date: day(2026, 2, 2),
                                              personID: person.id, itemDescription: "cookies"))

        try store.deletePerson(id: person.id)
        let counts = try store.recordCounts()
        #expect(counts.people == 0)
        #expect(counts.ideas == 0)
        #expect(counts.slots == 0)
        #expect(counts.ledger == 0)
    }
}

// MARK: - Ideas CRUD

@Suite("Ideas CRUD")
struct IdeaTests {
    @Test("Idea round-trips all fields including optional price hint")
    func ideaRoundTrip() throws {
        let store = try makeStore()
        let person = Person(name: "Idea Owner")
        try store.savePerson(person)
        let idea = GiftIdea(personID: person.id, note: "vinyl box set",
                            priceHintCents: 6_200, sourceText: "record fair",
                            createdOn: day(2026, 1, 20))
        try store.saveIdea(idea)
        #expect(try store.idea(id: idea.id) == idea)

        let noHint = GiftIdea(personID: person.id, note: "mystery want", createdOn: day(2026, 2, 1))
        try store.saveIdea(noHint)
        #expect(try store.idea(id: noHint.id)?.priceHintCents == nil)
    }

    @Test("Saving an idea for an unknown person fails and stores nothing")
    func ideaRequiresPerson() throws {
        let store = try makeStore()
        let ghostID = UUID()
        do {
            try store.saveIdea(GiftIdea(personID: ghostID, note: "ghost", createdOn: day(2026, 1, 1)))
            Issue.record("expected notFound")
        } catch let error as GiftVaultStoreError {
            #expect(error == .notFound(entity: "person", id: ghostID))
        }
        #expect(try store.recordCounts().ideas == 0)
    }

    @Test("Ideas list for a person is ordered oldest day first")
    func ideaOrdering() throws {
        let store = try makeStore()
        let person = Person(name: "Orderer")
        try store.savePerson(person)
        let later = GiftIdea(personID: person.id, note: "later", createdOn: day(2026, 6, 1))
        let earlier = GiftIdea(personID: person.id, note: "earlier", createdOn: day(2026, 1, 1))
        try store.saveIdea(later)
        try store.saveIdea(earlier)
        #expect(try store.ideas(forPerson: person.id).map(\.note) == ["earlier", "later"])
    }

    @Test("Delete idea removes it and clears slot references")
    func deleteIdeaClearsSelection() throws {
        let store = try makeStore()
        let person = Person(name: "Idea Owner")
        try store.savePerson(person)
        let occasion = Occasion(name: "Birthday", date: day(2026, 10, 4))
        try store.saveOccasion(occasion)
        let idea = GiftIdea(personID: person.id, note: "chosen thing", createdOn: day(2026, 1, 1))
        try store.saveIdea(idea)
        let slot = OccasionSlot(occasionID: occasion.id, personID: person.id,
                                budgetCents: 5_000, status: .chosen, chosenIdeaID: idea.id)
        try store.saveSlot(slot)

        try store.deleteIdea(id: idea.id)
        #expect(try store.slot(id: slot.id)?.chosenIdeaID == nil)
    }
}

// MARK: - Occasions CRUD

@Suite("Occasions CRUD")
struct OccasionTests {
    @Test("Occasion round-trips with and without a date")
    func occasionRoundTrip() throws {
        let store = try makeStore()
        let dated = Occasion(name: "Birthday", date: day(2026, 10, 4))
        let fuzzy = Occasion(name: "Holiday 2026")
        try store.saveOccasion(dated)
        try store.saveOccasion(fuzzy)
        #expect(try store.occasion(id: dated.id) == dated)
        #expect(try store.occasion(id: fuzzy.id) == fuzzy)
    }

    @Test("Occasion list: dated chronologically first, undated by name last")
    func occasionOrdering() throws {
        let store = try makeStore()
        try store.saveOccasion(Occasion(name: "Undated B", date: nil))
        try store.saveOccasion(Occasion(name: "zmas", date: day(2026, 12, 25)))
        try store.saveOccasion(Occasion(name: "Alpha", date: day(2026, 3, 1)))
        try store.saveOccasion(Occasion(name: "undated a", date: nil))
        #expect(try store.allOccasions().map(\.name) == ["Alpha", "zmas", "undated a", "Undated B"])
    }

    @Test("Deleting an occasion cascades slots; ledger keeps rows with nil occasion")
    func occasionDeleteEffects() throws {
        let store = try makeStore()
        let person = Person(name: "Ledger Keeper")
        try store.savePerson(person)
        let occasion = Occasion(name: "Gone Soon", date: day(2026, 5, 1))
        try store.saveOccasion(occasion)
        try store.saveSlot(OccasionSlot(occasionID: occasion.id, personID: person.id, budgetCents: 10))
        try store.saveLedgerEntry(LedgerEntry(direction: .given, date: day(2026, 5, 1),
                                              personID: person.id, occasionID: occasion.id,
                                              itemDescription: "kept history"))
        try store.deleteOccasion(id: occasion.id)
        let counts = try store.recordCounts()
        #expect(counts.slots == 0)
        let entries = try store.allLedgerEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.occasionID == nil)
        #expect(entries.first?.itemDescription == "kept history")
    }
}

// MARK: - Slot persistence and budget contract

@Suite("Slots and budget contract")
struct SlotTests {
    @Test("Slot round-trips budget, status, and chosen idea")
    func slotRoundTrip() throws {
        let store = try makeStore()
        let person = Person(name: "Slot Owner")
        try store.savePerson(person)
        let occasion = Occasion(name: "Graduation", date: day(2026, 6, 6))
        try store.saveOccasion(occasion)
        let idea = GiftIdea(personID: person.id, note: "nice pen", priceHintCents: 3_300,
                            createdOn: day(2026, 2, 2))
        try store.saveIdea(idea)
        let slot = OccasionSlot(occasionID: occasion.id, personID: person.id,
                                budgetCents: 4_000, status: .chosen, chosenIdeaID: idea.id)
        try store.saveSlot(slot)
        #expect(try store.slot(id: slot.id) == slot)
    }

    @Test("Budget over the contract limit is rejected atomically")
    func budgetLimitEnforced() throws {
        let store = try makeStore()
        let person = Person(name: "Rich")
        try store.savePerson(person)
        let occasion = Occasion(name: "Grand", date: nil)
        try store.saveOccasion(occasion)
        let oversized = OccasionSlot(occasionID: occasion.id, personID: person.id,
                                     budgetCents: GiftVaultLimits.maximumBudgetMinorUnitsPerPerson + 1)
        #expect(throws: GiftVaultStoreError.budgetOutOfRange(oversized.budgetCents)) {
            try store.saveSlot(oversized)
        }
        #expect(try store.recordCounts().slots == 0)
        let negative = OccasionSlot(occasionID: occasion.id, personID: person.id, budgetCents: -1)
        #expect(throws: GiftVaultStoreError.budgetOutOfRange(-1)) {
            try store.saveSlot(negative)
        }
    }

    @Test("One slot per person per occasion (unique constraint)")
    func uniqueSlotPerPersonOccasion() throws {
        let store = try makeStore()
        let person = Person(name: "Double Booked")
        try store.savePerson(person)
        let occasion = Occasion(name: "Shared", date: nil)
        try store.saveOccasion(occasion)
        let first = OccasionSlot(occasionID: occasion.id, personID: person.id, budgetCents: 500)
        try store.saveSlot(first)
        let second = OccasionSlot(id: UUID(), occasionID: occasion.id, personID: person.id,
                                  budgetCents: 600)
        #expect(throws: (any Error).self) {
            try store.saveSlot(second)
        }
        #expect(try store.recordCounts().slots == 1)
    }

    @Test("Slot for unknown occasion fails without writing")
    func slotRequiresOccasion() throws {
        let store = try makeStore()
        let person = Person(name: "Orphan")
        try store.savePerson(person)
        let ghostOccasion = UUID()
        do {
            try store.saveSlot(OccasionSlot(occasionID: ghostOccasion, personID: person.id, budgetCents: 1))
            Issue.record("expected notFound")
        } catch let error as GiftVaultStoreError {
            #expect(error == .notFound(entity: "occasion", id: ghostOccasion))
        }
        #expect(try store.recordCounts().slots == 0)
    }

    @Test("Stored status string outside vocabulary is rejected by CHECK")
    func statusVocabularyCheck() throws {
        let store = try makeStore()
        let person = Person(name: "Status Tester")
        try store.savePerson(person)
        let occasion = Occasion(name: "Check", date: nil)
        try store.saveOccasion(occasion)
        #expect(throws: (any Error).self) {
            try store.writer.write { db in
                try db.execute(
                    sql: """
                    INSERT INTO occasion_slot (id, occasion_id, person_id, budget_cents, status)
                    VALUES (?, ?, ?, 100, 'shipped')
                    """,
                    arguments: [UUID().uuidString, occasion.id.uuidString, person.id.uuidString]
                )
            }
        }
    }
}

// MARK: - State-machine transitions (atomic ledger side effects)

@Suite("Slot transitions persist atomically")
struct TransitionTests {
    /// Seed: person, occasion, idea, and a slot at `idea` with budget ≥ price.
    private struct Fixture {
        let store: GiftVaultStore
        let person: Person
        let occasion: Occasion
        let idea: GiftIdea
        let slot: OccasionSlot
    }

    private func makeFixture(budget: BudgetMinorUnits = 5_000) throws -> Fixture {
        let store = try makeStore()
        let person = Person(name: "Walker")
        try store.savePerson(person)
        let occasion = Occasion(name: "Housewarming", date: day(2026, 9, 1))
        try store.saveOccasion(occasion)
        let idea = GiftIdea(personID: person.id, note: "espresso machine",
                            priceHintCents: 4_900, createdOn: day(2026, 4, 4))
        try store.saveIdea(idea)
        let slot = OccasionSlot(occasionID: occasion.id, personID: person.id, budgetCents: budget)
        try store.saveSlot(slot)
        return Fixture(store: store, person: person, occasion: occasion, idea: idea, slot: slot)
    }

    @Test("Full walk idea→chosen→bought→wrapped→given persists each step")
    func fullWalk() throws {
        let f = try makeFixture()
        let date = day(2026, 9, 1)

        var slot = try f.store.advanceSlot(id: f.slot.id, to: .chosen,
                                           chosenIdeaID: f.idea.id, givenOn: date)
        #expect(slot.status == .chosen)
        #expect(try f.store.slot(id: f.slot.id)?.status == .chosen)
        #expect(try f.store.allLedgerEntries().isEmpty)

        slot = try f.store.advanceSlot(id: f.slot.id, to: .bought, givenOn: date)
        #expect(slot.status == .bought)
        slot = try f.store.advanceSlot(id: f.slot.id, to: .wrapped, givenOn: date)
        #expect(slot.status == .wrapped)

        slot = try f.store.advanceSlot(id: f.slot.id, to: .given, givenOn: day(2026, 9, 2))
        #expect(slot.status == .given)

        let entries = try f.store.allLedgerEntries()
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.direction == .given)
        #expect(entry.personID == f.person.id)
        #expect(entry.occasionID == f.occasion.id)
        #expect(entry.itemDescription == "espresso machine")
        #expect(entry.valueCents == 4_900)
        #expect(entry.date == day(2026, 9, 2))
    }

    @Test("Chosen idea persists through later steps")
    func chosenIdeaPersists() throws {
        let f = try makeFixture()
        try f.store.advanceSlot(id: f.slot.id, to: .chosen, chosenIdeaID: f.idea.id,
                                givenOn: day(2026, 9, 1))
        try f.store.advanceSlot(id: f.slot.id, to: .bought, givenOn: day(2026, 9, 1))
        #expect(try f.store.slot(id: f.slot.id)?.chosenIdeaID == f.idea.id)
    }

    @Test("Illegal transition throws and writes nothing")
    func illegalTransitionRollsBack() throws {
        let f = try makeFixture()
        #expect(throws: SlotTransitionError.illegal(from: .idea, to: .bought)) {
            try f.store.advanceSlot(id: f.slot.id, to: .bought, givenOn: day(2026, 9, 1))
        }
        #expect(try f.store.slot(id: f.slot.id)?.status == .idea)
    }

    @Test("Transition to chosen without idea throws and persists nothing")
    func chosenWithoutIdeaRejected() throws {
        let f = try makeFixture()
        #expect(throws: SlotTransitionError.chosenWithoutIdea) {
            try f.store.advanceSlot(id: f.slot.id, to: .chosen, givenOn: day(2026, 9, 1))
        }
        #expect(try f.store.slot(id: f.slot.id)?.status == .idea)
        #expect(try f.store.slot(id: f.slot.id)?.chosenIdeaID == nil)
    }

    @Test("Terminal given state rejects further transitions")
    func terminalState() throws {
        let f = try makeFixture()
        let date = day(2026, 9, 1)
        try f.store.advanceSlot(id: f.slot.id, to: .chosen, chosenIdeaID: f.idea.id, givenOn: date)
        try f.store.advanceSlot(id: f.slot.id, to: .bought, givenOn: date)
        try f.store.advanceSlot(id: f.slot.id, to: .wrapped, givenOn: date)
        try f.store.advanceSlot(id: f.slot.id, to: .given, givenOn: date)
        #expect(throws: SlotTransitionError.terminal(state: .given)) {
            try f.store.advanceSlot(id: f.slot.id, to: .given, givenOn: date)
        }
        // Only one ledger row was ever created.
        #expect(try f.store.allLedgerEntries().count == 1)
    }

    @Test("Advance-one-step convenience covers the same walk")
    func advanceOneStep() throws {
        let f = try makeFixture()
        let date = day(2026, 12, 25)
        var slot = try #require(try f.store.advanceSlotOneStep(
            id: f.slot.id, chosenIdeaID: f.idea.id, givenOn: date))
        #expect(slot.status == .chosen)
        while let next = try f.store.advanceSlotOneStep(id: f.slot.id, givenOn: date) {
            slot = next
        }
        #expect(slot.status == .given)
        #expect(try f.store.allLedgerEntries().count == 1)
        // Terminal: returns nil instead of throwing.
        #expect(try f.store.advanceSlotOneStep(id: f.slot.id, givenOn: date) == nil)
    }

    @Test("Given step without price hint stores nil value cents")
    func givenWithoutValue() throws {
        let f = try makeFixture()
        let plain = GiftIdea(personID: f.person.id, note: "handwritten coupon",
                             createdOn: day(2026, 3, 3))
        try f.store.saveIdea(plain)
        let date = day(2026, 9, 1)
        try f.store.advanceSlot(id: f.slot.id, to: .chosen, chosenIdeaID: plain.id, givenOn: date)
        try f.store.advanceSlot(id: f.slot.id, to: .bought, givenOn: date)
        try f.store.advanceSlot(id: f.slot.id, to: .wrapped, givenOn: date)
        try f.store.advanceSlot(id: f.slot.id, to: .given, givenOn: date)
        let entry = try #require(try f.store.allLedgerEntries().first)
        #expect(entry.itemDescription == "handwritten coupon")
        #expect(entry.valueCents == nil)
    }

    @Test("Advance on missing slot throws notFound")
    func advanceMissingSlot() throws {
        let store = try makeStore()
        let missingID = UUID()
        do {
            try store.advanceSlot(id: missingID, to: .chosen, givenOn: day(2026, 1, 1))
            Issue.record("expected notFound")
        } catch let error as GiftVaultStoreError {
            #expect(error == GiftVaultStoreError.notFound(entity: "occasion_slot", id: missingID))
        }
    }
}

// MARK: - Ledger CRUD

@Suite("Ledger CRUD")
struct LedgerTests {
    @Test("Ledger entry round-trips and lists newest-first")
    func ledgerRoundTrip() throws {
        let store = try makeStore()
        let person = Person(name: "Giver")
        try store.savePerson(person)
        let early = LedgerEntry(direction: .received, date: day(2026, 1, 5), personID: person.id,
                                itemDescription: "cookies", valueCents: 1_200)
        let late = LedgerEntry(direction: .given, date: day(2026, 7, 5), personID: person.id,
                               itemDescription: "scarf", valueCents: 2_200)
        try store.saveLedgerEntry(early)
        try store.saveLedgerEntry(late)
        let all = try store.allLedgerEntries()
        #expect(all.map(\.itemDescription) == ["scarf", "cookies"])
        #expect(try store.ledgerEntries(forPerson: person.id).count == 2)
        try store.deleteLedgerEntry(id: early.id)
        #expect(try store.allLedgerEntries().count == 1)
    }

    @Test("Ledger entry for unknown person is rejected atomically")
    func ledgerRequiresPerson() throws {
        let store = try makeStore()
        let ghostID = UUID()
        do {
            try store.saveLedgerEntry(LedgerEntry(direction: .given, date: day(2026, 1, 1),
                                                  personID: ghostID, itemDescription: "ghost gift"))
            Issue.record("expected notFound")
        } catch let error as GiftVaultStoreError {
            #expect(error == .notFound(entity: "person", id: ghostID))
        }
        #expect(try store.allLedgerEntries().isEmpty)
    }
}

// MARK: - File-backed store durability

@Suite("File-backed store")
struct FileStoreTests {
    @Test("Data survives close and reopen of the database file")
    func reopenKeepsData() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("giftvault-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("vault.sqlite")

        let person = Person(name: "Durable", birthday: day(2000, 2, 29))
        do {
            let store = try GiftVaultStore(url: url)
            try store.savePerson(person)
            #expect(try store.appliedMigrations() == ["v1"])
        }
        let reopened = try GiftVaultStore(url: url)
        #expect(try reopened.person(id: person.id) == person)
        #expect(try reopened.appliedMigrations() == ["v1"])  // no re-apply
    }
}

// MARK: - Fixtures

@Suite("Seeded fixtures")
struct FixtureTests {
    @Test("Seed produces people with ideas, one live occasion covering every status, ledger rows")
    func fixtureShape() throws {
        let store = try makeStore()
        try GiftVaultFixtures.seed(into: store)

        let people = try store.allPeople()
        #expect(people.count == 5)
        #expect(people.allSatisfy { !$0.name.isEmpty })

        let occasion = try #require(try store.occasion(id: GiftVaultFixtures.occasionID))
        #expect(occasion.date != nil)

        let slots = try store.slots(forOccasion: occasion.id)
        #expect(Set(slots.map(\.status)) == Set(OccasionStatus.allCases))
        #expect(Set(slots.map(\.id)) == [
            GiftVaultFixtures.slotAvaID, GiftVaultFixtures.slotBenID,
            GiftVaultFixtures.slotCleoID, GiftVaultFixtures.slotDanaID,
            GiftVaultFixtures.slotEzraID,
        ])

        let ledger = try store.allLedgerEntries()
        #expect(ledger.count == 2)
        #expect(Set(ledger.map(\.direction)) == [.given, .received])

        for person in people {
            #expect(!(try store.ideas(forPerson: person.id)).isEmpty)
        }
    }

    @Test("Seeding twice is idempotent (same fixed ids, no duplicates)")
    func seedIdempotent() throws {
        let store = try makeStore()
        try GiftVaultFixtures.seed(into: store)
        try GiftVaultFixtures.seed(into: store)
        let counts = try store.recordCounts()
        #expect(counts.people == 5)
        #expect(counts.ideas == 6)
        #expect(counts.occasions == 1)
        #expect(counts.slots == 5)
        #expect(counts.ledger == 2)
    }

    @Test("Fixture identifiers and dates are deterministic across calls")
    func fixturesDeterministic() {
        #expect(GiftVaultFixtures.people.map(\.id) == GiftVaultFixtures.people.map(\.id))
        #expect(GiftVaultFixtures.slots.map(\.id) == GiftVaultFixtures.slots.map(\.id))
        #expect(GiftVaultFixtures.occasion.date == CalendarDate(year: 2026, month: 10, day: 4))
    }

    @Test("Seeded given slot carries its implied ledger row")
    func givenFixtureConsistency() throws {
        let store = try makeStore()
        try GiftVaultFixtures.seed(into: store)
        let givenEntry = try #require(try store.allLedgerEntries().first {
            $0.direction == .given
        })
        let givenSlot = try #require(
            try store.slots(forOccasion: GiftVaultFixtures.occasionID)
                .first { $0.status == .given }
        )
        #expect(givenEntry.personID == givenSlot.personID)
        #expect(givenEntry.occasionID == givenSlot.occasionID)
        let chosenIdea = try store.idea(id: try #require(givenSlot.chosenIdeaID))
        #expect(givenEntry.itemDescription == chosenIdea?.note)
        #expect(givenEntry.valueCents == chosenIdea?.priceHintCents)
    }
}
