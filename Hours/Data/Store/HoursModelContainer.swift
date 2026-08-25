import Foundation
import SwiftData

/// Builds the app's SwiftData stack.
enum HoursModelContainer {
    static let schema = Schema([DayEntry.self, HolidayRecord.self])

    static func make(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            // Explicitly no CloudKit: this app is local-first by design, and
            // enabling it would also rule out the unique constraints the data
            // model depends on.
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// A throwaway in-memory stack. Used by previews, by tests, and as the
    /// last-resort fallback if the on-disk store cannot be opened — the app
    /// stays usable and says so rather than refusing to launch.
    static func ephemeral() -> ModelContainer {
        do {
            return try make(inMemory: true)
        } catch {
            // An in-memory container failing means the schema itself is broken,
            // which is a programming error and cannot be recovered at runtime.
            fatalError("Unable to create an in-memory model container: \(error)")
        }
    }
}
