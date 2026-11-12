import Foundation

/// The Connect protocol, v1, as the app reads and writes it: the wire types
/// of `packages/protocol/src/v1` in the Connect repository, field for field.
///
/// Dates (`YYYY-MM-DD`), months (`YYYY-MM`), times (`HH:MM`), moments
/// (ISO 8601) and quantities ("45.5") stay strings here, exactly as they
/// travel; `ConnectMapping` turns them into the app's own types. Ids are
/// strings too, because the server answers in lower case and the app's
/// UUIDs print in upper case: compare them through `ConnectID`.
///
/// Everything decodes leniently (see `ConnectCoding`), so a field a newer
/// server adds is ignored and a word this version does not know is kept.
enum ConnectV1 {
    static let apiVersion = 1

    // MARK: - Words

    struct RecordKind: ConnectWord {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        static let site: Self = "site"
        static let crewMember: Self = "crewMember"
        static let assignment: Self = "assignment"
        static let siteDay: Self = "siteDay"
        static let sheet: Self = "sheet"
        static let signOff: Self = "signOff"
        static let extraWork: Self = "extraWork"
        static let defect: Self = "defect"
        static let missingItem: Self = "missingItem"
        static let delivery: Self = "delivery"
        static let comment: Self = "comment"

        /// Sites, crew and assignments go first in a batch, so a site day can
        /// name a site created in the same batch.
        var sendsFirst: Bool { self == .site || self == .crewMember || self == .assignment }
    }

    struct UploadStatus: ConnectWord {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        static let accepted: Self = "accepted"
        static let stale: Self = "stale"
        static let conflict: Self = "conflict"
        static let rejected: Self = "rejected"
    }

    struct ErrorCode: ConnectWord {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        static let badRequest: Self = "bad_request"
        static let validationFailed: Self = "validation_failed"
        static let unauthorized: Self = "unauthorized"
        static let deviceRevoked: Self = "device_revoked"
        static let forbidden: Self = "forbidden"
        static let notFound: Self = "not_found"
        static let methodNotAllowed: Self = "method_not_allowed"
        static let conflict: Self = "conflict"
        static let pairingCodeInvalid: Self = "pairing_code_invalid"
        static let pairingCodeExpired: Self = "pairing_code_expired"
        static let pairingCodeUsed: Self = "pairing_code_used"
        static let rateLimited: Self = "rate_limited"
        static let payloadTooLarge: Self = "payload_too_large"
        static let unsupportedMediaType: Self = "unsupported_media_type"
        static let `internal`: Self = "internal"
    }

    struct CrewRole: ConnectWord {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        static let worker: Self = "worker"
        static let teamLeader: Self = "teamLeader"
    }

    struct FilePurpose: ConnectWord {
        let rawValue: String
        init(rawValue: String) { self.rawValue = rawValue }

        static let sheetPdf: Self = "sheetPdf"
        static let sheetXlsx: Self = "sheetXlsx"
        static let sheetCsv: Self = "sheetCsv"
        static let photo: Self = "photo"
        static let signature: Self = "signature"
        static let deliveryPhoto: Self = "deliveryPhoto"
        static let other: Self = "other"
    }

    // MARK: - Building blocks

    struct FileRef: Codable, Hashable, Sendable {
        var fileId: String
        var contentType: String
        var byteSize: Int
        var sha256: String?
        var name: String?
    }

    struct Point: Codable, Hashable, Sendable {
        var x: Double
        var y: Double
    }

    struct Limits: Codable, Hashable, Sendable {
        var maxBatch: Int
        var maxFileBytes: Int
        var maxRequestBytes: Int

        static let standard = Limits(maxBatch: 200, maxFileBytes: 25_000_000, maxRequestBytes: 4_000_000)
    }

    // MARK: - What the director owns

    struct Company: Codable, Hashable, Sendable {
        var id: String
        var name: String
        var timeZone: String
        var breaksPaid: Bool
        var rounding: String
        var createdAt: String?
        var updatedAt: String?
    }

    struct CompanyPatch: Codable, Hashable, Sendable {
        var name: String?
        var timeZone: String?
        var breaksPaid: Bool?
        var rounding: String?
    }

    struct CompanyResponse: Codable, Hashable, Sendable {
        var company: Company
    }

