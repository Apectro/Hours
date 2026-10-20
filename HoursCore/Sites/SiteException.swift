import Foundation

/// How one person's hours differed from the site's, for the short label the
/// day screen puts on their row.
///
/// Decided here rather than in the view so that the label and the hours it
/// sits beside come from the same `SiteDay` rules: someone is "left early"
/// only when their own end falls inside the site's day, which takes an
/// overnight site day into account the way the calculator does.
enum SiteException: Hashable, Sendable {
    /// Started later than the site and finished with it.
    case cameLate
    /// Started with the site and finished before it.
    case leftEarly
    /// Anything else: both ends changed, a different break, or a time
    /// outside the site's day.
    case changedTimes

    /// `nil` when the member worked the site's times or was not there.
    static func of(_ memberID: UUID, in day: SiteDay) -> SiteException? {
        guard day.hasException(memberID), let attendance = day.attendance(for: memberID) else { return nil }
        guard attendance.breakMinutes == nil, let siteStart = day.start, let siteEnd = day.end else {
            return .changedTimes
        }

        // Minutes into the site's day, so 02:00 after a 22:00 start reads as
        // four hours in rather than as earlier than the start.
        let length = offset(of: siteEnd, from: siteStart)
        func isInside(_ time: TimeOfDay) -> Bool {
            let into = offset(of: time, from: siteStart)
            return into > 0 && into < length
        }

        switch (attendance.start, attendance.end) {
        case let (start?, nil) where isInside(start):
            return .cameLate
        case let (nil, end?) where isInside(end):
            return .leftEarly
        default:
            return .changedTimes
        }
    }

    private static func offset(of time: TimeOfDay, from start: TimeOfDay) -> Int {
        (time.minutes - start.minutes + TimeOfDay.minutesPerDay) % TimeOfDay.minutesPerDay
    }
}
