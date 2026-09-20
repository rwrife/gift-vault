import Foundation

/// Stable product bounds shared by the app and the future domain implementation.
/// These mirror the published MVP plan; issue #2 owns enforcement logic.
public enum GiftVaultLimits {
    /// README target audience: family and friend circles of 5–30 people.
    public static let maximumPeople = 30
    /// Per-person occasion budgets are stored in integer cents only.
    public static let maximumBudgetMinorUnitsPerPerson: Int64 = 100_000_000
    /// Per-person wishlist ideas kept on record.
    public static let maximumIdeasPerPerson = 200
}

/// Money is integer cents by contract — never floating point.
public typealias BudgetMinorUnits = Int64

/// The occasion-slot status vocabulary promised by the MVP plan.
/// Enforcement of legal transitions is issue #2's domain state machine;
/// this pipeline only pins the published order.
public enum OccasionStatus: String, CaseIterable, Sendable {
    case idea
    case chosen
    case bought
    case wrapped
    case given

    /// The README status timeline: idea → chosen → bought → wrapped → given.
    public static var pipeline: [OccasionStatus] { allCases }
}

/// Ledger directions from the README given/received history feature.
public enum LedgerDirection: String, CaseIterable, Sendable {
    case given
    case received
}