    struct UsualDay: Codable, Hashable, Sendable {
        var start: String
        var end: String
        var breakMinutes: Int
    }

    struct SitePause: Codable, Hashable, Sendable {
        var start: String
        var end: String?
    }

    struct Site: Codable, Hashable, Sendable {
        var id: String
        var name: String
        @Defaulted<ConnectDefaults.Empty> var address: String = ""
        var timeZone: String?
        @Defaulted<ConnectDefaults.NoInts> var workDays: [Int] = []
        var usualDay: UsualDay?
        var pause: SitePause?
        @Defaulted<ConnectDefaults.False> var archived: Bool = false
        @Defaulted<ConnectDefaults.False> var allowanceByDefault: Bool = false
        var jobNumber: String?
        var version: Int
        var origin: String
        var updatedAt: String
    }

    /// A site as the phone sends one it made (and as a director creates one).
    struct SiteInput: Codable, Hashable, Sendable {
        var id: String?
        var name: String
        @Defaulted<ConnectDefaults.Empty> var address: String = ""
        var timeZone: String?
        @Defaulted<ConnectDefaults.NoInts> var workDays: [Int] = []
        var usualDay: UsualDay?
        var pause: SitePause?
        @Defaulted<ConnectDefaults.False> var archived: Bool = false
        @Defaulted<ConnectDefaults.False> var allowanceByDefault: Bool = false
        var jobNumber: String?
    }

    struct SitePatch: Codable, Hashable, Sendable {
        var name: String?
        var address: String?
        var timeZone: String?
        var workDays: [Int]?
        var usualDay: UsualDay?
        var pause: SitePause?
        var archived: Bool?
        var allowanceByDefault: Bool?
        var jobNumber: String?
    }

    struct CrewMember: Codable, Hashable, Sendable {
        var id: String
        var name: String
        @Defaulted<ConnectDefaults.Worker> var role: CrewRole = .worker
        @Defaulted<ConnectDefaults.False> var hidden: Bool = false
        var personnelNumber: String?
        var version: Int
        var origin: String
        var updatedAt: String
    }

    struct CrewMemberInput: Codable, Hashable, Sendable {
        var id: String?
        var name: String
        @Defaulted<ConnectDefaults.Worker> var role: CrewRole = .worker
        @Defaulted<ConnectDefaults.False> var hidden: Bool = false
        var personnelNumber: String?
    }

    struct CrewMemberPatch: Codable, Hashable, Sendable {
        var name: String?
        var role: CrewRole?
        var hidden: Bool?
        var personnelNumber: String?
    }

    struct Assignment: Codable, Hashable, Sendable {
        var id: String
        var siteId: String
        var memberId: String
        var from: String?
        var to: String?
        @Defaulted<ConnectDefaults.Worker> var role: CrewRole = .worker
        var version: Int
        var origin: String
        var updatedAt: String
    }

    struct AssignmentInput: Codable, Hashable, Sendable {
        var id: String?
        var siteId: String
        var memberId: String
        var from: String?
        var to: String?
        @Defaulted<ConnectDefaults.Worker> var role: CrewRole = .worker
    }

    struct AssignmentPatch: Codable, Hashable, Sendable {
        var from: String?
        var to: String?
        var role: CrewRole?
    }

    // MARK: - Pairing and the device

    struct DeviceInfo: Codable, Hashable, Sendable {
        var name: String
        var model: String?
        @Defaulted<ConnectDefaults.IOS> var platform: String = "ios"
        var osVersion: String?
        var appVersion: String
        var appBuild: String?
    }

    struct Device: Codable, Hashable, Sendable {
        var id: String
        var name: String
        var model: String?
        var platform: String
        var appVersion: String?
        var crewMemberId: String?
        var label: String?
        var pairedAt: String
        var lastSeenAt: String?
        var revokedAt: String?
    }

    /// What the QR code on the director's page holds.
    struct PairingQr: Codable, Hashable, Sendable {
        var v: Int
        var url: String
        var code: String
    }

    struct PairRequest: Codable, Hashable, Sendable {
        var code: String
        var device: DeviceInfo
    }

    struct CompanySummary: Codable, Hashable, Sendable {
        var id: String
        var name: String
        var timeZone: String
        var breaksPaid: Bool
        var rounding: String
    }

