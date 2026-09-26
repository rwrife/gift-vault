import Foundation
import GiftVaultKit
import GRDB

// Issue #6: private backup/export/restore.
//
// Exports a single versioned JSON bundle (with integrity checksum) and three
// CSV views (ideas, occasions+slots, ledger). Restore validates format/schema
// compatibility, checksum integrity, and graph references before writing.
// Restore writes happen inside one transaction: either all rows land or none.

public enum GiftVaultBackupError: Error, Equatable, Sendable {
    case unsupportedBundleFormatVersion(Int)
    case unsupportedSchemaVersion(String)
    case invalidBundle(String)
    case integrityMismatch
    case invalidPayload(String)
}

extension GiftVaultBackupError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .unsupportedBundleFormatVersion(version):
            return "This backup uses bundle format v\(version), which this app cannot read yet. Update the app before restoring."
        case let .unsupportedSchemaVersion(version):
            return "This backup targets schema \(version), which this app cannot restore yet."
        case let .invalidBundle(message):
            return "Backup file is invalid: \(message)"
        case .integrityMismatch:
            return "Backup integrity check failed. The file is corrupted or was modified."
        case let .invalidPayload(message):
            return "Backup content is invalid: \(message)"
        }
    }
}

struct GiftVaultBackupPayload: Codable, Sendable {
    var schemaVersion: String
    var appVersion: String
    var people: [Person]
    var ideas: [GiftIdea]
    var occasions: [Occasion]
    var slots: [OccasionSlot]
    var ledger: [LedgerEntry]
}

private struct GiftVaultBackupBundle: Codable, Sendable {
    var formatVersion: Int
    var exportedAt: String
    var payload: GiftVaultBackupPayload
    var integrity: String
}

private enum GiftVaultBackupCodec {
    static let currentFormatVersion = 1

    static func encode(payload: GiftVaultBackupPayload, exportedAt: Date) throws -> Data {
        let integrity = try checksumHex(for: payload)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let bundle = GiftVaultBackupBundle(
            formatVersion: currentFormatVersion,
            exportedAt: formatter.string(from: exportedAt),
            payload: payload,
            integrity: integrity
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(bundle)
    }

    static func decodeAndValidate(_ data: Data, currentSchemaVersion: String) throws -> GiftVaultBackupPayload {
        let decoder = JSONDecoder()
        let bundle: GiftVaultBackupBundle
        do {
            bundle = try decoder.decode(GiftVaultBackupBundle.self, from: data)
        } catch {
            throw GiftVaultBackupError.invalidBundle("JSON decoding failed")
        }

        guard bundle.formatVersion <= currentFormatVersion else {
            throw GiftVaultBackupError.unsupportedBundleFormatVersion(bundle.formatVersion)
        }

        // First validate integrity against the exact bytes represented by the
        // decoded payload in canonical JSON form.
        let expected = try checksumHex(for: bundle.payload)
        guard expected == bundle.integrity else {
            throw GiftVaultBackupError.integrityMismatch
        }

        // Future bundle-format migrations hook: add `case 2`, `case 3`, ...
        // and map older payload shapes into `GiftVaultBackupPayload`.
        let migratedPayload = try migratePayload(bundle.payload, fromBundleFormat: bundle.formatVersion)

        // Future schema migrations hook: map backup schema vN to current DB
        // schema if/when older snapshots need transformation.
        return try migrateSchemaIfNeeded(
            payload: migratedPayload,
            toSchemaVersion: currentSchemaVersion
        )
    }

    private static func migratePayload(
        _ payload: GiftVaultBackupPayload,
        fromBundleFormat version: Int
    ) throws -> GiftVaultBackupPayload {
        switch version {
        case 1:
            return payload
        default:
            throw GiftVaultBackupError.unsupportedBundleFormatVersion(version)
        }
    }

    private static func migrateSchemaIfNeeded(
        payload: GiftVaultBackupPayload,
        toSchemaVersion currentSchemaVersion: String
    ) throws -> GiftVaultBackupPayload {
        if payload.schemaVersion == currentSchemaVersion {
            return payload
        }

        let currentOrdinal = schemaOrdinal(currentSchemaVersion)
        let payloadOrdinal = schemaOrdinal(payload.schemaVersion)
        if let currentOrdinal, let payloadOrdinal, payloadOrdinal > currentOrdinal {
            throw GiftVaultBackupError.unsupportedSchemaVersion(payload.schemaVersion)
        }

        // Hook for older-schema migrations. Add explicit cases when v2+ lands.
        switch (payload.schemaVersion, currentSchemaVersion) {
        default:
            throw GiftVaultBackupError.unsupportedSchemaVersion(payload.schemaVersion)
        }
    }

    private static func schemaOrdinal(_ version: String) -> Int? {
        guard version.hasPrefix("v") else { return nil }
        return Int(version.dropFirst())
    }

    private static func checksumHex(for payload: GiftVaultBackupPayload) throws -> String {
        let data = try canonicalPayloadData(payload)
        var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a 64 offset basis
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    private static func canonicalPayloadData(_ payload: GiftVaultBackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }
}

private struct GiftVaultBackupSnapshot: Sendable {
    var people: [Person]
    var ideas: [GiftIdea]
    var occasions: [Occasion]
    var slots: [OccasionSlot]
    var ledger: [LedgerEntry]
}

private enum GiftVaultCSV {
    static func render(rows: [[String]]) -> String {
        rows.map { row in row.map(escape).joined(separator: ",") }
            .joined(separator: "\n") + "\n"
    }

    private static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return field
    }
}

extension GiftVaultStore {
    public func exportBackupBundle(appVersion: String, exportedAt: Date = Date()) throws -> Data {
        let snapshot = try backupSnapshot()
        let payload = GiftVaultBackupPayload(
            schemaVersion: GiftVaultSchema.currentVersion,
            appVersion: appVersion,
            people: snapshot.people,
            ideas: snapshot.ideas,
            occasions: snapshot.occasions,
            slots: snapshot.slots,
            ledger: snapshot.ledger
        )
        return try GiftVaultBackupCodec.encode(payload: payload, exportedAt: exportedAt)
    }

