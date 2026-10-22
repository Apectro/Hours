#if DEBUG || CLOUDKIT_SCHEMA_TOOLS
import CoreData
import Foundation
import SwiftData

/// Creates the record types the store needs in the CloudKit container's
/// **Development** environment, so they can be deployed to Production.
///
/// TestFlight and App Store builds talk to the Production environment, where
/// a record type cannot be created on the fly: until the schema has been
/// deployed there, a syncing store opens but nothing it sends is accepted.
/// SwiftData has no call for this, so it goes through Core Data's
/// `initializeCloudKitSchema` on the same models — Apple's documented route
/// for SwiftData — and on a scratch store in the temporary directory, never
/// the person's own.
///
/// Compiled into Debug builds, started with the launch argument below from
/// Xcode, and into TestFlight builds made with the workflow's "CloudKit
/// development" switch, started from a button in Settings › iCloud. The
/// owner's steps are in README.md, *iCloud*.
enum CloudKitSchema {
    static let launchArgument = "-hours-initialize-cloudkit-schema"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }

    /// What the last attempt came to, in plain (English, developer-facing) words.
    private(set) static var outcome: String?

    static func initialize() {
        // Only a build that may use the container: anything else would be the
        // 1.0 crash again, from a developer tool.
        guard SyncPreference.entitlement == .present else {
            report("not initialised: this build is not signed for iCloud (" + SyncPreference.entitlement.rawValue + ").")
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cloudkit-schema-\(UUID().uuidString).store")
        do {
            // Released before the real stack opens, as Apple's sample does.
            try autoreleasepool {
                guard let model = NSManagedObjectModel.makeManagedObjectModel(for: HoursSchemaV6.models) else {
                    throw CocoaError(.featureUnsupported)
                }
                let description = NSPersistentStoreDescription(url: url)
                description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
                    containerIdentifier: SyncPreference.containerIdentifier
                )
                description.shouldAddStoreAsynchronously = false
                let container = NSPersistentCloudKitContainer(name: "ZeitkontoSchema", managedObjectModel: model)
                container.persistentStoreDescriptions = [description]
                var loadError: Error?
                container.loadPersistentStores { _, error in loadError = error }
                if let loadError { throw loadError }
                try container.initializeCloudKitSchema()
                for store in container.persistentStoreCoordinator.persistentStores {
                    try container.persistentStoreCoordinator.remove(store)
                }
            }
            report("initialised in the Development environment. Deploy it to Production in the CloudKit Console.")
        } catch {
            report("not initialised: " + String(describing: error))
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Developer-facing and English on purpose: this never ships to anyone
    /// but whoever is setting up the container, and it goes to the console.
    private static func report(_ text: String) {
        let line = "CloudKit schema " + text
        outcome = line
        print("[Zeitkonto] " + line)
    }
}
#endif
