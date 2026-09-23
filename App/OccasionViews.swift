import GiftVaultKit
import GiftVaultStoreKit
import SwiftUI

// MARK: - Occasion list + create/edit sheet

struct OccasionsView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    @State private var editorPresentation: OccasionEditorPresentation?

    struct OccasionEditorPresentation: Identifiable {
        let id: UUID?  // nil = create
        init(id: UUID?) { self.id = id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if model.occasions.isEmpty {
                    ContentUnavailableView(
                        "No occasions yet",
                        systemImage: "calendar",
                        description: Text("Create an occasion to build an idea board.")
                    )
                } else {
                    List {
                        ForEach(model.occasions) { occasion in
                            NavigationLink(value: occasion.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(occasion.name)
                                    if let date = occasion.date {
                                        Text("\(date)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    } else {
                                        Text("No date")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(minHeight: 44)
                            }
                        }
                        .onDelete { offsets in
                            for index in offsets {
                                model.deleteOccasion(id: model.occasions[index].id)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Occasions")
            .navigationDestination(for: UUID.self) { occasionID in
                OccasionBoardView(occasionID: occasionID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editorPresentation = OccasionEditorPresentation(id: nil)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add occasion")
                    .accessibilityIdentifier("occasions.add")
                }
            }
            .sheet(item: $editorPresentation) { presentation in
                OccasionEditorView(editingID: presentation.id)
            }
            .accessibilityIdentifier("screen.occasions")
        }
    }
}

// MARK: - Occasion editor (name, optional date, attach people, budget)

struct OccasionEditorView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    @Environment(\.dismiss) private var dismiss
    /// nil = create.
    let editingID: UUID?

    @State private var name: String = ""
    @State private var hasDate: Bool = false
    @State private var occasionDate: Date = AppClock.date(from: AppClock.today)
    @State private var budgetText: String = ""
    @State private var attached: Set<UUID> = []

    private var editing: Occasion? {
        model.occasions.first { $0.id == editingID }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Occasion") {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("occasion.name")
                    Toggle("Has a date", isOn: $hasDate)
                        .accessibilityIdentifier("occasion.hasDate")
                    if hasDate {
                        DatePicker("Date", selection: $occasionDate, displayedComponents: .date)
                            .accessibilityIdentifier("occasion.date")
                    }
                    TextField("Per-person budget (e.g. 50.00)", text: $budgetText)
                        .keyboardType(.decimalPad)
                        .accessibilityIdentifier("occasion.budget")
                }
                Section("People") {
                    if model.people.isEmpty {
                        Text("Add people first, then attach them here.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.people) { person in
                            Toggle(person.name, isOn: Binding(
                                get: { attached.contains(person.id) },
                                set: { included in
                                    if included { attached.insert(person.id) }
                                    else { attached.remove(person.id) }
                                }
                            ))
                            .accessibilityIdentifier("occasion.attach.\(person.id)")
                        }
                    }
                }
            }
            .navigationTitle(editingID == nil ? "New Occasion" : "Edit Occasion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        model.saveOccasion(
                            name: name,
                            date: hasDate ? AppClock.calendarDate(from: occasionDate) : nil,
                            budgetText: budgetText,
                            attachedPersonIDs: attached,
                            id: editingID
                        )
                        if model.lastError == nil { dismiss() }
                    }
                    .accessibilityIdentifier("occasion.save")
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    hasDate = editing.date != nil
                    if let date = editing.date {
                        occasionDate = AppClock.date(from: date)
                    }
                    budgetText = existingBudget(occasionID: editing.id)
                    attached = Set(((try? model.store.slots(forOccasion: editing.id)) ?? [])
                        .map(\.personID))
                } else {
                    attached = []
                }
            }
            .accessibilityIdentifier("sheet.occasion")
        }
    }

    private func existingBudget(occasionID: UUID) -> String {
        let slots = (try? model.store.slots(forOccasion: occasionID)) ?? []
        guard let first = slots.first else { return "" }
        return MoneyFormatting.decimalString(first.budgetCents)
    }
}

// MARK: - Occasion board (person slots, status, budget vs price hint)

