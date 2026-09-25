#if canImport(Combine)

import Foundation
import Testing
@testable import GiftVaultKit
@testable import GiftVaultStoreKit

// Issue #4: the app model wraps the store for the SwiftUI screens.
// Combine exists only on Apple platforms, so these run where the model
// is compiled (Linux CI skips them; the Apple CI `domain_tests` phase
// runs them before the app build).

@MainActor
@Suite("GiftVaultAppModel")
struct GiftVaultAppModelTests {
    private func makeModel() throws -> GiftVaultAppModel {
        GiftVaultAppModel(store: try GiftVaultStore.inMemory(),
                          today: CalendarDate(year: 2026, month: 9, day: 23)!)
    }

    @Test("Golden path through the model: person → idea → occasion → choose → given → ledger")
    func goldenPath() throws {
        let model = try makeModel()
        model.savePerson(name: "Nova")
        #expect(model.people.count == 1)
        let nova = try #require(model.people.first)

        model.saveIdea(personID: nova.id, note: "Trail daypack", priceHintText: "45.00", sourceText: nil)
        model.openIdeas(personID: nova.id)
        let idea = try #require(model.ideas.first)
        #expect(idea.priceHintCents == 4500)

        model.saveOccasion(name: "Nova quiz", date: nil, budgetText: "50.00", attachedPersonIDs: [nova.id])
        #expect(model.occasions.count == 1)
        let occasion = try #require(model.occasions.first)
        model.openBoard(occasionID: occasion.id)
        let entry = try #require(model.board.first)
        #expect(entry.slot.status == .idea)
        // 4500 <= 5000 → under budget (integer comparison).
        #expect(entry.comparison(for: idea) == .under)
        // No prior given history for the idea note.
        #expect(model.repeatMatches(idea: idea, in: entry).isEmpty)

        // Walk the machine: idea → chosen (via chooser), then three steps.
        model.chooseIdea(idea: idea, in: entry)
        #expect(model.board.first?.slot.status == .chosen)
        model.advance(try #require(model.board.first))
        #expect(model.board.first?.slot.status == .bought)
        model.advance(try #require(model.board.first))
        #expect(model.board.first?.slot.status == .wrapped)
        model.advance(try #require(model.board.first))
        #expect(model.board.first?.slot.status == .given)
        #expect(model.lastError == nil)

        // The given transition wrote the implied ledger row.
        #expect(model.ledger.count == 1)
        let row = try #require(model.ledger.first)
        #expect(row.direction == .given)
        #expect(row.personID == nova.id)
        #expect(row.itemDescription == "Trail daypack")
        #expect(row.valueCents == 4500)
    }

    @Test("Terminal slots offer no further control and record an error if forced")
    func terminalControl() throws {
        let model = try makeModel()
        try GiftVaultFixtures.seed(into: model.store)
        model.reloadAll()
        model.openBoard(occasionID: GiftVaultFixtures.occasionID)
        let givenEntry = try #require(
            model.board.first { $0.slot.status == .given }
        )
        #expect(GiftWorkspaceLayout.statusControl(for: givenEntry.slot) == .none)
        model.advance(givenEntry)
        #expect(model.lastError != nil)
    }

    @Test("Choosing requires an idea; choosing surfaces repeats from history")
    func chooseGuardsAndRepeatCheck() throws {
        let model = try makeModel()
        try GiftVaultFixtures.seed(into: model.store)
        model.reloadAll()
        model.openBoard(occasionID: GiftVaultFixtures.occasionID)
        let avaEntry = try #require(
            model.board.first { $0.person.id == GiftVaultFixtures.personAvaID }
        )
        // idea-status slot with no chosen idea: advancing to chosen fails cleanly.
        model.advance(avaEntry)
        #expect(model.lastError != nil)
        #expect(avaEntry.slot.status == .idea)

        // Dana's given history contains the desk lamp idea → repeat match.
        let danaEntry = try #require(
            model.board.first { $0.person.id == GiftVaultFixtures.personDanaID }
        )
        let lampIdea = try #require(danaEntry.ideas.first)
        let repeats = model.repeatMatches(idea: lampIdea, in: danaEntry)
        #expect(repeats.count == 1)
    }

    @Test("Bad money and empty names are rejected with errors, not crashes")
    func validationErrors() throws {
        let model = try makeModel()
        model.savePerson(name: "   ")
        #expect(model.lastError != nil)
        #expect(model.people.isEmpty)

        model.savePerson(name: "Ok")
        let person = try #require(model.people.first)
        model.saveIdea(personID: person.id, note: "Thing", priceHintText: "12.345", sourceText: nil)
        #expect(model.lastError != nil)
        model.openIdeas(personID: person.id)
        #expect(model.ideas.isEmpty)
    }
}

#endif
