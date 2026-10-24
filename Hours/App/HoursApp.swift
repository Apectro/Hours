import SwiftUI
import SwiftData
import UserNotifications

@main
struct HoursApp: App {
    init() {
        // Before launch finishes, because a tap that launched the app is
        // handed to the delegate as soon as it does.
        UNUserNotificationCenter.current().delegate = NotificationTapDelegate.shared
        // The arrival reminder's buttons. The whole set: this replaces any
        // other, and no other notification has buttons.
        UNUserNotificationCenter.current().setNotificationCategories(ArrivalReminders.categories)
        // Here rather than in a view: a message from the watch launches the
        // app in the background, where no window — and no view — appears.
        PhoneWatchLink.shared.activate()
        // Before the store opens, so CloudKit's first setup report is heard
        // and the launch mark cleared by it (see `SyncLaunch`).
        HoursStack.syncMonitor.start()
        // Before launch finishes too: a site reached or left while the app
        // was not running relaunches it in the background and hands the
        // event to the location manager made here. Asks for nothing.
        HoursStack.arrivals.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailure: HoursStack.storeFailure)
                .environment(HoursStack.settings)
                .environment(HoursStack.clock)
                .environment(HoursStack.subscriptions)
                .preferredColorScheme(HoursStack.settings.settings.appearance.colorScheme)
        }
        // The same container Shortcuts and Siri use, rather than a second one
        // opened on the same file.
        .modelContainer(HoursStack.container)
    }
}
