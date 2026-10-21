import Foundation

/// Whether a launch asks the three first-run questions.
///
/// Only a fresh install is asked, once. The difficulty is telling a fresh
/// install from someone who has just updated to the version that has the
/// setup, since neither has seen it: anyone with stored data, or with any
/// setting moved off its default, has been using the app, so they are not
/// asked and the answer is remembered. Remembering it matters — someone who
/// later clears their data is still not a new user.
enum FirstRunSetup {
    enum Decision: Equatable {
        /// Ask the questions; they are marked done when finished or skipped.
        case show
        /// An existing user: do not ask, and mark it done now.
        case skip
        /// Already asked, or already decided.
        case nothing
    }

    static func decide(isDone: Bool, hasStoredData: Bool, settings: AppSettings) -> Decision {
        if isDone { return .nothing }
        if hasStoredData || settings != AppSettings() { return .skip }
        return .show
    }
}

/// What the first-run questions ask, prefilled from the settings so that
/// continuing past a question without changing it changes nothing.
struct FirstRunAnswers: Hashable, Sendable {
    /// For the sheets you hand in (`ExportPreferences.ownerName`).
    var name: String
    /// 1 = Sunday ... 7 = Saturday.
    var workingWeekdays: Set<Int>
    var start: TimeOfDay
    var end: TimeOfDay
    var breakMinutes: Int
    var breaksArePaid: Bool

    init(settings: AppSettings) {
        let schedule = settings.primarySchedule
        name = settings.export.ownerName
        workingWeekdays = Set((1...7).filter { schedule.isWorkingWeekday($0) })
        start = schedule.defaultStart
        end = schedule.defaultEnd
        breakMinutes = schedule.defaultBreakMinutes
        breaksArePaid = settings.primaryJob.breaksArePaid
    }

    /// What one working day comes to, which is what each ticked weekday is
    /// then contracted for. Worked out by the schedule, as the settings
    /// screen's own "that comes to" is, so the two cannot disagree.
    var dailyMinutes: Int {
        shaped(WorkSchedule()).defaultShiftMinutes(breaksArePaid: breaksArePaid)
    }

    /// Writes every answer. Through the same helpers the settings screens
    /// use, so the week lands wherever the primary job keeps it.
    func apply(to settings: inout AppSettings) {
        settings.export.ownerName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        var schedule = shaped(settings.primarySchedule)
        let minutes = dailyMinutes
        for weekday in 1...7 {
            schedule.setContractedMinutes(workingWeekdays.contains(weekday) ? minutes : 0, forWeekday: weekday)
        }
        settings.setPrimarySchedule(schedule)
        settings.setPrimaryBreaksArePaid(breaksArePaid)
    }

    private func shaped(_ schedule: WorkSchedule) -> WorkSchedule {
        var schedule = schedule
        schedule.defaultStart = start
        schedule.defaultEnd = end
        schedule.defaultBreakMinutes = max(0, breakMinutes)
        return schedule
    }
}
