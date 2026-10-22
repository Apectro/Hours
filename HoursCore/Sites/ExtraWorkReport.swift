import Foundation

/// Which jobs a report carries, as the report screen offers them. Only
/// finished jobs, unless the user asks for the ones still in progress too.
enum ExtraWorkRange: Hashable, Sendable {
    /// Every job the boss does not have as it stands, whatever its date:
    /// never sent, or finished since it was sent in progress.
    case notSentYet
    /// The calendar week containing today, sent or not.
    case thisWeek
    /// Picked dates, both ends included, sent or not.
    case dates(CalendarDateRange)

    func select(
        _ jobs: [ExtraWorkJob],
        siteID: UUID,
        today: CalendarDate,
        calendar: Calendar,
        includeInProgress: Bool = false
    ) -> [ExtraWorkJob] {
        let onSite = jobs.filter { $0.siteID == siteID && ($0.isDone || includeInProgress) }
        switch self {
        case .notSentYet:
            return onSite.filter(\.awaitsReport)
        case .thisWeek:
            let week = CalendarDateRange.week(containing: today, in: calendar)
            return onSite.filter { week.contains($0.date) }
        case let .dates(range):
            return onSite.filter { range.contains($0.date) }
        }
    }
}

/// One item's material in total over a report.
struct ExtraWorkTotal: Hashable, Sendable {
    /// As it was most recently written.
    var name: String
    var unit: ExtraWorkUnit
    var quantity: Decimal
}

/// The extra work of one site that goes to the boss: the jobs, newest first,
/// the material they add up to, and the client's signature under the lot if
/// they gave one. Pure: made from jobs, nothing read.
struct ExtraWorkReport: Hashable, Sendable {
    var siteID: UUID
    /// Newest day first; within a day, in the order they were written.
    var jobs: [ExtraWorkJob]
    var totals: [ExtraWorkTotal]
    /// The client confirming the whole report, on top of any job's own.
    var clientSignature: ExtraWorkSignature?

    init(siteID: UUID, jobs: [ExtraWorkJob], clientSignature: ExtraWorkSignature? = nil) {
        self.siteID = siteID
        self.clientSignature = clientSignature
        // Sync can deliver one job twice; the first is kept, as for site days.
        var seen = Set<UUID>()
        let unique = jobs.filter { $0.siteID == siteID && seen.insert($0.id).inserted }
        self.jobs = unique.sorted(by: ExtraWorkReport.newestDayFirst)
        self.totals = ExtraWorkReport.totals(of: self.jobs)
    }

    static func newestDayFirst(_ lhs: ExtraWorkJob, _ rhs: ExtraWorkJob) -> Bool {
        if lhs.date != rhs.date { return lhs.date > rhs.date }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    var isEmpty: Bool { jobs.isEmpty }

    /// The finished jobs, newest day first: what the report is about.
    var done: [ExtraWorkJob] { jobs.filter(\.isDone) }
    /// Jobs still in progress, when the user included them: a section of
    /// their own after the finished ones.
    var inProgress: [ExtraWorkJob] { jobs.filter { !$0.isDone } }

    /// From the first job's day to the last's.
    var period: CalendarDateRange? {
        guard let first = jobs.map(\.date).min(), let last = jobs.map(\.date).max() else { return nil }
        return CalendarDateRange(start: first, end: last)
    }

    var hasHours: Bool { jobs.contains(where: \.hasHours) }
    var totalMinutes: Int { jobs.reduce(0) { $0 + $1.totalMinutes } }

    /// Signed for, by the client: on the job itself or under the report.
    func isConfirmed(_ job: ExtraWorkJob) -> Bool {
        clientSignature != nil || job.isSigned
    }

    // MARK: - Totals

    /// Summed per item and unit. Case, accents and spacing do not make a new
    /// item; the name and a typed unit are printed as last written. Grouped
    /// by unit — pieces first, then the measures, then typed units — and
    /// within a unit in the order the report lists them.
    private static func totals(of jobs: [ExtraWorkJob]) -> [ExtraWorkTotal] {
        struct Group {
            var total: ExtraWorkTotal
            var firstSeen: Int
            var latest: (date: CalendarDate, updatedAt: Date)
        }
        var groups: [String: Group] = [:]
        var order = 0
        for job in jobs {
            for item in job.cleaned().items {
                let key = ExtraWorkCatalog.key(item.name) + "|" + item.unit.groupingKey
                let stamp = (job.date, job.updatedAt)
                if var group = groups[key] {
                    group.total.quantity += item.quantity
                    if stamp.0 > group.latest.date || (stamp.0 == group.latest.date && stamp.1 > group.latest.updatedAt) {
                        group.total.name = item.name
                        group.total.unit = item.unit
                        group.latest = stamp
                    }
                    groups[key] = group
                } else {
                    groups[key] = Group(
                        total: ExtraWorkTotal(name: item.name, unit: item.unit, quantity: item.quantity),
                        firstSeen: order,
                        latest: stamp
                    )
                    order += 1
                }
            }
        }
        return groups.values
            .sorted { lhs, rhs in
                let left = lhs.total.unit
                let right = rhs.total.unit
                if left.sortIndex != right.sortIndex { return left.sortIndex < right.sortIndex }
                if left.groupingKey != right.groupingKey { return left.groupingKey < right.groupingKey }
                return lhs.firstSeen < rhs.firstSeen
            }
            .map(\.total)
    }

    // MARK: - The day screen

    /// "This day: 2 · In progress: 1 · Not sent: 5": jobs on a date, every
    /// job on the site still in progress, and every finished job the boss
    /// does not have yet.
    static func counts(_ jobs: [ExtraWorkJob], on date: CalendarDate) -> (onDay: Int, notSent: Int, inProgress: Int) {
        (
            jobs.filter { $0.date == date }.count,
            jobs.filter { $0.isDone && $0.awaitsReport }.count,
            jobs.filter { !$0.isDone }.count
        )
    }

    /// The days the site's month grid marks.
    static func dateKeys(_ jobs: [ExtraWorkJob]) -> Set<Int> {
        Set(jobs.map(\.date.key))
    }
}
