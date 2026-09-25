import Foundation

/// Pure calendar-day planning for local occasion reminders.
///
/// The app turns the returned `CalendarDate` into a local calendar trigger.
/// No elapsed-hour arithmetic is used, so the reminder remains one local day
/// before the occasion across 23-hour and 25-hour DST transitions.
public enum OccasionReminderSchedule {
    public static let daysBeforeOccasion = 1
    public static let deliveryHour = 9

    public static func reminderDate(
        for occasionDate: CalendarDate,
        daysBefore: Int = daysBeforeOccasion
    ) -> CalendarDate? {
        guard daysBefore >= 0 else { return nil }
        return occasionDate.addingCalendarDays(-daysBefore)
    }
}
