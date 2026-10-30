import Foundation
import UserNotifications

/// What happens when the phone reaches or leaves a watched site (1.2): the
/// question, and the answer from the notification's buttons.
///
/// Whether to ask is `ArrivalReminderPolicy`'s decision, in the engine; this
/// only gathers its inputs — the site, today resolved by `PeriodEngine`, the
/// running clock, the log — and posts what it decides, at once (no trigger).
///
/// **Clock in** and **Clock out** run without opening the app, on the same
/// `TimeClock` as the clock card, Siri, the controls and the watch, and then
/// refresh the widget, which brings the Live Activity in line. As with a tap
/// on the watch, iOS refuses to start a Live Activity from the background,
/// so one started from the notification appears the next time the app comes
/// forward. The clock is put at the moment you arrived or left rather than
/// the moment the button was tapped (`ArrivalReminderPolicy.clockInstant`).
///
/// **Leaving with no clock running** while the site has no day for today
/// asks "Left <site> — write today's hours?" instead. **Same as last day**
/// writes the day the site screen's own "Same as last day" would
/// (`SiteRepository.sameAsLastDay`, under the month lock), without opening
/// the app; a tap on the notification opens the site on that day. Without a
/// last day there is only the tap. Once asked, the evening site reminder
/// leaves that site out for the day (`SiteReminderPlan.dates`).
@MainActor
enum ArrivalReminders {
    nonisolated static let arrivalCategory = "arrival-reminder"
    nonisolated static let departureCategory = "departure-reminder"
    nonisolated static let startAction = "arrival-start"
    nonisolated static let arrivalNotNowAction = "arrival-not-now"
    nonisolated static let stopAction = "departure-stop"
    nonisolated static let departureNotNowAction = "departure-not-now"
    /// Leaving with no clock and today not written, with a last day to copy.
    nonisolated static let writeCategory = "leave-write-reminder"
    /// The same question with no last day: only the tap that opens the day.
    nonisolated static let writeOpenCategory = "leave-write-open"
    nonisolated static let sameAsLastDayAction = "leave-same-as-last-day"
    nonisolated static let writeNotNowAction = "leave-write-not-now"

    /// The categories this answers or shows while the app is open.
    nonisolated static let allCategories: Set<String> = [
        arrivalCategory, departureCategory, writeCategory, writeOpenCategory,
    ]
    /// The notification's own identifier starts with this and names the
    /// site, so a newer question about a site replaces the older one.
    nonisolated static let identifierPrefix = "arrival-reminder-"

    private static let siteKey = "arrivalSiteID"
    private static let instantKey = "arrivalInstant"
    private static let dateKey = "arrivalDateKey"
    private static let logKey = "hours.arrivalReminderLog"

