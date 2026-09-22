import Foundation
import GiftVaultKit
import GRDB

// Persistence schema and errors for Gift Vault (issue #3).
//
// One GRDB `DatabaseMigrator` owns the schema. Migrations are forward-only:
// `v1` is defined here and any later schema ships as `v2`, `v3`, … appended
// below — never edited in place. Re-running migrations is a no-op.
//
// Money columns (`budget_cents`, `price_hint_cents`, `value_cents`) are
// INTEGER cent counts with CHECK constraints; there is no REAL anywhere.
// Calendar dates are stored as year/month/day INTEGER triples, matching
// `CalendarDate`'s DST-immune day arithmetic (no timestamps anywhere).

public enum GiftVaultStoreError: Error, Equatable, Sendable {
    /// A row with the given id does not exist.
    case notFound(entity: String, id: UUID)
    /// A stored date triple could not be revalidated as a `CalendarDate`.
    case invalidStoredDate(entity: String, id: UUID)
    /// A stored status string is outside the domain vocabulary.
    case invalidStoredStatus(String)
    /// A stored ledger direction is outside the domain vocabulary.
    case invalidStoredDirection(String)
    /// A budget value fell outside the product contract limits.
    case budgetOutOfRange(BudgetMinorUnits)
}

public enum GiftVaultSchema {
    /// A SQL literal `('a', 'b', …)` for CHECK constraints (values here are
    /// fixed, app-controlled enum raw values — not user input).
    static func sqlStringList(_ values: [String]) -> String {
        values.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }
            .joined(separator: ", ")
    }

    /// The latest schema version applied by `migrator`.
    public static let currentVersion = "v1"

    /// Forward-only migrator. New schema changes register additional
    /// migrations *after* `v1`; `v1` itself is frozen.
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "person") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("birthday_year", .integer)
                t.column("birthday_month", .integer)
                t.column("birthday_day", .integer)
            }

            try db.create(table: "occasion") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("date_year", .integer)
                t.column("date_month", .integer)
                t.column("date_day", .integer)
            }

            try db.create(table: "gift_idea") { t in
                t.column("id", .text).primaryKey()
                t.column("person_id", .text).notNull()
                    .indexed()
                    .references("person", onDelete: .cascade)
                t.column("note", .text).notNull()
                t.column("price_hint_cents", .integer)
                t.column("source_text", .text)
                t.column("created_year", .integer).notNull()
                t.column("created_month", .integer).notNull()
                t.column("created_day", .integer).notNull()
            }

            try db.create(table: "occasion_slot") { t in
                t.column("id", .text).primaryKey()
                t.column("occasion_id", .text).notNull()
                    .indexed()
                    .references("occasion", onDelete: .cascade)
                t.column("person_id", .text).notNull()
                    .indexed()
                    .references("person", onDelete: .cascade)
                t.column("budget_cents", .integer).notNull()
                    .check(
                        sql: "budget_cents BETWEEN 0 AND \(GiftVaultLimits.maximumBudgetMinorUnitsPerPerson)"
                    )
                t.column("status", .text).notNull()
                    .check(sql: "status IN (\(sqlStringList(OccasionStatus.allCases.map(\.rawValue))))")
                t.column("chosen_idea_id", .text)
                    .references("gift_idea", onDelete: .setNull)
                t.uniqueKey(["occasion_id", "person_id"])
            }

            try db.create(table: "ledger_entry") { t in
                t.column("id", .text).primaryKey()
                t.column("direction", .text).notNull()
                    .check(sql: "direction IN (\(sqlStringList(LedgerDirection.allCases.map(\.rawValue))))")
                t.column("date_year", .integer).notNull()
                t.column("date_month", .integer).notNull()
                t.column("date_day", .integer).notNull()
                t.column("person_id", .text).notNull()
                    .indexed()
                    .references("person", onDelete: .cascade)
                t.column("occasion_id", .text)
                    .indexed()
                    .references("occasion", onDelete: .setNull)
                t.column("item_description", .text).notNull()
                t.column("value_cents", .integer)
            }
        }

        return migrator
    }
}

// MARK: - Record <-> domain mapping