    struct PairResponse: Codable, Hashable, Sendable {
        var apiVersion: Int
        var token: String
        var device: Device
        var company: CompanySummary
        var member: CrewMember?
        var limits: Limits
    }

    struct MeResponse: Codable, Hashable, Sendable {
        var apiVersion: Int
        var device: Device
        var company: CompanySummary
        var member: CrewMember?
        var limits: Limits
    }

    struct OkResponse: Codable, Hashable, Sendable {
        var ok: Bool
    }

    // MARK: - Sync

    struct Review: Codable, Hashable, Sendable {
        var kind: RecordKind
        var id: String
        var version: Int
        /// sheet: submitted, approved, returned, replaced; defect: open,
        /// fixed; missingItem: needed, ordered, arrived; others: new,
        /// acknowledged, archived.
        var state: String
        var changedAt: String
        @Defaulted<ConnectDefaults.NoStrings> var commentIds: [String] = []
    }

    struct Tombstone: Codable, Hashable, Sendable {
        var kind: RecordKind
        var id: String
        var deletedAt: String
    }

    struct SyncResponse: Codable, Hashable, Sendable {
        var cursor: String
        var hasMore: Bool
        var full: Bool
        var serverTime: String
        var company: CompanySummary
        @Defaulted<ConnectDefaults.None<Site>> var sites: [Site] = []
        @Defaulted<ConnectDefaults.None<CrewMember>> var crew: [CrewMember] = []
        @Defaulted<ConnectDefaults.None<Assignment>> var assignments: [Assignment] = []
        @Defaulted<ConnectDefaults.None<Comment>> var comments: [Comment] = []
        @Defaulted<ConnectDefaults.None<Review>> var reviews: [Review] = []
        @Defaulted<ConnectDefaults.None<Tombstone>> var tombstones: [Tombstone] = []
    }

    // MARK: - Upload

    /// One record of a batch. `data` is the record by its kind's schema, kept
    /// as JSON so one envelope carries every kind.
    struct UploadRecord: Codable, Hashable, Sendable {
        var kind: RecordKind
        var id: String
        var version: Int
        var baseVersion: Int?
        @Defaulted<ConnectDefaults.False> var deleted: Bool = false
        var data: JSONValue?

        /// The record's data as its own type, for a kind whose type is known.
        func decodedData<T: Decodable>(as type: T.Type) throws -> T? {
            guard let data else { return nil }
            return try ConnectJSON.decode(T.self, from: ConnectJSON.encode(data))
        }
    }

    struct UploadRequest: Codable, Hashable, Sendable {
        var records: [UploadRecord]
    }

    struct UploadError: Codable, Hashable, Sendable {
        var code: String
        var message: String
        var details: JSONValue?
    }

    struct UploadResult: Codable, Hashable, Sendable {
        var kind: RecordKind
        var id: String
        var status: UploadStatus
        var version: Int
        var duplicate: Bool?
        /// locked, returned, editedOnWeb, newer, directorOwned, unknownSite…
        var reason: String?
        var server: JSONValue?
        var comments: [Comment]?
        var error: UploadError?
    }

    struct UploadResponse: Codable, Hashable, Sendable {
        var results: [UploadResult]
    }

    // MARK: - Files

    struct FileUploadRequest: Codable, Hashable, Sendable {
        var fileId: String
        var purpose: FilePurpose
        var contentType: String
        var byteSize: Int
        var sha256: String?
        var name: String?
    }

    struct FileUploadResponse: Codable, Hashable, Sendable {
        var fileId: String
        var path: String
        var uploadUrl: String
        var uploadToken: String
        var expiresAt: String
        var alreadyUploaded: Bool
    }

    struct FileDownloadResponse: Codable, Hashable, Sendable {
        var fileId: String
        var url: String
        var expiresAt: String
        var contentType: String
    }

    // MARK: - Errors

    struct ErrorBody: Codable, Hashable, Sendable {
        var code: ErrorCode
        var message: String
        var details: JSONValue?
        var requestId: String?
    }

    struct ErrorResponse: Codable, Hashable, Sendable {
        var error: ErrorBody
    }

    // MARK: - Records: the site day

    struct Attendance: Codable, Hashable, Sendable {
        var memberId: String
        var start: String?
        var end: String?
        var breakMinutes: Int?
    }

