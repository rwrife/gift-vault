import Foundation
import GiftVaultKit

// The observable app model for the core workflow UI (issue #4).
//
// This is the only mutable UI-facing state in the app. It wraps the
// issue #3 store: every mutation goes through a store method (so the
// state machine and ledger side effects stay in the domain/persistence
// layers), then re-loads the snapshots it owns. It never reads clocks
// for domain facts — `today` is supplied by the caller — and never
// touches the network.
//
// Lives in the package (not App/) so its logic is compile-checked in CI
// everywhere it can be; SwiftUI itself only exists on Apple platforms,
// so the SwiftUI screens stay under App/ and consume this model.

#if canImport(Combine)
import Combine

@MainActor
public final class GiftVaultAppModel: ObservableObject {
    // MARK: Snapshots (single source of truth for the screens)

    @Published public private(set) var people: [Person] = []
    @Published public private(set) var occasions: [Occasion] = []
    @Published public private(set) var ledger: [LedgerEntry] = []
    /// Slots of the occasion currently open on the board, with their
    /// ideas pre-resolved for budget comparison.
    @Published public private(set) var board: [BoardSlot] = []
    /// Ideas of the person currently open on the idea list.
    @Published public private(set) var ideas: [GiftIdea] = []

    /// Last user-facing error message (nil = none). Set on failed
    /// mutations; screens present it as an alert.
    @Published public var lastError: String?

    /// The store the model drives. Exposed read-only-ish for tests and
    /// for the store's own in-memory construction.
    public let store: GiftVaultStore

    /// Today's calendar date supplied by the host app (the store never
    /// reads clocks; neither does the model — issue #2 contract).
    public let today: CalendarDate

    public struct BoardSlot: Identifiable, Sendable, Hashable {
        public let slot: OccasionSlot
        public let person: Person
        /// Ideas belonging to this slot's person, newest board order.
        public let ideas: [GiftIdea]
        /// The chosen idea, once the slot has one.
        public let chosenIdea: GiftIdea?

        public var id: UUID { slot.id }

        /// Budget vs chosen-idea (or any candidate) comparison helper.
        public func comparison(for idea: GiftIdea) -> BudgetComparison {
            slot.budgetComparison(for: idea)
        }
    }

    public init(store: GiftVaultStore, today: CalendarDate, appVersion: String = "0.1.0") {
        self.store = store
        self.today = today
        self.appVersion = appVersion
        reloadAll()
    }

    /// In-memory model seeded with the deterministic fixtures (previews
    /// and UI-test launches).
    public static func fixtures(today: CalendarDate, appVersion: String = "0.1.0") throws -> GiftVaultAppModel {
        let store = try GiftVaultStore.inMemory()
        try GiftVaultFixtures.seed(into: store)
        return GiftVaultAppModel(store: store, today: today, appVersion: appVersion)
    }

    // MARK: - Loading

    public func reloadAll() {
        reloadPeople()
        reloadOccasions()
        reloadLedger()
    }

    public func reloadPeople() {
        people = (try? store.allPeople()) ?? []
    }

    public func reloadOccasions() {
        occasions = (try? store.allOccasions()) ?? []
    }

    public func reloadLedger() {
        ledger = (try? store.allLedgerEntries()) ?? []
    }

    public func openBoard(occasionID: UUID) {
        let slots = ((try? store.slots(forOccasion: occasionID)) ?? [])
        let allIdeas = ((try? store.allIdeas()) ?? [])
        let byPerson = Dictionary(grouping: allIdeas, by: \.personID)
        board = slots.compactMap { slot in
            guard let person = ((try? store.person(id: slot.personID)) ?? nil) else { return nil }
            return BoardSlot(
                slot: slot,
                person: person,
                ideas: byPerson[slot.personID] ?? [],
                chosenIdea: (slot.chosenIdeaID.flatMap { id in try? store.idea(id: id) }) ?? nil
            )
        }
    }

