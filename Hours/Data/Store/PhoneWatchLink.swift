import Foundation
import WatchConnectivity

/// The phone's end of the Apple Watch app.
///
/// The watch cannot read the App Group the widgets read — it is another
/// device — and it cannot open the store, so it is sent the widgets' own
/// snapshot as the application context every time the snapshot is written,
/// and it asks the phone to clock in or out. The phone obeys through the same
/// `TimeClock` as the clock card, Siri and the controls, then writes the
/// snapshot again, which sends it back.
///
/// Nothing leaves the person's own devices: WatchConnectivity talks to the
/// paired watch directly, with no account and no server in between.
///
/// What a command means — once only, at the time it was tapped, never a
/// clock-out older than the running clock — is `WatchCommandLedger`'s
/// decision, in the engine where it is tested.
///
/// Not tied to an actor: WatchConnectivity calls its delegate on a queue of
/// its own. Its state is only touched on the main actor, where the delegate
/// methods hop before doing anything.
final class PhoneWatchLink: NSObject, WCSessionDelegate {
    static let shared = PhoneWatchLink()

    private static let ledgerKey = "hours.watchCommandLedger"

    /// Main actor only.
    private var ledger: WatchCommandLedger
    /// The last context made, for the reply to a command. Main actor only.
    private var lastContext: Data?

    private override init() {
        ledger = Self.loadLedger()
        super.init()
    }

    /// Called as the app launches — including the launches iOS makes in the
    /// background to hand over a message from the watch, which never show a
    /// window — so a command is heard however the app was started. Does
    /// nothing on a phone that cannot pair a watch, or under UI tests.
    func activate() {
        guard WCSession.isSupported() else { return }
        guard !ProcessInfo.processInfo.arguments.contains("-hours-ui-testing") else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Sends the snapshot to the watch. Called from the snapshot writer, so
    /// the watch hears of every change the widgets hear of. A no-op without
    /// a paired watch that has the app installed.
    @MainActor
    func send(_ snapshot: WidgetSnapshot) {
        guard let data = WatchContext(snapshot: snapshot, handledCommandIDs: ledger.handledIDs).encoded() else { return }
        lastContext = data
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.delegate != nil, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        // Only the latest context is kept, which is what a snapshot wants.
        try? session.updateApplicationContext([WatchContext.key: data])
    }

    /// Obeys one command and writes the snapshot, which reloads the widgets
    /// and controls, brings the Live Activity in line and tells the watch.
    ///
    /// The Live Activity is started only when iOS allows it: a message from
    /// the watch wakes the app in the background, where starting one is
    /// refused, so a clock started from the wrist appears on the Lock Screen
    /// the next time the app comes forward (see `ClockActivityController`).
    @MainActor
    private func obey(_ command: WatchCommand) -> [String: Any] {
        let clock = HoursStack.timeClock
        switch ledger.decide(command, runningSince: clock.running?.startedAt, now: Date()) {
        case let .clockIn(instant):
            clock.clockIn(at: instant)
        case let .clockOut(instant):
            clock.clockOut(at: instant)
        case .ignore:
            break
        }
        saveLedger()
        HoursStack.refreshWidget()
        guard let lastContext else { return [:] }
        return [WatchContext.key: lastContext]
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.send(HoursStack.widgetWriter.snapshot()) }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// A different watch was paired: start again with it.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    /// The watch app was installed, or a watch paired: it has nothing yet.
    func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.send(HoursStack.widgetWriter.snapshot()) }
    }

    /// A tap made while the phone was in reach. The reply carries the fresh
    /// context, so the watch does not wait for the next one.
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[WatchCommand.key] as? Data, let command = WatchCommand(data: data) else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            replyHandler(self.obey(command))
        }
    }

    /// A tap queued while the phone was out of reach, delivered in order.
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let data = userInfo[WatchCommand.key] as? Data, let command = WatchCommand(data: data) else { return }
        Task { @MainActor in
            _ = self.obey(command)
        }
    }

    // MARK: - Storage

    private static func loadLedger() -> WatchCommandLedger {
        guard
            let data = UserDefaults.standard.data(forKey: ledgerKey),
            let ledger = try? JSONDecoder().decode(WatchCommandLedger.self, from: data)
        else { return WatchCommandLedger() }
        return ledger
    }

    private func saveLedger() {
        guard let data = try? JSONEncoder().encode(ledger) else { return }
        UserDefaults.standard.set(data, forKey: Self.ledgerKey)
    }
}
