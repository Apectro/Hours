import SwiftUI
import SwiftData

@main
struct HoursApp: App {
    @State private var settingsStore = SettingsStore()

    private let container: ModelContainer
    private let storeFailure: String?

    init() {
        do {
            container = try HoursModelContainer.make()
            storeFailure = nil
        } catch {
            // Never refuse to launch. The app runs on a temporary store and
            // says so, which is far better than a blank screen over data the
            // user cannot reach.
            container = HoursModelContainer.ephemeral()
            storeFailure = "Your data could not be opened, so this session is temporary. Nothing you enter now will be saved."
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(storeFailure: storeFailure)
                .environment(settingsStore)
                .preferredColorScheme(settingsStore.settings.appearance.colorScheme)
        }
        .modelContainer(container)
    }
}