    public func restoreBackupBundle(_ data: Data) throws {
        let payload = try GiftVaultBackupCodec.decodeAndValidate(
            data,
            currentSchemaVersion: GiftVaultSchema.currentVersion
        )
        try validate(payload: payload)

        try writer.write { db in
            try db.execute(sql: "DELETE FROM ledger_entry")
            try db.execute(sql: "DELETE FROM occasion_slot")
            try db.execute(sql: "DELETE FROM gift_idea")
            try db.execute(sql: "DELETE FROM occasion")
            try db.execute(sql: "DELETE FROM person")

            for person in payload.people {
                try PersonRecord(person).insert(db)
            }
            for idea in payload.ideas {
                try GiftIdeaRecord(idea).insert(db)
            }
            for occasion in payload.occasions {
                try OccasionRecord(occasion).insert(db)
            }
            for slot in payload.slots {
                try OccasionSlotRecord(slot).insert(db)
            }
            for entry in payload.ledger {
                try LedgerEntryRecord(entry).insert(db)
            }
        }
    }

    public func exportIdeasCSV() throws -> String {
        let snapshot = try backupSnapshot()
        let peopleByID = Dictionary(uniqueKeysWithValues: snapshot.people.map { ($0.id, $0.name) })
        var rows: [[String]] = [[
            "idea_id", "person_id", "person_name", "note", "price_hint_cents", "source_text", "created_on"
        ]]
        for idea in snapshot.ideas {
            rows.append([
                idea.id.uuidString,
                idea.personID.uuidString,
                peopleByID[idea.personID] ?? "",
                idea.note,
                idea.priceHintCents.map(String.init) ?? "",
                idea.sourceText ?? "",
                String(describing: idea.createdOn),
            ])
        }
        return GiftVaultCSV.render(rows: rows)
    }

    public func exportOccasionsCSV() throws -> String {
        let snapshot = try backupSnapshot()
        let peopleByID = Dictionary(uniqueKeysWithValues: snapshot.people.map { ($0.id, $0.name) })
        let occasionsByID = Dictionary(uniqueKeysWithValues: snapshot.occasions.map { ($0.id, $0) })
        let ideasByID = Dictionary(uniqueKeysWithValues: snapshot.ideas.map { ($0.id, $0) })

        var rows: [[String]] = [[
            "occasion_id", "occasion_name", "occasion_date", "slot_id", "person_id", "person_name",
            "budget_cents", "status", "chosen_idea_id", "chosen_idea_note"
        ]]

        for slot in snapshot.slots {
            let occasion = occasionsByID[slot.occasionID]
            let chosenIdea = slot.chosenIdeaID.flatMap { ideasByID[$0] }
            rows.append([
                slot.occasionID.uuidString,
                occasion?.name ?? "",
                occasion?.date.map(String.init(describing:)) ?? "",
                slot.id.uuidString,
                slot.personID.uuidString,
                peopleByID[slot.personID] ?? "",
                String(slot.budgetCents),
                slot.status.rawValue,
                slot.chosenIdeaID?.uuidString ?? "",
                chosenIdea?.note ?? "",
            ])
        }

        return GiftVaultCSV.render(rows: rows)
    }