    /// Registered as the app launches, with every other category there is
    /// (none so far): `setNotificationCategories` replaces the whole set.
    static var categories: Set<UNNotificationCategory> {
        let start = UNNotificationAction(
            identifier: startAction,
            title: String(localized: "Clock in", comment: "Arrival notification button: start the clock"),
            options: []
        )
        let stop = UNNotificationAction(
            identifier: stopAction,
            title: String(localized: "Clock out", comment: "Departure notification button: stop the clock"),
            options: []
        )
        let notNow = String(localized: "Not now", comment: "Arrival or departure notification button: leave the clock as it is")
        return [
            UNNotificationCategory(
                identifier: arrivalCategory,
                actions: [start, UNNotificationAction(identifier: arrivalNotNowAction, title: notNow, options: [])],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: departureCategory,
                actions: [stop, UNNotificationAction(identifier: departureNotNowAction, title: notNow, options: [])],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: writeCategory,
                actions: [
                    UNNotificationAction(
                        identifier: sameAsLastDayAction,
                        title: String(
                            localized: "Same as last day",
                            comment: "Notification button on leaving a site: write today from the last site day"
                        ),
                        options: []
                    ),
                    UNNotificationAction(identifier: writeNotNowAction, title: notNow, options: []),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(identifier: writeOpenCategory, actions: [], intentIdentifiers: [], options: []),
        ]
    }

    // MARK: - Asking

    /// A watched region was crossed. Asks, or not, as the policy decides.
    static func handle(_ event: ArrivalEvent, regionIdentifier: String, at instant: Date) {
        guard !HoursStack.isRunningUITests,
              let siteID = ArrivalReminderPolicy.siteID(fromRegionIdentifier: regionIdentifier)
        else { return }

        let sites = SiteRepository(context: HoursStack.container.mainContext, lock: HoursStack.settings.settings.monthLock)
        guard let site = sites.site(id: siteID) else {
            // A site deleted since the region was set up: stop watching it.
            HoursStack.arrivals.refresh()
            return
        }

        let calendar = HoursStack.calendar
        let date = CalendarDate(instant, calendar: calendar)
        let workdays = HoursStack.repository
        let today = HoursStack.engine.day(date, record: workdays.record(on: date), holidays: workdays.holidayRules())
        let log = loadLog()
        let isClockRunning = HoursStack.clock.running != nil

        // Only leaving with no clock reads the site's day: the rest never
        // asks about it.
        var siteToday = ArrivalReminderPolicy.SiteToday.written
        if event == .left && !isClockRunning {
            let onDate = sites.siteDays(siteID: site.id, in: CalendarDateRange(single: date))
            siteToday = ArrivalReminderPolicy.SiteToday(
                isWritten: SiteReminderPlan.isWritten(siteID: site.id, on: date, siteDays: onDate),
                sameAsLastDay: sites.sameAsLastDay(siteID: site.id, on: date)
            )
        }

        let decision = ArrivalReminderPolicy.decide(
            event,
            site: site,
            today: today,
            isClockRunning: isClockRunning,
            siteToday: siteToday,
            log: log,
            now: instant
        )

        var updated = log.pruned(now: instant, today: date)
        switch decision {
        case .quiet:
            return
        case let .askToWrite(offersSameAsLastDay):
            updated.record(event, siteID: site.id, at: instant)
            updated.recordAskedToWrite(siteID: site.id, on: date)
            saveLog(updated)
            askToWrite(
                site: site,
                on: date,
                lastDay: offersSameAsLastDay ? siteToday.sameAsLastDay : nil,
                people: sites.crew(for: site.id, includeHidden: false).count + 1,
                at: instant
            )
            return
        case .remind:
            updated.record(event, siteID: site.id, at: instant)
            saveLog(updated)
        }

        // As on the lock screen in the 1.2 mockup: the site in the title,
        // the question under it.
        let content = UNMutableNotificationContent()
        switch event {
        case .arrived:
            content.title = String(localized: "At \(site.name)", comment: "Arrival notification title; the site's name")
            content.body = String(localized: "Clock in now?", comment: "Arrival notification body")
            content.categoryIdentifier = arrivalCategory
        case .left:
            content.title = String(localized: "Leaving \(site.name)", comment: "Notification title on leaving a site; the site's name")
            content.body = String(localized: "Clock out now?", comment: "Departure notification body, while the clock runs")
            content.categoryIdentifier = departureCategory
        }
        content.sound = .default
        content.userInfo = [siteKey: site.id.uuidString, instantKey: instant.timeIntervalSince1970]

        let request = UNNotificationRequest(
            identifier: identifierPrefix + site.id.uuidString,
            content: content,
            trigger: nil
        )
        Task {
            guard await ReminderScheduler().isAuthorized() else { return }
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    /// "Leaving <site>" / "Write today's hours? The usual day is 5 people,
    /// 07:00–16:00." — or the last day's times when the site has no usual
    /// day and there is one to copy. A tap opens the site on that day.
    private static func askToWrite(site: Site, on date: CalendarDate, lastDay: SiteDay?, people: Int, at instant: Date) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Leaving \(site.name)", comment: "Notification title on leaving a site; the site's name")
        let formatting = HoursStack.settings.dateFormatting
        let setup = HoursStack.settings.settings.siteSetup(for: site.id)
        let question = String(
            localized: "Write today's hours?",
            comment: "Notification body on leaving a site with no clock running and today not written"
        )
        if let start = setup.start, let end = setup.end {
            let range = formatting.time(start, on: date) + "–" + formatting.time(end, on: date)
            let usual = String(
                inflected: "The usual day is ^[\(people) person](inflect: true), \(range)."
            )
            content.body = question + " " + usual
        } else if let times = ArrivalReminderPolicy.lastTimes(lastDay) {
            let range = formatting.time(times.start, on: date) + "–" + formatting.time(times.end, on: date)
            content.body = question + " " + String(
                localized: "\(range) like last time",
                comment: "Notification body on leaving a site: the last site day's times, e.g. 07:00–15:30"
            )
        } else {
            content.body = question
        }
        content.categoryIdentifier = lastDay == nil ? writeOpenCategory : writeCategory
        content.sound = .default
        content.userInfo = [
            siteKey: site.id.uuidString,
            instantKey: instant.timeIntervalSince1970,
            dateKey: date.key,
            ReminderScheduler.linkKey: AppLink.site(site.id).url.absoluteString,
        ]

        let request = UNNotificationRequest(
            identifier: identifierPrefix + site.id.uuidString,
            content: content,
            trigger: nil
        )
        Task {
            guard await ReminderScheduler().isAuthorized() else { return }
            try? await UNUserNotificationCenter.current().add(request)
            // Asked now, so tonight's reminder leaves this site out.
            await refreshSiteReminders()
        }
    }

    /// The sites asked "write today's hours?" on `date`, which the evening
    /// site reminder leaves out (`SiteReminderRefresher`).
    static func sitesAskedToWrite(on date: CalendarDate) -> Set<UUID> {
        loadLog().sitesAskedToWrite(on: date)
    }

    private static func refreshSiteReminders() async {
        await SiteReminderRefresher.refresh(
            context: HoursStack.container.mainContext,
            preferences: HoursStack.settings.settings.reminders,
            calendar: HoursStack.calendar
        )
    }

    // MARK: - Answering

    /// Clock in, Clock out or Same as last day from the notification.
    /// Not now and a dismissal leave everything as it is; a tap on the write
    /// question follows its link instead (`NotificationTapDelegate`).
    static func respond(to actionIdentifier: String, userInfo: [AnyHashable: Any]) async {
        let eventAt = (userInfo[instantKey] as? Double).map(Date.init(timeIntervalSince1970:))
        let clock = HoursStack.timeClock
        let now = Date()

        switch actionIdentifier {
        case startAction:
            guard clock.running == nil else { return }
            let siteID = (userInfo[siteKey] as? String).flatMap(UUID.init(uuidString:))
            let site = siteID.flatMap { SiteRepository(context: HoursStack.container.mainContext).site(id: $0) }
            clock.clockIn(at: ArrivalReminderPolicy.clockInstant(eventAt: eventAt, now: now), jobID: site?.jobID)
            HoursStack.refreshWidget()

        case stopAction:
            guard let running = clock.running else { return }
            let instant = ArrivalReminderPolicy.clockInstant(eventAt: eventAt, now: now, notBefore: running.startedAt)
            let result = clock.clockOut(at: instant)
            HoursStack.refreshWidget()
            if case let .monthIsClosed(month) = result {
                tellMonthIsClosed(month)
            }

        case sameAsLastDayAction:
            await writeSameAsLastDay(userInfo: userInfo)

        default:
            return
        }
    }

    /// Writes the asked day from the last site day, exactly as the site
    /// screen's "Same as last day": only while that day is still unwritten,
    /// the site still active and there is something to copy, and under the
    /// month lock — a closed month is told in a notification of its own.
    private static func writeSameAsLastDay(userInfo: [AnyHashable: Any]) async {
        guard
            let siteID = (userInfo[siteKey] as? String).flatMap(UUID.init(uuidString:)),
            let key = userInfo[dateKey] as? Int,
            let date = CalendarDate(key: key)
        else { return }
        let context = HoursStack.container.mainContext
        let repository = SiteRepository(context: context, lock: HoursStack.settings.settings.monthLock)
        guard
            let site = repository.site(id: siteID), !site.isArchived,
            repository.siteDay(siteID: siteID, on: date) == nil,
            let day = repository.sameAsLastDay(siteID: siteID, on: date), !day.isBlank
        else { return }

        do {
            try repository.save(day)
        } catch MonthLock.Refusal.monthIsClosed(let month) {
            tellDayNotWritten(month)
            return
        } catch {
            return
        }
        HoursStack.refreshWidget()
        // Written, so tonight's nudge about it would be wrong; and a day
        // written can decide whether its site gets a note on the 1st.
        await refreshSiteReminders()
        await MonthlySheetRefresher.refresh(context: context, settingsStore: HoursStack.settings)
    }

    /// Same as last day refused by a closed month: nothing was written.
    private static func tellDayNotWritten(_ month: YearMonth) {
        let formatting = HoursStack.settings.dateFormatting
        let content = UNMutableNotificationContent()
        content.title = AppIdentity.name
        content.body = String(
            localized: "\(formatting.monthTitle(month)) is closed, so today's hours were not written.",
            comment: "Notification after Same as last day from leaving a site, into a month that refuses edits; the month and year"
        )
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifierPrefix + "closed", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    /// The shift is gone either way — the clock has stopped — so say which
    /// month refused it, as Siri does.
    private static func tellMonthIsClosed(_ month: YearMonth) {
        let formatting = HoursStack.settings.dateFormatting
        let content = UNMutableNotificationContent()
        content.title = AppIdentity.name
        content.body = String(
            localized: "\(formatting.monthTitle(month)) is closed, so that shift was not recorded.",
            comment: "Siri, clocking out into a month that refuses edits"
        )
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifierPrefix + "closed", content: content, trigger: nil)
        Task { try? await UNUserNotificationCenter.current().add(request) }
    }

    // MARK: - The log

    private static func loadLog() -> ArrivalReminderLog {
        guard let data = UserDefaults.standard.data(forKey: logKey),
              let log = try? JSONDecoder().decode(ArrivalReminderLog.self, from: data)
        else { return ArrivalReminderLog() }
        return log
    }

    private static func saveLog(_ log: ArrivalReminderLog) {
        guard let data = try? JSONEncoder().encode(log) else { return }
        UserDefaults.standard.set(data, forKey: logKey)
    }
}
