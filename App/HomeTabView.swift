import GiftVaultStoreKit
import SwiftUI

/// iPhone tab shell: People · Occasions · Ledger (issue #4). Every
/// screen lives inside one of these three NavigationStacks; there are
/// no iPad-specific layouts and `GiftWorkspaceLayout` is the only
/// layout seam (single-pane today).
struct HomeTabView: View {
    @EnvironmentObject private var model: GiftVaultAppModel

    var body: some View {
        TabView {
            PeopleView()
                .tabItem { Label("People", systemImage: "person.2") }
            OccasionsView()
                .tabItem { Label("Occasions", systemImage: "calendar") }
            LedgerView()
                .tabItem { Label("Ledger", systemImage: "list.bullet.rectangle") }
        }
        .accessibilityIdentifier("workspace.home")
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { model.lastError != nil },
                set: { presented in if !presented { model.lastError = nil } }
            )
        ) {
            Button("OK") { model.lastError = nil }
        } message: {
            Text(model.lastError ?? "")
        }
    }
}
