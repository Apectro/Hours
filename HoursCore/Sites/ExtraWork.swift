import Foundation

// Extra work (Zusatzarbeiten, dodatni radovi): what a crew did on a site
// beyond the contract, written down so the boss knows what is done — "8
// emergency lights and 10 lamps". A progress report, not a bill: quantities
// only, there is no price anywhere in this feature, and none is ever printed. Hours on a job are optional, as is the client's
// signature. None of it is hours of anyone's own day, so it is never on the
// personal timesheet and not under the month lock (see `ExtraWorkRepository`).

/// What an item is counted in. The built-in units are translated on export
/// (Stk, kom, …); a unit the user typed is kept exactly as typed.
enum ExtraWorkUnit: Hashable, Sendable {
    case pieces, metres, squareMetres, cubicMetres, kilograms, hours, sets
    case custom(String)

    /// In the order they are offered, and the order totals are grouped in.
    static let builtIn: [ExtraWorkUnit] = [.pieces, .metres, .squareMetres, .cubicMetres, .kilograms, .hours, .sets]

    private static let customPrefix = "custom:"

    /// How it is stored and written to a backup.
    var code: String {
        switch self {
        case .pieces: return "pcs"
        case .metres: return "m"
        case .squareMetres: return "m2"
        case .cubicMetres: return "m3"
        case .kilograms: return "kg"
        case .hours: return "h"
        case .sets: return "set"
        case let .custom(text): return ExtraWorkUnit.customPrefix + text
        }
    }

    /// Reads a stored code. One this version does not know — a unit added
    /// later — reads as that word, so the line still says what it was.
    init(code: String) {
        if let match = ExtraWorkUnit.builtIn.first(where: { $0.code == code }) {
            self = match
        } else if code.hasPrefix(ExtraWorkUnit.customPrefix) {
            self = .custom(String(code.dropFirst(ExtraWorkUnit.customPrefix.count)))
        } else {
            self = .custom(code)
        }
    }

    /// A unit typed into "New item…": a built-in when it spells one in any
    /// language ("m", "Stk", "m²"), otherwise the word as typed. Nothing typed
    /// is no unit.
    static func typed(_ text: String) -> ExtraWorkUnit? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let key = ExtraWorkCatalog.key(trimmed)
        for unit in builtIn {
            let spellings = [unit.code] + ExportLanguage.allCases.map { unit.name(in: $0) }
            if spellings.contains(where: { ExtraWorkCatalog.key($0) == key }) { return unit }
        }
        return .custom(trimmed)
    }

    /// Its word in a language. Symbols are the same everywhere; pieces and
    /// sets have words of their own.
    func name(in language: ExportLanguage) -> String {
        switch self {
        case .pieces: return language(.unitPieces)
        case .metres: return "m"
        case .squareMetres: return "m²"
        case .cubicMetres: return "m³"
        case .kilograms: return "kg"
        case .hours: return "h"
        case .sets: return language(.unitSets)
        case let .custom(text): return text
        }
    }

    /// Counted rather than measured: written "8 × Lamp", not "8 pcs Lamp".
    var isCount: Bool { self == .pieces }

    /// Two spellings of the same custom unit total together.
    var groupingKey: String {
        if case let .custom(text) = self { return "custom:" + ExtraWorkCatalog.key(text) }
        return code
    }

    /// Where totals in this unit sit: the built-ins in their order, then any
    /// typed unit.
    var sortIndex: Int {
        ExtraWorkUnit.builtIn.firstIndex(of: self) ?? ExtraWorkUnit.builtIn.count
    }
}

extension ExtraWorkUnit: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(code: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(code)
    }
}

/// Reading and writing a quantity. Decimal, so 12.5 m of cable stays 12.5.
enum ExtraWorkQuantity {
    /// More than anyone fits in a day; a slip of the thumb stops here.
    static let maximum: Decimal = 999_999

