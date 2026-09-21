import Foundation
import Testing
@testable import GiftVaultKit

// Issue #2 domain tests: models, status state machine, integer-cent budget
// math, repeat matching, and DST-safe calendar-date arithmetic.

private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDate {
    guard let date = CalendarDate(year: y, month: m, day: d) else {
        preconditionFailure("invalid test date \(y)-\(m)-\(d)")
    }
    return date
}

// MARK: - CalendarDate validity

@Suite("CalendarDate validity")
struct CalendarDateValidityTests {
    @Test("Common valid dates construct")
    func validDates() {
        #expect(CalendarDate(year: 2026, month: 3, day: 8) != nil)
        #expect(CalendarDate(year: 2024, month: 2, day: 29) != nil)  // leap year
        #expect(CalendarDate(year: 2000, month: 2, day: 29) != nil)  // /400 leap
        #expect(CalendarDate(year: 1900, month: 2, day: 28) != nil)
    }

    @Test("Impossible dates are rejected")
    func invalidDates() {
        #expect(CalendarDate(year: 2026, month: 13, day: 1) == nil)
        #expect(CalendarDate(year: 2026, month: 0, day: 1) == nil)
        #expect(CalendarDate(year: 2026, month: 2, day: 0) == nil)
        #expect(CalendarDate(year: 2026, month: 4, day: 31) == nil)
        #expect(CalendarDate(year: 2026, month: 2, day: 29) == nil)  // 2026 not leap
        #expect(CalendarDate(year: 1900, month: 2, day: 29) == nil)  // century rule
        #expect(CalendarDate(year: 2026, month: 1, day: 32) == nil)
    }

    @Test("Leap-year rule follows Gregorian definition")
    func leapYears() {
        #expect(CalendarDate.isLeapYear(2024))
        #expect(!CalendarDate.isLeapYear(2026))
        #expect(!CalendarDate.isLeapYear(1900))
        #expect(CalendarDate.isLeapYear(2000))
        #expect(CalendarDate.daysInMonth(year: 2024, month: 2) == 29)
        #expect(CalendarDate.daysInMonth(year: 2025, month: 2) == 28)
    }
}

// MARK: - Serial-day arithmetic

@Suite("CalendarDate day arithmetic")
struct CalendarDateArithmeticTests {
    @Test("Epoch anchor and known serial values")
    func anchors() {
        #expect(day(1970, 1, 1).serialDayNumber == 0)
        #expect(day(1970, 1, 2).serialDayNumber == 1)
        #expect(day(1969, 12, 31).serialDayNumber == -1)
        #expect(day(2000, 1, 1).serialDayNumber == 10_957)
    }

    @Test("Serial round-trip across boundaries")
    func serialRoundTrip() {
        let samples = [
            day(1900, 2, 28), day(1900, 3, 1), day(1970, 1, 1), day(1999, 12, 31),
            day(2000, 2, 29), day(2000, 3, 1), day(2024, 2, 29), day(2026, 12, 31),
        ]
        for date in samples {
            #expect(CalendarDate(serialDayNumber: date.serialDayNumber) == date)
        }
    }

    @Test("Adding days crosses month, year, and leap boundaries")
    func addingDays() {
        #expect(day(2026, 2, 28).addingCalendarDays(1) == day(2026, 3, 1))
        #expect(day(2024, 2, 28).addingCalendarDays(1) == day(2024, 2, 29))
        #expect(day(2024, 2, 28).addingCalendarDays(2) == day(2024, 3, 1))
        #expect(day(2026, 12, 31).addingCalendarDays(1) == day(2027, 1, 1))
        #expect(day(2026, 1, 1).addingCalendarDays(-1) == day(2025, 12, 31))
        #expect(day(2026, 3, 1).addingCalendarDays(-1) == day(2026, 2, 28))
    }

