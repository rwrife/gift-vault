import Foundation
import Testing
@testable import GiftVaultKit
@testable import GiftVaultStoreKit

@Suite("Backup, Export, and Restore")
struct BackupBundleTests {
    private func makeStore() throws -> GiftVaultStore {
        try GiftVaultStore.inMemory()
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate {
        CalendarDate(year: y, month: m, day: d)!
    }

    @Test("Round-trip export and restore restores data equivalence")
    func roundTripEquivalence() throws {
        let original = try makeStore()
        try GiftVaultFixtures.seed(into: original)

        let bundleData = try original.exportBackupBundle(appVersion: "0.1.0")
        #expect(!bundleData.isEmpty)

        let target = try makeStore()
        try target.restoreBackupBundle(bundleData)

        let originalCounts = try original.recordCounts()
        let targetCounts = try target.recordCounts()
        #expect(targetCounts.people == originalCounts.people)
        #expect(targetCounts.ideas == originalCounts.ideas)
        #expect(targetCounts.occasions == originalCounts.occasions)
        #expect(targetCounts.slots == originalCounts.slots)
        #expect(targetCounts.ledger == originalCounts.ledger)

        #expect(try target.allPeople() == (try original.allPeople()))
        #expect(try target.allIdeas() == (try original.allIdeas()))
        #expect(try target.allOccasions() == (try original.allOccasions()))
        #expect(try target.allLedgerEntries() == (try original.allLedgerEntries()))

        let originalSlots = try original.slots(forOccasion: GiftVaultFixtures.occasionID)
        let targetSlots = try target.slots(forOccasion: GiftVaultFixtures.occasionID)
        #expect(targetSlots == originalSlots)
    }

    @Test("Tampered or corrupt backup bundle is rejected by checksum check")
    func tamperedBundleRejected() throws {
        let store = try makeStore()
        try GiftVaultFixtures.seed(into: store)
        let bundleData = try store.exportBackupBundle(appVersion: "0.1.0")

        guard var jsonString = String(data: bundleData, encoding: .utf8) else {
            Issue.record("bundleData was not valid utf8")
            return
        }

        // Tamper with one person's name inside the payload without updating checksum
        jsonString = jsonString.replacingOccurrences(of: "Ava Chen", with: "Eve Chen")
        let tamperedData = Data(jsonString.utf8)

        let target = try makeStore()
        #expect(throws: GiftVaultBackupError.integrityMismatch) {
            try target.restoreBackupBundle(tamperedData)
        }
    }

    @Test("Future bundle format version is refused cleanly")
    func futureBundleFormatRefused() throws {
        let store = try makeStore()
        try GiftVaultFixtures.seed(into: store)
        let bundleData = try store.exportBackupBundle(appVersion: "0.1.0")

        guard var jsonString = String(data: bundleData, encoding: .utf8) else {
            Issue.record("bundleData was not valid utf8")
            return
        }

        jsonString = jsonString.replacingOccurrences(of: "\"formatVersion\" : 1", with: "\"formatVersion\" : 99")
        let futureData = Data(jsonString.utf8)

        let target = try makeStore()
        do {
            try target.restoreBackupBundle(futureData)
            Issue.record("expected failure")
        } catch let error as GiftVaultBackupError {
            #expect(error == .unsupportedBundleFormatVersion(99))
        }
    }

    @Test("Unknown future schema version in backup is refused cleanly")
    func futureSchemaVersionRefused() throws {
        let store = try makeStore()
        try GiftVaultFixtures.seed(into: store)

        // Fabricate payload with schema v99 and compute valid checksum for it
        let snapshot = try store.allPeople()
        let payload = GiftVaultBackupPayload(
            schemaVersion: "v99",
            appVersion: "0.1.0",
            people: snapshot,
            ideas: [],
            occasions: [],
            slots: [],
            ledger: []
        )

        let bundleData = try encodeBundleWithCustomPayload(payload)

        let target = try makeStore()
        do {
            try target.restoreBackupBundle(bundleData)
            Issue.record("expected failure")
        } catch let error as GiftVaultBackupError {
            #expect(error == .unsupportedSchemaVersion("v99"))
        }
    }