    /// What was typed — "12,5", "12.5", " 8 " — or `nil` when it is not a
    /// number of zero or more.
    static func parse(_ text: String) -> Decimal? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty else { return nil }
        // Decimal(string:) reads "12abc" as 12, so the shape is checked first.
        var seenPoint = false
        var digits = 0
        for character in cleaned {
            if character == "." {
                guard !seenPoint else { return nil }
                seenPoint = true
            } else if character.isASCII, character.isNumber {
                digits += 1
            } else {
                return nil
            }
        }
        guard digits > 0, let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        return min(value, maximum)
    }

    /// At most three decimals and none that say nothing: 8, 12,5, 0,125.
    static func string(_ value: Decimal, decimalSeparator: String) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 3, .plain)
        var text = "\(rounded)"
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text.replacingOccurrences(of: ".", with: decimalSeparator)
    }

    /// The stepper's −/+: one at a time, never below zero.
    static func stepped(_ value: Decimal, by step: Int) -> Decimal {
        let next = value + Decimal(step)
        return min(max(next, 0), maximum)
    }

    /// For a workbook cell, which holds a binary number.
    static func double(_ value: Decimal) -> Double {
        Double(string(value, decimalSeparator: ".")) ?? 0
    }
}

/// One line of material on a job: "8 × Emergency light", "25 m Cable".
struct ExtraWorkItem: Hashable, Sendable {
    /// The user's own word for it, printed as typed.
    var name: String
    var quantity: Decimal
    var unit: ExtraWorkUnit

    init(name: String, quantity: Decimal, unit: ExtraWorkUnit) {
        self.name = name
        self.quantity = quantity
        self.unit = unit
    }

    /// "8 × Emergency light" for a count, "25 m Cable NYM 3×1.5" otherwise.
    func line(in language: ExportLanguage, decimalSeparator: String) -> String {
        let amount = ExtraWorkQuantity.string(quantity, decimalSeparator: decimalSeparator)
        if unit.isCount { return "\(amount) × \(name)" }
        return "\(amount) \(unit.name(in: language)) \(name)"
    }
}

extension ExtraWorkItem: Codable {
    private enum CodingKeys: String, CodingKey { case name, quantity, unit }

    /// The quantity is written as text, "12.5", so it is exact on every
    /// platform and readable by eye in a backup.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(ExtraWorkQuantity.string(quantity, decimalSeparator: "."), forKey: .quantity)
        try container.encode(unit, forKey: .unit)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let quantity: Decimal
        if let text = try? container.decode(String.self, forKey: .quantity) {
            quantity = ExtraWorkQuantity.parse(text) ?? 0
        } else if let number = try? container.decode(Double.self, forKey: .quantity), number.isFinite {
            quantity = ExtraWorkQuantity.parse(String(number)) ?? 0
        } else {
            quantity = 0
        }
        self.init(
            name: container.lenient(.name, ""),
            quantity: quantity,
            unit: container.lenient(.unit, .pieces)
        )
    }
}

/// How long a job took: one time for the job, however many were on it —
/// "it took us an hour" — in quarter-hour steps, or typed.
enum ExtraWorkTime {
    /// The stepper's step.
    static let step = 15
    /// A day: more than one job takes, so a slip of the thumb stops here.
    static let maximum = 24 * 60

    static func clamped(_ minutes: Int) -> Int {
        min(max(minutes, 0), maximum)
    }

    /// The stepper's −/+: a quarter of an hour at a time, within a day.
    static func stepped(_ minutes: Int, by steps: Int) -> Int {
        clamped(minutes + steps * step)
    }

    /// What was typed: "1:30" as hours and minutes, "1.5" or "1,5" as hours.
    /// `nil` when it is neither.
    static func parse(_ text: String) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        if cleaned.contains(":") {
            let parts = cleaned.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }),
                  let hours = Int(parts[0]), let minutes = Int(parts[1]), minutes < 60 else { return nil }
            return clamped(hours * 60 + minutes)
        }
        guard let hours = ExtraWorkQuantity.parse(cleaned) else { return nil }
        let minutes = NSDecimalNumber(decimal: hours * 60).doubleValue.rounded()
        return clamped(Int(min(minutes, Double(maximum))))
    }

    /// What the field opens on: "1:30", or nothing for no time.
    static func typingText(_ minutes: Int) -> String {
        guard minutes > 0 else { return "" }
        return String(format: "%d:%02d", minutes / 60, minutes % 60)
    }
}