    struct AbsenceReason: Codable, Hashable, Sendable {
        /// "dayType" or "otherSite".
        var type: String
        var dayType: String?
        var siteId: String?
    }

    struct Absence: Codable, Hashable, Sendable {
        var memberId: String
        var reason: AbsenceReason
    }

    struct SiteMove: Codable, Hashable, Sendable {
        var id: String
        var toSiteId: String
        var left: String
        var started: String
        @Defaulted<ConnectDefaults.Here> var breakPlacement: String = "here"
        var memberIds: [String]
    }

    struct SiteDiary: Codable, Hashable, Sendable {
        var weather: String?
        var temperatureCelsius: Int?
        @Defaulted<ConnectDefaults.Empty> var workDone: String = ""
        @Defaulted<ConnectDefaults.Empty> var deliveries: String = ""
        @Defaulted<ConnectDefaults.Empty> var problems: String = ""
        @Defaulted<ConnectDefaults.Empty> var visitors: String = ""
        @Defaulted<ConnectDefaults.None<FileRef>> var photos: [FileRef] = []
    }

    struct SiteDay: Codable, Hashable, Sendable {
        var id: String
        var siteId: String
        var date: String
        var start: String?
        var end: String?
        @Defaulted<ConnectDefaults.Zero> var breakMinutes: Int = 0
        @Defaulted<ConnectDefaults.None<Attendance>> var attendance: [Attendance] = []
        @Defaulted<ConnectDefaults.None<Absence>> var absences: [Absence] = []
        var noWork: String?
        @Defaulted<ConnectDefaults.False> var badWeatherStop: Bool = false
        @Defaulted<ConnectDefaults.Empty> var note: String = ""
        @Defaulted<ConnectDefaults.NoStrings> var allowanceMemberIds: [String] = []
        @Defaulted<ConnectDefaults.Zero> var kilometres: Int = 0
        @Defaulted<ConnectDefaults.None<SiteMove>> var moves: [SiteMove] = []
        var diary: SiteDiary?
        var writtenBy: String?
        var updatedAt: String
    }

    // MARK: - Records: the month sheet

    struct SheetDay: Codable, Hashable, Sendable {
        var date: String
        var siteId: String?
        var start: String?
        var end: String?
        var breakMinutes: Int?
        var workedMinutes: Int
        var dayType: String?
        @Defaulted<ConnectDefaults.Empty> var note: String = ""
        @Defaulted<ConnectDefaults.False> var allowance: Bool = false
    }

    struct SheetPerson: Codable, Hashable, Sendable {
        var memberId: String
        var name: String
        var workedMinutes: Int
        var daysWorked: Int
        @Defaulted<ConnectDefaults.NoCounts> var dayTypes: [String: Double] = [:]
        @Defaulted<ConnectDefaults.Zero> var allowanceDays: Int = 0
        @Defaulted<ConnectDefaults.None<SheetDay>> var days: [SheetDay] = []
    }

    struct SheetSite: Codable, Hashable, Sendable {
        var siteId: String
        var name: String
        @Defaulted<ConnectDefaults.Empty> var address: String = ""
        var workedMinutes: Int
        @Defaulted<ConnectDefaults.Zero> var kilometres: Int = 0
    }

    struct SheetHoliday: Codable, Hashable, Sendable {
        var date: String
        var name: String
    }

    struct SheetTotals: Codable, Hashable, Sendable {
        var workedMinutes: Int
        var people: Int
        @Defaulted<ConnectDefaults.NoCounts> var dayTypes: [String: Double] = [:]
        @Defaulted<ConnectDefaults.Zero> var allowanceDays: Int = 0
        @Defaulted<ConnectDefaults.Zero> var kilometres: Int = 0
    }

    struct SheetRules: Codable, Hashable, Sendable {
        var breaksPaid: Bool
        var rounding: String
    }

    struct SentBy: Codable, Hashable, Sendable {
        var memberId: String?
        var name: String
    }

    struct MonthSheet: Codable, Hashable, Sendable {
        var id: String
        var month: String
        var title: String
        var siteIds: [String]
        var sites: [SheetSite]
        var people: [SheetPerson]
        @Defaulted<ConnectDefaults.None<SheetHoliday>> var holidays: [SheetHoliday] = []
        var totals: SheetTotals
        var rules: SheetRules
        var pdf: FileRef?
        @Defaulted<ConnectDefaults.None<FileRef>> var attachments: [FileRef] = []
        var sentBy: SentBy
        var sentAt: String
        var replacesSheetId: String?
    }

