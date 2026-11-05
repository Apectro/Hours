import Foundation

/// A short hint at the top of a screen (2026-11-05), shown only while what
/// it is about is true, so it goes away by itself once acted on.
///
/// The owner's site calendar greyed out half the month because the site's
/// work days were never set, and nothing said that mattered. A tip says it,
/// once, quietly: a lightbulb, a title, one sentence, perhaps an action,
/// and ✕ to hide it for good.
///
/// Raw values are what is stored in the dismissed set: never rename them.
enum TipID: String, CaseIterable, Hashable, Codable, Sendable {
    /// The site has no work days set and has a day or a crew.
    case siteWorkDays
    /// The site has days not written in the shown month (the red count).
    case siteDaysNotWritten
    /// Your name is not on the sheets yet, and there is something to send.
    case ownerName
    /// The extra-work editor's material is empty, the scanner can run, and
    /// no material was ever added.
    case scanMaterial
    /// The calendar's week list: swipe a day.
    case swipeDays
    /// The defects list is empty: photo first.
    case defectPhotos

    /// The screen it is shown on.
    var screen: TipScreen {
        switch self {
        case .siteWorkDays, .siteDaysNotWritten: return .site
        case .ownerName: return .export
        case .scanMaterial: return .extraWorkEditor
        case .swipeDays: return .calendarWeek
        case .defectPhotos: return .defects
        }
    }

    /// The accessibility identifier's middle: `tip-<this>`, `tip-<this>-action`
    /// and `tip-<this>-dismiss`.
    var identifier: String {
        switch self {
        case .siteWorkDays: return "site-work-days"
        case .siteDaysNotWritten: return "site-days-not-written"
        case .ownerName: return "owner-name"
        case .scanMaterial: return "scan-material"
        case .swipeDays: return "swipe-days"
        case .defectPhotos: return "defect-photos"
        }
    }

    /// Whether what the tip is about is true now.
    func applies(to facts: TipFacts) -> Bool {
        switch self {
        case .siteWorkDays:
            return !facts.siteIsReadOnly && !facts.siteHasWorkDays && facts.siteHasDaysOrCrew
        case .siteDaysNotWritten:
            return !facts.siteIsReadOnly && facts.siteDaysNotWritten > 0
        case .ownerName:
            return facts.ownerNameIsEmpty && facts.hasSitesOrDays
        case .scanMaterial:
            return facts.materialIsEmpty && facts.scannerIsAvailable && !facts.materialUsedBefore
        case .swipeDays:
            return facts.weekListIsShown
        case .defectPhotos:
            return facts.defectsAreEmpty
        }
    }
}

/// The screens a tip can be on.
enum TipScreen: CaseIterable, Hashable, Sendable {
    case site
    case export
    case extraWorkEditor
    case calendarWeek
    case defects

    /// Its tips, the most relevant first: at most one shows.
    var tips: [TipID] {
        switch self {
        // The red count goes by the work days, so they come first.
        case .site: return [.siteWorkDays, .siteDaysNotWritten]
        case .export: return [.ownerName]
        case .extraWorkEditor: return [.scanMaterial]
        case .calendarWeek: return [.swipeDays]
        case .defects: return [.defectPhotos]
        }
    }
}

/// What a screen knows, for deciding its tip. Every default is the state in
/// which no tip shows, so a screen fills in only its own.
struct TipFacts: Hashable, Sendable {
    // The site's page.
    var siteHasWorkDays = true
    var siteHasDaysOrCrew = false
    /// The red "N not written" of the shown month.
    var siteDaysNotWritten = 0
    /// One of the extra sites after Pro lapsed: shown, not changed.
    var siteIsReadOnly = false

    // Export.
    var ownerNameIsEmpty = false
    /// At least one site, or one day written.
    var hasSitesOrDays = false

    // The extra-work editor.
    var materialIsEmpty = false
    var scannerIsAvailable = false
    /// Material was added or scanned before: the remembered items are not
    /// empty.
    var materialUsedBefore = false

