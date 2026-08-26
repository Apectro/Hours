import Foundation

/// A length of time as it should be said out loud.
///
/// The three display styles are all written to be read rather than spoken, and
/// Siri makes that plain: it reads `8:30` as a time of day and `8.50` as a
/// decimal number. Neither is what someone who asked "how am I doing" wants to
/// hear back, and the third, `8h 30m`, becomes "eight h thirty m".
///
/// Deliberately not in the engine. Saying this properly needs the localisation
/// APIs, and the engine also builds on Linux where they are not reliably
/// present — and nothing but a spoken intent response has any use for it.
enum SpokenDuration {
    static func string(_ minutes: Int) -> String {
        let magnitude = abs(minutes)
        let hours = magnitude / 60
        let remainder = magnitude % 60

        switch (hours, remainder) {
        case (0, 0):
            return String(localized: "no time at all")
        case (0, _):
            return String(localized: "^[\(remainder) minute](inflect: true)")
        case (_, 0):
            return String(localized: "^[\(hours) hour](inflect: true)")
        default:
            return String(localized: "^[\(hours) hour](inflect: true) ^[\(remainder) minute](inflect: true)")
        }
    }
}
