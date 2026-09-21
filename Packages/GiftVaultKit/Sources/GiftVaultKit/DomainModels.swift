import Foundation

// Domain value types for the Gift Vault core workflow (issue #2).
// All money is integer cents (`BudgetMinorUnits`, defined in
// GiftVaultContract.swift) — never floating point. Every type here is a
// pure, Codable, Sendable value type so persistence (issue #3) can store
// and restore them verbatim.

// MARK: - Person

/// Someone you buy gifts for or receive gifts from.
public struct Person: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    /// Optional birthday as a pure calendar date (no time-of-day).
    public var birthday: CalendarDate?

    public init(id: UUID = UUID(), name: String, birthday: CalendarDate? = nil) {
        self.id = id
        self.name = name
        self.birthday = birthday
    }
}

// MARK: - GiftIdea

/// A captured idea on someone's wishlist.
public struct GiftIdea: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var personID: UUID
    /// What the idea is, freeform text (also the repeat-match key source).
    public var note: String
    /// Optional price hint in integer cents — never a floating-point amount.
    public var priceHintCents: BudgetMinorUnits?
    /// Optional freeform "where I saw it" text (no URLs, no links by design).
    public var sourceText: String?
    /// Date the idea was captured (calendar day, no time-of-day).
    public var createdOn: CalendarDate

    public init(
        id: UUID = UUID(),
        personID: UUID,
        note: String,
        priceHintCents: BudgetMinorUnits? = nil,
        sourceText: String? = nil,
        createdOn: CalendarDate
    ) {
        self.id = id
        self.personID = personID
        self.note = note
        self.priceHintCents = priceHintCents
        self.sourceText = sourceText
        self.createdOn = createdOn
    }
}

// MARK: - Occasion

/// A gifting occasion (birthday, holiday, wedding…). The date is optional
/// because recurring or fuzzy occasions ("Holiday 2026") may not pin a day.
public struct Occasion: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var name: String
    /// Optional calendar date — never a timestamp.
    public var date: CalendarDate?

    public init(id: UUID = UUID(), name: String, date: CalendarDate? = nil) {
        self.id = id
        self.name = name
        self.date = date
    }
}

// MARK: - OccasionSlot

/// One person's place in one occasion, carrying the budget, the status
/// timeline position, and (once chosen) the selected idea.
public struct OccasionSlot: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var occasionID: UUID
    public var personID: UUID
    /// Per-person budget in integer cents.
    public var budgetCents: BudgetMinorUnits
    public var status: OccasionStatus
    /// The idea selected for this slot, once the status reaches `chosen`.
    public var chosenIdeaID: UUID?

    public init(
        id: UUID = UUID(),
        occasionID: UUID,
        personID: UUID,
        budgetCents: BudgetMinorUnits,
        status: OccasionStatus = .idea,
        chosenIdeaID: UUID? = nil
    ) {
        self.id = id
        self.occasionID = occasionID
        self.personID = personID
        self.budgetCents = budgetCents
        self.status = status
        self.chosenIdeaID = chosenIdeaID
    }
}

// MARK: - LedgerEntry

/// One row of the given/received history.
public struct LedgerEntry: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public var direction: LedgerDirection
    public var date: CalendarDate
    public var personID: UUID
    /// Optional link to the occasion this gift was for.
    public var occasionID: UUID?
    /// Item description, freeform text (normalized for repeat matching).
    public var itemDescription: String
    /// Optional value in integer cents.
    public var valueCents: BudgetMinorUnits?

    public init(
        id: UUID = UUID(),
        direction: LedgerDirection,
        date: CalendarDate,
        personID: UUID,
        occasionID: UUID? = nil,
        itemDescription: String,
        valueCents: BudgetMinorUnits? = nil
    ) {
        self.id = id
        self.direction = direction
        self.date = date
        self.personID = personID
        self.occasionID = occasionID
        self.itemDescription = itemDescription
        self.valueCents = valueCents
    }
}

// MARK: - Budget comparison

/// Outcome of comparing a slot's budget against an idea's price hint.
/// Integer-cent comparison only; exactly-on-budget counts as fitting the
/// budget (`priceHintCents <= budgetCents`).
public enum BudgetComparison: String, Sendable, Hashable, Codable, CaseIterable {
    /// Price hint exists and is at or under the budget.
    case under
    /// Price hint exists and exceeds the budget.
    case over
    /// No price hint recorded.
    case unknownPrice
}

extension OccasionSlot {
    /// Budget vs price-hint comparison for an idea against this slot.
    public func budgetComparison(for idea: GiftIdea) -> BudgetComparison {
        guard let price = idea.priceHintCents else { return .unknownPrice }
        return price <= budgetCents ? .under : .over
    }
}
