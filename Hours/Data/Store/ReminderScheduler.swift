import Foundation
import UserNotifications

/// Schedules the weekly nudge about days with nothing recorded.
///
/// The only part of the app that asks the system for anything. It is asked for
/// nothing until the reminder is switched on, so someone who never wants it is
/// never prompted.
struct ReminderScheduler {
    static let identifier = "hours.gap-reminder"

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
}