/// Someone's time on one job. Optional: only where it is noted. Since 1.1's
/// editor sets one time for the job, everyone on it has the same minutes;
/// older jobs can differ (see `ExtraWorkJob.duration`).
struct ExtraWorkHours: Hashable, Codable, Sendable {
    /// A `CrewMember.id`, `CrewMember.youID`, or `nil` for a name typed in.
    var memberID: UUID?
    /// Their name as it was when written, so the line still reads after the
    /// crew list changes.
    var name: String
    var minutes: Int

    init(memberID: UUID? = nil, name: String, minutes: Int) {
        self.memberID = memberID
        self.name = name
        self.minutes = minutes
    }

    private enum CodingKeys: String, CodingKey { case memberID, name, minutes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            memberID: container.lenientOptional(.memberID),
            name: container.lenient(.name, ""),
            minutes: max(0, container.lenient(.minutes, 0))
        )
    }
}

/// The client confirming extra work with a finger on the supervisor's phone,
/// drawn and stored as the crew sign-off is (`SignaturePoint`).
struct ExtraWorkSignature: Hashable, Codable, Sendable {
    /// "Ing. M. Horvat · site manager": typed by whoever signs.
    var signerName: String
    var signedAt: Date
    var strokes: [[SignaturePoint]]
    var aspectRatio: Double

    init(signerName: String, signedAt: Date, strokes: [[SignaturePoint]], aspectRatio: Double = 3) {
        self.signerName = signerName
        self.signedAt = signedAt
        self.strokes = strokes
        self.aspectRatio = aspectRatio
    }

    private enum CodingKeys: String, CodingKey { case signerName, signedAt, strokes, aspectRatio }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            signerName: container.lenient(.signerName, ""),
            signedAt: container.lenient(.signedAt, Date(timeIntervalSince1970: 0)),
            strokes: container.lenient(.strokes, []),
            aspectRatio: container.lenient(.aspectRatio, 3)
        )
    }
}

/// Whether the boss has the job: written down, or in a report that was
/// shared. Separate from whether the work is finished (`ExtraWorkJob.isDone`).
enum ExtraWorkStatus: String, CaseIterable, Sendable {
    /// Written down, not yet sent to the boss.
    case open
    /// In a report that was shared.
    case sent

    /// Reads a stored value. Builds of 1.1 before it shipped had a third
    /// step, "invoiced", marked by hand on a sent job; that is a job the boss
    /// had, so it reads as sent. Anything else unknown is open.
    init(storedValue: String) {
        switch storedValue {
        case "sent", "invoiced": self = .sent
        default: self = .open
        }
    }
}

