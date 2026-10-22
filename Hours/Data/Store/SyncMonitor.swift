import CloudKit
import CoreData
import Foundation
import Observation

/// What the syncing store has been doing, for the launch mark, the duplicate
/// collapse and Settings › iCloud.
///
/// SwiftData mirrors through Core Data's CloudKit machinery, which reports
/// each setup, import and export as an `NSPersistentCloudKitContainer.Event`.
/// Started in the app's `init`, before the store is opened, so the first
/// setup is not missed.
@MainActor
@Observable
final class SyncMonitor {
    /// The iCloud account on this device, asked only while syncing — CloudKit
    /// is only ever touched once the store has proven the build may use it.
    enum Account: Equatable {
        case unknown
        case available
        case noAccount
        case restricted
        case temporarilyUnavailable
    }

    private(set) var account: Account = .unknown
    /// The last setup, import or export that failed, as the system words it.
    private(set) var lastError: String?
    /// When anything last came in or went out.
    private(set) var lastExchange: Date?

    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let started = Date()

    func start() {
        guard observer == nil, !HoursStack.isRunningUITests else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event else { return }
            Task { @MainActor in self?.handle(event) }
        }
        // If CloudKit never reports, surviving this long is proof enough:
        // the exception that killed 1.0 came within a second or two.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(SyncLaunch.provingTime))
            SyncLaunchMark.clear()
        }
    }

    /// Going to the background is also proof, once the launch is a few
    /// seconds old — and the last chance before the system may end the app.
    func appWentToBackground() {
        if Date().timeIntervalSince(started) > 3 { SyncLaunchMark.clear() }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        guard event.endDate != nil else { return }
        // Setup finished, well or badly, and the process is still here.
        if event.type == .setup { SyncLaunchMark.clear() }

        if event.succeeded {
            if event.type == .import || event.type == .export { lastExchange = event.endDate }
            lastError = nil
        } else if let error = event.error {
            lastError = error.localizedDescription
        }

        // Rows from another device are in: the moment to notice two rows
        // meaning the same Tuesday, rather than at the next return to the app.
        if event.type == .import, event.succeeded {
            HoursStack.repository.reconcileDuplicates()
            SiteRepository(context: HoursStack.container.mainContext).reconcileDuplicates()
            HoursStack.refreshWidget()
        }
    }

    func refreshAccount() async {
        guard HoursStack.isSyncing else { return }
        do {
            switch try await CKContainer(identifier: SyncPreference.containerIdentifier).accountStatus() {
            case .available: account = .available
            case .noAccount: account = .noAccount
            case .restricted: account = .restricted
            case .temporarilyUnavailable: account = .temporarilyUnavailable
            case .couldNotDetermine: account = .unknown
            @unknown default: account = .unknown
            }
        } catch {
            account = .unknown
        }
    }
}
