import Foundation
import GiftVaultKit

// Local-notification scheduling (issue #5). `UserNotifications` is an
// Apple-only local-scheduling framework (never push, never a server) — the
// zero-network gate does not need to allowlist it because it makes no
// network calls. This file lives in the package (not App/) so its logic is
// compile-checked wherever Combine/UIKit-adjacent code can compile; the
// actual `UNUserNotificationCenter` calls are isolated behind a small
// protocol so the scheduling *decisions* are unit-testable without a real
// notification center.
//
// Permission is requested lazily: the app calls
// `NotificationScheduler.requestAuthorizationIfNeeded` only the first time
// the user opens an occasion with a date (never at launch), per the issue
// #5 acceptance criteria.

#if canImport(Combine)
import UserNotifications

/// Minimal seam over `UNUserNotificationCenter` so scheduling logic can be
/// exercised without invoking real system APIs.
public protocol NotificationCenterScheduling: Sendable {
    func requestAuthorization() async throws -> Bool
    func authorizationStatus() async -> UNAuthorizationStatus
    func addRequest(_ request: UNNotificationRequest) async throws
    func removePendingRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: NotificationCenterScheduling {
    public func requestAuthorization() async throws -> Bool {
        try await requestAuthorization(options: [.alert, .sound, .badge])
    }

    public func authorizationStatus() async -> UNAuthorizationStatus {
        await notificationSettings().authorizationStatus
    }

    public func addRequest(_ request: UNNotificationRequest) async throws {
        try await add(request)
    }

    public func removePendingRequests(withIdentifiers identifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// Schedules/cancels local reminders for occasion dates. One occasion maps
/// to at most one pending notification, identified by a stable id derived
/// from the occasion's UUID so reschedule-on-edit and cancel-on-delete are
/// simple upserts/removals — no separate bookkeeping store needed.
@MainActor
public final class NotificationScheduler {
    private let center: NotificationCenterScheduling

    public init(center: NotificationCenterScheduling = UNUserNotificationCenter.current()) {
        self.center = center
    }

    public static func identifier(for occasionID: UUID) -> String {
        "occasion-reminder-\(occasionID.uuidString)"
    }

    /// True once the user has answered the system prompt (granted or
    /// denied); `.notDetermined` means the prompt has never been shown.
    public func hasRequestedAuthorization() async -> Bool {
        await center.authorizationStatus() != .notDetermined
    }

    public func isAuthorized() async -> Bool {
        let status = await center.authorizationStatus()
        return status == .authorized || status == .provisional
    }

    /// Requests permission only if it has never been requested before.
    /// Safe to call every time an occasion-date screen appears — cheap and
    /// idempotent on the second call onward.
    @discardableResult
    public func requestAuthorizationIfNeeded() async -> Bool {
        if await hasRequestedAuthorization() {
            return await isAuthorized()
        }
        return (try? await center.requestAuthorization()) ?? false
    }

    /// Schedules (or reschedules) the reminder for `occasion`. No-ops
    /// silently if the occasion has no date, if reminder math rejects the
    /// date, or if the user has not granted permission — the caller is not
    /// required to check authorization first.
    public func scheduleReminder(
        occasionID: UUID,
        occasionName: String,
        occasionDate: CalendarDate,
        today: CalendarDate,
        calendar: Calendar = .current
    ) async {
        let identifier = Self.identifier(for: occasionID)
        // Always clear any existing reminder first — reschedule-on-edit is
        // implemented as cancel-then-add rather than an in-place update
        // (UNUserNotificationCenter has no update API).
        center.removePendingRequests(withIdentifiers: [identifier])

        guard await isAuthorized() else { return }
        guard let reminderDay = OccasionReminderSchedule.reminderDate(for: occasionDate) else { return }
        // Do not schedule reminders that would fire in the past.
        guard reminderDay >= today else { return }

        var components = DateComponents()
        components.year = reminderDay.year
        components.month = reminderDay.month
        components.day = reminderDay.day
        components.hour = OccasionReminderSchedule.deliveryHour
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Upcoming occasion"
        content.body = "\(occasionName) is coming up — check your gift plan."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await center.addRequest(request)
    }

    /// Cancels the reminder for an occasion (edit removing its date, or
    /// deleting the occasion entirely).
    public func cancelReminder(occasionID: UUID) {
        center.removePendingRequests(withIdentifiers: [Self.identifier(for: occasionID)])
    }
}

#endif
