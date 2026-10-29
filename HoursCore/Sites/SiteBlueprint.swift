import Foundation

/// Everything the new-site wizard sets up except where the site is (1.2):
/// the job, the field allowance by default, the usual day and extras, and
/// the crew by name. "Copy from a site" fills it from a site, "Start fresh"
/// from what new sites start with, and "Create and set up another like it"
/// keeps it for the next site.
struct SiteBlueprint: Hashable, Sendable {
    var jobID: UUID?
    var allowanceByDefault: Bool
    var setup: SiteSetup
    /// The crew other than you, in order. You are on every site.
    var crewNames: [String]

    /// "Start fresh": what new sites start with, the working week filling in
    /// what was not chosen, and nobody yet.
    static func fresh(defaults: NewSiteDefaults, schedule: WorkSchedule, jobID: UUID?) -> SiteBlueprint {
        SiteBlueprint(
            jobID: jobID,
            allowanceByDefault: defaults.allowanceByDefault,
            setup: defaults.setup(schedule: schedule),
            crewNames: []
        )
    }

    /// "Copy from a site": its crew (not anyone hidden from it — they have
    /// left), its usual day, work days and extras, its job and its allowance
    /// by default. Never its name, address or place, which are the new
    /// site's own.
    ///
    /// A site set up before usual days existed has none, so its latest day
    /// in `recentDays` gives the times and the weekdays it was worked lately
    /// give the work days; with neither, `fallback` does.
    static func copying(
        site: Site,
        setup: SiteSetup,
        crew: [CrewMember],
        recentDays: [SiteDay],
        calendar: Calendar,
        fallback: SiteSetup
    ) -> SiteBlueprint {
        var copied = setup
        let own = recentDays.filter { $0.siteID == site.id }
        if !copied.hasUsualTimes {
            let latest = own
                .filter { $0.start != nil && $0.end != nil }
                .max { $0.date < $1.date }
            copied.start = latest?.start ?? fallback.start
            copied.end = latest?.end ?? fallback.end
            copied.breakMinutes = latest?.breakMinutes ?? fallback.breakMinutes
        }
        if copied.workDays.isEmpty, let newest = own.map(\.date).max() {
            copied.workDays = SiteWorkDays.inferred(
                siteID: site.id,
                siteDays: own,
                before: newest.adding(days: 1, in: calendar),
                calendar: calendar
            )
        }
        if copied.workDays.isEmpty {
            copied.workDays = fallback.workDays
        }
        let names = crew
            .filter { $0.siteID == site.id && !$0.isHidden }
            .sorted { $0.sortOrder < $1.sortOrder }
            .map(\.name)
        return SiteBlueprint(
            jobID: site.jobID,
            allowanceByDefault: site.allowanceByDefault,
            setup: copied,
            crewNames: CrewPicking.merge(ticked: names, typed: [])
        )
    }

    /// What creating a site writes: the site, its crew and its setup.
    struct Made: Hashable, Sendable {
        var site: Site
        var crew: [CrewMember]
        var setup: SiteSetup
    }

    /// A new site from the blueprint, with a new id and new crew members of
    /// its own (each site keeps its own crew). `arrival` carries the arrival
    /// reminder's place, radius and switch as the wizard's place step set
    /// them; nothing else is read from it.
    func make(name: String, address: String, arrival: Site?, sortOrder: Int) -> Made {
        var site = Site(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            jobID: jobID,
            sortOrder: sortOrder,
            allowanceByDefault: allowanceByDefault,
            address: address.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if let arrival {
            site.place = arrival.place
            site.arrivalRadius = arrival.arrivalRadius
            site.remindsOnArrival = arrival.remindsOnArrival && arrival.place != nil
        }
        let crew = crewNames.enumerated().map { offset, name in
            CrewMember(siteID: site.id, name: name, sortOrder: offset)
        }
        return Made(site: site, crew: crew, setup: setup)
    }
}

/// Names typed or pasted one per line: new people, or several sites at once.
enum NameList {
    /// Each line a name, trimmed and with its spaces tidied; blank lines and
    /// a name already given (by `CrewCandidates.key`: case, accents and
    /// spacing aside) left out. A single line with commas or semicolons is a
    /// list typed in one go; once there are lines, a comma is part of a name
    /// ("Kovač, Josip").
    static func parse(_ text: String) -> [String] {
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let meaningful = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let pieces: [String]
        if meaningful.count == 1, let only = meaningful.first {
            pieces = only.split(whereSeparator: { $0 == "," || $0 == ";" }).map(String.init)
        } else {
            pieces = meaningful
        }
        return unique(pieces)
    }

    /// The names tidied (trimmed, single spaces), blanks left out, and each
    /// person once by `CrewCandidates.key`, the first spelling kept.
    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for piece in names {
            let name = piece.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let key = CrewCandidates.key(for: name)
            guard !key.isEmpty, seen.insert(key).inserted else { continue }
            result.append(name)
        }
        return result
    }

    /// Whether a site of this name exists, archived or not.
    static func isTaken(_ name: String, among sites: [Site]) -> Bool {
        let key = CrewCandidates.key(for: name)
        guard !key.isEmpty else { return false }
        return sites.contains { CrewCandidates.key(for: $0.name) == key }
    }

    /// "Several sites at once": the names that can be made, and those a
    /// site already has.
    static func newSites(from text: String, among sites: [Site]) -> (new: [String], taken: [String]) {
        var new: [String] = []
        var taken: [String] = []
        for name in parse(text) {
            if isTaken(name, among: sites) { taken.append(name) } else { new.append(name) }
        }
        return (new, taken)
    }
}

/// Someone on one of your active crews, offered once in the wizard's crew
/// step with the sites they are on.
struct CrewChoice: Identifiable, Hashable, Sendable {
    /// The folded name (`CrewCandidates.key`).
    let id: String
    /// As written on the first site they are on.
    let name: String
    /// The active sites they are on, in the sites' order.
    let siteNames: [String]
}

/// The wizard's crew step: who can be ticked, and the crew it makes.
enum CrewPicking {
    /// Everyone on an active site's crew, hidden people left out, once each
    /// by name, in the sites' order and then each crew's.
    static func choices(sites: [Site], crew: [CrewMember]) -> [CrewChoice] {
        var order: [String] = []
        var names: [String: String] = [:]
        var where_: [String: [String]] = [:]
        for site in sites where !site.isArchived {
            let members = crew
                .filter { $0.siteID == site.id && !$0.isHidden }
                .sorted { $0.sortOrder < $1.sortOrder }
            for member in members {
                let name = member.name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                let key = CrewCandidates.key(for: name)
                guard !key.isEmpty else { continue }
                if names[key] == nil {
                    names[key] = name
                    order.append(key)
                }
                if where_[key]?.contains(site.name) != true {
                    where_[key, default: []].append(site.name)
                }
            }
        }
        return order.map { CrewChoice(id: $0, name: names[$0] ?? $0, siteNames: where_[$0] ?? []) }
    }

    /// The crew: who was ticked, then who was typed, each person once.
    static func merge(ticked: [String], typed: [String]) -> [String] {
        NameList.unique(ticked + typed)
    }
}