    @Test("Corrupt non-JSON data is rejected")
    func corruptDataRejected() throws {
        let target = try makeStore()
        let corruptData = Data("this is not json at all".utf8)
        #expect(throws: GiftVaultBackupError.invalidBundle("JSON decoding failed")) {
            try target.restoreBackupBundle(corruptData)
        }
    }

    @Test("Payload with dangling foreign keys is refused atomically without modifying vault")
    func danglingForeignKeyRejected() throws {
        let target = try makeStore()
        let person = Person(id: UUID(), name: "Solo")
        try target.savePerson(person)

        // Payload with an idea referencing non-existent person
        let ghostPersonID = UUID()
        let badIdea = GiftIdea(personID: ghostPersonID, note: "Ghost item", createdOn: day(2026, 1, 1))
        let payload = GiftVaultBackupPayload(
            schemaVersion: "v1",
            appVersion: "0.1.0",
            people: [],
            ideas: [badIdea],
            occasions: [],
            slots: [],
            ledger: []
        )

        let badData = try encodeBundleWithCustomPayload(payload)
        do {
            try target.restoreBackupBundle(badData)
            Issue.record("expected invalidPayload error")
        } catch let error as GiftVaultBackupError {
            guard case .invalidPayload = error else {
                Issue.record("unexpected error: \(error)")
                return
            }
        }

        // Target vault still has original person and 0 ideas
        #expect(try target.recordCounts().people == 1)
        #expect(try target.recordCounts().ideas == 0)
    }

    @Test("CSV views export expected headers and handle commas, quotes, and newlines safely")
    func csvExportEscaping() throws {
        let store = try makeStore()
        let trickyPerson = Person(name: "O'Connor, \"Bob\"\nJr.")
        try store.savePerson(trickyPerson)

        let trickyIdea = GiftIdea(
            personID: trickyPerson.id,
            note: "Item with, comma and \"quotes\" and\nline break",
            priceHintCents: 1250,
            sourceText: "Shop, Downtown",
            createdOn: day(2026, 9, 26)
        )
        try store.saveIdea(trickyIdea)

        let occasion = Occasion(name: "Holiday, 2026", date: day(2026, 12, 25))
        try store.saveOccasion(occasion)
        let slot = OccasionSlot(
            occasionID: occasion.id,
            personID: trickyPerson.id,
            budgetCents: 5000,
            status: .chosen,
            chosenIdeaID: trickyIdea.id
        )
        try store.saveSlot(slot)

        let ledgerEntry = LedgerEntry(
            direction: .given,
            date: day(2026, 12, 25),
            personID: trickyPerson.id,
            occasionID: occasion.id,
            itemDescription: "Item with, comma and \"quotes\"",
            valueCents: 1250
        )
        try store.saveLedgerEntry(ledgerEntry)

        let ideasCSV = try store.exportIdeasCSV()
        let occasionsCSV = try store.exportOccasionsCSV()
        let ledgerCSV = try store.exportLedgerCSV()

        #expect(ideasCSV.starts(with: "idea_id,person_id,person_name,note,price_hint_cents,source_text,created_on\n"))
        #expect(ideasCSV.contains("\"O'Connor, \"\"Bob\"\"\nJr.\""))
        #expect(ideasCSV.contains("\"Item with, comma and \"\"quotes\"\" and\nline break\""))

        #expect(occasionsCSV.starts(with: "occasion_id,occasion_name,occasion_date,slot_id,person_id,person_name,budget_cents,status,chosen_idea_id,chosen_idea_note\n"))
        #expect(occasionsCSV.contains("\"Holiday, 2026\""))

        #expect(ledgerCSV.starts(with: "entry_id,direction,date,person_id,person_name,occasion_id,item_description,value_cents\n"))
        #expect(ledgerCSV.contains("\"Item with, comma and \"\"quotes\"\"\""))
    }

    private func encodeBundleWithCustomPayload(_ payload: GiftVaultBackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(payload)
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let integrity = String(format: "%016llx", hash)
        let dict: [String: Any] = [
            "formatVersion": 1,
            "exportedAt": "2026-09-26T00:00:00Z",
            "integrity": integrity,
            "payload": try JSONSerialization.jsonObject(with: data)
        ]
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }
}
