import Foundation
import SwiftData

/// Builds the app's SwiftData stack.
enum HoursModelContainer {
    /// Always the current version's schema. The older one is reachable through
    /// `HoursMigrationPlan`, which is what gets a store from there to here.
    static let schema = Schema(versionedSchema: HoursSchemaV2.self)

    static func make(inMemory: Bool = false, syncsWithICloud: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            // Local by default and by preference. Turning sync on is an
            // explicit choice, made once, and it is fixed for the life of the
            // container — which is why it is read before the store is opened
            // rather than watched.
            cloudKitDatabase: inMemory || !syncsWithICloud
                ? .none
                : .private(SyncPreference.containerIdentifier)
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: HoursMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// Opens a store at a specific file. Only the migration tests need this —
    /// everything else wants the one store in the usual place.
    static func make(at url: URL, syncsWithICloud: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        return try ModelContainer(
            for: schema,
            migrationPlan: HoursMigrationPlan.self,
            configurations: [configuration]
        )
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
