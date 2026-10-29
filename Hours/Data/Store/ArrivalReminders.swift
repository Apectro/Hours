import Foundation
import UserNotifications

/// What happens when the phone reaches or leaves a watched site (1.2): the
/// question, and the answer from the notification's buttons.
///
/// Whether to ask is `ArrivalReminderPolicy`'s decision, in the engine; this
/// only gathers its inputs — the site, today resolved by `PeriodEngine`, the
/// running clock, the log — and posts what it decides, at once (no trigger).
///
/// **Start clock** and **Stop clock** run without opening the app, on the same
/// `TimeClock` as the clock card, Siri, the controls and the watch, and then
/// refresh the widget, which brings the Live Activity in line. As with a tap
/// on the watch, iOS refuses to start a Live Activity from the background,
/// so one started from the notification appears the next time the app comes
/// forward. The clock is put at the moment you arrived or left rather than
/// the moment the button was tapped (`ArrivalReminderPolicy.clockInstant`).
@MainActor
enum ArrivalReminders {
    nonisolated static let arrivalCategory = "arrival-reminder"
    nonisolated static let departureCategory = "departure-reminder"
    nonisolated static let startAction = "arrival-start"
    nonisolated static let arrivalNotNowAction = "arrival-not-now"
    nonisolated static let stopAction = "departure-stop"
    nonisolated static let departureNotNowAction = "departure-not-now"
    /// The notification's own identifier starts with this and names the
    /// site, so a newer question about a site replaces the older one.
    nonisolated static let identifierPrefix = "arrival-reminder-"

    private static let siteKey = "arrivalSiteID"
    private static let instantKey = "arrivalInstant"
    private static let logKey = "hours.arrivalReminderLog"

    /// Registered as the app launches, with every other category there is
    /// (none so far): `setNotificationCategories` replaces the whole set.
    static var categories: Set<UNNotificationCategory> {
        let start = UNNotificationAction(
            identifier: startAction,
            title: String(localized: "Start clock", comment: "Arrival notification button: start the clock"),
            options: []
        )
        let stop = UNNotificationAction(
            identifier: stopAction,
            title: String(localized: "Stop clock", comment: "Departure notification button: stop the clock"),
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
        ]
    }

    // MARK: - Asking

    /// A watched region was crossed. Asks, or not, as the policy decides.
    static func handle(_ event: ArrivalEvent, regionIdentifier: String, at instant: Date) {
        guard !HoursStack.isRunningUITests,
              let siteID = ArrivalReminderPolicy.siteID(fromRegionIdentifier: regionIdentifier)
        else { return }

        let sites = SiteRepository(context: HoursStack.container.mainContext)
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

        let decision = ArrivalReminderPolicy.decide(
            event,
            site: site,
            today: today,
            isClockRunning: HoursStack.clock.running != nil,
            log: log,
            now: instant
        )
        guard decision == .remind else { return }

        var updated = log.pruned(now: instant)
        updated.record(event, siteID: site.id, at: instant)
        saveLog(updated)

        let content = UNMutableNotificationContent()
        // The name, not a translated word: see AppIdentity.
        content.title = AppIdentity.name
        switch event {
        case .arrived:
            content.body = String(
                localized: "Arrived at \(site.name) — start the clock?",
                comment: "Arrival notification; the site's name"
            )
            content.categoryIdentifier = arrivalCategory
        case .left:
            content.body = String(
                localized: "Left \(site.name) — stop the clock?",
                comment: "Departure notification, while the clock runs; the site's name"
            )
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

    // MARK: - Answering

    /// Start clock or Stop clock from the notification. Not now, a tap on the
    /// notification itself and a dismissal leave the clock as it is.
    static func respond(to actionIdentifier: String, userInfo: [AnyHashable: Any]) {
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

        default:
            return
        }
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
