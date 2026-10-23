import Foundation

/// A job: somewhere you work, with its own contracted week.
///
/// Shifts belong to a job rather than days belonging to a job, because a single
/// Tuesday can contain a morning at one and an evening at another. That keeps
/// one entry per date — the calendar, the day editor and the unique date key
/// all stay as they were.
struct Job: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var name: String
    var tint: TypeTint
    /// The contracted week, and how it changed over time. Read a date's week
    /// through `schedule(on:)`.
    var schedules: ScheduleHistory
    /// Whether this employer pays for breaks. When it does, a shift's break is
    /// still recorded and reported, but it counts as worked time rather than
    /// being taken off it. A property of the job rather than of the app,
    /// because two employers seldom agree on it.
    var breaksArePaid: Bool
    /// What the job pays, and how that changed over time. Nil until a rate is
    /// set, and a job without one earns nothing rather than a guess.
    var pay: PayHistory?
    /// Archived jobs keep their history but stop contributing expected hours
    /// and stop appearing when you record new work.
    var isArchived: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        tint: TypeTint = .blue,
        schedule: WorkSchedule = WorkSchedule(),
        breaksArePaid: Bool = false,
        pay: PayHistory? = nil,
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.tint = tint
        self.schedules = ScheduleHistory(schedule)
        self.breaksArePaid = breaksArePaid
        self.pay = pay
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    /// The identifier of the job every shift belongs to until a second one is
    /// created. Fixed rather than random so that shifts recorded before jobs
    /// existed — which carry no job id at all — resolve to it forever.
    static let primaryID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    static func primary(schedule: WorkSchedule, breaksArePaid: Bool = false, name: String = Job.defaultName) -> Job {
        primary(schedules: ScheduleHistory(schedule), breaksArePaid: breaksArePaid, name: name)
    }

    static func primary(
        schedules: ScheduleHistory,
        breaksArePaid: Bool = false,
        pay: PayHistory? = nil,
        name: String = Job.defaultName
    ) -> Job {
        var job = Job(id: Job.primaryID, name: name, tint: .blue, breaksArePaid: breaksArePaid, pay: pay, sortOrder: 0)
        job.schedules = schedules
        return job
    }

    var isPrimary: Bool { id == Job.primaryID }

    /// The name the first job is created with, stored in English.
    static let defaultName = "Work"

    /// What the job is called on screen and in an export. The first job keeps
    /// its stored English "Work" until renamed, and shows it in the language
    /// at hand, as the Work day type does; any name the user gave is shown as
    /// written, including a second job they called "Work" themselves.
    func displayName(in language: ExportLanguage = .device) -> String {
        isPrimary && name == Job.defaultName ? language(.work) : name
    }

    /// The week in force on `date`.
    func schedule(on date: CalendarDate) -> WorkSchedule {
        schedules.schedule(on: date)
    }

    /// The newest week. With no changes recorded it is simply the schedule;
    /// for a date, read `schedule(on:)` instead.
    var schedule: WorkSchedule {
        get { schedules.latest }
        set { schedules.latest = newValue }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tint, schedule, scheduleVersions, breaksArePaid, pay, isArchived, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            name: container.lenient(.name, Job.defaultName),
            tint: container.lenient(.tint, .blue),
            // Absent from every job written before the switch existed, and
            // those employers were all being treated as not paying.
            breaksArePaid: container.lenient(.breaksArePaid, false),
            // Absent from every job written before earnings existed: no rate
            // has been set, so nothing is earned.
            pay: container.lenientOptional(.pay, PayHistory.self),
            isArchived: container.lenient(.isArchived, false),
            sortOrder: container.lenient(.sortOrder, 0)
        )
        self.schedules = container.scheduleHistory(versionsKey: .scheduleVersions, scheduleKey: .schedule)
    }

    /// The newest week goes under `schedule` as well as in the list, so a
    /// version of the app from before schedules changed over time still
    /// reads a sensible week — the current contract, applied to everything,
    /// which is what it always did.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(tint, forKey: .tint)
        try container.encode(schedules.latest, forKey: .schedule)
        try container.encode(schedules, forKey: .scheduleVersions)
        try container.encode(breaksArePaid, forKey: .breaksArePaid)
        try container.encodeIfPresent(pay, forKey: .pay)
        try container.encode(isArchived, forKey: .isArchived)
        try container.encode(sortOrder, forKey: .sortOrder)
    }
}

