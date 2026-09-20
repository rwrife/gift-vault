import Foundation
import Testing
@testable import GiftVaultKit

@Suite("Issue 1 domain contract")
struct GiftVaultContractTests {
    @Test("Published MVP bounds remain coherent")
    func limitsAreCoherent() {
        #expect(GiftVaultLimits.maximumPeople == 30)
        #expect(GiftVaultLimits.maximumIdeasPerPerson == 200)
        #expect(GiftVaultLimits.maximumBudgetMinorUnitsPerPerson == 100_000_000)
        #expect(GiftVaultLimits.maximumBudgetMinorUnitsPerPerson > 0)
    }

    @Test("Budget minor units are an integer-cent contract")
    func budgetIsIntegerCents() {
        let budget: BudgetMinorUnits = 4_599  // $45.99 expressed in cents
        #expect(type(of: budget) == Int64.self)
        #expect(budget == 4_599)
    }

    @Test("The status pipeline has exactly the published five states in order")
    func statusPipelineMatchesPlan() {
        #expect(OccasionStatus.pipeline == [.idea, .chosen, .bought, .wrapped, .given])
    }

    @Test("The status vocabulary has no duplicates")
    func statusVocabularyIsBounded() {
        #expect(Set(OccasionStatus.allCases).count == 5)
    }

    @Test("Ledger directions are exactly given and received")
    func ledgerDirectionVocabularyIsBounded() {
        #expect(Set(LedgerDirection.allCases.map(\.rawValue)) == ["given", "received"])
    }
}
