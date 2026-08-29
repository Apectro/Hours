import Foundation

/// What the gap reminder notification says.
///
/// This used to live in `HoursCore` beside `GapFinder`, branching on the count
/// and writing each sentence out by hand — because the engine also builds on
/// Linux, where the localisation APIs are not reliably present, and the
/// comment explaining that promised the strings were "extracted from the app
/// that calls it". They were not. Nothing extracted them, nothing translated
/// them, and a German phone was notified in English.
///
/// It belongs here rather than there. This side has `String(inflected:)`, so
/// the plural is the catalogue's problem rather than a switch statement's —
/// which matters beyond tidiness: Slovenian needs a different word at three
/// days than at five, and a `default:` arm covering "three or more" cannot say
/// both. Finding the gaps is still the engine's job and stays where it was.
enum GapMessage {
    /// Nil when there is nothing to report. A reminder that fires to say
    /// "all good" is a reminder people switch off.
    static func text(for gaps: [CalendarDate], formatting: CalendarFormatting) -> String? {
        switch gaps.count {
        case 0:
            return nil
        case 1:
            return String(
                localized: "\(formatting.mediumDate(gaps[0])) has no hours recorded.",
                comment: "Gap reminder, a single missing day"
            )
        case 2:
            return String(
                localized: "\(formatting.mediumDate(gaps[0])) and \(formatting.mediumDate(gaps[1])) have no hours recorded.",
                comment: "Gap reminder, exactly two missing days"
            )
        default:
            // The count is inflected on its own and then dropped into the
            // sentence, rather than the whole sentence being one inflected
            // key. Not a style choice: build-catalog.py can only add
            // languages to a key the catalogue already holds, and the English
            // side of a new substitution has to come from Xcode's extraction,
            // which this project does not run. "^[%lld day](inflect: true)"
            // is already there and already carries every plural form.
            let count = String(inflected: "^[\(gaps.count) day](inflect: true)")
            return String(
                localized: "\(count) have no hours recorded, starting \(formatting.mediumDate(gaps[0])).",
                comment: "Gap reminder, three or more missing days; the first value is a counted noun"
            )
        }
    }
}
