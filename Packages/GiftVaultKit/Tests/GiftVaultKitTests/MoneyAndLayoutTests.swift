import Foundation
import Testing
@testable import GiftVaultKit

// Issue #4: money display/parsing and the layout seam, pure Swift and
// Linux-testable. Money is integer cents end to end — these tests pin
// the exact-cent behavior the UI depends on ("no floating-point
// artifacts" acceptance criterion).

// MARK: - MoneyFormatting

@Suite("Money formatting")
struct MoneyFormattingTests {
    @Test("Decimal strings are exact cent forms")
    func decimalStrings() {
        #expect(MoneyFormatting.decimalString(0) == "0.00")
        #expect(MoneyFormatting.decimalString(1) == "0.01")
        #expect(MoneyFormatting.decimalString(10) == "0.10")
        #expect(MoneyFormatting.decimalString(100) == "1.00")
        #expect(MoneyFormatting.decimalString(123456) == "1234.56")
        #expect(MoneyFormatting.decimalString(-2500) == "-25.00")
        // Int64.min must not trap (abs-overflow trap avoided via UInt64).
        #expect(MoneyFormatting.decimalString(Int64.min) == "-92233720368547758.08")
        #expect(MoneyFormatting.usdString(4500) == "$45.00")
    }

    @Test("No binary-float artifacts at awkward decimal values")
    func exactDecimals() {
        // 0.1 + 0.2 would be 0.30000000000000004 in Double.
        #expect(MoneyFormatting.decimalString(10 + 20) == "0.30")
        #expect(MoneyFormatting.decimalString(8900) == "89.00")
        #expect(MoneyFormatting.decimalString(5_000_000) == "50000.00")
    }
}

// MARK: - MoneyParsing

@Suite("Money parsing")
struct MoneyParsingTests {
    @Test("Plain amounts parse to exact cents")
    func plainAmounts() {
        #expect(MoneyParsing.parseCents("0") == 0)
        #expect(MoneyParsing.parseCents("40") == 4000)
        #expect(MoneyParsing.parseCents("40.00") == 4000)
        #expect(MoneyParsing.parseCents("0.05") == 5)
        #expect(MoneyParsing.parseCents("3.5") == 350)
        #expect(MoneyParsing.parseCents("  12.34 ") == 1234)
        #expect(MoneyParsing.parseCents("-3.50") == -350)
        #expect(MoneyParsing.parseCents(".99") == 99)
    }

    @Test("Rejects everything outside the accepted shape")
    func rejections() {
        #expect(MoneyParsing.parseCents("") == nil)
        #expect(MoneyParsing.parseCents("   ") == nil)
        #expect(MoneyParsing.parseCents("abc") == nil)
        #expect(MoneyParsing.parseCents("1,234") == nil)       // separators
        #expect(MoneyParsing.parseCents("1.234") == nil)       // 3 fraction digits
        #expect(MoneyParsing.parseCents("1e3") == nil)         // scientific
        #expect(MoneyParsing.parseCents("12.") == nil)         // trailing dot
        #expect(MoneyParsing.parseCents(".") == nil)
        #expect(MoneyParsing.parseCents("-") == nil)
        #expect(MoneyParsing.parseCents("1.2.3") == nil)
        #expect(MoneyParsing.parseCents("12 34") == nil)
        #expect(MoneyParsing.parseCents("$5") == nil)
    }

    @Test("Overflow past Int64 returns nil")
    func overflow() {
        #expect(MoneyParsing.parseCents("92233720368547758.07") == 9_223_372_036_854_775_807)
        #expect(MoneyParsing.parseCents("92233720368547758.08") == nil)
        #expect(MoneyParsing.parseCents("99999999999999999999") == nil)
    }

    @Test("Round-trip: parse(format(x)) == x for the product range")
    func roundTrip() {
        for cents in [0, 1, 99, 100, 3_100, 4_500, 12_000, 100_000_000] {
            #expect(MoneyParsing.parseCents(MoneyFormatting.decimalString(BudgetMinorUnits(cents))) == BudgetMinorUnits(cents))
        }
    }
}

// MARK: - GiftWorkspaceLayout

@Suite("GiftWorkspaceLayout seam")
struct GiftWorkspaceLayoutTests {
    @Test("The seam is single-pane and there is no dual-pane mode today")
    func singlePaneToday() {
        #expect(GiftWorkspaceLayout.supportsDualPane == false)
        // Even a proposed split resolves to single.
        let mode = GiftWorkspaceLayout.screenMode(focused: .people, secondary: .occasions)
        #expect(mode == .single(.people))
        #expect(GiftWorkspaceLayout.screenMode(focused: nil, secondary: nil) == .single(.people))
    }

    @Test("Status control offers exactly the state machine's next step")
    func statusControlOffersOnlyNext() throws {
        let person = Person(name: "Test")
        let occasion = Occasion(name: "Test")
        func slot(_ status: OccasionStatus) -> OccasionSlot {
            OccasionSlot(occasionID: occasion.id, personID: person.id, budgetCents: 100, status: status)
        }
        #expect(GiftWorkspaceLayout.statusControl(for: slot(.idea)) == .advance(to: .chosen))
        #expect(GiftWorkspaceLayout.statusControl(for: slot(.chosen)) == .advance(to: .bought))
        #expect(GiftWorkspaceLayout.statusControl(for: slot(.bought)) == .advance(to: .wrapped))
        #expect(GiftWorkspaceLayout.statusControl(for: slot(.wrapped)) == .advance(to: .given))
        #expect(GiftWorkspaceLayout.statusControl(for: slot(.given)) == .none)
    }
}

// MARK: - Display vocabulary

@Suite("Display vocabulary")
struct DisplayVocabularyTests {
    @Test("Budget comparisons carry UI labels")
    func comparisonLabels() {
        #expect(BudgetComparison.under.label == "Within budget")
        #expect(BudgetComparison.over.label == "Over budget")
        #expect(BudgetComparison.unknownPrice.label == "No price hint")
    }

    @Test("Status and direction display names")
    func displayNames() {
        #expect(OccasionStatus.idea.displayName == "Idea")
        #expect(OccasionStatus.wrapped.displayName == "Wrapped")
        #expect(OccasionStatus.given.displayName == "Given")
        #expect(LedgerDirection.given.displayName == "Given")
        #expect(LedgerDirection.received.displayName == "Received")
    }
}
