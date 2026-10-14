import Foundation

/// A calendar day stored as `YYYY-MM-DD`, independent of time zones.
///
/// Event, expense and payment dates are calendar facts ("we had dinner on the 12th"),
/// so they never shift when the device time zone changes.
struct CalendarDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let calendar = CalendarDate.gregorianUTC
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a strict `YYYY-MM-DD` string.
    init?(isoString: String) {
        let parts = isoString.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2])
        else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The calendar day of `date` in the given time zone (Gregorian calendar).
    init(date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // Components of a real Date are always valid.
        self.year = c.year ?? 1970
        self.month = c.month ?? 1
        self.day = c.day ?? 1
    }

    static func today(now: Date = Date(), timeZone: TimeZone = .current) -> CalendarDate {
        CalendarDate(date: now, timeZone: timeZone)
    }

    var isoString: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    var description: String { isoString }

    /// Local noon of this day; safe to bind to a `DatePicker` without DST edge cases.
    func date(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    func adding(days: Int) -> CalendarDate {
        let calendar = CalendarDate.gregorianUTC
        let base = calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
        let shifted = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return CalendarDate(date: shifted, timeZone: TimeZone(identifier: "UTC")!)
    }

    static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    private static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

extension CalendarDate: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let value = CalendarDate(isoString: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid calendar date \(raw)")
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(isoString)
    }
}
