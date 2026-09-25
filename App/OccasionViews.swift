import GiftVaultKit
import GiftVaultStoreKit
import SwiftUI

// MARK: - Occasion list + create/edit sheet

struct OccasionsView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    let notificationScheduler: NotificationScheduler
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
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    occasion.date.map {
                                        "\(occasion.name), on \($0)"
                                    } ?? "\(occasion.name), no date"
                                )
                            }
                        }
                        .onDelete { offsets in
                            let idsToDelete = offsets.map { model.occasions[$0].id }
                            for id in idsToDelete {
                                model.deleteOccasion(id: id)
                                notificationScheduler.cancelReminder(occasionID: id)
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
                OccasionEditorView(editingID: presentation.id, notificationScheduler: notificationScheduler)
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
    let notificationScheduler: NotificationScheduler

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
                        .onChange(of: hasDate) { _, newValue in
                            // Permission is requested lazily, the first time
                            // the user actually opts an occasion into a date
                            // (never at app launch) — issue #5 contract.
                            if newValue {
                                Task { await notificationScheduler.requestAuthorizationIfNeeded() }
                            }
                        }
                    if hasDate {
                        DatePicker("Date", selection: $occasionDate, displayedComponents: .date)
                            .accessibilityIdentifier("occasion.date")
                        Text("A reminder is scheduled the day before, if notifications are allowed.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("occasion.reminderNote")
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
                        let savedDate = hasDate ? AppClock.calendarDate(from: occasionDate) : nil
                        if let saved = model.saveOccasion(
                            name: name,
                            date: savedDate,
                            budgetText: budgetText,
                            attachedPersonIDs: attached,
                            id: editingID
                        ) {
                            if let savedDate {
                                Task {
                                    await notificationScheduler.scheduleReminder(
                                        occasionID: saved.id,
                                        occasionName: saved.name,
                                        occasionDate: savedDate,
                                        today: model.today
                                    )
                                }
                            } else {
                                notificationScheduler.cancelReminder(occasionID: saved.id)
                            }
                            dismiss()
                        }
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
                        Task { await notificationScheduler.requestAuthorizationIfNeeded() }
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
            ForEach(Array(model.board.enumerated()), id: \.element.id) { index, entry in
                BoardSlotRow(
                    entry: entry,
                    rowIndex: index + 1,
                    totalRows: model.board.count,
                    occasionName: occasion?.name ?? "Occasion"
                ) {
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
    @EnvironmentObject private var model: GiftVaultAppModel
    let entry: GiftVaultAppModel.BoardSlot
    let rowIndex: Int
    let totalRows: Int
    let occasionName: String
    let onChoose: () -> Void
    @State private var advanceConfirmation: OccasionStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.person.name)
                    .font(.headline)
                    .accessibilityLabel(
                        "\(occasionName), row \(rowIndex) of \(totalRows), person \(entry.person.name)"
                    )
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: statusIcon(entry.slot.status))
                    Text(entry.slot.status.displayName)
                }
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

    private func statusIcon(_ status: OccasionStatus) -> String {
        switch status {
        case .idea: "lightbulb"
        case .chosen: "checkmark.circle"
        case .bought: "cart"
        case .wrapped: "shippingbox"
        case .given: "checkmark.seal"
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
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    "\(idea.note), \(idea.priceHintCents.map(MoneyFormatting.usdString) ?? "no price hint"), \(entry.slot.budgetComparison(for: idea).label)"
                                )
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