    public func openIdeas(personID: UUID) {
        ideas = (try? store.ideas(forPerson: personID)) ?? []
    }

    // MARK: - People

    /// Add or update a person (name required; blank names rejected here
    /// so the sheet can surface it).
    public func savePerson(name: String, birthday: CalendarDate? = nil, id: UUID? = nil) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Person name cannot be empty."
            return
        }
        guard people.count < GiftVaultLimits.maximumPeople || id != nil else {
            lastError = "This vault holds at most \(GiftVaultLimits.maximumPeople) people."
            return
        }
        let person = Person(id: id ?? UUID(), name: trimmed, birthday: birthday)
        do {
            try store.savePerson(person)
            lastError = nil
            reloadPeople()
        } catch {
            lastError = "Could not save \(trimmed): \(error)"
        }
    }

    public func deletePerson(id: UUID) {
        do {
            try store.deletePerson(id: id)
            reloadAll()
        } catch {
            lastError = "Could not delete person: \(error)"
        }
    }

    // MARK: - Ideas

    public func saveIdea(
        personID: UUID,
        note: String,
        priceHintText: String,
        sourceText: String?,
        id: UUID? = nil
    ) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Idea cannot be empty."
            return
        }
        let hint: BudgetMinorUnits?
        let trimmedHint = priceHintText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedHint.isEmpty {
            hint = nil
        } else {
            guard let parsed = MoneyParsing.parseCents(trimmedHint) else {
                lastError = "Price hint must look like 40 or 40.00 (up to 2 decimals)."
                return
            }
            hint = parsed
        }
        let idea = GiftIdea(
            id: id ?? UUID(),
            personID: personID,
            note: trimmed,
            priceHintCents: hint,
            sourceText: sourceText?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            createdOn: today
        )
        do {
            try store.saveIdea(idea)
            lastError = nil
            openIdeas(personID: personID)
        } catch {
            lastError = "Could not save idea: \(error)"
        }
    }

    public func deleteIdea(id: UUID, personID: UUID) {
        do {
            try store.deleteIdea(id: id)
            openIdeas(personID: personID)
        } catch {
            lastError = "Could not delete idea: \(error)"
        }
    }

    // MARK: - Occasions

    /// Create or edit an occasion and (re)sync its person attachments.
    /// New attachments start as `idea`-status slots with the given
    /// budget; existing slots are untouched (the state machine owns
    /// their status). Removing a person removes their slot only while
    /// it has not recorded anything (status `idea`).
    @discardableResult
    public func saveOccasion(
        name: String,
        date: CalendarDate?,
        budgetText: String,
        attachedPersonIDs: Set<UUID>,
        id: UUID? = nil
    ) -> Occasion? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Occasion name cannot be empty."
            return nil
        }
        guard let budget = MoneyParsing.parseCents(budgetText.isEmpty ? "0" : budgetText),
              (0...GiftVaultLimits.maximumBudgetMinorUnitsPerPerson).contains(budget)
        else {
            lastError = "Budget must be a non-negative amount up to \(MoneyFormatting.usdString(GiftVaultLimits.maximumBudgetMinorUnitsPerPerson))."
            return nil
        }
        let occasion = Occasion(id: id ?? UUID(), name: trimmed, date: date)
        do {
            try store.saveOccasion(occasion)
            let existing = try store.slots(forOccasion: occasion.id)
            let existingPeople = Set(existing.map(\.personID))
            for personID in attachedPersonIDs where !existingPeople.contains(personID) {
                try store.saveSlot(
                    OccasionSlot(occasionID: occasion.id, personID: personID, budgetCents: budget)
                )
            }
            for slot in existing where !attachedPersonIDs.contains(slot.personID) {
                if slot.status == .idea {
                    try store.deleteSlot(id: slot.id)
                }
            }
            lastError = nil
            reloadOccasions()
            return occasion
        } catch {
            lastError = "Could not save occasion: \(error)"
            return nil
        }
    }

    public func deleteOccasion(id: UUID) {
        do {
            try store.deleteOccasion(id: id)
            reloadOccasions()
        } catch {
            lastError = "Could not delete occasion: \(error)"
        }
    }

    // MARK: - Board actions (state machine + repeat check)

    /// Repeat-check for choosing `idea` in `slot`: prior given entries
    /// for that person matching the idea's note (issue #2 rule).
    public func repeatMatches(idea: GiftIdea, in slot: BoardSlot) -> [LedgerEntry] {
        RepeatMatcher.matches(candidateDescription: idea.note, personID: slot.person.id, in: ledger)
    }

    /// Step a slot forward via the seam's offered control. Choosing an
    /// idea (→ `chosen`) requires one; marking `given` writes the implied
    /// ledger row atomically (issue #3 store).
    public func advance(_ boardSlot: BoardSlot, chosenIdeaID: UUID? = nil) {
        guard case let .advance(to: target) = GiftWorkspaceLayout.statusControl(for: boardSlot.slot) else {
            lastError = "\(boardSlot.person.name)'s gift is already given — nothing more to do."
            return
        }
        if target == .chosen && (chosenIdeaID ?? boardSlot.slot.chosenIdeaID) == nil {
            lastError = "Choose an idea before marking this gift chosen."
            return
        }
        do {
            _ = try store.advanceSlot(id: boardSlot.slot.id, to: target, chosenIdeaID: chosenIdeaID, givenOn: today)
            lastError = nil
            reloadLedger()
            reloadOccasions()
            openBoard(occasionID: boardSlot.slot.occasionID)
        } catch {
            lastError = "Could not update \(boardSlot.person.name)'s slot: \(error)"
        }
    }

    /// Choose an idea for a still-`idea` slot (repeat-check result is
    /// surfaced by the chooser UI before this is called).
    public func chooseIdea(idea: GiftIdea, in boardSlot: BoardSlot) {
        advance(boardSlot, chosenIdeaID: idea.id)
    }

    // MARK: - Backup / export / restore (issue #6)

    /// The version string written into export bundles (matches the app's
    /// `MARKETING_VERSION`; kept here so the model is testable without
    /// Bundle APIs on Linux).
    public let appVersion: String

    /// Render the versioned JSON bundle for the whole vault. Errors are
    /// surfaced through `lastError` and returned as nil.
    public func exportBundleData() -> Data? {
        do {
            lastError = nil
            return try store.exportBackupBundle(appVersion: appVersion)
        } catch {
            lastError = "Could not export backup: \(error)"
            return nil
        }
    }

    public func exportIdeasCSV() -> String? {
        csvExport { try self.store.exportIdeasCSV() }
    }

    public func exportOccasionsCSV() -> String? {
        csvExport { try self.store.exportOccasionsCSV() }
    }

    public func exportLedgerCSV() -> String? {
        csvExport { try self.store.exportLedgerCSV() }
    }

    /// Restore the vault from a bundle's bytes (share-sheet/file-picker
    /// data). Validation + atomic replacement happen in the store; on any
    /// failure the existing vault is untouched and `lastError` explains why.
    public func restoreBundle(data: Data) -> Bool {
        do {
            try store.restoreBackupBundle(data)
            lastError = nil
            reloadAll()
            board = []
            ideas = []
            return true
        } catch {
            lastError = "Could not restore backup: \(error)"
            return false
        }
    }

    private func csvExport(_ body: () throws -> String) -> String? {
        do {
            lastError = nil
            return try body()
        } catch {
            lastError = "Could not export CSV: \(error)"
            return nil
        }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

#else

// On Linux (no Combine/SwiftUI) the model is not compiled; the pure
// helpers it relies on (MoneyParsing, GiftWorkspaceLayout) still are and
// are directly unit-tested.

#endif
