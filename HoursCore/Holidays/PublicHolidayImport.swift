import Foundation

/// Turning a country's holidays into the person's own rules.
///
/// What comes out is ordinary `HolidayRule`s — paid absence, editable,
/// disable-able, deletable like hand-made ones. The set is only remembered
/// (`PublicHolidayPreferences`) so the screen can say which one was added and
/// offer to take exactly those away again.
enum PublicHolidayImport {
    struct Plan: Hashable, Sendable {
        /// The rules to add.
        var rules: [HolidayRule]
        /// Ticked holidays not added because a rule already falls on the
        /// same dates.
        var skipped: [PublicHoliday]
    }

    /// How many years from `fromYear` a holiday and an existing rule must
    /// agree on to count as the same holiday. A one-off on this year's
    /// Easter Monday agrees for one year and so stands in for nothing.
    static let comparedYears = 5

    static func plan(
        set: PublicHolidaySet,
        selection: Set<String>,
        existing: [HolidayRule],
        language: ExportLanguage,
        calendar: Calendar,
        fromYear: Int
    ) -> Plan {
        let years = fromYear..<(fromYear + comparedYears)
        // Every rule counts, disabled ones too: a holiday switched off on
        // purpose must not come back switched on.
        let taken = Set(existing.flatMap { rule in
            years.compactMap { rule.recurrence.occurrence(inYear: $0, calendar: calendar)?.key }
        })

        var rules: [HolidayRule] = []
        var skipped: [PublicHoliday] = []
        for holiday in set.holidays where selection.contains(holiday.id) {
            let dates = years.compactMap { holiday.recurrence.occurrence(inYear: $0, calendar: calendar)?.key }
            if !dates.isEmpty, dates.allSatisfy(taken.contains) {
                skipped.append(holiday)
                continue
            }
            rules.append(HolidayRule(
                name: holiday.name(in: language, setLanguage: set.language),
                recurrence: holiday.recurrence
            ))
        }
        return Plan(rules: rules, skipped: skipped)
    }
}

/// Which country's holidays were added, and whether the calendar's one-time
/// offer has been answered. Part of `AppSettings`, so a backup carries it.
struct PublicHolidayPreferences: Codable, Hashable, Sendable {
    /// `PublicHolidaySet.id` of the set added, while it is.
    var addedSetID: String?
    /// The rules that adding it created, for "Remove these holidays".
    var addedRuleIDs: [UUID]
    /// The calendar's "Show public holidays for your country?" card was put
    /// away, or answered by adding a set.
    var offerDismissed: Bool

    init(addedSetID: String? = nil, addedRuleIDs: [UUID] = [], offerDismissed: Bool = false) {
        self.addedSetID = addedSetID
        self.addedRuleIDs = addedRuleIDs
        self.offerDismissed = offerDismissed
    }

    var addedSet: PublicHolidaySet? { addedSetID.flatMap(PublicHolidayCatalog.set(id:)) }

    mutating func recordAdded(set: PublicHolidaySet, rules: [HolidayRule]) {
        addedSetID = set.id
        addedRuleIDs = rules.map(\.id)
        offerDismissed = true
    }

    /// The added rules still on the device. Ones deleted by hand since are
    /// already gone; the person's own rules are never in the list.
    func rulesToRemove(from existing: [HolidayRule]) -> [UUID] {
        let added = Set(addedRuleIDs)
        return existing.map(\.id).filter(added.contains)
    }

    mutating func forgetAdded() {
        addedSetID = nil
        addedRuleIDs = []
    }

    /// Once, to someone with no holidays at all, until answered either way.
    func shouldOffer(hasHolidayRules: Bool) -> Bool {
        !offerDismissed && addedSetID == nil && !hasHolidayRules
    }

    private enum CodingKeys: String, CodingKey {
        case addedSetID, addedRuleIDs, offerDismissed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            addedSetID: container.lenientOptional(.addedSetID, String.self),
            addedRuleIDs: container.lenient(.addedRuleIDs, []),
            offerDismissed: container.lenient(.offerDismissed, false)
        )
    }
}