struct OccasionBoardView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    let occasionID: UUID
    @State private var chooser: SlotChooser?

    struct SlotChooser: Identifiable {
        let id: UUID
    }

    private var occasion: Occasion? {
        model.occasions.first { $0.id == occasionID }
    }

    var body: some View {
        List {
            ForEach(model.board) { entry in
                BoardSlotRow(entry: entry) {
                    chooser = SlotChooser(id: entry.id)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(occasion?.name ?? "Board")
        .onAppear { model.openBoard(occasionID: occasionID) }
        .sheet(item: $chooser) { selection in
            if let entry = model.board.first(where: { $0.id == selection.id }) {
                IdeaChooserView(entry: entry)
            }
        }
        .accessibilityIdentifier("screen.board")
    }
}

// MARK: - Slot row

struct BoardSlotRow: View {
    let entry: GiftVaultAppModel.BoardSlot
    let onChoose: () -> Void
    @State private var advanceConfirmation: OccasionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.person.name)
                    .font(.headline)
                Spacer()
                Text(entry.slot.status.displayName)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(statusTint.opacity(0.18)))
                    .foregroundStyle(statusTint)
                    .accessibilityIdentifier("board.status.\(entry.id)")
            }
            HStack(spacing: 10) {
                Text("Budget \(MoneyFormatting.usdString(entry.slot.budgetCents))")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
                if let chosen = entry.chosenIdea {
                    Text("• \(chosen.note) \(MoneyFormatting.usdString(chosen.priceHintCents ?? 0))")
                        .font(.footnote)
                        .foregroundStyle(comparisonColor(entry.comparison(for: chosen)))
                        .accessibilityIdentifier("board.comparison.\(entry.id)")
                } else if entry.slot.status == .idea {
                    Button("Choose idea", action: onChoose)
                        .font(.footnote)
                        .accessibilityIdentifier("board.choose.\(entry.id)")
                }
            }
            switch GiftWorkspaceLayout.statusControl(for: entry.slot) {
            case let .advance(to: target):
                Button {
                    advanceConfirmation = target
                } label: {
                    Text(controlTitle(for: target))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("board.advance.\(entry.id)")
            case .none:
                // Terminal: the state machine offers nothing further, so
                // neither does the UI.
                Label("Gift given", systemImage: "checkmark.seal")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .confirmationDialog(
            "Move to \(advanceConfirmation?.displayName ?? "")?",
            isPresented: Binding(
                get: { advanceConfirmation != nil },
                set: { shown in if !shown { advanceConfirmation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Confirm") {
                if let target = advanceConfirmation {
                    model.advance(entry, chosenIdeaID: target == .chosen ? entry.slot.chosenIdeaID : nil)
                }
                advanceConfirmation = nil
            }
            Button("Cancel", role: .cancel) { advanceConfirmation = nil }
        }
    }

    /// Labels for the offered transition. Entering `chosen` without a
    /// selected idea is blocked in the model; the button is still the
    /// only legal next step, and the chooser covers the idea pick.
    private func controlTitle(for target: OccasionStatus) -> String {
        switch target {
        case .chosen: entry.chosenIdea == nil ? "Choose an idea first" : "Mark chosen"
        case .bought: "Mark bought"
        case .wrapped: "Mark wrapped"
        case .given: "Mark given"
        case .idea: ""
        }
    }

    private var statusTint: Color {
        switch entry.slot.status {
        case .idea: .secondary
        case .chosen: .blue
        case .bought: .orange
        case .wrapped: .purple
        case .given: .green
        }
    }

    private func comparisonColor(_ comparison: BudgetComparison) -> Color {
        switch comparison {
        case .under: .green
        case .over: .red
        case .unknownPrice: .secondary
        }
    }
}

// MARK: - Idea chooser (repeat-check + budget comparison before pick)

struct IdeaChooserView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    @Environment(\.dismiss) private var dismiss
    let entry: GiftVaultAppModel.BoardSlot

    var body: some View {
        NavigationStack {
            Group {
                if entry.ideas.isEmpty {
                    ContentUnavailableView(
                        "No ideas yet",
                        systemImage: "gift",
                        description: Text("Add ideas for \(entry.person.name) first.")
                    )
                } else {
                    List {
                        ForEach(entry.ideas) { idea in
                            Button {
                                model.chooseIdea(idea: idea, in: entry)
                                if model.lastError == nil { dismiss() }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(idea.note)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 8) {
                                        if let cents = idea.priceHintCents {
                                            Text(MoneyFormatting.usdString(cents))
                                                .font(.footnote.monospacedDigit())
                                            Text(entry.slot.budgetComparison(for: idea).label)
                                                .font(.footnote)
                                        } else {
                                            Text(BudgetComparison.unknownPrice.label)
                                                .font(.footnote)
                                        }
                                    }
                                    .foregroundStyle(.secondary)
                                    let repeats = model.repeatMatches(idea: idea, in: entry)
                                    if !repeats.isEmpty {
                                        Label(
                                            "Already given before (\(repeats.count)×)",
                                            systemImage: "arrow.triangle.2.circlepath"
                                        )
                                        .font(.footnote)
                                        .foregroundStyle(.orange)
                                        .accessibilityIdentifier("choose.repeat.\(idea.id)")
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(minHeight: 44)
                            }
                            .accessibilityIdentifier("choose.pick.\(idea.id)")
                        }
                    }
                }
            }
            .navigationTitle("Choose for \(entry.person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .accessibilityIdentifier("sheet.choose")
        }
    }
}
