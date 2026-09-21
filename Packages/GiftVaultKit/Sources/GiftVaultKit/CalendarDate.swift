import Foundation

/// A pure calendar date (no time-of-day), per the issue #2 contract:
/// occasions store calendar dates and all date arithmetic is done on
/// calendar days, never on absolute second counts (which break across
/// DST transitions where a local day is 23 or 25 hours long).
///
/// Day-number arithmetic uses the days-from-civil algorithm: pure integer
/// math on the proleptic Gregorian calendar, independent of any time zone
/// or Foundation calendar state.
public struct CalendarDate: Sendable, Hashable, Codable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Failable initializer validating against the Gregorian calendar,
    /// including the leap-year rule (divisible by 4, except centuries
    /// unless divisible by 400).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...12).contains(month), day >= 1 else { return nil }
        guard day <= CalendarDate.daysInMonth(year: year, month: month) else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    public static func isLeapYear(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    public static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: 31
        case 4, 6, 9, 11: 30
        case 2: isLeapYear(year) ? 29 : 28
        default: 0
        }
    }

    // MARK: - Serial-day arithmetic (DST-immune, pure integers)

    /// Days since 1970-01-01 (may be negative for earlier dates).
    /// Howard Hinnant's `days_from_civil` algorithm — exact integer math.
    public var serialDayNumber: Int {
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400                                  // [0, 399]
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1  // [0, 365]
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Inverse of `serialDayNumber` (`civil_from_days`). All intermediate
    /// quantities are non-negative after the era shift, so truncating
    /// integer division behaves as floor division here.
    public init?(serialDayNumber: Int) {
        let z = serialDayNumber + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097                                    // [0, 146_096]
        let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365  // [0, 399]
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)              // [0, 365]
        let mp = (5 * doy + 2) / 153                                   // [0, 11]
        let day = doy - (153 * mp + 2) / 5 + 1                         // [1, 31]
        let month = mp + (mp < 10 ? 3 : -9)                            // [1, 12]
        self.init(year: y + (month <= 2 ? 1 : 0), month: month, day: day)
    }

    /// Whole calendar days from `self` up to `later` (negative if `later`
    /// is earlier). Counting local days, never elapsed hours.
    public func calendarDays(until later: CalendarDate) -> Int {
        later.serialDayNumber - serialDayNumber
    }

    /// Returns the date exactly `days` calendar days away (may be negative).
    public func addingCalendarDays(_ days: Int) -> CalendarDate? {
        CalendarDate(serialDayNumber: serialDayNumber + days)
    }

    // MARK: - Foundation bridging (always with an explicit time zone)

    /// The first instant of this local day in `timeZone`
    /// (e.g. 2026-03-08 00:00 America/New_York, regardless of DST).
    public func startOfDay(in timeZone: TimeZone) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)
    }

    /// The calendar date containing `instant` as observed in `timeZone`.
    public init?(date instant: Date, timeZone: TimeZone) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: instant)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return nil
        }
        self.init(year: year, month: month, day: day)
    }

    // MARK: - Comparable / description

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        lhs.serialDayNumber < rhs.serialDayNumber
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}
