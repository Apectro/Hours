import Foundation

/// Someone from another of your crews who could join this one.
struct CrewCandidate: Identifiable, Hashable, Sendable {
    /// The name as it is written on the crew they last worked on.
    let name: String
    /// The last day they were ticked present on any of your sites; `nil` if
    /// they never were.
    let lastWorked: CalendarDate?
    /// The folded name, which is what makes two spellings one person.
    let id: String

    /// A new member of `siteID`'s crew with this name. Each site keeps its own
    /// crew, so this is a new member rather than the other site's one.
    func member(on siteID: UUID, sortOrder: Int) -> CrewMember {
        CrewMember(siteID: siteID, name: name, sortOrder: sortOrder)
    }
}

/// Who to offer under "Add from other sites".
///
/// A supervisor takes much the same people from site to site, but each site
/// has its own crew (a person's days belong to the site they were worked on),
/// so a new site used to mean typing the same names again. This offers the
/// names from every other crew, active sites and archived ones alike, once
/// each, without anyone already here, most recently worked with first.
enum CrewCandidates {
    static func candidates(for siteID: UUID, crew: [CrewMember], siteDays: [SiteDay]) -> [CrewCandidate] {
        // Hidden members here count as here: they are brought back with Show,
        // and a second copy of them would split their days between two names.
        let here = Set(crew.filter { $0.siteID == siteID }.map { key(for: $0.name) })

        var lastWorked: [UUID: CalendarDate] = [:]
        for day in siteDays where day.siteID != siteID {
            for attendance in day.present {
                if let known = lastWorked[attendance.memberID], known >= day.date { continue }
                lastWorked[attendance.memberID] = day.date
            }
        }

        var found: [String: CrewCandidate] = [:]
        for member in crew where member.siteID != siteID {
            let name = member.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = key(for: name)
            guard !key.isEmpty, !here.contains(key) else { continue }

            let worked = lastWorked[member.id]
            guard let existing = found[key] else {
                found[key] = CrewCandidate(name: name, lastWorked: worked, id: key)
                continue
            }
            // The latest date wins, and brings its spelling with it. A tie
            // keeps the first, so the result does not depend on luck.
            if let worked, existing.lastWorked.map({ worked > $0 }) ?? true {
                found[key] = CrewCandidate(name: name, lastWorked: worked, id: key)
            }
        }

        return found.values.sorted { lhs, rhs in
            switch (lhs.lastWorked, rhs.lastWorked) {
            case let (left?, right?) where left != right:
                return left > right
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            default:
                let order = lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive])
                return order == .orderedSame ? lhs.id < rhs.id : order == .orderedAscending
            }
        }
    }

    /// "  Čedo  Ivić" and "cedo ivić" are the same person: case, accents and
    /// spacing are how a name was typed, not who it names.
    static func key(for name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
