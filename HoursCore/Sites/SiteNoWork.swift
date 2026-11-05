import Foundation

/// Why nobody worked on a site on a day it would have been expected (the
/// "N not written" sheet): a site day recorded as "no work" with one of
/// these, no hours for anyone.
///
/// Stored with the site day (`SiteDay.noWork`): in the database inside
/// `absenceData` as an entry of its own kind (`SiteDayStorage`), so no new
/// column and no CloudKit schema; in a backup as the site day's `noWork`
/// key, written only when set. Raw values are what is stored: never rename
/// them.
enum SiteNoWorkReason: String, CaseIterable, Hashable, Codable, Sendable {
    /// The crew was on another of your sites. When every person expected
    /// is ticked there the day is not missing to begin with
    /// (`SiteDayStatus.elsewhere`); this is for the days that cannot tell.
    case crewElsewhere
    /// Nothing to work on: waiting for other trades, no material.
    case noWork
    /// Rained off: the day is the bad-weather stop with no hours
    /// (`SiteDay.stoppedForBadWeather(at: nil)`), which also gives your own
    /// day the Bad weather type when nothing else is on it.
    case badWeather
    /// A holiday or a day off for the site.
    case dayOff

    /// The reasons in the order the sheet offers them: "Crew on another
    /// site" first when some of the crew were on another site that day,
    /// last otherwise.
    static func offered(someoneElsewhere: Bool) -> [SiteNoWorkReason] {
        someoneElsewhere ? [.crewElsewhere, .noWork, .badWeather, .dayOff] : [.noWork, .badWeather, .dayOff, .crewElsewhere]
    }

    /// The reason after "No work · " on a sheet, nil for plain "No work".
    func exportName(in language: ExportLanguage) -> String? {
        switch self {
        case .crewElsewhere: return language(.crewOnOtherSite)
        case .noWork: return nil
        case .badWeather: return language(.badWeather)
        case .dayOff: return language(.dayOff)
        }
    }
}

extension SiteDay {
    /// A day recorded as "no work" for `reason`: nobody ticked, no times.
    /// Bad weather is the full bad-weather stop of `usual` (who would have
    /// been ticked, no hours), exactly what "Bad weather… › No work today"
    /// writes on a day not written yet, so your own day gets the type as it
    /// does there.
    static func noWork(
        _ reason: SiteNoWorkReason,
        siteID: UUID,
        date: CalendarDate,
        jobID: UUID?,
        usual: SiteDay? = nil
    ) -> SiteDay {
        guard reason == .badWeather else {
            return SiteDay(siteID: siteID, date: date, jobID: jobID, noWork: reason)
        }
        var base = usual ?? SiteDay(siteID: siteID, date: date, jobID: jobID)
        base.siteID = siteID
        base.date = date
        base.jobID = jobID
        base.absences = []
        base.moves = []
        var day = base.stoppedForBadWeather(at: nil)
        day.allowanceMemberIDs = []
        day.noWork = .badWeather
        return day
    }

    /// Whether the day reads as "no work": marked so, and still so. A day
    /// someone was ticked on since is an ordinary day again, except a
    /// bad-weather one, whose crew stays ticked with no hours until the stop
    /// is lifted.
    var isNoWorkDay: Bool {
        guard let noWork else { return false }
        return noWork == .badWeather ? isBadWeatherStop : present.isEmpty
    }

    /// The "no work" taken back: Undo on the day and on the sheet. What the
    /// choice wrote goes with it — for bad weather the stop and the crew it
    /// left ticked with no hours — so a day that held nothing else is blank
    /// again (`isBlank`) and is deleted rather than kept.
    func clearingNoWork() -> SiteDay {
        var day = self
        let reason = day.noWork
        day.noWork = nil
        if reason == .badWeather {
            day.isBadWeatherStop = false
            day.present = present.filter { $0.start != nil || $0.end != nil }
            day.allowanceMemberIDs = []
        }
        return day
    }

