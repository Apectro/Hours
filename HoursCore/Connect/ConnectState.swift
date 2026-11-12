import Foundation

/// Everything the phone remembers about its connection, apart from the token
/// (Keychain) and the company's name and address (`ConnectAccount`): the
/// sync cursor, who is who, the upload queue, what each record was last
/// sent as, and what the office said back.
///
/// Kept in a file of its own on this device: not in the settings that
/// iCloud carries to the user's other devices, not in the backup file, not
/// in the SwiftData store. Each phone sends its own queue, under its own
/// token; a second device of the same person pairs on its own.
struct ConnectState: Codable, Hashable, Sendable {
    /// The last cursor `GET /v1/device/sync` gave, once everything in its
    /// page was applied. Nil: the next sync is a full snapshot.
    var cursor: String?
    var people = ConnectPeople()
    /// What each record was last queued as, by `ConnectRecordKey`.
    var marks: [String: ConnectRecordMark] = [:]
    /// What is waiting to be sent, oldest first.
    var queue: [ConnectQueueEntry] = []
    /// Files already uploaded (or already there), by file id.
    var uploadedFiles: Set<String> = []
    /// Sites the company owns (they came from the web), and sites made on
    /// this phone that its user chose to send.
    var companySites: Set<UUID> = []
    var sharedSites: Set<UUID> = []
    /// The office's copy of each web site, as last received: applied again
    /// at every sync, so a local rename of a web site lasts until then.
    var siteCopies: [UUID: ConnectV1.Site] = [:]
    /// Who is on which site, by assignment id, as the web said.
    var assignments: [String: ConnectAssignmentMark] = [:]
    /// What a full snapshot has delivered so far, while its pages come in;
    /// what it did not deliver is gone from the web once the last arrives.
    var snapshot: ConnectSnapshotSeen?
    /// Comments meant for this phone, by id.
    var comments: [String: ConnectV1.Comment] = [:]
    var readComments: Set<String> = []
    /// What the office did with what this phone sent, by record key.
    var reviews: [String: ConnectReview] = [:]
    /// Records the office changed since the phone last saw them, kept until
    /// the phone sends a newer version.
    var conflicts: [String: ConnectConflict] = [:]
    /// The last few records the server refused, for the log.
    var rejections: [ConnectRejection] = []
    /// What the last sync could not apply because a month is closed.
    var lockedConflicts: [ConnectMergeConflict] = []
    var backoff = ConnectBackoff()
    var lastSyncedAt: Date?
    var lastSentAt: Date?
    /// The server's limits, from pairing.
    var limits = ConnectV1.Limits.standard

    init() {}

    /// Everything about the connection forgotten, as Disconnect does; the
    /// data on the phone stays.
    static let disconnected = ConnectState()

    var waitingCount: Int { queue.count }

    // MARK: - Coding

    private enum CodingKeys: String, CodingKey {
        case cursor, people, marks, queue, uploadedFiles, companySites, sharedSites, siteCopies, assignments, snapshot
        case comments, readComments, reviews, conflicts, rejections, lockedConflicts, backoff
        case lastSyncedAt, lastSentAt, limits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = container.lenientOptional(.cursor)
        people = container.lenient(.people, ConnectPeople())
        marks = container.lenient(.marks, [:])
        queue = container.lenient(.queue, [])
        uploadedFiles = container.lenient(.uploadedFiles, [])
        companySites = container.lenient(.companySites, [])
        sharedSites = container.lenient(.sharedSites, [])
        siteCopies = container.lenient(.siteCopies, [:])
        assignments = container.lenient(.assignments, [:])
        snapshot = container.lenientOptional(.snapshot)
        comments = container.lenient(.comments, [:])
        readComments = container.lenient(.readComments, [])
        reviews = container.lenient(.reviews, [:])
        conflicts = container.lenient(.conflicts, [:])
        rejections = container.lenient(.rejections, [])
        lockedConflicts = container.lenient(.lockedConflicts, [])
        backoff = container.lenient(.backoff, ConnectBackoff())
        lastSyncedAt = container.lenientOptional(.lastSyncedAt)
        lastSentAt = container.lenientOptional(.lastSentAt)
        limits = container.lenient(.limits, .standard)
    }
}