    // MARK: - Records: sign-off, extra work, defects, Missing, deliveries

    struct SignOff: Codable, Hashable, Sendable {
        var id: String
        var siteId: String
        var memberId: String
        var month: String
        var signedOn: String
        var fingerprint: String
        @Defaulted<ConnectDefaults.None<[Point]>> var strokes: [[Point]] = []
        @Defaulted<ConnectDefaults.Three> var aspectRatio: Double = 3
        var image: FileRef?
        @Defaulted<ConnectDefaults.False> var revoked: Bool = false
    }

    struct ExtraWorkMaterial: Codable, Hashable, Sendable {
        var name: String
        var quantity: String
        var unit: String
        @Defaulted<ConnectDefaults.NoStrings> var codes: [String] = []
    }

    struct ExtraWorkHours: Codable, Hashable, Sendable {
        var memberId: String?
        var name: String
        var minutes: Int
    }

    struct ClientSignature: Codable, Hashable, Sendable {
        var signerName: String
        var signedAt: String
        var image: FileRef
    }

    struct ExtraWork: Codable, Hashable, Sendable {
        var id: String
        var siteId: String
        var date: String
        var description: String
        @Defaulted<ConnectDefaults.None<ExtraWorkMaterial>> var materials: [ExtraWorkMaterial] = []
        @Defaulted<ConnectDefaults.None<ExtraWorkHours>> var hours: [ExtraWorkHours] = []
        @Defaulted<ConnectDefaults.None<FileRef>> var photos: [FileRef] = []
        var clientSignature: ClientSignature?
        @Defaulted<ConnectDefaults.False> var done: Bool = false
        var doneAt: String?
        var createdAt: String
        var updatedAt: String
    }

    struct DefectMark: Codable, Hashable, Sendable {
        var kind: String
        @Defaulted<ConnectDefaults.Red> var colour: String = "red"
        var points: [Point]
    }

    struct DefectPhoto: Codable, Hashable, Sendable {
        var file: FileRef
        @Defaulted<ConnectDefaults.None<DefectMark>> var marks: [DefectMark] = []
    }

    struct DefectAssignee: Codable, Hashable, Sendable {
        /// nobody, you, person.
        var kind: String
        @Defaulted<ConnectDefaults.Empty> var name: String = ""
    }

    struct Defect: Codable, Hashable, Sendable {
        var id: String
        var siteId: String
        var what: String
        @Defaulted<ConnectDefaults.Empty> var floor: String = ""
        @Defaulted<ConnectDefaults.Empty> var room: String = ""
        @Defaulted<ConnectDefaults.NoOne> var assignee: DefectAssignee = DefectAssignee(kind: "nobody", name: "")
        @Defaulted<ConnectDefaults.Empty> var notedBy: String = ""
        var notedAt: String
        var state: String
        var fixedAt: String?
        @Defaulted<ConnectDefaults.None<DefectPhoto>> var photos: [DefectPhoto] = []
        var updatedAt: String
    }

    struct MissingItem: Codable, Hashable, Sendable {
        var id: String
        var siteId: String
        var name: String
        var quantity: String
        var unit: String
        @Defaulted<ConnectDefaults.NoStrings> var codes: [String] = []
        @Defaulted<ConnectDefaults.Empty> var note: String = ""
        @Defaulted<ConnectDefaults.Empty> var notedBy: String = ""
        var notedAt: String
        var state: String
        var orderedAt: String?
        var arrivedAt: String?
        var updatedAt: String
    }

    struct DeliveryLine: Codable, Hashable, Sendable {
        /// arrived, short, extra.
        var kind: String
        var name: String
        var unit: String
        var came: String
        var ordered: String
        var missingItemId: String?
    }

    struct Delivery: Codable, Hashable, Sendable {
        var id: String
        var siteId: String
        var receivedAt: String
        var lines: [DeliveryLine]
        var photo: FileRef?
        var updatedAt: String
    }

    struct CommentTarget: Codable, Hashable, Sendable {
        var kind: RecordKind
        var id: String
    }