    @Test("calendarDays counts local days exactly")
    func dayCounts() {
        #expect(day(2026, 1, 1).calendarDays(until: day(2026, 1, 31)) == 30)
        #expect(day(2026, 3, 8).calendarDays(until: day(2026, 3, 9)) == 1)   // spring-forward day
        #expect(day(2026, 11, 1).calendarDays(until: day(2026, 11, 2)) == 1) // fall-back day
        #expect(day(2026, 3, 9).calendarDays(until: day(2026, 3, 8)) == -1)
    }

    @Test("Ordering follows chronology")
    func ordering() {
        #expect(day(2026, 3, 7) < day(2026, 3, 8))
        #expect(day(2025, 12, 31) < day(2026, 1, 1))
        #expect(!(day(2026, 3, 8) < day(2026, 3, 8)))
    }
}

// MARK: - DST safety

@Suite("CalendarDate DST safety")
struct CalendarDateDSTTests {
    private let newYork = TimeZone(identifier: "America/New_York")!

    @Test("A spring-forward day is 23 elapsed hours but always 1 calendar day")
    func springForward() throws {
        let before = try #require(day(2026, 3, 7).startOfDay(in: newYork))
        let during = try #require(day(2026, 3, 8).startOfDay(in: newYork))
        let after = try #require(day(2026, 3, 9).startOfDay(in: newYork))
        let hoursFirst = during.timeIntervalSince(before) / 3600
        let hoursSecond = after.timeIntervalSince(during) / 3600
        // Elapsed-hour math IS broken by DST — that's the point: never use it.
        #expect(hoursFirst == 24)
        #expect(hoursSecond == 23)
        // Calendar-day math is immune.
        #expect(day(2026, 3, 7).calendarDays(until: day(2026, 3, 8)) == 1)
        #expect(day(2026, 3, 8).calendarDays(until: day(2026, 3, 9)) == 1)
        #expect(day(2026, 3, 7).addingCalendarDays(2) == day(2026, 3, 9))
    }

    @Test("A fall-back day is 25 elapsed hours but always 1 calendar day")
    func fallBack() throws {
        let before = try #require(day(2026, 10, 31).startOfDay(in: newYork))
        let during = try #require(day(2026, 11, 1).startOfDay(in: newYork))
        let after = try #require(day(2026, 11, 2).startOfDay(in: newYork))
        #expect(during.timeIntervalSince(before) / 3600 == 24)
        #expect(after.timeIntervalSince(during) / 3600 == 25)
        #expect(day(2026, 10, 31).calendarDays(until: day(2026, 11, 2)) == 2)
        #expect(day(2026, 11, 1).addingCalendarDays(1) == day(2026, 11, 2))
    }

    @Test("Date-to-calendar-date conversion is time-zone explicit across DST")
    func instantToCalendarDate() throws {
        // 2026-11-01 09:00 UTC is 05:00 EDT — still Nov 1 in New York.
        let fallBackMorning = Date(timeIntervalSince1970: 1_793_523_600)
        #expect(CalendarDate(date: fallBackMorning, timeZone: newYork) == day(2026, 11, 1))
        // 2026-11-02 02:00 UTC is 21:00 EST on Nov 1 in New York…
        let afterMidnightUTC = Date(timeIntervalSince1970: 1_793_584_800)
        #expect(CalendarDate(date: afterMidnightUTC, timeZone: newYork) == day(2026, 11, 1))
        // The same instant observed in UTC is already the next calendar date.
        #expect(CalendarDate(date: afterMidnightUTC, timeZone: TimeZone(identifier: "UTC")!) == day(2026, 11, 2))
    }
}

// MARK: - Status state machine

@Suite("Slot status state machine")
struct SlotStateMachineTests {
    private let person = UUID()
    private let occasion = UUID()
    private let ideaRef = UUID()

    private func slot(status: OccasionStatus = .idea) -> OccasionSlot {
        OccasionSlot(occasionID: occasion, personID: person, budgetCents: 5000,
                     status: status, chosenIdeaID: status == .idea ? nil : ideaRef)
    }

