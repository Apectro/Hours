import Foundation

/// Which printed days stand out, and in what colour (2026-11).
///
/// A cell or a row that says what kind of day it was instead of giving
/// times — "Bolovanje", "Public holiday", "No work · Day off" — is washed
/// lightly in that day type's own colour, the one the calendar shows it in,
/// with the word a darker shade of it. A whole day off for everyone washes
/// the row; one person away washes only their cell.
///
/// The colours are named here (`TypeTint`) and resolved to fixed print
/// values below, because a PDF and a workbook are paper: they must not
/// follow the phone's appearance, and they must still read when printed
/// in black and white.
enum ReportDayHighlight {
    /// The tint a day of `type` stands out in, when nothing was worked on it;
    /// nil for a working day and for a weekend, which the page already greys.
    ///
    /// A type of the user's own that is meant for work — expected like a
    /// working day and with times shown by default — is not highlighted
    /// either: it reads as a working day, not as a day away.
    static func tint(for type: DayTypeDefinition, workedMinutes: Int = 0) -> TypeTint? {
        guard workedMinutes <= 0 else { return nil }
        switch type.id {
        case .work, .weekend:
            return nil
        default:
            if type.expectation == .scheduled && type.showsTimesByDefault { return nil }
            return type.tint
        }
    }

    /// A site's day nobody worked, for the reason given: a day off and a
    /// rained-off day in their day types' colours, plain "no work" in grey.
    /// The crew on another site was working, so nothing stands out.
    static func tint(for reason: SiteNoWorkReason, catalog: DayTypeCatalog) -> TypeTint? {
        switch reason {
        case .crewElsewhere: return nil
        case .noWork: return .gray
        case .badWeather: return catalog.definition(for: .badWeather).tint
        case .dayOff: return catalog.definition(for: .dayOff).tint
        }
    }

    /// The whole row of a site's day on a director's sheet: only a day that
    /// still reads as "no work".
    static func rowTint(for day: SiteDay, catalog: DayTypeCatalog) -> TypeTint? {
        guard day.isNoWorkDay, let reason = day.noWork else { return nil }
        return tint(for: reason, catalog: catalog)
    }
}

extension TypeTint {
    /// The light wash behind a highlighted day on paper, as 0xRRGGBB: pale
    /// enough that black-and-white printing leaves a faint grey and the text
    /// on it stays readable.
    var printWash: UInt32 {
        switch self {
        case .blue: return 0xEAF1FC
        case .teal: return 0xE5F4F5
        case .green: return 0xE8F4EA
        case .yellow: return 0xFBF3D6
        case .orange: return 0xFCEEDF
        case .red: return 0xFBE9E8
        case .pink: return 0xFBE8F0
        case .purple: return 0xF2EAF9
        case .indigo: return 0xEBECFA
        case .brown: return 0xF3EDE6
        case .gray: return 0xEFEFF2
        }
    }

    /// The word on that wash, a darker shade of the same colour, as
    /// 0xRRGGBB: at least 4.5:1 against the wash and against white.
    var printInk: UInt32 {
        switch self {
        case .blue: return 0x1F5FAD
        case .teal: return 0x1B6A73
        case .green: return 0x2B7230
        case .yellow: return 0x735600
        case .orange: return 0x9A4A00
        case .red: return 0xAD2A20
        case .pink: return 0x9E2456
        case .purple: return 0x66379A
        case .indigo: return 0x3D43A6
        case .brown: return 0x6B4F35
        case .gray: return 0x55555B
        }
    }
}

extension ReportTable {
    /// Whether any day on the sheet is highlighted, so the legend says what
    /// the shading means only where there is some.
    var hasDayHighlights: Bool {
        rows.contains { $0.dayTint != nil || !$0.groupTints.isEmpty }
    }
}
