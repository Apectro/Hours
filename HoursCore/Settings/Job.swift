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
    var schedule: WorkSchedule
    /// Archived jobs keep their history but stop contributing expected hours
    /// and stop appearing when you record new work.
    var isArchived: Bool
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        tint: TypeTint = .blue,
        schedule: WorkSchedule = WorkSchedule(),
        isArchived: Bool = false,
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.tint = tint
        self.schedule = schedule
        self.isArchived = isArchived
        self.sortOrder = sortOrder
    }

    /// The identifier of the job every shift belongs to until a second one is
    /// created. Fixed rather than random so that shifts recorded before jobs
    /// existed — which carry no job id at all — resolve to it forever.
    static let primaryID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    static func primary(schedule: WorkSchedule, name: String = "Work") -> Job {
        Job(id: Job.primaryID, name: name, tint: .blue, schedule: schedule, sortOrder: 0)
    }

    var isPrimary: Bool { id == Job.primaryID }

    private enum CodingKeys: String, CodingKey {
        case id, name, tint, schedule, isArchived, sortOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            name: container.lenient(.name, "Work"),
            tint: container.lenient(.tint, .blue),
            schedule: container.lenient(.schedule, WorkSchedule()),
            isArchived: container.lenient(.isArchived, false),
            sortOrder: container.lenient(.sortOrder, 0)
        )
    }
}

extension AppSettings {
    /// Every job, in display order.
    ///
    /// A settings blob with no jobs is the single-job case: the primary job is
    /// synthesised from the top-level schedule, so nothing has to be migrated
    /// and the app behaves exactly as it did before jobs existed.
    var resolvedJobs: [Job] {
        guard !jobs.isEmpty else { return [Job.primary(schedule: schedule)] }
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

    func schedule(forJob id: UUID?) -> WorkSchedule {
        job(id).schedule
    }

    /// True once there is more than one job to choose between — which is when
    /// the UI starts showing job pickers at all.
    var tracksMultipleJobs: Bool { activeJobs.count > 1 }

    /// The primary job's contracted week, wherever it currently lives.
    var primarySchedule: WorkSchedule { primaryJob.schedule }

    /// Writes the primary job's week back to whichever place holds it.
    mutating func setPrimarySchedule(_ newValue: WorkSchedule) {
        if let index = jobs.firstIndex(where: { $0.isPrimary }) {
            jobs[index].schedule = newValue
        } else if jobs.isEmpty {
            schedule = newValue
        } else {
            jobs[0].schedule = newValue
        }
    }

    /// Adds a job, materialising the implicit primary one first so the list is
    /// complete the moment there is more than one thing in it.
    mutating func addJob(_ job: Job) {
        if jobs.isEmpty { jobs = [Job.primary(schedule: schedule)] }
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
            schedule = jobs.first?.schedule ?? schedule
            jobs = []
        }
    }

    mutating func updateJob(id: UUID, _ transform: (inout Job) -> Void) {
        if jobs.isEmpty { jobs = [Job.primary(schedule: schedule)] }
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        transform(&jobs[index])
    }

    /// What every active job expects of this weekday, added together.
    ///
    /// Each job's own weekly override is applied before the sum, so two jobs
    /// with different contracts each contribute their own share.
    func contractedMinutes(forWeekday weekday: Int) -> Int {
        activeJobs.reduce(0) { $0 + $1.schedule.expectedMinutes(forWeekday: weekday) }
    }
}
