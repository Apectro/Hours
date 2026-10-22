import SwiftUI

/// The Apple Watch app: today's hours and one big button.
///
/// It records nothing itself. Every figure is the phone's, sent as the same
/// snapshot the widgets read, and Clock in and Clock out are commands the
/// phone obeys with the clock it already has (see `WatchConnection`).
@main
struct ZeitkontoWatchApp: App {
    init() {
        // At launch, so a context the phone sent while the app was closed is
        // read before the first screen is drawn.
        WatchConnection.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchHomeView()
                .environment(WatchConnection.shared)
        }
    }
}