extension AppSettings {
    /// Every job, in display order.
    ///
    /// A settings blob with no jobs is the single-job case: the primary job is
    /// synthesised from the top-level schedule, so nothing has to be migrated
    /// and the app behaves exactly as it did before jobs existed.
    var resolvedJobs: [Job] {
        guard !jobs.isEmpty else { return [Job.primary(schedules: schedules, breaksArePaid: primaryBreaksArePaid, pay: primaryPay)] }
        return jobs.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
        }
    }

    /// Jobs that still expect hours and can still be assigned new work.
    var activeJobs: [Job] { resolvedJobs.filter { !$0.isArchived } }

    var primaryJob: Job {
        resolvedJobs.first { $0.isPrimary } ?? resolvedJobs[0]
    }

    /// Resolution never fails: a shift pointing at a deleted job falls back to
    /// the primary one so historical hours stay visible and counted.
    func job(_ id: UUID?) -> Job {
        guard let id else { return primaryJob }
        return resolvedJobs.first { $0.id == id } ?? primaryJob
    }

    /// A job's newest week; for a date, `job(id).schedule(on:)`.
    func schedule(forJob id: UUID?) -> WorkSchedule {
        job(id).schedule
    }

    /// True once there is more than one job to choose between — which is when
    /// the UI starts showing job pickers at all.
    var tracksMultipleJobs: Bool { activeJobs.count > 1 }

    /// The primary job's week in force on `date`, wherever it currently lives.
    func primarySchedule(on date: CalendarDate) -> WorkSchedule {
        primaryJob.schedule(on: date)
    }

    /// The primary job's history, wherever it currently lives.
    var primarySchedules: ScheduleHistory {
        get { primaryJob.schedules }
        set {
            if let index = jobs.firstIndex(where: { $0.isPrimary }) {
                jobs[index].schedules = newValue
            } else if jobs.isEmpty {
                schedules = newValue
            } else {
                jobs[0].schedules = newValue
            }
        }
    }

    /// The primary job's week is `newValue` from `date` onward, or always
    /// when `date` is nil. See `ScheduleHistory.change(to:from:)`.
    mutating func changePrimarySchedule(to newValue: WorkSchedule, from date: CalendarDate?) {
        primarySchedules.change(to: newValue, from: date)
    }

    /// Writes the primary job's break rule back to whichever place holds it,
    /// the same way `primarySchedules` does for its week.
    mutating func setPrimaryBreaksArePaid(_ newValue: Bool) {
        if let index = jobs.firstIndex(where: { $0.isPrimary }) {
            jobs[index].breaksArePaid = newValue
        } else if jobs.isEmpty {
            primaryBreaksArePaid = newValue
        } else {
            jobs[0].breaksArePaid = newValue
        }
    }

    /// A job's pay is `rules` from `date` onward, or always when `date` is
    /// nil — the first rate a job is given is its rate since always, since
    /// nothing earned anything before it. Written wherever the job lives, the
    /// way `primarySchedules` is.
    mutating func changePay(forJob id: UUID, to rules: PayRules, from date: CalendarDate?) {
        updatePay(forJob: id) { pay in
            if pay == nil {
                pay = PayHistory(rules)
            } else {
                pay?.change(to: rules, from: date)
            }
        }
    }

    /// Takes back the pay change that started on `date`.
    mutating func removePayChange(forJob id: UUID, from date: CalendarDate) {
        updatePay(forJob: id) { $0?.removeChange(from: date) }
    }

    /// Stops earnings for a job altogether, rates and their history with it.
    mutating func removePay(forJob id: UUID) {
        updatePay(forJob: id) { $0 = nil }
    }

    /// While there is one job its pay lives beside `schedules`, as
    /// `primaryPay`, so setting a rate never creates a job list.
    private mutating func updatePay(forJob id: UUID, _ change: (inout PayHistory?) -> Void) {
        if jobs.isEmpty, id == Job.primaryID {
            change(&primaryPay)
        } else {
            updateJob(id: id) { change(&$0.pay) }
        }
    }

    /// Whether any job has a rate, which is what earnings need before there
    /// is anything to show.
    var earningsAreSetUp: Bool {
        resolvedJobs.contains { $0.pay != nil }
    }

    /// Whether earnings take the hours balance's place. Without a rate there
    /// is nothing to show, so the balance stays whatever the choice says.
    var showsEarnings: Bool {
        earningsAreSetUp && mainFigure == .earnings
    }

    /// The currency amounts are written in: the chosen one, or `fallback` —
    /// the phone's — while none has been chosen.
    func currencyCode(fallback: String) -> String {
        currencyCode ?? fallback
    }

    /// Adds a job, materialising the implicit primary one first so the list is
    /// complete the moment there is more than one thing in it.
    mutating func addJob(_ job: Job) {
        if jobs.isEmpty { jobs = [Job.primary(schedules: schedules, breaksArePaid: primaryBreaksArePaid, pay: primaryPay)] }
        var appended = job
        appended.sortOrder = (jobs.map(\.sortOrder).max() ?? 0) + 1
        jobs.append(appended)
    }

    /// Removing the last remaining extra job collapses back to the single-job
    /// case rather than leaving a one-element list behind.
    mutating func removeJob(id: UUID) {
        guard !jobs.isEmpty else { return }
        jobs.removeAll { $0.id == id }
        if jobs.count <= 1 {
            schedules = jobs.first?.schedules ?? schedules
            primaryBreaksArePaid = jobs.first?.breaksArePaid ?? primaryBreaksArePaid
            primaryPay = jobs.first.map(\.pay) ?? primaryPay
            jobs = []
        }
    }

    mutating func updateJob(id: UUID, _ transform: (inout Job) -> Void) {
        if jobs.isEmpty { jobs = [Job.primary(schedules: schedules, breaksArePaid: primaryBreaksArePaid, pay: primaryPay)] }
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        transform(&jobs[index])
    }

    /// What every active job expects of `date`, added together, each from
    /// the week it had in force that day.
    ///
    /// Each job's own weekly override is applied before the sum, so two jobs
    /// with different contracts each contribute their own share.
    func contractedMinutes(on date: CalendarDate, calendar: Calendar) -> Int {
        let weekday = date.weekday(in: calendar)
        return activeJobs.reduce(0) { $0 + $1.schedule(on: date).expectedMinutes(forWeekday: weekday) }
    }
}
