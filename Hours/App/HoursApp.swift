import SwiftUI
import SwiftData

@main
struct HoursApp: App {
    var body: some Scene {
        WindowGroup {
            RootView(storeFailure: HoursStack.storeFailure)
                .environment(HoursStack.settings)
                .environment(HoursStack.clock)
                .preferredColorScheme(HoursStack.settings.settings.appearance.colorScheme)
        }
        // The same container Shortcuts and Siri use, rather than a second one
        // opened on the same file.
        .modelContainer(HoursStack.container)
    }
}
