import Foundation

// The single layout seam for the dual-screen (iPhone Duo) design target
// (issue #4 contract).
//
// Every Gift Vault screen composes through this seam. The dual-screen
// form factor is a *documented design target*, not a tested platform:
// no fold SDK API is referenced anywhere (see the zero-network /
// compatibility contracts), and this type always resolves to a single
// pane today (`supportsDualPane == false`). A future dual-screen mode
// changes only here. This file is pure Swift (no SwiftUI) so the seam
// rules stay Linux-testable.

public enum GiftWorkspaceLayout {
    /// The app's primary panes (issue #4 screens).
    public enum Pane: String, CaseIterable, Sendable, Hashable {
        case people
        case occasions
        case ledger
    }

    /// Single-pane today. Flipping this is the ONLY way a second pane
    /// could ever appear; nothing else in the app may branch on screen
    /// count or fold hardware.
    public static let supportsDualPane = false

    /// Resolved screen mode. While `supportsDualPane == false` this is
    /// always `.single` — even if a caller proposes two panes — so the
    /// dual-screen concept cannot leak into the iPhone-only MVP.
    public enum ScreenMode: Sendable, Hashable {
        case single(Pane)
        case split(Pane, Pane)
    }

    public static func screenMode(focused: Pane?, secondary: Pane?) -> ScreenMode {
        guard supportsDualPane,
              let focused,
              let secondary,
              focused != secondary
        else {
            return .single(focused ?? secondary ?? .people)
        }
        return .split(focused, secondary)
    }

    // MARK: - Slot status control (issue #4: illegal transitions not offered)

    /// The ONLY status control the UI may offer for a slot. The state
    /// machine's `next` step is the single offered target; the terminal
    /// `given` state offers nothing. Because the UI only ever calls
    /// `advanceSlot` with this target, illegal transitions are not even
    /// reachable, let alone offered.
    public enum SlotStatusControl: Sendable, Hashable {
        case advance(to: OccasionStatus)
        case none
    }

    public static func statusControl(for slot: OccasionSlot) -> SlotStatusControl {
        guard let next = slot.status.next else { return .none }
        return .advance(to: next)
    }
}