    @Test("The full legal walk idea → chosen → bought → wrapped → given")
    func fullLegalWalk() throws {
        var current = slot()
        current = try current.byTransitioning(to: .chosen, chosenIdeaID: ideaRef)
        #expect(current.status == .chosen)
        #expect(current.chosenIdeaID == ideaRef)
        current = try current.byTransitioning(to: .bought)
        current = try current.byTransitioning(to: .wrapped)
        current = try current.byTransitioning(to: .given)
        #expect(current.status == .given)
    }

    @Test("byAdvancing walks one legal step at a time and stops at given")
    func advancing() throws {
        var current = slot()
        // First step into chosen needs an idea attached beforehand.
        current.chosenIdeaID = ideaRef
        let expected: [OccasionStatus] = [.chosen, .bought, .wrapped, .given]
        for want in expected {
            current = try #require(try current.byAdvancing())
            #expect(current.status == want)
        }
        #expect(try current.byAdvancing() == nil)  // terminal
    }

    @Test("Skipping ahead is illegal")
    func skipsRejected() {
        let legalPairs: Set<[OccasionStatus]> = [
            [.idea, .chosen], [.chosen, .bought], [.bought, .wrapped], [.wrapped, .given],
        ]
        for from in OccasionStatus.allCases {
            for to in OccasionStatus.allCases {
                let legal = legalPairs.contains([from, to])
                #expect(from.canTransition(to: to) == legal)
            }
        }
        #expect(throws: SlotTransitionError.illegal(from: .idea, to: .bought)) {
            try slot().byTransitioning(to: .bought)
        }
        #expect(throws: SlotTransitionError.illegal(from: .idea, to: .given)) {
            try slot().byTransitioning(to: .given)
        }
    }

    @Test("Backward moves are illegal")
    func backwardRejected() {
        #expect(throws: SlotTransitionError.illegal(from: .bought, to: .idea)) {
            try slot(status: .bought).byTransitioning(to: .idea)
        }
        #expect(throws: SlotTransitionError.illegal(from: .wrapped, to: .chosen)) {
            try slot(status: .wrapped).byTransitioning(to: .chosen)
        }
        // From the terminal state the terminal error takes precedence (covered
        // exhaustively in givenIsTerminal).
    }

    @Test("`given` is terminal for every target, including itself")
    func givenIsTerminal() {
        for to in OccasionStatus.allCases {
            #expect(throws: SlotTransitionError.terminal(state: .given)) {
                try slot(status: .given).byTransitioning(to: to)
            }
        }
    }

    @Test("Entering `chosen` requires a selected idea")
    func chosenRequiresIdea() {
        let bare = OccasionSlot(occasionID: occasion, personID: person, budgetCents: 1)
        #expect(throws: SlotTransitionError.chosenWithoutIdea) {
            try bare.byTransitioning(to: .chosen)
        }
        // Providing the idea in the same call is legal.
        var advanced: OccasionSlot?
        #expect(throws: (Never).self) {
            advanced = try bare.byTransitioning(to: .chosen, chosenIdeaID: ideaRef)
        }
        #expect(advanced?.status == .chosen)
    }
}

// MARK: - Given-side ledger implication contract

@Suite("Given-side ledger implication")
struct GivenLedgerContractTests {
    @Test("A given slot implies the given-side ledger row with idea details")
    func implicationShape() throws {
        let person = UUID()
        let occasionID = UUID()
        let idea = GiftIdea(personID: person, note: "Pour-over coffee set",
                            priceHintCents: 4_250, createdOn: day(2026, 1, 5))
        let given = OccasionSlot(occasionID: occasionID, personID: person, budgetCents: 5000,
                                 status: .given, chosenIdeaID: idea.id)
        let implication = try #require(given.givenLedgerImplication(on: day(2026, 12, 25), chosenIdea: idea))
        #expect(implication.direction == .given)
        #expect(implication.personID == person)
        #expect(implication.occasionID == occasionID)
        #expect(implication.itemDescription == "Pour-over coffee set")
        #expect(implication.valueCents == 4_250)

        let entry = try #require(given.givenLedgerEntry(on: day(2026, 12, 25), chosenIdea: idea))
        #expect(entry.direction == .given)
        #expect(entry.date == day(2026, 12, 25))
        #expect(entry.occasionID == occasionID)
    }