/// An assignment from the web: a person on a site, and the crew row that
/// stands for them there.
struct ConnectAssignmentMark: Codable, Hashable, Sendable {
    var siteID: UUID
    var personID: UUID
    var rowID: UUID?
}

/// The ids a full snapshot has delivered so far.
struct ConnectSnapshotSeen: Codable, Hashable, Sendable {
    var sites: Set<UUID> = []
    var people: Set<UUID> = []
    var assignments: Set<String> = []
}

/// A record's key in the queue and the marks: its kind and its id, lower case.
enum ConnectRecordKey {
    static func make(_ kind: ConnectV1.RecordKind, _ id: String) -> String {
        kind.rawValue + ":" + id.lowercased()
    }
}

/// What a record was last queued as.
struct ConnectRecordMark: Codable, Hashable, Sendable {
    /// The phone's version, raised on every change that is queued.
    var version: Int
    /// The server's version as last seen: from an accepted result, a stale
    /// or conflicting copy, or a review. 0 when never seen.
    var baseVersion: Int
    /// The content as last queued, so the same content is never queued twice.
    var hash: String
    var deleted: Bool = false
    /// The site it belongs to, and the sites a sheet covers.
    var siteIDs: [UUID] = []
    /// The month it is part of, for a dated record.
    var month: YearMonth?
}

/// One record waiting to go.
struct ConnectQueueEntry: Codable, Hashable, Sendable {
    var kind: ConnectV1.RecordKind
    var id: String
    var version: Int
    var baseVersion: Int
    var deleted: Bool
    var data: JSONValue?
    /// The files the record refers to, uploaded before it.
    var files: [ConnectFileNeed]
    var queuedAt: Date

    var key: String { ConnectRecordKey.make(kind, id) }

    var uploadRecord: ConnectV1.UploadRecord {
        ConnectV1.UploadRecord(kind: kind, id: id, version: version, baseVersion: baseVersion, deleted: deleted, data: deleted ? nil : data)
    }
}

/// A file a record refers to, and where the app finds its bytes.
struct ConnectFileNeed: Codable, Hashable, Sendable {
    var fileId: String
    var purpose: ConnectV1.FilePurpose
    var contentType: String
    var byteSize: Int
    var name: String?
    var source: ConnectFileSource

    var ref: ConnectV1.FileRef {
        ConnectV1.FileRef(fileId: fileId, contentType: contentType, byteSize: max(1, byteSize), sha256: nil, name: name)
    }
}

/// Where a file's bytes are on the phone. The engine never holds them; the
/// app reads them when the file is uploaded.
enum ConnectFileSource: Codable, Hashable, Sendable {
    case diaryPhoto(UUID)
    case extraWorkPhoto(UUID)
    case defectPhoto(UUID)
    case deliveryPhoto(UUID)
    /// The client's signature on a job, drawn as a PNG.
    case extraWorkSignature(UUID)
    /// A file the app wrote into its Connect folder (a sheet's PDF), by name.
    case stored(String)
}

/// The office's verdict on something this phone sent.
struct ConnectReview: Codable, Hashable, Sendable {
    var kind: ConnectV1.RecordKind
    var id: String
    var version: Int
    var state: String
    var changedAt: String
    var commentIDs: [String]
}

/// The office changed a record since the phone last saw it.
struct ConnectConflict: Codable, Hashable, Sendable {
    var kind: ConnectV1.RecordKind
    var id: String
    /// returned, editedOnWeb, locked.
    var reason: String
    var serverVersion: Int
    var server: JSONValue?
    var commentIDs: [String]
}

struct ConnectRejection: Codable, Hashable, Sendable {
    var kind: ConnectV1.RecordKind
    var id: String
    var reason: String
    var message: String
    var at: Date
}