    struct CommentAuthor: Codable, Hashable, Sendable {
        /// director or device.
        var kind: String
        var name: String
        var memberId: String?
    }

    struct Comment: Codable, Hashable, Sendable {
        var id: String
        var target: CommentTarget
        var body: String
        /// note, or return: sent back to be corrected.
        @Defaulted<ConnectDefaults.Note> var purpose: String = "note"
        var author: CommentAuthor
        var createdAt: String
    }

    // MARK: - The director's side
    //
    // The app never calls these; they are here so the app's tests decode
    // every fixture the protocol publishes, and a change to one is noticed.

    struct ListOf<Item: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        var items: [Item]
    }

    struct OfficeView<Record: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
        var id: String
        var version: Int
        var state: String
        var receivedAt: String
        var updatedAt: String
        var deviceId: String?
        var data: Record
    }

    struct Sheet: Codable, Hashable, Sendable {
        var id: String
        var version: Int
        var status: String
        var receivedAt: String
        var reviewedAt: String?
        var reviewedBy: String?
        var deviceId: String?
        var data: MonthSheet
    }

    struct SheetSummary: Codable, Hashable, Sendable {
        var id: String
        var version: Int
        var status: String
        var month: String
        var title: String
        var siteIds: [String]
        var people: Int
        var workedMinutes: Int
        var sentBy: String
        var sentAt: String
        var receivedAt: String
        var hasPdf: Bool
        var pdfFileId: String?
    }

    struct ReturnRequest: Codable, Hashable, Sendable {
        var comment: String
    }

    struct CommentRequest: Codable, Hashable, Sendable {
        var target: CommentTarget
        var body: String
    }

    struct CommentResponse: Codable, Hashable, Sendable {
        var comment: Comment
    }

    struct StatePatch: Codable, Hashable, Sendable {
        var state: String
    }

    struct PairingCodeRequest: Codable, Hashable, Sendable {
        var crewMemberId: String?
        var label: String?
        var ttlMinutes: Int?
    }

    struct PairingCodeResponse: Codable, Hashable, Sendable {
        var id: String
        var code: String
        var expiresAt: String
        var qr: PairingQr
        var qrText: String
    }

    struct PairingCodeSummary: Codable, Hashable, Sendable {
        var id: String
        var label: String?
        var crewMemberId: String?
        var createdAt: String
        var expiresAt: String
        var usedAt: String?
        var revokedAt: String?
        var deviceId: String?
    }

    struct SiteMinutes: Codable, Hashable, Sendable {
        var siteId: String
        var workedMinutes: Int
        var days: Int
    }

    struct PersonHours: Codable, Hashable, Sendable {
        var memberId: String
        var name: String
        var workedMinutes: Int
        var daysWorked: Int
        var dayTypes: [String: Int]
        var allowanceDays: Int
        var bySite: [SiteMinutes]
    }

    struct SiteHours: Codable, Hashable, Sendable {
        var siteId: String
        var name: String
        var workedMinutes: Int
        var daysWritten: Int
        var noWorkDays: Int
        var kilometres: Int
    }

    struct DayHours: Codable, Hashable, Sendable {
        var date: String
        var memberId: String
        var siteId: String
        var workedMinutes: Int
        var start: String?
        var end: String?
        var breakMinutes: Int
    }

    struct MonthHours: Codable, Hashable, Sendable {
        var month: String
        var rules: SheetRules
        var workedMinutes: Int
        var people: [PersonHours]
        var sites: [SiteHours]
        var days: [DayHours]?
    }

    struct CompanyExport: Codable, Hashable, Sendable {
        var exportedAt: String
        var company: Company
        var sites: [Site]
        var crew: [CrewMember]
        var assignments: [Assignment]
        var devices: [Device]
        var siteDays: [SiteDay]
        var sheets: [Sheet]
        var signOffs: [SignOff]
        var extraWork: [ExtraWork]
        var defects: [Defect]
        var missingItems: [MissingItem]
        var deliveries: [Delivery]
        var comments: [Comment]
    }
}

/// Ids as both sides compare them: any case in, lower case out.
enum ConnectID {
    static func string(_ id: UUID) -> String { id.uuidString.lowercased() }

    static func uuid(_ text: String?) -> UUID? {
        text.flatMap { UUID(uuidString: $0) }
    }

    static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.lowercased() == rhs.lowercased()
    }
}