    @Test("Slots before `given` imply no ledger row")
    func earlierStatesImplyNothing() {
        let idea = GiftIdea(personID: UUID(), note: "x", createdOn: day(2026, 1, 5))
        for status in [OccasionStatus.idea, .chosen, .bought, .wrapped] {
            let s = OccasionSlot(occasionID: UUID(), personID: UUID(), budgetCents: 100,
                                 status: status, chosenIdeaID: idea.id)
            #expect(s.givenLedgerImplication(on: day(2026, 12, 25), chosenIdea: idea) == nil)
            #expect(s.givenLedgerEntry(on: day(2026, 12, 25), chosenIdea: idea) == nil)
        }
    }

    @Test("Unresolvable idea yields nil description/value in the implication")
    func missingIdeaDetails() throws {
        let given = OccasionSlot(occasionID: UUID(), personID: UUID(), budgetCents: 100,
                                 status: .given, chosenIdeaID: UUID())
        let implication = try #require(given.givenLedgerImplication(on: day(2026, 5, 1), chosenIdea: nil))
        #expect(implication.itemDescription == nil)
        #expect(implication.valueCents == nil)
    }
}

// MARK: - Budget math (integer cents only)

@Suite("Budget math in integer cents")
struct BudgetMathTests {
    private func slot(budget: BudgetMinorUnits) -> OccasionSlot {
        OccasionSlot(occasionID: UUID(), personID: UUID(), budgetCents: budget)
    }

    private func idea(price: BudgetMinorUnits?) -> GiftIdea {
        GiftIdea(personID: UUID(), note: "book", priceHintCents: price, createdOn: day(2026, 1, 1))
    }

    @Test("Under, over, and exactly-on-budget comparison states")
    func comparisonStates() {
        let s = slot(budget: 4_599)
        #expect(s.budgetComparison(for: idea(price: 4_598)) == .under)
        #expect(s.budgetComparison(for: idea(price: 4_599)) == .under)   // exactly on budget fits
        #expect(s.budgetComparison(for: idea(price: 4_600)) == .over)
        #expect(s.budgetComparison(for: idea(price: 0)) == .under)
        #expect(s.budgetComparison(for: idea(price: nil)) == .unknownPrice)
    }

    @Test("Comparison stays exact at the contract ceiling")
    func ceilingExactness() {
        let ceiling = GiftVaultLimits.maximumBudgetMinorUnitsPerPerson
        let s = slot(budget: ceiling)
        #expect(s.budgetComparison(for: idea(price: ceiling)) == .under)
        #expect(s.budgetComparison(for: idea(price: ceiling + 1)) == .over)
    }

    @Test("Money is Int64 cents end to end")
    func moneyIsIntegerCents() {
        let idea = GiftIdea(personID: UUID(), note: "n", priceHintCents: 123_456,
                            createdOn: day(2026, 1, 1))
        let entry = LedgerEntry(direction: .received, date: day(2026, 1, 2),
                                personID: UUID(), itemDescription: "scarf", valueCents: 2_500)
        let slotValue: BudgetMinorUnits = OccasionSlot(occasionID: UUID(), personID: UUID(),
                                                       budgetCents: 10_000).budgetCents
        #expect(type(of: idea.priceHintCents!) == BudgetMinorUnits.self)
        #expect(type(of: entry.valueCents!) == BudgetMinorUnits.self)
        #expect(type(of: slotValue) == BudgetMinorUnits.self)
        // No floating-point literal ever touches a money field.
        #expect(idea.priceHintCents == 123_456)
    }
}