    /// What a sheet writes before the day's note: "No work · Day off" on a
    /// no-work day, "Bad weather" on a day the crew was rained off, nil on
    /// any other day. In the export language.
    func sheetLead(in language: ExportLanguage) -> String? {
        if isNoWorkDay, let noWork {
            let word = language(.noWork)
            return noWork.exportName(in: language).map { "\(word) · \($0)" } ?? word
        }
        return isBadWeatherStop ? language(.badWeather) : nil
    }

    /// The lead and the note together, " · " between them.
    func sheetNote(in language: ExportLanguage) -> String {
        let note = self.note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let lead = sheetLead(in: language) else { return note }
        return note.isEmpty ? lead : "\(lead) · \(note)"
    }
}

/// A site paused (Site settings › Paused): no day is expected while it is,
/// so nothing reads as not written and no reminder comes. A day written
/// during a pause counts as any other. Kept in the site's `SiteSetup`.
struct SitePause: Hashable, Codable, Sendable {
    /// The first day paused.
    var start: CalendarDate
    /// The last day paused, inclusive; nil until turned back on.
    var end: CalendarDate?

    init(start: CalendarDate, end: CalendarDate? = nil) {
        self.start = start
        // An end before the start means the start's day only.
        self.end = end.map { max($0, start) }
    }

    func contains(_ date: CalendarDate) -> Bool {
        guard date >= start else { return false }
        guard let end else { return true }
        return date <= end
    }

    private enum CodingKeys: String, CodingKey {
        case start, end
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try container.decode(CalendarDate.self, forKey: .start),
            end: container.lenientOptional(.end)
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(start, forKey: .start)
        try container.encodeIfPresent(end, forKey: .end)
    }
}

extension SiteSetup {
    /// Whether the site is paused on `date`.
    func isPaused(on date: CalendarDate) -> Bool {
        pause?.contains(date) ?? false
    }
}

/// The days the "N not written" sheet lists, and what it offers on each.
enum SiteNoWorkList {
    struct Day: Hashable, Sendable {
        var date: CalendarDate
        /// Some, not all, of the people expected were on another of your
        /// sites that day: "Crew on another site" is offered first.
        var someoneElsewhere: Bool
    }

    /// The missing days of `statuses` in `month`, in order.
    static func days(
        statuses: [CalendarDate: SiteDayStatus],
        month: YearMonth,
        check: SiteCrewCheck
    ) -> [Day] {
        SiteDayStatus.missingDays(in: statuses.filter { month.contains($0.key) }).map { date in
            Day(date: date, someoneElsewhere: check.isPartlyElsewhere(on: date))
        }
    }
}

extension SiteMonthOverview {
    /// Whether everyone expected on `siteID` on `date` was on another of
    /// your sites that day (`SiteCrewCheck.isAllElsewhere`): for the
    /// reminders, which ask about one day. `siteDays` as for `crew`.
    static func isCrewElsewhere(
        siteID: UUID,
        on date: CalendarDate,
        members: [CrewMember],
        siteDays: [SiteDay],
        calendar: Calendar
    ) -> Bool {
        crew(siteID: siteID, members: members, siteDays: siteDays, month: date.yearMonth, calendar: calendar)
            .isAllElsewhere(on: date)
    }
}

extension SiteCrewCheck {
    /// Everyone who has joined by `date`, before anyone is taken off for
    /// being elsewhere.
    private func joinedBy(_ date: CalendarDate) -> Set<UUID> {
        always.union(joined.compactMap { $0.value <= date ? $0.key : nil })
    }

    /// Someone was expected on `date` and every one of them was on another
    /// of your sites: the day is not missing (`SiteDayStatus.elsewhere`).
    /// Nobody expected is not this: with no crew the day stays missing.
    func isAllElsewhere(on date: CalendarDate) -> Bool {
        !joinedBy(date).isEmpty && expected(on: date).isEmpty
    }

    /// Some, not all, of those expected on `date` were on another site.
    func isPartlyElsewhere(on date: CalendarDate) -> Bool {
        let everyone = joinedBy(date)
        let away = everyone.intersection(elsewhere[date] ?? [])
        return !away.isEmpty && away.count < everyone.count
    }
}
