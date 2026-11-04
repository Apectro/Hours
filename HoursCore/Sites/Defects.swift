import Foundation

/// Where a defect stands: noted and open, or fixed.
enum DefectState: String, CaseIterable, Hashable, Sendable {
    case open, fixed

    /// A stored value this version does not know reads as open: shown,
    /// rather than lost or quietly closed.
    init(storedValue: String) {
        self = DefectState(rawValue: storedValue) ?? .open
    }
}

/// Who fixes a defect, when the site assigns them (`SiteSetup.assignsDefects`):
/// nobody yet ("Later"), you, or someone on the crew by name.
enum DefectAssignee: Hashable, Sendable {
    case nobody
    case you
    case person(String)

    /// The stored pair: a kind ("", "you", "person") and a name.
    init(kind: String, name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case "you": self = .you
        case "person" where !trimmed.isEmpty: self = .person(trimmed)
        default: self = .nobody
        }
    }

    var kind: String {
        switch self {
        case .nobody: return ""
        case .you: return "you"
        case .person: return "person"
        }
    }

    var name: String {
        if case let .person(name) = self { return name }
        return ""
    }
}

extension DefectAssignee: Codable {
    private enum CodingKeys: String, CodingKey { case kind, name }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(kind: container.lenient(.kind, ""), name: container.lenient(.name, ""))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if !name.isEmpty { try container.encode(name, forKey: .name) }
    }
}

/// Something wrong on a site (1.3): "Socket loose, 2nd floor · Room 4",
/// with a photo or three, noted by you or someone on the crew, and fixed —
/// by you, the one person who marks a defect fixed — with the day. The
/// photos are `DefectPhoto`s of their own. Not hours, so not under the
/// month lock.
struct Defect: Identifiable, Hashable, Sendable {
    var id: UUID
    var siteID: UUID
    /// What's wrong: "Socket loose".
    var what: String
    /// One of the site's floors as it was written, or empty.
    var floor: String
    /// Free text, remembered per site: "Room 4".
    var room: String
    /// Only shown while the site assigns defects to people.
    var assignee: DefectAssignee
    /// Who noticed: a crew member's name, or empty for you.
    var notedBy: String
    var notedAt: Date
    var state: DefectState
    var fixedAt: Date?
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        siteID: UUID,
        what: String,
        floor: String = "",
        room: String = "",
        assignee: DefectAssignee = .nobody,
        notedBy: String = "",
        notedAt: Date = Date(),
        state: DefectState = .open,
        fixedAt: Date? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.siteID = siteID
        self.what = what
        self.floor = floor
        self.room = room
        self.assignee = assignee
        self.notedBy = notedBy
        self.notedAt = notedAt
        self.state = state
        self.fixedAt = fixedAt
        self.updatedAt = updatedAt
    }

    /// "2nd floor · Room 4", either alone, or empty.
    var whereLine: String {
        [floor, room].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

extension Defect: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, siteID, what, floor, room, assignee, notedBy, notedAt, state, fixedAt, updatedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(what, forKey: .what)
        if !floor.isEmpty { try container.encode(floor, forKey: .floor) }
        if !room.isEmpty { try container.encode(room, forKey: .room) }
        if assignee != .nobody { try container.encode(assignee, forKey: .assignee) }
        if !notedBy.isEmpty { try container.encode(notedBy, forKey: .notedBy) }
        try container.encode(notedAt, forKey: .notedAt)
        try container.encode(state.rawValue, forKey: .state)
        try container.encodeIfPresent(fixedAt, forKey: .fixedAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            what: container.lenient(.what, ""),
            floor: container.lenient(.floor, ""),
            room: container.lenient(.room, ""),
            assignee: container.lenient(.assignee, DefectAssignee.nobody),
            notedBy: container.lenient(.notedBy, ""),
            notedAt: container.lenient(.notedAt, Date(timeIntervalSince1970: 0)),
            state: DefectState(storedValue: container.lenient(.state, "open")),
            fixedAt: container.lenientOptional(.fixedAt),
            updatedAt: container.lenient(.updatedAt, Date(timeIntervalSince1970: 0))
        )
    }
}

// MARK: - Marks

/// A point on a photo, normalised: (0, 0) its top left corner, (1, 1) its
/// bottom right, whatever size it is drawn at.
struct DefectPoint: Hashable, Codable, Sendable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    /// Held inside the photo.
    var clamped: DefectPoint {
        DefectPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}

