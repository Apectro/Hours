import Foundation

/// The same holiday, made separately on two devices before they synced.
///
/// Every other synced record has a natural key both devices agree on (a date;
/// a site and a date; a person, a site and a month) or an id only one device
/// ever makes. A holiday rule's id is made wherever the rule is, so "Christmas
/// Day" added on the phone and again on the iPad — or the same country's list
/// added on both — arrives as two rules. The calendar would not count the day
/// twice (one day, one type), but the list would show everything twice.
///
/// Two rules are the same holiday when they say exactly the same thing: the
/// same recurrence, the same name (ignoring case and surrounding spaces), and
/// the same choices about it — working day, enabled, notes. Rules that differ
/// in any of those are a disagreement the person has to settle, and both stay.
///
/// The oldest rule survives, and a tie on creation is broken by the id. That
/// is safe here, where it is not for a day (see `collapseDuplicates`): the id
/// travels with the rule, so every device sees the same ids and picks the
/// same survivor, and none deletes the rule another kept.
enum HolidayDuplicates {
    struct Stored {
        let rule: HolidayRule
        let createdAt: Date
    }

    private struct Identity: Hashable {
        let name: String
        let recurrence: HolidayRecurrence
        let countsAsWorkingDay: Bool
        let isEnabled: Bool
        let notes: String

        init(_ rule: HolidayRule) {
            name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            recurrence = rule.recurrence
            countsAsWorkingDay = rule.countsAsWorkingDay
            isEnabled = rule.isEnabled
            notes = rule.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// The ids of rules that only repeat an older one, to delete.
    static func redundant(_ stored: [Stored]) -> Set<UUID> {
        var groups: [Identity: [Stored]] = [:]
        for item in stored { groups[Identity(item.rule), default: []].append(item) }

        var doomed = Set<UUID>()
        for group in groups.values {
            // One rule stored in two rows is the id collapse's business.
            let ids = Set(group.map(\.rule.id))
            guard ids.count > 1 else { continue }
            let survivor = group.min { a, b in
                a.createdAt == b.createdAt
                    ? a.rule.id.uuidString < b.rule.id.uuidString
                    : a.createdAt < b.createdAt
            }!.rule.id
            doomed.formUnion(ids.subtracting([survivor]))
        }
        return doomed
    }
}
