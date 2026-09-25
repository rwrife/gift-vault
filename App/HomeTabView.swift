import GiftVaultStoreKit
import SwiftUI

/// iPhone tab shell: People · Occasions · Ledger (issue #4). Every
/// screen lives inside one of these three NavigationStacks; there are
/// no iPad-specific layouts and `GiftWorkspaceLayout` is the only
/// layout seam (single-pane today).
struct HomeTabView: View {
    @EnvironmentObject private var model: GiftVaultAppModel
    let notificationScheduler: NotificationScheduler

    /// UI-test-only Dynamic Type override (issue #5 accessibility pass):
    /// launches with `-ui-testing-ax-max` render at an accessibility size
    /// so UI tests can prove the shipped layouts survive AX sizes without
    /// reconfiguring the simulator's global setting.
    private var uiTestDynamicTypeOverride: DynamicTypeSize? {
        CommandLine.arguments.contains("-ui-testing-ax-max") ? .accessibility3 : nil
    }

    var body: some View {
        Group {
            if let uiTestDynamicTypeOverride {
                tabShell.dynamicTypeSize(uiTestDynamicTypeOverride)
            } else {
                tabShell
            }
        }
    }

    private var tabShell: some View {
        TabView {
            PeopleView()
                .tabItem { Label("People", systemImage: "person.2") }
            OccasionsView(notificationScheduler: notificationScheduler)
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
