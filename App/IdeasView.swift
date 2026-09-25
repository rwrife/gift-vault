import GiftVaultKit
import GiftVaultStoreKit
import SwiftUI

// MARK: - Per-person idea list (add / edit / delete, price-hint entry)

struct IdeasView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    let personID: UUID
    @State private var editorPresentation: IdeaEditorPresentation?

    private var person: Person? {
        model.people.first { $0.id == personID }
    }

    struct IdeaEditorPresentation: Identifiable {
        let id: UUID?  // nil = new idea
        init(id: UUID?) { self.id = id }
    }

    var body: some View {
        Group {
            if model.ideas.isEmpty {
                ContentUnavailableView(
                    "No ideas yet",
                    systemImage: "gift",
                    description: Text("Capture the first idea for \(person?.name ?? "this person").")
                )
            } else {
                List {
                    ForEach(model.ideas) { idea in
                        Button {
                            editorPresentation = IdeaEditorPresentation(id: idea.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(idea.note)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                HStack(spacing: 8) {
                                    if let cents = idea.priceHintCents {
                                        Text(MoneyFormatting.usdString(cents))
                                            .font(.footnote.monospacedDigit())
                                    } else {
                                        Text("No price hint")
                                            .font(.footnote)
                                    }
                                    if let source = idea.sourceText, !source.isEmpty {
                                        Text(source)
                                            .font(.footnote)
                                            .lineLimit(1)
                                    }
                                }
                                .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                model.deleteIdea(id: idea.id, personID: personID)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle(person?.name ?? "Ideas")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorPresentation = IdeaEditorPresentation(id: nil)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add idea")
                .accessibilityIdentifier("ideas.add")
            }
        }
        .onAppear { model.openIdeas(personID: personID) }
        .sheet(item: $editorPresentation) { presentation in
            IdeaEditorView(personID: personID, editingID: presentation.id)
        }
        .accessibilityIdentifier("screen.ideas")
    }
}

/// Add/edit sheet for one idea, including the integer-cent price hint
/// entered as decimal text and parsed without floating point.
struct IdeaEditorView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    @Environment(\.dismiss) private var dismiss
    let personID: UUID
    /// nil = new idea.
    let editingID: UUID?

    @State private var note: String = ""
    @State private var priceHintText: String = ""
    @State private var sourceText: String = ""

    private var editing: GiftIdea? {
        model.ideas.first { $0.id == editingID }
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Idea", text: $note)
                    .accessibilityIdentifier("idea.note")
                TextField("Price hint (e.g. 40.00)", text: $priceHintText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("idea.price")
                TextField("Where I saw it (optional)", text: $sourceText)
                    .accessibilityIdentifier("idea.source")
            }
            .navigationTitle(editingID == nil ? "Add Idea" : "Edit Idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        model.saveIdea(
                            personID: personID,
                            note: note,
                            priceHintText: priceHintText,
                            sourceText: sourceText,
                            id: editingID
                        )
                        if model.lastError == nil { dismiss() }
                    }
                    .accessibilityIdentifier("idea.save")
                }
            }
            .onAppear {
                if let editing {
                    note = editing.note
                    priceHintText = editing.priceHintCents.map(MoneyFormatting.decimalString) ?? ""
                    sourceText = editing.sourceText ?? ""
                }
            }
            .accessibilityIdentifier("sheet.idea")
        }
    }
}