    public func exportLedgerCSV() throws -> String {
        let snapshot = try backupSnapshot()
        let peopleByID = Dictionary(uniqueKeysWithValues: snapshot.people.map { ($0.id, $0.name) })

        var rows: [[String]] = [[
            "entry_id", "direction", "date", "person_id", "person_name", "occasion_id", "item_description", "value_cents"
        ]]
        for entry in snapshot.ledger {
            rows.append([
                entry.id.uuidString,
                entry.direction.rawValue,
                String(describing: entry.date),
                entry.personID.uuidString,
                peopleByID[entry.personID] ?? "",
                entry.occasionID?.uuidString ?? "",
                entry.itemDescription,
                entry.valueCents.map(String.init) ?? "",
            ])
        }
        return GiftVaultCSV.render(rows: rows)
    }

    private func backupSnapshot() throws -> GiftVaultBackupSnapshot {
        try reader.read { db in
            let people = try PersonRecord
                .order(Column("id"))
                .fetchAll(db)
                .map { try $0.toDomain() }
            let ideas = try GiftIdeaRecord
                .order(Column("id"))
                .fetchAll(db)
                .map { try $0.toDomain() }
            let occasions = try OccasionRecord
                .order(Column("id"))
                .fetchAll(db)
                .map { try $0.toDomain() }
            let slots = try OccasionSlotRecord
                .order(Column("id"))
                .fetchAll(db)
                .map { try $0.toDomain() }
            let ledger = try LedgerEntryRecord
                .order(Column("id"))
                .fetchAll(db)
                .map { try $0.toDomain() }
            return GiftVaultBackupSnapshot(
                people: people,
                ideas: ideas,
                occasions: occasions,
                slots: slots,
                ledger: ledger
            )
        }
    }

    private func validate(payload: GiftVaultBackupPayload) throws {
        let personIDs = Set(payload.people.map(\.id))
        guard personIDs.count == payload.people.count else {
            throw GiftVaultBackupError.invalidPayload("Duplicate person IDs")
        }

        let occasionIDs = Set(payload.occasions.map(\.id))
        guard occasionIDs.count == payload.occasions.count else {
            throw GiftVaultBackupError.invalidPayload("Duplicate occasion IDs")
        }

        let ideaIDs = Set(payload.ideas.map(\.id))
        guard ideaIDs.count == payload.ideas.count else {
            throw GiftVaultBackupError.invalidPayload("Duplicate idea IDs")
        }

        let slotIDs = Set(payload.slots.map(\.id))
        guard slotIDs.count == payload.slots.count else {
            throw GiftVaultBackupError.invalidPayload("Duplicate slot IDs")
        }

        let ledgerIDs = Set(payload.ledger.map(\.id))
        guard ledgerIDs.count == payload.ledger.count else {
            throw GiftVaultBackupError.invalidPayload("Duplicate ledger IDs")
        }

        for idea in payload.ideas {
            guard personIDs.contains(idea.personID) else {
                throw GiftVaultBackupError.invalidPayload("Idea \(idea.id.uuidString) references missing person \(idea.personID.uuidString)")
            }
        }

        var slotPairs = Set<String>()
        for slot in payload.slots {
            guard personIDs.contains(slot.personID) else {
                throw GiftVaultBackupError.invalidPayload("Slot \(slot.id.uuidString) references missing person \(slot.personID.uuidString)")
            }
            guard occasionIDs.contains(slot.occasionID) else {
                throw GiftVaultBackupError.invalidPayload("Slot \(slot.id.uuidString) references missing occasion \(slot.occasionID.uuidString)")
            }
            if let chosenIdeaID = slot.chosenIdeaID, !ideaIDs.contains(chosenIdeaID) {
                throw GiftVaultBackupError.invalidPayload("Slot \(slot.id.uuidString) references missing chosen idea \(chosenIdeaID.uuidString)")
            }
            guard (0...GiftVaultLimits.maximumBudgetMinorUnitsPerPerson).contains(slot.budgetCents) else {
                throw GiftVaultBackupError.invalidPayload("Slot \(slot.id.uuidString) has out-of-range budget \(slot.budgetCents)")
            }
            let pairKey = "\(slot.occasionID.uuidString)|\(slot.personID.uuidString)"
            guard !slotPairs.contains(pairKey) else {
                throw GiftVaultBackupError.invalidPayload("Duplicate slot for occasion/person pair \(pairKey)")
            }
            slotPairs.insert(pairKey)
        }

        for entry in payload.ledger {
            guard personIDs.contains(entry.personID) else {
                throw GiftVaultBackupError.invalidPayload("Ledger entry \(entry.id.uuidString) references missing person \(entry.personID.uuidString)")
            }
            if let occasionID = entry.occasionID, !occasionIDs.contains(occasionID) {
                throw GiftVaultBackupError.invalidPayload("Ledger entry \(entry.id.uuidString) references missing occasion \(occasionID.uuidString)")
            }
        }
    }
}
