import Foundation
import SwiftData

/// Builds the app's SwiftData stack.
enum HoursModelContainer {
    /// Always the current version's schema. The older ones are reachable through
    /// `HoursMigrationPlan`, which is what gets a store from there to here.
    static let schema = Schema(versionedSchema: HoursSchemaV8.self)

    /// Synced or not, this is the same store file: the configuration's name,
    /// and so its URL, does not depend on `cloudKitDatabase`. That is what
    /// makes turning sync on mirror the months already recorded rather than
    /// start an empty store beside them — CloudKit mirroring exports every row
    /// a store holds the first time it is set up on it — and what makes
    /// turning it off keep everything. Only call this with `syncsWithICloud`
    /// as `SyncLaunch.plan` decides: a build not signed for iCloud that opens
    /// a syncing store is killed, not thrown at.
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
