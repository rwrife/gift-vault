import Foundation
import GiftVaultKit
import GRDB

// The persisted vault (issue #3).
//
// `GiftVaultStore` wraps one GRDB database — a `DatabasePool` on a file for
// the app, or an in-memory `DatabaseQueue` for tests — and exposes the
// CRUD repositories for every domain entity. All mutations run inside a
// single SQLite transaction, and slot status changes go through the issue
// #2 state machine: an illegal transition throws `SlotTransitionError` and
// writes nothing. The transition to `given` atomically inserts the implied
// ledger row (see `SlotStateMachine.givenLedgerEntry`).
//
// The store never reads clocks and never touches the network; dates always
// arrive as `CalendarDate` values from the caller.

public struct GiftVaultStore: Sendable {
    public let reader: any DatabaseReader
    public let writer: any DatabaseWriter

    /// The database file URL, or nil for in-memory databases.
    public let fileURL: URL?

    // MARK: - Construction

    /// Internal designated initializer shared by file-backed and in-memory
    /// construction (migrations are applied by the callers).
    private init(reader: any DatabaseReader, writer: any DatabaseWriter, fileURL: URL?) {
        self.reader = reader
        self.writer = writer
        self.fileURL = fileURL
    }

    /// Open (creating if needed) the vault at `url`, applying migrations.
    ///
    /// On Apple platforms the database file (and its WAL sidecars) are
    /// marked `isExcludedFromBackup` — the vault is private to the device
    /// and restores go through the explicit export/flow in issue #6, not
    /// through iCloud device backups.
    public init(url: URL) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: config)
        self.reader = pool
        self.writer = pool
        self.fileURL = url
        try GiftVaultSchema.migrator.migrate(pool)
        Self.excludeFromBackup(at: url)
    }

    /// An isolated in-memory database for tests (same migrations applied).
    public static func inMemory() throws -> GiftVaultStore {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        let store = GiftVaultStore(reader: queue, writer: queue, fileURL: nil)
        try GiftVaultSchema.migrator.migrate(queue)
        return store
    }

    /// Migrate an already-open GRDB writer (used by fixtures on test DBs).
    public func migrate() throws {
        try GiftVaultSchema.migrator.migrate(writer)
    }

    /// The applied schema versions, oldest first.
    public func appliedMigrations() throws -> [String] {
        try reader.read { try GiftVaultSchema.migrator.appliedMigrations($0) }
    }

    // MARK: - Backup exclusion (Apple platforms)

    #if canImport(Darwin)
    private static func excludeFromBackup(at url: URL) {
        // SQLite writes `vault`, `vault-wal`, and `vault-shm` next to each
        // other; mark each existing path excluded from Time Machine /
        // iCloud backup so private gift data never leaves the device
        // implicitly. Failures are non-fatal: the app keeps working, the
        // file just isn't hidden from backups.
        let sidecarSuffixes = ["", "-wal", "-shm"]
        let directory = url.deletingLastPathComponent()
        let base = url.lastPathComponent
        for suffix in sidecarSuffixes {
            var candidate = directory.appendingPathComponent(base + suffix)
            guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? candidate.setResourceValues(values)
        }
    }
    #else
    private static func excludeFromBackup(at url: URL) {
        // No iCloud backup concept on Linux; nothing to do.
    }
    #endif

    // MARK: - People

    @discardableResult
    public func savePerson(_ person: Person) throws -> Person {
        try writer.write { db in
            try PersonRecord(person).save(db)
            return person
        }
    }

    public func person(id: UUID) throws -> Person? {
        try reader.read { db in
            try PersonRecord.fetchOne(db, id: id)?.toDomain()
        }
    }

    /// All people, sorted by name (case-insensitive), then id for stability.
    public func allPeople() throws -> [Person] {
        try reader.read { db in
            try PersonRecord
                .order(SQL("name COLLATE NOCASE ASC"), Column("id"))
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func deletePerson(id: UUID) throws {
        // FK cascades remove that person's ideas, slots, and ledger rows.
        _ = try writer.write { db in try PersonRecord.deleteOne(db, id: id) }
    }

    // MARK: - Ideas

    @discardableResult
    public func saveIdea(_ idea: GiftIdea) throws -> GiftIdea {
        try writer.write { db in
            guard try PersonRecord.fetchOne(db, id: idea.personID) != nil else {
                throw GiftVaultStoreError.notFound(entity: "person", id: idea.personID)
            }
            try GiftIdeaRecord(idea).save(db)
            return idea
        }
    }

    public func idea(id: UUID) throws -> GiftIdea? {
        try reader.read { db in
            try GiftIdeaRecord.fetchOne(db, id: id)?.toDomain()
        }
    }

    /// A person's ideas, oldest first, then by id for determinism.
    public func ideas(forPerson id: UUID) throws -> [GiftIdea] {
        try reader.read { db in
            try GiftIdeaRecord
                .filter(Column("person_id") == id)
                .order(
                    Column("created_year"), Column("created_month"),
                    Column("created_day"), Column("id")
                )
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func allIdeas() throws -> [GiftIdea] {
        try reader.read { db in
            try GiftIdeaRecord
                .order(
                    Column("created_year"), Column("created_month"),
                    Column("created_day"), Column("id")
                )
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func deleteIdea(id: UUID) throws {
        _ = try writer.write { db in try GiftIdeaRecord.deleteOne(db, id: id) }
    }

    // MARK: - Occasions

    @discardableResult
    public func saveOccasion(_ occasion: Occasion) throws -> Occasion {
        try writer.write { db in
            try OccasionRecord(occasion).save(db)
            return occasion
        }
    }

    public func occasion(id: UUID) throws -> Occasion? {
        try reader.read { db in
            try OccasionRecord.fetchOne(db, id: id)?.toDomain()
        }
    }

    /// All occasions; dated ones first in chronological order, undated by
    /// name last.
    public func allOccasions() throws -> [Occasion] {
        try reader.read { db in
            try OccasionRecord
                .order(
                    SQL("date_year IS NULL ASC"),
                    Column("date_year"), Column("date_month"), Column("date_day"),
                    SQL("name COLLATE NOCASE ASC"), Column("id")
                )
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func deleteOccasion(id: UUID) throws {
        _ = try writer.write { db in try OccasionRecord.deleteOne(db, id: id) }
    }

    // MARK: - Occasion slots

    /// Insert or update a slot wholesale. Direct saves must not skip the
    /// state machine for status changes on an existing slot; use
    /// `advanceSlot` for that. Saving a brand-new slot with any status is
    /// allowed (fixtures import historical data), and the budget contract
    /// is enforced here with a typed error before the CHECK constraint.
    @discardableResult
    public func saveSlot(_ slot: OccasionSlot) throws -> OccasionSlot {
        try writer.write { db in
            guard (0...GiftVaultLimits.maximumBudgetMinorUnitsPerPerson).contains(slot.budgetCents) else {
                throw GiftVaultStoreError.budgetOutOfRange(slot.budgetCents)
            }
            guard try PersonRecord.fetchOne(db, id: slot.personID) != nil else {
                throw GiftVaultStoreError.notFound(entity: "person", id: slot.personID)
            }
            guard try OccasionRecord.fetchOne(db, id: slot.occasionID) != nil else {
                throw GiftVaultStoreError.notFound(entity: "occasion", id: slot.occasionID)
            }
            try OccasionSlotRecord(slot).save(db)
            return slot
        }
    }

    public func slot(id: UUID) throws -> OccasionSlot? {
        try reader.read { db in
            try OccasionSlotRecord.fetchOne(db, id: id)?.toDomain()
        }
    }

    /// The slots of one occasion, ordered by person name (case-insensitive)
    /// for the board, with id as the stable tiebreaker.
    public func slots(forOccasion occasionID: UUID) throws -> [OccasionSlot] {
        try reader.read { db in
            let records = try OccasionSlotRecord
                .filter(Column("occasion_id") == occasionID)
                .fetchAll(db)
            let people = try PersonRecord
                .fetchAll(db)
                .reduce(into: [UUID: String]()) { names, person in
                    names[person.id] = person.name
                }
            return try records
                .sorted { lhs, rhs in
                    let lhsName = (people[lhs.personId] ?? "").lowercased()
                    let rhsName = (people[rhs.personId] ?? "").lowercased()
                    if lhsName != rhsName { return lhsName < rhsName }
                    return lhs.id < rhs.id
                }
                .map { try $0.toDomain() }
        }
    }

    public func deleteSlot(id: UUID) throws {
        _ = try writer.write { db in try OccasionSlotRecord.deleteOne(db, id: id) }
    }

    // MARK: - State-machine transitions (atomic with ledger side effects)

    /// Advance a slot to `target` through the issue #2 state machine.
    ///
    /// Inside ONE transaction: load → validate transition (throws
    /// `SlotTransitionError`, rolling the transaction back), optionally set
    /// the chosen idea, persist the new status, and — when the target is
    /// `given` — insert the implied `LedgerEntry` (direction `.given`,
    /// description/value from the chosen idea). Either everything is
    /// stored or nothing is.
    @discardableResult
    public func advanceSlot(
        id: UUID,
        to target: OccasionStatus,
        chosenIdeaID: UUID? = nil,
        givenOn date: CalendarDate
    ) throws -> OccasionSlot {
        try writer.write { db in
            guard let record = try OccasionSlotRecord.fetchOne(db, id: id) else {
                throw GiftVaultStoreError.notFound(entity: "occasion_slot", id: id)
            }
            let current = try record.toDomain()
            let advanced = try current.byTransitioning(to: target, chosenIdeaID: chosenIdeaID)

            var updated = OccasionSlotRecord(advanced)
            // Preserve any chosen idea already stored unless overridden.
            if updated.chosenIdeaId == nil { updated.chosenIdeaId = record.chosenIdeaId }
            try updated.update(db)

            if advanced.status == .given {
                var idea: GiftIdea?
                if let ideaID = advanced.chosenIdeaID,
                   let record = try GiftIdeaRecord.fetchOne(db, id: ideaID) {
                    idea = try record.toDomain()
                }
                if let entry = advanced.givenLedgerEntry(on: date, chosenIdea: idea) {
                    try LedgerEntryRecord(entry).insert(db)
                }
            }
            return advanced
        }
    }

    /// Advance exactly one step (`idea→chosen→bought→wrapped→given`).
    public func advanceSlotOneStep(
        id: UUID,
        chosenIdeaID: UUID? = nil,
        givenOn date: CalendarDate
    ) throws -> OccasionSlot? {
        try writer.write { db in
            guard let record = try OccasionSlotRecord.fetchOne(db, id: id) else {
                throw GiftVaultStoreError.notFound(entity: "occasion_slot", id: id)
            }
            let current = try record.toDomain()
            guard let target = current.status.next else { return nil }
            let advanced = try current.byTransitioning(to: target, chosenIdeaID: chosenIdeaID)
            var updated = OccasionSlotRecord(advanced)
            if updated.chosenIdeaId == nil { updated.chosenIdeaId = record.chosenIdeaId }
            try updated.update(db)
            if advanced.status == .given {
                var idea: GiftIdea?
                if let ideaID = advanced.chosenIdeaID,
                   let record = try GiftIdeaRecord.fetchOne(db, id: ideaID) {
                    idea = try record.toDomain()
                }
                if let entry = advanced.givenLedgerEntry(on: date, chosenIdea: idea) {
                    try LedgerEntryRecord(entry).insert(db)
                }
            }
            return advanced
        }
    }

    // MARK: - Ledger

    @discardableResult
    public func saveLedgerEntry(_ entry: LedgerEntry) throws -> LedgerEntry {
        try writer.write { db in
            guard try PersonRecord.fetchOne(db, id: entry.personID) != nil else {
                throw GiftVaultStoreError.notFound(entity: "person", id: entry.personID)
            }
            try LedgerEntryRecord(entry).save(db)
            return entry
        }
    }

    /// All ledger rows, newest day first, then id for stability.
    public func allLedgerEntries() throws -> [LedgerEntry] {
        try reader.read { db in
            try LedgerEntryRecord
                .order(
                    Column("date_year").desc, Column("date_month").desc,
                    Column("date_day").desc, Column("id").desc
                )
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func ledgerEntries(forPerson id: UUID) throws -> [LedgerEntry] {
        try reader.read { db in
            try LedgerEntryRecord
                .filter(Column("person_id") == id)
                .order(
                    Column("date_year"), Column("date_month"),
                    Column("date_day"), Column("id")
                )
                .fetchAll(db)
                .map { try $0.toDomain() }
        }
    }

    public func deleteLedgerEntry(id: UUID) throws {
        _ = try writer.write { db in try LedgerEntryRecord.deleteOne(db, id: id) }
    }

    // MARK: - Counts (for smoke tests and diagnostics)

    public func recordCounts() throws -> (
        people: Int, ideas: Int, occasions: Int, slots: Int, ledger: Int
    ) {
        try reader.read { db in
            (
                people: try PersonRecord.fetchCount(db),
                ideas: try GiftIdeaRecord.fetchCount(db),
                occasions: try OccasionRecord.fetchCount(db),
                slots: try OccasionSlotRecord.fetchCount(db),
                ledger: try LedgerEntryRecord.fetchCount(db)
            )
        }
    }
}