/// Who is who: the paired person, and which company-wide person each of
/// the app's per-site crew rows is.
///
/// The app keeps a crew per site (`CrewMember`, one row per site and
/// person). The company keeps each person once. A row is linked to its
/// person by the id sync delivered once it is known, else by name the way
/// `CrewCandidates.key` joins crews (case, accents and spacing aside), and a
/// row nobody on the web matches is a person of its own, whose id is the
/// row's — sent as a `crewMember` so the office sees them at once. The same
/// name on two sites is one person.
struct ConnectPeople: Codable, Hashable, Sendable {
    /// The paired person: who the app's fixed "You" is on this phone.
    var you: UUID?
    /// "You" was made on this phone because the office paired it without
    /// choosing a person; sent as a `crewMember` like anyone added here.
    var youIsLocal = false
    /// A crew row's person.
    var rows: [UUID: UUID] = [:]
    /// The company's people as last received, by id.
    var company: [UUID: ConnectPerson] = [:]

    struct ConnectPerson: Codable, Hashable, Sendable {
        var name: String
        var hidden: Bool
    }

    /// The id to send for an id the app uses in a day: "You" becomes the
    /// paired person, a crew row becomes its person. Nil for a row not
    /// linked yet, and for "You" on a phone with no person.
    func outgoing(_ memberID: UUID) -> UUID? {
        if memberID == CrewMember.youID { return you }
        return rows[memberID]
    }

    /// Links every row not linked yet: by name to the company's people
    /// first, then to a row of the same name on another site, else to
    /// itself. Rows already linked keep their person.
    func linking(_ crew: [CrewMember]) -> ConnectPeople {
        var people = self
        var byName: [String: UUID] = [:]
        for (id, person) in company.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            let key = CrewCandidates.key(for: person.name)
            if !key.isEmpty, byName[key] == nil { byName[key] = id }
        }
        let ordered = crew.sorted { ($0.id.uuidString) < ($1.id.uuidString) }
        for row in ordered {
            guard let person = people.rows[row.id] else { continue }
            let key = CrewCandidates.key(for: row.name)
            if !key.isEmpty, byName[key] == nil { byName[key] = person }
        }
        for row in ordered where people.rows[row.id] == nil {
            let key = CrewCandidates.key(for: row.name)
            if !key.isEmpty, let person = byName[key], person != you {
                people.rows[row.id] = person
            } else {
                people.rows[row.id] = row.id
                if !key.isEmpty { byName[key] = row.id }
            }
        }
        return people
    }

    /// Whether the person came from the web (and so is not sent back).
    func isCompanyPerson(_ id: UUID) -> Bool { company[id] != nil }
}

/// When to try again after a failure: from 5 seconds, doubling, to 15
/// minutes, with jitter; never sooner than the server's Retry-After.
struct ConnectBackoff: Codable, Hashable, Sendable {
    var failures = 0
    var notBefore: Date?

    static let first: TimeInterval = 5
    static let longest: TimeInterval = 15 * 60

    /// The wait after `failures` failures in a row, before jitter.
    static func delay(afterFailures failures: Int) -> TimeInterval {
        guard failures > 0 else { return 0 }
        let doubled = first * pow(2, Double(min(failures - 1, 20)))
        return min(longest, doubled)
    }

    /// One more failure. `jitter` is 0…1 (random in the app, fixed in the
    /// tests) and moves the wait by up to a fifth either way.
    mutating func failed(at now: Date, retryAfter: TimeInterval? = nil, jitter: Double) -> TimeInterval {
        failures += 1
        let base = Self.delay(afterFailures: failures)
        let spread = base * 0.2 * (min(max(jitter, 0), 1) * 2 - 1)
        let wait = max(min(Self.longest, base + spread), retryAfter ?? 0)
        notBefore = now.addingTimeInterval(wait)
        return wait
    }

    mutating func succeeded() {
        failures = 0
        notBefore = nil
    }

    func allows(at now: Date) -> Bool {
        guard let notBefore else { return true }
        return now >= notBefore
    }
}
