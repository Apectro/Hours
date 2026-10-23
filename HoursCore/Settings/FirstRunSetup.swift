import Foundation

/// Whether a launch asks the first-run questions.
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
    /// The language of the sheets for the boss (`ExportPreferences.language`).
    var reportLanguage: ExportLanguage
    /// Whether you lead a crew (`AppSettings.leadsCrew`).
    var leadsCrew: Bool
    /// The primary job's hourly rate; 0 is none, and sets nothing up.
    var hourlyRateCents: Int
    /// Nil follows the phone's region, as in Settings › Pay.
    var currencyCode: String?

    init(settings: AppSettings) {
        let schedule = settings.primarySchedules.latest
        name = settings.export.ownerName
        workingWeekdays = Set((1...7).filter { schedule.isWorkingWeekday($0) })
        start = schedule.defaultStart
        end = schedule.defaultEnd
        breakMinutes = schedule.defaultBreakMinutes
        breaksArePaid = settings.primaryJob.breaksArePaid
        reportLanguage = settings.export.language
        leadsCrew = settings.leadsCrew
        hourlyRateCents = settings.primaryJob.pay?.latest.hourlyRateCents ?? 0
        currencyCode = settings.currencyCode
    }

    /// The report language and the currency the country suggests, or the
    /// settings' own without a country. `deviceCurrency` is the phone
    /// region's: choosing it stores nothing, as Settings › Pay does, so the
    /// phone keeps deciding.
    mutating func preselect(country: HolidayCountry?, region: String?, settings: AppSettings, deviceCurrency: String) {
        reportLanguage = ExportLanguage.suggested(for: country, region: region, otherwise: settings.export.language)
        if let code = country?.currencyCode {
            currencyCode = code == deviceCurrency ? nil : code
        } else {
            currencyCode = settings.currencyCode
        }
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

        var schedule = shaped(settings.primarySchedules.latest)
        let minutes = dailyMinutes
        for weekday in 1...7 {
            schedule.setContractedMinutes(workingWeekdays.contains(weekday) ? minutes : 0, forWeekday: weekday)
        }
        // A fresh install has no past for the week to leave alone, so it
        // applies since always rather than from today.
        settings.changePrimarySchedule(to: schedule, from: nil)
        settings.setPrimaryBreaksArePaid(breaksArePaid)

        settings.export.language = reportLanguage
        settings.leadsCrew = leadsCrew

        // A first rate applies since always, as Settings › Pay saves one. A
        // job that already has pay keeps it: its raises are not the
        // welcome's to rewrite.
        let primary = settings.primaryJob
        if primary.pay == nil, hourlyRateCents > 0 {
            settings.changePay(forJob: primary.id, to: PayRules(hourlyRateCents: hourlyRateCents), from: nil)
        }
        // The currency only matters with a rate; without one, a currency the
        // country preselected is not worth storing.
        if settings.earningsAreSetUp {
            settings.currencyCode = currencyCode
        }
    }

    private func shaped(_ schedule: WorkSchedule) -> WorkSchedule {
        var schedule = schedule
        schedule.defaultStart = start
        schedule.defaultEnd = end
        schedule.defaultBreakMinutes = max(0, breakMinutes)
        return schedule
    }
}