/// A rectangle in points or pixels: where a photo is drawn.
struct DefectRect: Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// One thing drawn over a defect's photo to show where the problem is: a
/// circle around it, an arrow at it, or a line drawn by finger. Kept as
/// vector data over the original photo, never burned into it, so the
/// photo stays as taken and the marking can be changed later.
struct DefectMark: Hashable, Sendable {
    enum Kind: String, CaseIterable, Hashable, Sendable {
        /// An ellipse in the box the drag spanned.
        case circle
        /// From where the drag started to where it ended, the head there.
        case arrow
        /// The finger's path.
        case draw
    }

    enum Colour: String, CaseIterable, Hashable, Sendable {
        case red, yellow, white
    }

    var kind: Kind
    var colour: Colour
    /// Normalised to the photo. A circle and an arrow use the first and the
    /// last; a drawing all of them.
    var points: [DefectPoint]

    init(kind: Kind, colour: Colour = .red, points: [DefectPoint]) {
        self.kind = kind
        self.colour = colour
        self.points = points.map(\.clamped)
    }

    /// Too small to be meant: a tap rather than a drag.
    var isMeaningful: Bool {
        guard let first = points.first, let last = points.last else { return false }
        switch kind {
        case .circle, .arrow:
            return DefectGeometry.distance(first, last) >= DefectGeometry.smallestMark
        case .draw:
            return points.count >= 2 && points.contains { DefectGeometry.distance($0, first) >= DefectGeometry.smallestMark / 2 }
        }
    }

    /// The box a circle is drawn in, normalised.
    var box: DefectRect? {
        guard let first = points.first, let last = points.last else { return nil }
        return DefectRect(
            x: min(first.x, last.x),
            y: min(first.y, last.y),
            width: abs(last.x - first.x),
            height: abs(last.y - first.y)
        )
    }
}

extension DefectMark: Codable {
    private enum CodingKeys: String, CodingKey { case kind, colour, points }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: Kind(rawValue: container.lenient(.kind, "circle")) ?? .circle,
            colour: Colour(rawValue: container.lenient(.colour, "red")) ?? .red,
            points: container.lenient(.points, [DefectPoint]())
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind.rawValue, forKey: .kind)
        try container.encode(colour.rawValue, forKey: .colour)
        // Four decimals: a tenth of a pixel on the largest photo kept.
        try container.encode(points.map { DefectPoint(x: DefectGeometry.rounded($0.x), y: DefectGeometry.rounded($0.y)) }, forKey: .points)
    }
}

/// Where marks go on a photo drawn at any size: from a touch to the
/// normalised point stored, and back, and the arrow's head. The same
/// numbers draw the marks on screen, on a thumbnail and in the PDF.
enum DefectGeometry {
    /// A mark shorter than this (a share of the photo) is a tap.
    static let smallestMark = 0.02

