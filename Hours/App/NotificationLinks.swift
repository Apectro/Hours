import Foundation
import Observation
import UserNotifications

/// The link a tapped notification carries, waiting for the root to follow it.
///
/// The Same as yesterday and Write today shortcuts leave theirs here too:
/// they run in the app as it opens, also outside any view.
///
/// A notification is tapped outside any view, often before there is one, so
/// the delegate leaves the link here and `RootView` follows it the way it
/// follows a widget's: through `AppLink`, by value, onto the Sites tab.
@MainActor
@Observable
final class NotificationLinks {
    var pending: AppLink?
}

/// Hears taps on the app's notifications.
///
/// Only the tap is handled. A notification arriving while the app is open is
/// left to the system's default, which is not to show it, so setting a
/// delegate changes nothing for the reminders that carry no link.
final class NotificationTapDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard
            let string = userInfo[ReminderScheduler.linkKey] as? String,
            let url = URL(string: string),
            let link = AppLink(url: url)
        else {
            completionHandler()
            return
        }
        Task { @MainActor in
            HoursStack.notificationLinks.pending = link
            completionHandler()
        }
    }
}
