import GiftVaultKit
import GiftVaultStoreKit
import SwiftUI

// MARK: - People list + quick-add

struct PeopleView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if model.people.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("Add the first person to start capturing gift ideas.")
                    )
                } else {
                    List {
                        ForEach(model.people) { person in
                            NavigationLink(value: person.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(person.name)
                                        .font(.body)
                                    if let birthday = person.birthday {
                                        Text("Birthday \(birthday)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .frame(minHeight: 44)
                                .accessibilityElement(children: .combine)
                                .accessibilityLabel(
                                    person.birthday.map { "\(person.name), birthday \($0)" } ?? person.name
                                )
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    model.deletePerson(id: person.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("People")
            .navigationDestination(for: UUID.self) { personID in
                IdeasView(personID: personID)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add person")
                    .accessibilityIdentifier("people.add")
                }
            }
            .sheet(isPresented: $showingAdd) {
                PersonEditorView()
            }
            .accessibilityIdentifier("screen.people")
        }
    }
}

/// Quick-add / edit sheet for a person.
struct PersonEditorView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    @Environment(\.dismiss) private var dismiss
    /// nil = create; set = edit existing person.
    var editing: Person?

    @State private var name: String = ""
    @State private var hasBirthday: Bool = false
    @State private var birthdayDate: Date = AppClock.date(
        from: CalendarDate(year: 1990, month: 1, day: 1)!
    )

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .accessibilityIdentifier("person.name")
                Toggle("Has birthday", isOn: $hasBirthday)
                    .accessibilityIdentifier("person.hasBirthday")
                if hasBirthday {
                    DatePicker("Birthday", selection: $birthdayDate, displayedComponents: .date)
                        .accessibilityIdentifier("person.birthday")
                }
            }
            .navigationTitle(editing == nil ? "Add Person" : "Edit Person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        model.savePerson(
                            name: name,
                            birthday: hasBirthday ? AppClock.calendarDate(from: birthdayDate) : nil,
                            id: editing?.id
                        )
                        if model.lastError == nil { dismiss() }
                    }
                    .accessibilityIdentifier("person.save")
                }
            }
            .onAppear {
                if let editing {
                    name = editing.name
                    hasBirthday = editing.birthday != nil
                    if let birthday = editing.birthday {
                        birthdayDate = AppClock.date(from: birthday)
                    }
                }
            }
            .accessibilityIdentifier("sheet.person")
        }
    }
}
