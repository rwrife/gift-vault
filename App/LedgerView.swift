import GiftVaultKit
import GiftVaultStoreKit
import SwiftUI

// MARK: - Given/received ledger log (issue #4)

struct LedgerView: View {
    @EnvironmentObject private var model: GiftVaultAppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.ledger.isEmpty {
                    ContentUnavailableView(
                        "Nothing in the ledger yet",
                        systemImage: "list.bullet.rectangle",
                        description: Text("Gifts appear here as you mark them given.")
                    )
                } else {
                    List {
                        ForEach(model.ledger) { entry in
                            LedgerRow(entry: entry)
                                .frame(minHeight: 44)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Ledger")
            .onAppear { model.reloadLedger() }
            .accessibilityIdentifier("screen.ledger")
        }
    }
}

private struct LedgerRow: View {
    let entry: LedgerEntry
    @EnvironmentObject private var model: GiftVaultAppModel

    private var personName: String {
        model.people.first { $0.id == entry.personID }?.name ?? "Someone"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.direction == .given ? "gift" : "gift.fill")
                .foregroundStyle(entry.direction == .given ? .tint : .green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.direction.displayName) \(personName)")
                    .font(.body)
                    .accessibilityIdentifier("ledger.row.\(entry.id)")
                HStack(spacing: 8) {
                    Text("\(entry.date)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !entry.itemDescription.isEmpty {
                        Text(entry.itemDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    if entry.occasionID != nil {
                        Text("occasion")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                }
            }
            Spacer()
            if let cents = entry.valueCents {
                Text(MoneyFormatting.usdString(cents))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}