// MARK: - Repeat matching

@Suite("Repeat matching")
struct RepeatMatchingTests {
    private func entry(_ person: UUID, _ description: String, direction: LedgerDirection = .given) -> LedgerEntry {
        LedgerEntry(direction: direction, date: day(2025, 12, 25), personID: person,
                    itemDescription: description)
    }

    @Test("Normalization is case, whitespace, and punctuation insensitive")
    func normalization() {
        #expect(DescriptionNormalizer.normalized("Pour-over Coffee, 12oz!")
                == DescriptionNormalizer.normalized("  pour  OVER coffee12oz. "))
        #expect(DescriptionNormalizer.normalized("!!!") == "")
        #expect(DescriptionNormalizer.normalized("") == "")
        #expect(DescriptionNormalizer.normalized("book #1") == "book1")
    }

    @Test("Matching finds prior given entries for the right person only")
    func matching() {
        let alex = UUID()
        let sam = UUID()
        let ledger = [
            entry(alex, "Book #1"),
            entry(alex, "book 1", direction: .received),     // wrong direction
            entry(sam, "Book #1"),                            // wrong person
            entry(alex, "Cookbook"),                          // different item
            entry(alex, "  BOOK1!!!"),
        ]
        let matches = RepeatMatcher.matches(candidateDescription: "book one", personID: alex, in: ledger)
        #expect(matches.isEmpty)  // "book one" != "book1"
        let hits = RepeatMatcher.matches(candidateDescription: "Book#1", personID: alex, in: ledger)
        #expect(hits.count == 2)
        #expect(hits.map(\.itemDescription) == ["Book #1", "  BOOK1!!!"])  // input order preserved
    }

    @Test("Empty or normalization-empty candidates match nothing")
    func emptyCandidates() {
        let alex = UUID()
        let ledger = [entry(alex, ""), entry(alex, "???"), entry(alex, "mug")]
        #expect(RepeatMatcher.matches(candidateDescription: "", personID: alex, in: ledger).isEmpty)
        #expect(RepeatMatcher.matches(candidateDescription: "!!!", personID: alex, in: ledger).isEmpty)
        // An empty-description entry is likewise never matched by a real candidate.
        #expect(RepeatMatcher.matches(candidateDescription: "mug", personID: alex, in: ledger)
                .map(\.itemDescription) == ["mug"])
    }
}

// MARK: - Codable round-trips (contract with issue #3 persistence)

@Suite("Domain Codable round-trips")
struct DomainCodableTests {
    @Test("Every domain value type survives JSON round-trip")
    func roundTrip() throws {
        let person = Person(name: "Alex", birthday: day(1990, 3, 8))
        let idea = GiftIdea(personID: person.id, note: "vinyl", priceHintCents: 2_999,
                            sourceText: "record fair", createdOn: day(2026, 2, 1))
        let occasion = Occasion(name: "Birthday", date: day(2026, 3, 8))
        let slot = OccasionSlot(occasionID: occasion.id, personID: person.id, budgetCents: 5_000,
                                status: .chosen, chosenIdeaID: idea.id)
        let entry = LedgerEntry(direction: .given, date: day(2026, 3, 8), personID: person.id,
                                occasionID: occasion.id, itemDescription: "vinyl", valueCents: 2_999)

        let decoder = JSONDecoder()
        func roundTrip<T: Codable & Equatable>(_ value: T) throws {
            let data = try JSONEncoder().encode(value)
            #expect(try decoder.decode(T.self, from: data) == value)
        }
        try roundTrip(person)
        try roundTrip(idea)
        try roundTrip(occasion)
        try roundTrip(slot)
        try roundTrip(entry)
    }
}
