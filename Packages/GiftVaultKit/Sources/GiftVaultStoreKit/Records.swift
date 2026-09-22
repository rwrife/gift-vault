import Foundation
import GRDB

// GRDB record types mirroring the `v1` schema columns (issue #3).
//
// These are storage shapes, not domain models: each declares explicit
// `CodingKeys` matching the snake_case column names and converts to/from
// the public domain types from `GiftVaultKit` (see AppSchema.swift).
// The app and UI layers only ever see the domain types.

struct PersonRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "person"

    var id: UUID
    var name: String
    var birthdayYear: Int?
    var birthdayMonth: Int?
    var birthdayDay: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case birthdayYear = "birthday_year"
        case birthdayMonth = "birthday_month"
        case birthdayDay = "birthday_day"
    }
}

struct GiftIdeaRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "gift_idea"

    var id: UUID
    var personId: UUID
    var note: String
    var priceHintCents: Int64?
    var sourceText: String?
    var createdYear: Int
    var createdMonth: Int
    var createdDay: Int

    enum CodingKeys: String, CodingKey {
        case id
        case personId = "person_id"
        case note
        case priceHintCents = "price_hint_cents"
        case sourceText = "source_text"
        case createdYear = "created_year"
        case createdMonth = "created_month"
        case createdDay = "created_day"
    }
}

struct OccasionRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "occasion"

    var id: UUID
    var name: String
    var dateYear: Int?
    var dateMonth: Int?
    var dateDay: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case dateYear = "date_year"
        case dateMonth = "date_month"
        case dateDay = "date_day"
    }
}

struct OccasionSlotRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "occasion_slot"

    var id: UUID
    var occasionId: UUID
    var personId: UUID
    var budgetCents: Int64
    var status: String
    var chosenIdeaId: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case occasionId = "occasion_id"
        case personId = "person_id"
        case budgetCents = "budget_cents"
        case status
        case chosenIdeaId = "chosen_idea_id"
    }
}

struct LedgerEntryRecord: Codable, FetchableRecord, PersistableRecord, Identifiable {
    static let databaseTableName = "ledger_entry"

    var id: UUID
    var direction: String
    var dateYear: Int
    var dateMonth: Int
    var dateDay: Int
    var personId: UUID
    var occasionId: UUID?
    var itemDescription: String
    var valueCents: Int64?

    enum CodingKeys: String, CodingKey {
        case id
        case direction
        case dateYear = "date_year"
        case dateMonth = "date_month"
        case dateDay = "date_day"
        case personId = "person_id"
        case occasionId = "occasion_id"
        case itemDescription = "item_description"
        case valueCents = "value_cents"
    }
}