extension PersonRecord {
    init(_ domain: Person) {
        self.init(
            id: domain.id,
            name: domain.name,
            birthdayYear: domain.birthday?.year,
            birthdayMonth: domain.birthday?.month,
            birthdayDay: domain.birthday?.day
        )
    }

    func toDomain() throws -> Person {
        var birthday: CalendarDate?
        if let year = birthdayYear, let month = birthdayMonth, let day = birthdayDay {
            guard let date = CalendarDate(year: year, month: month, day: day) else {
                throw GiftVaultStoreError.invalidStoredDate(entity: "person", id: id)
            }
            birthday = date
        } else if birthdayYear != nil || birthdayMonth != nil || birthdayDay != nil {
            throw GiftVaultStoreError.invalidStoredDate(entity: "person", id: id)
        }
        return Person(id: id, name: name, birthday: birthday)
    }
}

extension GiftIdeaRecord {
    init(_ domain: GiftIdea) {
        self.init(
            id: domain.id,
            personId: domain.personID,
            note: domain.note,
            priceHintCents: domain.priceHintCents,
            sourceText: domain.sourceText,
            createdYear: domain.createdOn.year,
            createdMonth: domain.createdOn.month,
            createdDay: domain.createdOn.day
        )
    }

    func toDomain() throws -> GiftIdea {
        guard let createdOn = CalendarDate(
            year: createdYear, month: createdMonth, day: createdDay
        ) else {
            throw GiftVaultStoreError.invalidStoredDate(entity: "gift_idea", id: id)
        }
        return GiftIdea(
            id: id,
            personID: personId,
            note: note,
            priceHintCents: priceHintCents,
            sourceText: sourceText,
            createdOn: createdOn
        )
    }
}

extension OccasionRecord {
    init(_ domain: Occasion) {
        self.init(
            id: domain.id,
            name: domain.name,
            dateYear: domain.date?.year,
            dateMonth: domain.date?.month,
            dateDay: domain.date?.day
        )
    }

    func toDomain() throws -> Occasion {
        var date: CalendarDate?
        if let year = dateYear, let month = dateMonth, let day = dateDay {
            guard let parsed = CalendarDate(year: year, month: month, day: day) else {
                throw GiftVaultStoreError.invalidStoredDate(entity: "occasion", id: id)
            }
            date = parsed
        } else if dateYear != nil || dateMonth != nil || dateDay != nil {
            throw GiftVaultStoreError.invalidStoredDate(entity: "occasion", id: id)
        }
        return Occasion(id: id, name: name, date: date)
    }
}

extension OccasionSlotRecord {
    init(_ domain: OccasionSlot) {
        self.init(
            id: domain.id,
            occasionId: domain.occasionID,
            personId: domain.personID,
            budgetCents: domain.budgetCents,
            status: domain.status.rawValue,
            chosenIdeaId: domain.chosenIdeaID
        )
    }

    func toDomain() throws -> OccasionSlot {
        guard let status = OccasionStatus(rawValue: status) else {
            throw GiftVaultStoreError.invalidStoredStatus(status)
        }
        return OccasionSlot(
            id: id,
            occasionID: occasionId,
            personID: personId,
            budgetCents: budgetCents,
            status: status,
            chosenIdeaID: chosenIdeaId
        )
    }
}

extension LedgerEntryRecord {
    init(_ domain: LedgerEntry) {
        self.init(
            id: domain.id,
            direction: domain.direction.rawValue,
            dateYear: domain.date.year,
            dateMonth: domain.date.month,
            dateDay: domain.date.day,
            personId: domain.personID,
            occasionId: domain.occasionID,
            itemDescription: domain.itemDescription,
            valueCents: domain.valueCents
        )
    }

    func toDomain() throws -> LedgerEntry {
        guard let direction = LedgerDirection(rawValue: direction) else {
            throw GiftVaultStoreError.invalidStoredDirection(direction)
        }
        guard let date = CalendarDate(year: dateYear, month: dateMonth, day: dateDay) else {
            throw GiftVaultStoreError.invalidStoredDate(entity: "ledger_entry", id: id)
        }
        return LedgerEntry(
            id: id,
            direction: direction,
            date: date,
            personID: personId,
            occasionID: occasionId,
            itemDescription: itemDescription,
            valueCents: valueCents
        )
    }
}
