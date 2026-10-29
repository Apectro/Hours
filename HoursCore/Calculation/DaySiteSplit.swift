import Foundation

/// A day you worked on more than one site, as the calendar's day card draws
/// it (1.2): one row per site, "Trg Pravde · 12:00 – 16:00 · 3h 30m", and a
/// thin bar with a colour per site and a gap where neither was worked.
///
/// Read off the resolved day, so its hours are the ones the day already
/// counts; the day's Worked, Break and balance are still the day's own,
/// counted once.
struct DaySiteSplit: Hashable, Sendable {
    /// One block of the day, in the order worked.
    struct Part: Hashable, Sendable {
        /// Nil for hours you wrote on the day yourself.
        var siteID: UUID?
        var start: TimeOfDay?
        var end: TimeOfDay?
        var workedMinutes: Int
        var breakMinutes: Int
        var crossesMidnight: Bool
    }

    /// A stretch of the bar.
    enum Segment: Hashable, Sendable {
        /// The part at this index, this many minutes long.
        case site(Int, minutes: Int)
        /// Time between two parts.
        case gap(minutes: Int)
    }

    var parts: [Part]
    /// The bar from the first start to the last end; empty for a day that
    /// runs past midnight, which has no one line to draw.
    var segments: [Segment]
    /// The one site every minute of the day's breaks was taken on — "30m at
    /// Trg Pravde" — or nil when there was no break or it was on several.
    var breakSiteID: UUID?

    var start: TimeOfDay? { parts.first?.start }
    var end: TimeOfDay? { parts.last?.end }

    /// Nil unless the day's shifts come from at least two sites.
    static func make(_ day: DayComputation) -> DaySiteSplit? {
        let sites = Set(day.shifts.compactMap(\.siteID))
        guard sites.count >= 2 else { return nil }

        // The engine already sorts a day that stays within midnight.
        let parts = day.shifts.map {
            Part(
                siteID: $0.siteID,
                start: $0.start,
                end: $0.end,
                workedMinutes: $0.workedMinutes,
                breakMinutes: $0.breakMinutes,
                crossesMidnight: $0.crossesMidnight
            )
        }

        var segments: [Segment] = []
        if !day.crossesMidnight {
            var clock: Int?
            for (index, part) in parts.enumerated() {
                guard let start = part.start?.minutes, let end = part.end?.minutes else { continue }
                if let clock, start > clock { segments.append(.gap(minutes: start - clock)) }
                let from = max(start, clock ?? start)
                if end > from { segments.append(.site(index, minutes: end - from)) }
                clock = max(clock ?? end, end)
            }
        }

        let withBreaks = Set(parts.filter { $0.breakMinutes > 0 }.map(\.siteID))
        let breakSiteID = withBreaks.count == 1 ? withBreaks.first ?? nil : nil
        return DaySiteSplit(parts: parts, segments: segments, breakSiteID: breakSiteID)
    }
}
