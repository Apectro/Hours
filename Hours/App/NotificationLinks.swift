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
/// (`ArrivalReminders`), answered here without opening the app. The
/// question on leaving with nothing written carries Same as last day and Not
/// now, and a tap on it follows its link to the site's day.
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
        let isArrival = ArrivalReminders.allCategories.contains(category)
        completionHandler(isArrival ? [.banner, .list, .sound] : [])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let action = response.actionIdentifier
        // A tap on the write question opens the site's day through its link,
        // below; its buttons, and every arrival button, are answered here.
        let followsLink = action == UNNotificationDefaultActionIdentifier
            && (category == ArrivalReminders.writeCategory || category == ArrivalReminders.writeOpenCategory)
        if ArrivalReminders.allCategories.contains(category) && !followsLink {
            let userInfo = content.userInfo
            Task { @MainActor in
                await ArrivalReminders.respond(to: action, userInfo: userInfo)
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