    /// The photo's own proportions inside a container, centred: where it is
    /// drawn when it fits.
    static func fitted(imageWidth: Double, imageHeight: Double, in container: DefectRect) -> DefectRect {
        guard imageWidth > 0, imageHeight > 0, container.width > 0, container.height > 0 else { return container }
        let scale = min(container.width / imageWidth, container.height / imageHeight)
        let width = imageWidth * scale
        let height = imageHeight * scale
        return DefectRect(
            x: container.x + (container.width - width) / 2,
            y: container.y + (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// A touch at (x, y) on a photo drawn in `rect`, as stored.
    static func normalised(x: Double, y: Double, in rect: DefectRect) -> DefectPoint {
        guard rect.width > 0, rect.height > 0 else { return DefectPoint(x: 0, y: 0) }
        return DefectPoint(x: (x - rect.x) / rect.width, y: (y - rect.y) / rect.height).clamped
    }

    /// A stored point on a photo drawn in `rect`.
    static func absolute(_ point: DefectPoint, in rect: DefectRect) -> DefectPoint {
        DefectPoint(x: rect.x + point.x * rect.width, y: rect.y + point.y * rect.height)
    }

    /// A circle's box on a photo drawn in `rect`.
    static func absolute(_ box: DefectRect, in rect: DefectRect) -> DefectRect {
        DefectRect(
            x: rect.x + box.x * rect.width,
            y: rect.y + box.y * rect.height,
            width: box.width * rect.width,
            height: box.height * rect.height
        )
    }

    /// The two ends of an arrow's head at `tip`, pointing away from `tail`,
    /// in the same units as both: two lines of `length` at 28° to the shaft.
    static func arrowHead(tail: DefectPoint, tip: DefectPoint, length: Double) -> [DefectPoint] {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let spread = 28.0 * Double.pi / 180
        return [angle + Double.pi - spread, angle + Double.pi + spread].map { wing in
            DefectPoint(x: tip.x + cos(wing) * length, y: tip.y + sin(wing) * length)
        }
    }

    /// How thick marks are on a photo drawn in `rect`: thick enough to see
    /// on a thumbnail, never a smear on a full-screen photo.
    static func lineWidth(in rect: DefectRect) -> Double {
        max(1.5, min(rect.width, rect.height) * 0.012)
    }

    /// An arrow's head, as long as the marks are thick.
    static func arrowHeadLength(in rect: DefectRect) -> Double {
        lineWidth(in: rect) * 5
    }

    static func distance(_ a: DefectPoint, _ b: DefectPoint) -> Double {
        ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
    }

    static func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}

// MARK: - Photos

/// A photo of a defect: the first is the one marked, then close-ups, and
/// "after" photos once it is being fixed. The JPEG is stored as the diary's
/// are (`DiaryPhotoProcessor`, no metadata); the marks lie over it.
struct DefectPhoto: Identifiable, Hashable, Sendable {
    var id: UUID
    var defectID: UUID
    var siteID: UUID
    /// Position among the defect's photos, in the order they were added.
    var sortOrder: Int
    /// Taken after the fix, rather than of the problem.
    var isAfter: Bool
    var marks: [DefectMark]
    var takenAt: Date
    /// In a backup, base64.
    var jpegData: Data

    init(
        id: UUID = UUID(),
        defectID: UUID,
        siteID: UUID,
        sortOrder: Int,
        isAfter: Bool = false,
        marks: [DefectMark] = [],
        takenAt: Date = Date(),
        jpegData: Data
    ) {
        self.id = id
        self.defectID = defectID
        self.siteID = siteID
        self.sortOrder = sortOrder
        self.isAfter = isAfter
        self.marks = marks
        self.takenAt = takenAt
        self.jpegData = jpegData
    }

    /// The photos of the problem before those after the fix, each in the
    /// order added.
    static func ordered(_ photos: [DefectPhoto]) -> [DefectPhoto] {
        photos.sorted { ($0.isAfter ? 1 : 0, $0.sortOrder, $0.takenAt) < ($1.isAfter ? 1 : 0, $1.sortOrder, $1.takenAt) }
    }

    /// Up to three photos of the problem: the marked one and two close-ups.
    static let maximumBefore = 3
    /// And as many after the fix.
    static let maximumAfter = 3
}

extension DefectPhoto: Codable {
    private enum CodingKeys: String, CodingKey { case id, defectID, siteID, sortOrder, isAfter, marks, takenAt, jpegData }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            defectID: container.lenient(.defectID, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            sortOrder: container.lenient(.sortOrder, 0),
            isAfter: container.lenient(.isAfter, false),
            marks: container.lenient(.marks, [DefectMark]()),
            takenAt: container.lenient(.takenAt, Date(timeIntervalSince1970: 0)),
            jpegData: container.lenient(.jpegData, Data())
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(defectID, forKey: .defectID)
        try container.encode(siteID, forKey: .siteID)
        try container.encode(sortOrder, forKey: .sortOrder)
        if isAfter { try container.encode(true, forKey: .isAfter) }
        if !marks.isEmpty { try container.encode(marks, forKey: .marks) }
        try container.encode(takenAt, forKey: .takenAt)
        try container.encode(jpegData, forKey: .jpegData)
    }
}

// MARK: - The rules

/// What the new-defect sheet hands over.
struct DefectDraft: Hashable, Sendable {
    var what: String
    var floor: String = ""
    var room: String = ""
    var assignee: DefectAssignee = .nobody
    var notedBy: String = ""
}

/// The rules of a site's defects. Pure: the repository stores what these
/// return.
enum DefectList {
    /// A new open defect from the draft, its texts tidied. A defect needs to
    /// say what is wrong; a blank one is nothing.
    static func making(_ draft: DefectDraft, siteID: UUID, at moment: Date, id: UUID = UUID()) -> Defect? {
        let what = tidy(draft.what)
        guard !what.isEmpty else { return nil }
        return Defect(
            id: id,
            siteID: siteID,
            what: what,
            floor: tidy(draft.floor),
            room: tidy(draft.room),
            assignee: draft.assignee,
            notedBy: tidy(draft.notedBy),
            notedAt: moment,
            updatedAt: moment
        )
    }

    /// Fixed, today, by you: the only one who marks a defect fixed.
    /// Fixing a fixed defect keeps its day.
    static func fixed(_ defect: Defect, at moment: Date) -> Defect {
        guard defect.state != .fixed else { return defect }
        var next = defect
        next.state = .fixed
        next.fixedAt = moment
        next.updatedAt = moment
        return next
    }

    /// Open again, and no longer fixed on any day.
    static func reopened(_ defect: Defect, at moment: Date) -> Defect {
        guard defect.state != .open else { return defect }
        var next = defect
        next.state = .open
        next.fixedAt = nil
        next.updatedAt = moment
        return next
    }

    /// How many are in a state: "Open 4".
    static func count(_ state: DefectState, in defects: [Defect]) -> Int {
        defects.filter { $0.state == state }.count
    }

    /// The defects in a state, in the order a floor lists them: open ones
    /// the longest waiting first, fixed ones the latest fixed first.
    static func items(_ state: DefectState, in defects: [Defect]) -> [Defect] {
        let rows = defects.filter { $0.state == state }
        switch state {
        case .open:
            return rows.sorted { ($0.notedAt, $0.what) < ($1.notedAt, $1.what) }
        case .fixed:
            return rows.sorted { ($0.fixedAt ?? $0.notedAt, $1.what) > ($1.fixedAt ?? $1.notedAt, $0.what) }
        }
    }

    /// One floor's defects, under the floor's name as it is written.
    struct FloorGroup: Hashable, Sendable {
        /// Empty for the defects noted without a floor.
        let floor: String
        let defects: [Defect]
    }

    /// The defects grouped by floor, in the site's floor order: the floors
    /// of the site's list first as listed, then any floor no longer on it
    /// (in the order first noted), and those with no floor last. A floor
    /// matches whatever its case, accents and spacing.
    static func groupedByFloor(_ defects: [Defect], floors: [String]) -> [FloorGroup] {
        var order: [String] = []
        var names: [String: String] = [:]
        for floor in floors {
            let key = ExtraWorkCatalog.key(floor)
            guard !key.isEmpty, names[key] == nil else { continue }
            names[key] = floor
            order.append(key)
        }
        var byKey: [String: [Defect]] = [:]
        var unlisted: [String] = []
        for defect in defects {
            let key = ExtraWorkCatalog.key(defect.floor)
            if !key.isEmpty, names[key] == nil {
                names[key] = defect.floor
                unlisted.append(key)
            }
            byKey[key, default: []].append(defect)
        }
        return (order + unlisted + [""]).compactMap { key in
            guard let rows = byKey[key], !rows.isEmpty else { return nil }
            return FloorGroup(floor: names[key] ?? "", defects: rows)
        }
    }

    /// The order a list, a PDF and a message number the defects in: by
    /// floor, then as each floor lists them.
    static func listed(_ defects: [Defect], state: DefectState?, floors: [String]) -> [Defect] {
        let chosen: [Defect]
        if let state {
            chosen = items(state, in: defects)
        } else {
            chosen = items(.open, in: defects) + items(.fixed, in: defects)
        }
        return groupedByFloor(chosen, floors: floors).flatMap(\.defects)
    }

    /// Chips for "What's wrong": the site's earlier defect texts, the most
    /// used first and, between two used as often, the latest. Each text
    /// once whatever its case, as it was last written.
    static func whatSuggestions(_ defects: [Defect], limit: Int = 8) -> [String] {
        ranked(defects.map { ($0.what, $0.notedAt) }, limit: limit)
    }

    /// Chips for the room: the rooms remembered for the site and those its
    /// defects were noted in, the most used first, the remembered order
    /// breaking a tie.
    static func roomSuggestions(_ defects: [Defect], remembered: [String], limit: Int = 12) -> [String] {
        var uses: [String: Int] = [:]
        var latest: [String: (text: String, at: Date)] = [:]
        for defect in defects {
            let key = ExtraWorkCatalog.key(defect.room)
            guard !key.isEmpty else { continue }
            uses[key, default: 0] += 1
            if let seen = latest[key], seen.at > defect.notedAt { continue }
            latest[key] = (defect.room, defect.notedAt)
        }
        var order: [String] = []
        var texts: [String: String] = [:]
        for room in remembered {
            let key = ExtraWorkCatalog.key(room)
            guard !key.isEmpty, texts[key] == nil else { continue }
            texts[key] = latest[key]?.text ?? room
            order.append(key)
        }
        let others = latest.keys.filter { texts[$0] == nil }.sorted { latest[$0]!.at > latest[$1]!.at }
        for key in others {
            texts[key] = latest[key]!.text
            order.append(key)
        }
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return order
            .sorted { (uses[$0] ?? 0, -(position[$0] ?? 0)) > (uses[$1] ?? 0, -(position[$1] ?? 0)) }
            .prefix(limit)
            .compactMap { texts[$0] }
    }

    /// The site's remembered rooms with one more, at the end, unless it is
    /// there already.
    static func remembering(room: String, in rooms: [String]) -> [String] {
        let tidied = tidy(room)
        let key = ExtraWorkCatalog.key(tidied)
        guard !key.isEmpty, !rooms.contains(where: { ExtraWorkCatalog.key($0) == key }) else { return rooms }
        return rooms + [tidied]
    }

    private static func ranked(_ texts: [(String, Date)], limit: Int) -> [String] {
        var uses: [String: Int] = [:]
        var latest: [String: (text: String, at: Date)] = [:]
        for (text, moment) in texts {
            let key = ExtraWorkCatalog.key(text)
            guard !key.isEmpty else { continue }
            uses[key, default: 0] += 1
            if let seen = latest[key], seen.at > moment { continue }
            latest[key] = (tidy(text), moment)
        }
        return latest.keys
            .sorted { (uses[$0]!, latest[$0]!.at) > (uses[$1]!, latest[$1]!.at) }
            .prefix(limit)
            .map { latest[$0]!.text }
    }

    static func tidy(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

/// A site's floors (`SiteSetup.floors`): the list the new-defect sheet
/// offers as chips and the defects are grouped in, "Basement, Ground, 1st
/// floor … Roof", edited in the site's settings.
enum SiteFloors {
    /// The list as kept: each floor tidied, once whatever its case, no
    /// blanks.
    static func normalised(_ floors: [String]) -> [String] {
        var seen = Set<String>()
        return floors.map(DefectList.tidy).filter { floor in
            let key = ExtraWorkCatalog.key(floor)
            return !key.isEmpty && seen.insert(key).inserted
        }
    }

    /// "Add floors 1 to N": the numbered floors named by `name` that are
    /// not on the list yet, put in before the first of `above` found on it
    /// (the roof stays on top), else at the end.
    static func addingNumbered(
        upTo count: Int,
        to floors: [String],
        name: (Int) -> String,
        above: [String] = []
    ) -> [String] {
        guard count >= 1 else { return normalised(floors) }
        var result = normalised(floors)
        let existing = Set(result.map(ExtraWorkCatalog.key))
        let new = (1...min(count, 200)).map(name).filter { !existing.contains(ExtraWorkCatalog.key($0)) }
        let aboveKeys = Set(above.map(ExtraWorkCatalog.key))
        let index = result.firstIndex { aboveKeys.contains(ExtraWorkCatalog.key($0)) } ?? result.count
        result.insert(contentsOf: new, at: index)
        return normalised(result)
    }

    /// A list typed on one line: "Basement, Ground, 1–6, Roof". A range of
    /// numbers is each of its floors, named by `name`.
    static func parsing(_ text: String, name: (Int) -> String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n")
        var floors: [String] = []
        for part in text.components(separatedBy: separators) {
            let trimmed = DefectList.tidy(part)
            guard !trimmed.isEmpty else { continue }
            let bounds = trimmed
                .replacingOccurrences(of: "–", with: "-")
                .replacingOccurrences(of: "—", with: "-")
                .split(separator: "-")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            if bounds.count == 2, let low = Int(bounds[0]), let high = Int(bounds[1]), low <= high, high - low < 200 {
                floors += (low...high).map(name)
            } else {
                floors.append(trimmed)
            }
        }
        return normalised(floors)
    }
}

// MARK: - Settings

extension SiteSetup {
    /// The floors to offer: the site's own list, or `defaults` (Ground, 1st
    /// floor, 2nd floor, Roof in the language) when it has none yet.
    func floorList(defaults: [String]) -> [String] {
        if let floors, !floors.isEmpty { return floors }
        return defaults
    }
}