    // The calendar.
    var weekListIsShown = false

    // Defects.
    var defectsAreEmpty = false

    /// The site's page: its setup, how many days it has, its crew (you not
    /// counted), the red count and whether it is read-only.
    static func site(setup: SiteSetup, siteDays: Int, crew: Int, daysNotWritten: Int, isReadOnly: Bool) -> TipFacts {
        TipFacts(
            siteHasWorkDays: !setup.workDays.isEmpty,
            siteHasDaysOrCrew: siteDays > 0 || crew > 0,
            siteDaysNotWritten: max(0, daysNotWritten),
            siteIsReadOnly: isReadOnly
        )
    }

    /// Export: the name on the sheets as kept, and whether there is a site
    /// or a day written.
    static func export(ownerName: String, hasSitesOrDays: Bool) -> TipFacts {
        TipFacts(
            ownerNameIsEmpty: ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            hasSitesOrDays: hasSitesOrDays
        )
    }
}

/// Which tip a screen shows: the first of its tips, most relevant first,
/// that applies and was not dismissed; none while tips are switched off.
enum TipAdvisor {
    static func tip(
        for screen: TipScreen,
        facts: TipFacts,
        dismissed: Set<TipID> = [],
        enabled: Bool = true
    ) -> TipID? {
        guard enabled else { return nil }
        return screen.tips.first { !dismissed.contains($0) && $0.applies(to: facts) }
    }
}

/// Settings › More › Tips: whether tips show, and the ones hidden with ✕.
/// In the synced settings and every backup, written only when changed.
struct TipPreferences: Hashable, Codable, Sendable {
    /// "Show tips". On by default.
    var isEnabled: Bool
    /// Dismissed tips by raw value. Kept as text so a tip a newer version
    /// dismissed is written back as it was, not lost.
    private var dismissedIDs: Set<String>

    init(isEnabled: Bool = true, dismissed: Set<TipID> = []) {
        self.isEnabled = isEnabled
        self.dismissedIDs = Set(dismissed.map(\.rawValue))
    }

    /// The tips hidden with ✕, those this version knows.
    var dismissed: Set<TipID> {
        Set(dismissedIDs.compactMap(TipID.init(rawValue:)))
    }

    /// ✕: hidden for good, until "Show all tips again".
    mutating func dismiss(_ tip: TipID) {
        dismissedIDs.insert(tip.rawValue)
    }

    /// "Show all tips again": nothing dismissed.
    mutating func showAllAgain() {
        dismissedIDs = []
    }

    /// Whether anything was dismissed, a newer version's tips included.
    var hasDismissed: Bool { !dismissedIDs.isEmpty }

    /// Nothing differs from the defaults.
    var isStandard: Bool { self == TipPreferences() }

    private enum CodingKeys: String, CodingKey { case isEnabled, dismissed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = container.lenient(.isEnabled, true)
        // Entry by entry: one unreadable entry does not lose the rest.
        let entries = container.lenient(.dismissed, [LenientText]())
        dismissedIDs = Set(entries.compactMap(\.text).filter { !$0.isEmpty })
    }

    /// Only what differs from the defaults, the dismissed in order.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if !isEnabled { try container.encode(false, forKey: .isEnabled) }
        if !dismissedIDs.isEmpty { try container.encode(dismissedIDs.sorted(), forKey: .dismissed) }
    }
}

/// One entry of a stored list, nil where it is not text.
private struct LenientText: Decodable {
    let text: String?

    init(from decoder: Decoder) throws {
        text = try? decoder.singleValueContainer().decode(String.self)
    }
}

extension AppSettings {
    /// The tip `screen` shows given `facts`, by the switch and the
    /// dismissed set.
    func tip(for screen: TipScreen, facts: TipFacts) -> TipID? {
        TipAdvisor.tip(for: screen, facts: facts, dismissed: tips.dismissed, enabled: tips.isEnabled)
    }
}
