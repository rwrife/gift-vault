import GiftVaultKit
import SwiftUI

struct BootstrapHomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "gift")
                    .font(.system(size: 54))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Text("Gift Vault")
                        .font(.largeTitle.bold())
                    Text("A local-first gift planner that keeps every idea on your device.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Native app foundation is ready", systemImage: "checkmark.circle")
                        Text("People, ideas, occasions, and the ledger arrive in the next milestones.")
                            .foregroundStyle(.secondary)
                        Text("Supports up to \(GiftVaultLimits.maximumPeople) people per vault.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
            .navigationTitle("Home")
        }
        .accessibilityIdentifier("bootstrap.home")
    }
}
