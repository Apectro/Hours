import Foundation
import Observation
import WatchConnectivity
import WidgetKit

/// The watch's end of the link to the phone (see `PhoneWatchLink`).
///
/// The phone sends the widgets' snapshot as the application context whenever
/// it writes one; the watch keeps it, with the taps the phone has not
/// answered yet, in its own App Group for the complications. A tap is sent at
/// once while the phone is in reach and queued as a user-info transfer
/// otherwise — WatchConnectivity delivers those in order when the two meet
/// again — and until the phone answers, `WatchFace` shows what the tap did.
@MainActor
@Observable
final class WatchConnection {
    static let shared = WatchConnection()

    /// What the phone last sent; nil until it has sent anything.
    private(set) var context: WatchContext?
    /// Taps the phone has not reported back, oldest first.
    private(set) var pending: [WatchCommand]
    /// Whether the phone can be messaged right now.
    private(set) var isReachable = false

    @ObservationIgnored private var delegate: SessionDelegate?
    /// Showing `WatchSample` for the App Store screenshots, behind a launch
    /// argument only CI passes: no session, so nothing replaces it, and
    /// nothing is written to the App Group.
    private let isSample: Bool

    private init() {
        if let sample = WatchSample.context(
            arguments: ProcessInfo.processInfo.arguments,
            at: Date(),
            calendar: .current
        ) {
            isSample = true
            context = sample
            pending = []
            return
        }
        isSample = false
        context = WatchStore.readContext()
        pending = WatchCommand.stillWaiting(WatchStore.readPending(), handled: [], now: Date())
    }

    func activate() {
        guard !isSample, WCSession.isSupported(), delegate == nil else { return }
        let delegate = SessionDelegate(connection: self)
        self.delegate = delegate
        let session = WCSession.default
        session.delegate = delegate
        session.activate()
    }

    /// Clock in or Clock out, tapped on the watch.
    func tap(_ kind: WatchCommand.Kind) {
        guard !isSample else { return }
        let command = WatchCommand(kind: kind, issuedAt: Date())
        pending.append(command)
        savePending()
        send(command)
    }

    private func send(_ command: WatchCommand) {
        guard let data = command.encoded() else { return }
        let payload: [String: Any] = [WatchCommand.key: data]
        let session = WCSession.default
        // Before activation completes nothing can be sent; `activated`
        // sends whatever is still waiting.
        guard session.activationState == .activated else { return }

        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: { reply in
            guard let data = reply[WatchContext.key] as? Data, let context = WatchContext(data: data) else { return }
            Task { @MainActor in WatchConnection.shared.receive(context) }
        }, errorHandler: { _ in
            // Not delivered, or delivered with the reply lost. Queue it: the
            // phone obeys a command once, so a second copy changes nothing.
            WCSession.default.transferUserInfo(payload)
        })
    }

    // MARK: - From the delegate

    fileprivate func activated(_ session: WCSession) {
        isReachable = session.isReachable
        if let data = session.receivedApplicationContext[WatchContext.key] as? Data,
           let context = WatchContext(data: data) {
            receive(context)
        }
        // Taps made before activation, or queued transfers lost with a
        // reinstall: send again whatever is not already on its way.
        let onTheWay = Set(session.outstandingUserInfoTransfers.compactMap { transfer in
            (transfer.userInfo[WatchCommand.key] as? Data).flatMap(WatchCommand.init(data:))?.id
        })
        for command in pending where !onTheWay.contains(command.id) {
            send(command)
        }
    }

    fileprivate func reachabilityChanged(_ reachable: Bool) {
        isReachable = reachable
    }

    fileprivate func receive(_ context: WatchContext) {
        self.context = context
        pending = WatchCommand.stillWaiting(pending, handled: context.handledCommandIDs, now: Date())
        WatchStore.write(context)
        savePending()
    }

    private func savePending() {
        WatchStore.write(pending: pending)
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// WatchConnectivity's delegate, which it calls on a queue of its own; every
/// call hops to the main actor before touching the connection.
private final class SessionDelegate: NSObject, WCSessionDelegate {
    private let connection: WatchConnection

    init(connection: WatchConnection) {
        self.connection = connection
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.connection.activated(session) }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.connection.reachabilityChanged(reachable) }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext[WatchContext.key] as? Data, let context = WatchContext(data: data) else { return }
        Task { @MainActor in self.connection.receive(context) }
    }
}