extension ExtraWorkStatus: Codable {
    init(from decoder: Decoder) throws {
        self.init(storedValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Whether the work itself is finished: the first chip on every job.
enum ExtraWorkProgress: String, Hashable, Sendable {
    case inProgress, done
}

/// The second, optional chip on a job: "Sent" once the boss has it as it
/// stands, otherwise "Signed" when the client has signed it.
enum ExtraWorkChip: String, Hashable, Sendable {
    case signed, sent
}

/// One job of extra work on one site and day.
struct ExtraWorkJob: Identifiable, Hashable, Sendable {
    var id: UUID
    var siteID: UUID
    var date: CalendarDate
    /// What was done, in the user's words: "Emergency lighting, stairwell".
    var description: String
    var items: [ExtraWorkItem]
    /// Empty unless hours were added to the job.
    var hours: [ExtraWorkHours]
    var clientSignature: ExtraWorkSignature?
    /// The work is finished. A job can run over several days and is in
    /// progress until it is ticked done.
    var isDone: Bool
    /// When it was ticked done; `nil` while in progress, and for jobs written
    /// before there was a tick (they read as done).
    var doneAt: Date?
    var status: ExtraWorkStatus
    var sentAt: Date?
    /// The `ExtraWorkReportRecord` it was last sent in.
    var sentReportID: UUID?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        siteID: UUID,
        date: CalendarDate,
        description: String = "",
        items: [ExtraWorkItem] = [],
        hours: [ExtraWorkHours] = [],
        clientSignature: ExtraWorkSignature? = nil,
        isDone: Bool = false,
        doneAt: Date? = nil,
        status: ExtraWorkStatus = .open,
        sentAt: Date? = nil,
        sentReportID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.siteID = siteID
        self.date = date
        self.description = description
        self.items = items
        self.hours = hours
        self.clientSignature = clientSignature
        self.isDone = isDone
        self.doneAt = isDone ? doneAt : nil
        self.status = status
        self.sentAt = sentAt
        self.sentReportID = sentReportID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// The most photos one job keeps, as for a diary day.
    static let maximumPhotos = 6

    static func photoSlotsLeft(existing: Int) -> Int {
        max(0, maximumPhotos - existing)
    }

    var hasHours: Bool { hours.contains { $0.minutes > 0 } }

    /// How long the job took, in minutes: the one time everyone on it
    /// shares. A job written before there was one time per job can have
    /// different minutes per person; it took as long as the longest. Never a
    /// sum: two people for an hour is a one-hour job.
    var duration: Int { hours.map(\.minutes).max().map { max(0, $0) } ?? 0 }

    /// Who was on it: everyone with time on the job, in the order written.
    var people: [String] { hours.filter { $0.minutes > 0 }.map(\.name) }

    /// The job took `minutes`, and these people were on it — each stored
    /// with that same time. Nobody chosen, or no time, keeps nothing once
    /// cleaned.
    func settingTime(_ minutes: Int, for people: [ExtraWorkHours]) -> ExtraWorkJob {
        var copy = self
        let time = ExtraWorkTime.clamped(minutes)
        copy.hours = people.map { ExtraWorkHours(memberID: $0.memberID, name: $0.name, minutes: time) }
        return copy
    }

    /// "1h · Marijo Mikša, Dusko Bajlović": how long, then who. Empty when no
    /// time was noted.
    func timeLine(_ durations: DurationFormatting) -> String {
        guard hasHours else { return "" }
        let names = people
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let time = durations.string(duration)
        return names.isEmpty ? time : "\(time) · \(names.joined(separator: ", "))"
    }
    var isSigned: Bool { clientSignature != nil }

    /// Nothing written and nothing counted: not worth storing.
    var isBlank: Bool {
        let cleaned = self.cleaned()
        return cleaned.description.isEmpty && cleaned.items.isEmpty && cleaned.hours.isEmpty && clientSignature == nil
    }

    /// As it is stored: the description trimmed, and no line without a name
    /// or a quantity, no one without time on the job.
    func cleaned() -> ExtraWorkJob {
        var copy = self
        copy.description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.items = items.compactMap { item in
            let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, item.quantity > 0 else { return nil }
            return ExtraWorkItem(name: name, quantity: item.quantity, unit: item.unit)
        }
        copy.hours = hours.filter { $0.minutes > 0 }
        return copy
    }

    var progress: ExtraWorkProgress { isDone ? .done : .inProgress }

    /// Sent while still in progress and finished since: the boss has heard
    /// it was under way, not that it is done.
    var finishedSinceSent: Bool {
        guard isDone, status == .sent, let doneAt, let sentAt else { return false }
        return doneAt > sentAt
    }

    /// The boss does not have it as it stands: never sent, or finished since.
    var awaitsReport: Bool { status == .open || finishedSinceSent }

    /// At most one chip beside In progress / Done.
    var chip: ExtraWorkChip? {
        if status == .sent && !finishedSinceSent { return .sent }
        return isSigned ? .signed : nil
    }

    // MARK: - Done

    /// The work is finished. Ticking a done job again keeps when it was done.
    func markingDone(at moment: Date) -> ExtraWorkJob {
        guard !isDone else { return self }
        var copy = self
        copy.isDone = true
        copy.doneAt = moment
        return copy
    }

    /// Not finished after all.
    func markingInProgress() -> ExtraWorkJob {
        var copy = self
        copy.isDone = false
        copy.doneAt = nil
        return copy
    }

    /// The row's checkmark.
    func togglingDone(at moment: Date) -> ExtraWorkJob {
        isDone ? markingInProgress() : markingDone(at: moment)
    }

    // MARK: - Sent to the boss

    /// In a report that was shared. A job sent before records the report it
    /// was sent in last.
    func markingSent(at moment: Date, reportID: UUID) -> ExtraWorkJob {
        var copy = self
        copy.status = .sent
        copy.sentAt = moment
        copy.sentReportID = reportID
        return copy
    }
}

extension ExtraWorkJob: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, siteID, date, description, items, hours, clientSignature, isDone, doneAt, status, sentAt, sentReportID
        case createdAt, updatedAt
    }

    /// Lenient, as everything in a backup is: a damaged field costs that
    /// field, never the job. A job without `isDone` was written before a job
    /// could be in progress, as finished work, so it reads as done.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            date: container.lenient(.date, CalendarDate(year: 1970, month: 1, day: 1)),
            description: container.lenient(.description, ""),
            items: container.lenient(.items, []),
            hours: container.lenient(.hours, []),
            clientSignature: container.lenientOptional(.clientSignature),
            isDone: container.lenient(.isDone, true),
            doneAt: container.lenientOptional(.doneAt),
            status: container.lenient(.status, .open),
            sentAt: container.lenientOptional(.sentAt),
            sentReportID: container.lenientOptional(.sentReportID),
            createdAt: container.lenient(.createdAt, Date(timeIntervalSince1970: 0)),
            updatedAt: container.lenient(.updatedAt, Date(timeIntervalSince1970: 0))
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(date, forKey: .date)
        try container.encode(description, forKey: .description)
        try container.encode(items, forKey: .items)
        try container.encode(hours, forKey: .hours)
        try container.encodeIfPresent(clientSignature, forKey: .clientSignature)
        try container.encode(isDone, forKey: .isDone)
        try container.encodeIfPresent(doneAt, forKey: .doneAt)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(sentAt, forKey: .sentAt)
        try container.encodeIfPresent(sentReportID, forKey: .sentReportID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }
}

/// A photo on a job: a JPEG the app has already made small and stripped of
/// its metadata (`DiaryPhotoProcessor`), as for the diary.
struct ExtraWorkPhoto: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var jobID: UUID
    var siteID: UUID
    var sortOrder: Int
    /// In a backup, base64.
    var jpegData: Data

