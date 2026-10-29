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

/// Hears taps on the app's notifications, and the arrival reminder's
/// buttons.
///
/// A tap follows the notification's link. The arrival and departure
/// questions (1.2) carry Start clock / Stop clock and Not now instead
/// (`ArrivalReminders`), answered here without opening the app.
///
/// A notification arriving while the app is open is left to the system's
/// default, which is not to show it — except the arrival questions, which
/// are about this moment and are shown as a banner.
final class NotificationTapDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationTapDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let category = notification.request.content.categoryIdentifier
        let isArrival = category == ArrivalReminders.arrivalCategory || category == ArrivalReminders.departureCategory
        completionHandler(isArrival ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        if category == ArrivalReminders.arrivalCategory || category == ArrivalReminders.departureCategory {
            let action = response.actionIdentifier
            let userInfo = content.userInfo
            Task { @MainActor in
                ArrivalReminders.respond(to: action, userInfo: userInfo)
                completionHandler()
            }
            return
        }

        let userInfo = content.userInfo
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
