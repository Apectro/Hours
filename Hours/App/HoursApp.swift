import SwiftUI
import SwiftData
import UserNotifications

@main
struct HoursApp: App {
    init() {
        // Before launch finishes, because a tap that launched the app is
        // handed to the delegate as soon as it does.
        UNUserNotificationCenter.current().delegate = NotificationTapDelegate.shared
        // Here rather than in a view: a message from the watch launches the
        // app in the background, where no window — and no view — appears.
        PhoneWatchLink.shared.activate()
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