    init(id: UUID = UUID(), jobID: UUID, siteID: UUID, sortOrder: Int, jpegData: Data) {
        self.id = id
        self.jobID = jobID
        self.siteID = siteID
        self.sortOrder = sortOrder
        self.jpegData = jpegData
    }

    private enum CodingKeys: String, CodingKey { case id, jobID, siteID, sortOrder, jpegData }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            jobID: container.lenient(.jobID, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            sortOrder: container.lenient(.sortOrder, 0),
            jpegData: container.lenient(.jpegData, Data())
        )
    }
}

/// A report that was shared: which jobs it carried, and the client's
/// signature under all of them, if there was one.
struct ExtraWorkReportRecord: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var siteID: UUID
    var sentAt: Date
    var jobIDs: [UUID]
    var clientSignature: ExtraWorkSignature?

    init(id: UUID = UUID(), siteID: UUID, sentAt: Date, jobIDs: [UUID], clientSignature: ExtraWorkSignature? = nil) {
        self.id = id
        self.siteID = siteID
        self.sentAt = sentAt
        self.jobIDs = jobIDs
        self.clientSignature = clientSignature
    }

    private enum CodingKeys: String, CodingKey { case id, siteID, sentAt, jobIDs, clientSignature }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            sentAt: container.lenient(.sentAt, Date(timeIntervalSince1970: 0)),
            jobIDs: container.lenient(.jobIDs, []),
            clientSignature: container.lenientOptional(.clientSignature)
        )
    }
}

/// How the share sheet ended.
enum ExtraWorkShareOutcome: Hashable, Sendable {
    case completed
    case cancelled
    case failed
}

enum ExtraWorkSending {
    /// The jobs of a report as they stand after sharing it: marked sent only
    /// when the share went through, and then all of them. Returns only the jobs that change, so nothing is
    /// written for a share that was cancelled.
    static func marked(
        _ jobs: [ExtraWorkJob],
        after outcome: ExtraWorkShareOutcome,
        reportID: UUID,
        at moment: Date
    ) -> [ExtraWorkJob] {
        guard outcome == .completed else { return [] }
        return jobs.compactMap { job in
            let next = job.markingSent(at: moment, reportID: reportID)
            return next == job ? nil : next
        }
    }
}
