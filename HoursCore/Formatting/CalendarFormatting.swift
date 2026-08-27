import Foundation

/// Locale-aware names for days and months.
///
/// Formatters are comparatively expensive to build, so the shared instances are
/// cached per locale-and-calendar combination and reused.
struct CalendarFormatting: Sendable {
    let locale: Locale
    let calendar: Calendar

    init(locale: Locale, calendar: Calendar) {
        self.locale = locale
        self.calendar = calendar
    }

    private func formatter(_ template: String) -> DateFormatter {
        let key = "\(locale.identifier)|\(calendar.identifier)|\(calendar.timeZone.identifier)|\(template)"
        if let cached = CalendarFormatting.cache.value(for: key) { return cached }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        CalendarFormatting.cache.set(formatter, for: key)
        return formatter
    }

    private static let cache = FormatterCache()

    /// The calendar with this formatting's locale on it.
    ///
    /// `Calendar.shortStandaloneWeekdaySymbols` and its siblings read the
    /// *calendar's* locale, not the formatter's, so asking a device-locale
    /// calendar for weekday names returned English ones however the export
    /// language was set. The month and weekday templates above go through a
    /// DateFormatter and were never affected, which is what made it look like
    /// the setting was working.
    private var localised: Calendar {
        guard calendar.locale != locale else { return calendar }
        var copy = calendar
        copy.locale = locale
        return copy
    }

    /// "August 2026"
    func monthTitle(_ month: YearMonth) -> String {
        formatter("yMMMM").string(from: month.firstDay.date(in: calendar))
    }

    /// "Aug 2026"
    func shortMonthTitle(_ month: YearMonth) -> String {
        formatter("yMMM").string(from: month.firstDay.date(in: calendar))
    }

    /// "Aug"
    func monthAbbreviation(_ month: YearMonth) -> String {
        formatter("MMM").string(from: month.firstDay.date(in: calendar))
    }

    /// "Tuesday, 4 August 2026"
    func fullDate(_ date: CalendarDate) -> String {
        formatter("EEEEdMMMMy").string(from: date.date(in: calendar))
    }

    /// "Tue 4 Aug"
    func mediumDate(_ date: CalendarDate) -> String {
        formatter("EEEdMMM").string(from: date.date(in: calendar))
    }

    /// "4 Aug"
    func shortDate(_ date: CalendarDate) -> String {
        formatter("dMMM").string(from: date.date(in: calendar))
    }

    /// "Tue"
    func weekdayAbbreviation(_ date: CalendarDate) -> String {
        formatter("EEE").string(from: date.date(in: calendar))
    }

    /// Single letters for the calendar header, starting at the calendar's own
    /// first weekday.
    var weekdayHeaderSymbols: [String] {
        let symbols = orderedSymbols(calendar.veryShortStandaloneWeekdaySymbols)
        return symbols.isEmpty ? ["S", "M", "T", "W", "T", "F", "S"] : symbols
    }

    /// Short names in calendar order, e.g. Mon…Sun.
    var weekdayShortSymbols: [String] {
        orderedSymbols(calendar.shortStandaloneWeekdaySymbols)
    }

    /// A single-letter symbol for one weekday number (1 = Sunday).
    func veryShortWeekdaySymbol(for weekday: Int) -> String {
        symbol(from: calendar.veryShortStandaloneWeekdaySymbols, weekday: weekday)
    }

    /// A short name for one weekday number (1 = Sunday), e.g. "Mon".
    func shortWeekdaySymbol(for weekday: Int) -> String {
        symbol(from: localised.shortStandaloneWeekdaySymbols, weekday: weekday)
    }

    /// The full name for one weekday number (1 = Sunday), e.g. "Monday".
    func weekdayName(for weekday: Int) -> String {
        symbol(from: localised.standaloneWeekdaySymbols, weekday: weekday)
    }

    private func symbol(from symbols: [String], weekday: Int) -> String {
        guard symbols.count == 7, (1...7).contains(weekday) else { return "" }
        return symbols[weekday - 1]
    }

    /// Weekday numbers (1 = Sunday) in the calendar's display order.
    var orderedWeekdayNumbers: [Int] {
        (0..<7).map { ((calendar.firstWeekday - 1 + $0) % 7) + 1 }
    }

    private func orderedSymbols(_ symbols: [String]) -> [String] {
        guard symbols.count == 7 else { return symbols }
        let offset = calendar.firstWeekday - 1
        return (0..<7).map { symbols[(offset + $0) % 7] }
    }

    /// "16:30" or "4:30 PM", following the device setting.
    func time(_ time: TimeOfDay, on date: CalendarDate) -> String {
        let formatter = self.formatter("jmm")
        var parts = DateComponents()
        parts.year = date.year
        parts.month = date.month
        parts.day = date.day
        parts.hour = time.hour
        parts.minute = time.minute
        guard let resolved = calendar.date(from: parts) else { return time.description }
        return formatter.string(from: resolved)
    }
}

/// A tiny thread-safe cache. `DateFormatter` is not cheap to create and these
/// are read on every calendar cell.
private final class FormatterCache: @unchecked Sendable {
    private var storage: [String: DateFormatter] = [:]
    private let lock = NSLock()

    func value(for key: String) -> DateFormatter? {
        lock.lock()
        defer { lock.unlock() }
        return storage[key]
    }

    func set(_ formatter: DateFormatter, for key: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = formatter
    }
}
