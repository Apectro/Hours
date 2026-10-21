import Foundation
import UserNotifications

/// Schedules the weekly nudge about days with nothing recorded.
///
/// The only part of the app that asks the system for anything. It is asked for
/// nothing until the reminder is switched on, so someone who never wants it is
/// never prompted.
struct ReminderScheduler {
    static let identifier = "hours.gap-reminder"
    /// Every site reminder starts with this. The weekly reminder's identifier
    /// does not, so each kind can be replaced or cancelled without touching
    /// the other.
    static let siteIdentifierPrefix = "site-reminder-"
    /// Every monthly sheet reminder starts with this, for the same reason.
    static let monthlySheetIdentifierPrefix = "monthly-sheet-"
    /// Where a notification keeps the `AppLink` a tap on it follows.
    static let linkKey = "link"

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Asks for permission, returning whether it was granted. Safe to call
    /// repeatedly; the system only prompts once.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    /// Replaces whatever was scheduled with a single weekly reminder.
    ///
    /// The body is written now from the gaps that exist now, so it is accurate
    /// the moment it is set and goes stale slowly rather than being generic
    /// forever. It is rewritten every time the app is opened.
    func schedule(
        preferences: ReminderPreferences,
        body: String?
    ) async {
        cancel()
        guard preferences.isEnabled, await isAuthorized() else { return }

        let content = UNMutableNotificationContent()
        // The name, not a translated word: see AppIdentity.
        content.title = AppIdentity.name
        content.body = body ?? String(localized: "Check that this week's hours are recorded.")
        content.sound = .default

        var components = DateComponents()
        components.weekday = preferences.weekday
        components.hour = preferences.time.hour
        components.minute = preferences.time.minute

        let request = UNNotificationRequest(
            identifier: ReminderScheduler.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        )
        try? await center.add(request)
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [ReminderScheduler.identifier])
    }

    // MARK: - Site reminders

    /// `site-reminder-20260804`: one pending request per date, so saving that
    /// day can remove exactly its own.
    static func siteReminderIdentifier(for date: CalendarDate) -> String {
        siteIdentifierPrefix + String(format: "%08d", date.key)
    }

    /// Replaces every pending site reminder with one per date in `dates`, at
    /// `time` on that day. Instants already past (today, after the time) are
    /// skipped, since a calendar trigger in the past would never fire.
    func scheduleSiteReminders(
        dates: [CalendarDate],
        time: TimeOfDay,
        calendar: Calendar = .current,
        now: Date = Date()
    ) async {
        await cancelSiteReminders()
        guard await isAuthorized() else { return }

        for date in dates {
            var components = date.components
            components.hour = time.hour
            components.minute = time.minute
            guard let instant = calendar.date(from: components), instant > now else { continue }

            let content = UNMutableNotificationContent()
            content.title = AppIdentity.name
            content.body = String(localized: "Today's site hours aren't written yet.")
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: ReminderScheduler.siteReminderIdentifier(for: date),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Removes the reminder for one day, because that day has just been
    /// written.
    func cancelSiteReminder(on date: CalendarDate) {
        center.removePendingNotificationRequests(
            withIdentifiers: [ReminderScheduler.siteReminderIdentifier(for: date)]
        )
    }

    /// Removes every pending site reminder, leaving the weekly one alone.
    func cancelSiteReminders() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(ReminderScheduler.siteIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Monthly sheet reminders

    /// `monthly-sheet-<site>`: one per site, since only the next 1st is ever
    /// planned.
    static func monthlySheetIdentifier(for reminder: MonthlySheetReminder) -> String {
        monthlySheetIdentifierPrefix + reminder.siteID.uuidString
    }

    /// Replaces every pending monthly sheet reminder with `reminders`, each at
    /// `time` on its 1st. Each carries the link to that site's export on the
    /// month it covers, which a tap follows (see `NotificationLinks`).
    func scheduleMonthlySheetReminders(
        _ reminders: [MonthlySheetReminder],
        time: TimeOfDay,
        formatting: CalendarFormatting,
        calendar: Calendar = .current,
        now: Date = Date()
    ) async {
        await cancelMonthlySheetReminders()
        guard await isAuthorized() else { return }

        for reminder in reminders {
            var components = reminder.date.components
            components.hour = time.hour
            components.minute = time.minute
            guard let instant = calendar.date(from: components), instant > now else { continue }

            let month = formatting.monthName(reminder.month)
            let content = UNMutableNotificationContent()
            content.title = String(localized: "\(month) sheet for \(reminder.siteName) is ready")
            content.body = String(localized: "Send it to your director.")
            content.sound = .default
            content.userInfo = [
                ReminderScheduler.linkKey: AppLink.siteExport(reminder.siteID, reminder.month).url.absoluteString
            ]

            let request = UNNotificationRequest(
                identifier: ReminderScheduler.monthlySheetIdentifier(for: reminder),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }

    /// Removes every pending monthly sheet reminder, leaving the others alone.
    func cancelMonthlySheetReminders() async {
        let pending = await center.pendingNotificationRequests()
        let ids = pending.map(\.identifier).filter { $0.hasPrefix(ReminderScheduler.monthlySheetIdentifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
