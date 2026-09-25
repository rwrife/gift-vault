import Foundation
import GiftVaultKit
import Testing

@Suite("OccasionReminderSchedule")
struct OccasionReminderScheduleTests {
    private let newYork = TimeZone(identifier: "America/New_York")!

    @Test("Schedule returns day before occasion")
    func basicSchedule() {
        let occasion = CalendarDate(year: 2026, month: 10, day: 4)!
        let reminder = OccasionReminderSchedule.reminderDate(for: occasion)
        #expect(reminder == CalendarDate(year: 2026, month: 10, day: 3))
    }

    @Test("Crosses month boundary")
    func monthBoundary() {
        let occasion = CalendarDate(year: 2026, month: 3, day: 1)!
        let reminder = OccasionReminderSchedule.reminderDate(for: occasion)
        #expect(reminder == CalendarDate(year: 2026, month: 2, day: 28))
    }

    @Test("Crosses leap year boundary")
    func leapYearBoundary() {
        let occasion = CalendarDate(year: 2024, month: 3, day: 1)!
        let reminder = OccasionReminderSchedule.reminderDate(for: occasion)
        #expect(reminder == CalendarDate(year: 2024, month: 2, day: 29))
    }

    @Test("Crosses year boundary")
    func yearBoundary() {
        let occasion = CalendarDate(year: 2027, month: 1, day: 1)!
        let reminder = OccasionReminderSchedule.reminderDate(for: occasion)
        #expect(reminder == CalendarDate(year: 2026, month: 12, day: 31))
    }

    @Test("Negative offset returns nil")
    func negativeOffset() {
        let occasion = CalendarDate(year: 2026, month: 10, day: 4)!
        #expect(OccasionReminderSchedule.reminderDate(for: occasion, daysBefore: -1) == nil)
    }

    @Test("DST safety: across spring-forward, calendar date arithmetic remains 1 calendar day")
    func dstSafetySpringForward() {
        // Spring-forward in New York is 2026-03-08.
        let occasion = CalendarDate(year: 2026, month: 3, day: 8)!
        let reminder = OccasionReminderSchedule.reminderDate(for: occasion)!
        #expect(reminder == CalendarDate(year: 2026, month: 3, day: 7))
        #expect(reminder.calendarDays(until: occasion) == 1)
    }
}
