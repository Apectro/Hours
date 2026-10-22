import Foundation

// What the phone and the Apple Watch say to each other.
//
// The watch cannot read the phone's App Group, and it cannot open the store,
// so it is told the same snapshot the widgets read and asks the phone to do
// anything that writes. WatchConnectivity carries property lists; both kinds
// of message travel as JSON `Data` under one key, so the shape of a message
// is decided here, where the tests reach it, rather than in two dictionaries
// spelled out by hand on two devices.

/// A tap on the watch's Clock in or Clock out button, for the phone to obey.
///
/// Sent at once while the phone is in reach and queued otherwise, so it may
/// arrive hours late or, when a reply goes missing and it is queued as well,
/// twice. `issuedAt` is when it was tapped, which is when the shift started
/// or ended however late the phone hears about it; `id` is what lets the
/// phone obey it only once.
struct WatchCommand: Codable, Hashable, Sendable, Identifiable {
    enum Kind: String, Codable, Hashable, Sendable {
        case clockIn
        case clockOut
    }

    var id: UUID
    var kind: Kind
    var issuedAt: Date

    init(id: UUID = UUID(), kind: Kind, issuedAt: Date) {
        self.id = id
        self.kind = kind
        self.issuedAt = issuedAt
    }

    /// The key the command travels under in a message or a queued transfer.
    static let key = "command"

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    init?(data: Data) {
        guard let command = try? JSONDecoder().decode(WatchCommand.self, from: data) else { return nil }
        self = command
    }

    /// How long the watch keeps showing a tap the phone has not answered.
    /// A day: long enough for a phone left at home over a shift, short enough
    /// that a phone that will never answer — the app deleted, the watch moved
    /// to another phone — does not leave a shift showing for ever.
    static let waitingLimit: TimeInterval = 24 * 3600

    /// The taps still waiting for the phone, in the order they were made:
    /// not the ones the phone reports it has seen, and not ones older than
    /// `waitingLimit`.
    static func stillWaiting(_ pending: [WatchCommand], handled: [UUID], now: Date) -> [WatchCommand] {
        let seen = Set(handled)
        return pending.filter { command in
            !seen.contains(command.id) && now.timeIntervalSince(command.issuedAt) <= waitingLimit
        }
    }
}

/// What the phone tells the watch: the widgets' snapshot, and which of the
/// watch's commands it has seen, so the watch can stop showing them as
/// waiting. Sent as the application context, which keeps only the latest —
/// exactly right for a snapshot.
struct WatchContext: Codable, Hashable, Sendable {
    var snapshot: WidgetSnapshot
    var handledCommandIDs: [UUID]

    init(snapshot: WidgetSnapshot, handledCommandIDs: [UUID]) {
        self.snapshot = snapshot
        self.handledCommandIDs = handledCommandIDs
    }

    static let key = "context"

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    init?(data: Data) {
        guard let context = try? JSONDecoder().decode(WatchContext.self, from: data) else { return nil }
        self = context
    }

    private enum CodingKeys: String, CodingKey {
        case snapshot, handledCommandIDs
    }

    /// Strict about the snapshot, which is the point, and lenient about the
    /// rest, so a phone and a watch on different versions still talk.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            snapshot: try container.decode(WidgetSnapshot.self, forKey: .snapshot),
            handledCommandIDs: container.lenient(.handledCommandIDs, [])
        )
    }
}

/// The phone's memory of the watch's commands, and its rule for obeying one.
///
/// Stored on the phone between launches: a duplicate can arrive after the
/// app was quit.
struct WatchCommandLedger: Codable, Hashable, Sendable {
    enum Decision: Hashable, Sendable {
        case clockIn(at: Date)
        case clockOut(at: Date)
        case ignore(Reason)
    }

    enum Reason: Hashable, Sendable {
        /// The same command, seen before.
        case alreadyHandled
        /// Clock in, with a clock already running — as the in-app button and
        /// Siri, a running shift is never replaced.
        case alreadyRunning
        case nothingRunning
        /// Clock out, tapped before the running clock started: it ended an
        /// earlier shift, which the phone has already ended.
        case predatesRunningClock
    }

    /// Enough for a week of shifts with a few repeats; a duplicate arrives
    /// within minutes of the original, not weeks.
    static let capacity = 32

    /// Every command seen, oldest first, ignored or obeyed.
    private(set) var handledIDs: [UUID] = []

    init() {}

    /// What to do with `command`, given the clock the phone has running now,
    /// and remembers it was seen.
    ///
    /// The time is the tap's, not the delivery's — two hours queued in a
    /// pocket were still worked — except that a watch whose clock runs a
    /// little ahead cannot start or stop a shift in the future.
    mutating func decide(_ command: WatchCommand, runningSince: Date?, now: Date) -> Decision {
        guard !handledIDs.contains(command.id) else { return .ignore(.alreadyHandled) }
        remember(command.id)

        let instant = min(command.issuedAt, now)
        switch command.kind {
        case .clockIn:
            guard runningSince == nil else { return .ignore(.alreadyRunning) }
            return .clockIn(at: instant)
        case .clockOut:
            guard let runningSince else { return .ignore(.nothingRunning) }
            guard instant >= runningSince else { return .ignore(.predatesRunningClock) }
            return .clockOut(at: instant)
        }
    }

    private mutating func remember(_ id: UUID) {
        handledIDs.append(id)
        if handledIDs.count > Self.capacity {
            handledIDs.removeFirst(handledIDs.count - Self.capacity)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case handledIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        handledIDs = container.lenient(.handledIDs, [])
    }
}
