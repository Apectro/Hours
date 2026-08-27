import Foundation

/// Stable identifier for a day type. Built-in types use reserved string ids;
/// user-defined types use a UUID string. Storing a string (rather than an enum)
/// is what lets custom types exist without a schema migration.
struct DayTypeID: Hashable, Sendable {
    var rawValue: String

    init(_ rawValue: String) { self.rawValue = rawValue }
}

extension DayTypeID: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension DayTypeID {
    static let work = DayTypeID("work")
    static let weekend = DayTypeID("weekend")
    static let holiday = DayTypeID("holiday")
    static let vacation = DayTypeID("vacation")
    static let sick = DayTypeID("sick")
    static let dayOff = DayTypeID("dayOff")
    static let personal = DayTypeID("personal")
    static let other = DayTypeID("other")

    static let builtInOrder: [DayTypeID] = [
        .work, .weekend, .holiday, .vacation, .sick, .dayOff, .personal, .other
    ]
}

/// How a day type contributes to the expected-hours side of the balance.
///
/// This single enum is what makes the balance arithmetic correct for paid
/// absence, and it is the one modelling decision worth reading twice:
///
/// - `scheduled`  — an ordinary working day. Expected = contracted hours.
/// - `zero`       — the day is simply not a working day. Expected = 0, so not
///                  working it has no effect on the balance.
/// - `creditedAbsence` — paid absence. Expected = contracted hours *and* those
///                  hours are credited as worked, so the balance moves by 0 and
///                  the day still counts as a paid day in reports.
enum ExpectationPolicy: String, Codable, CaseIterable, Sendable {
    case scheduled
    case zero
    case creditedAbsence
}

/// Semantic colour token. The core layer never imports SwiftUI, so it names
/// colours rather than holding them.
enum TypeTint: String, Codable, CaseIterable, Sendable {
    case blue, teal, green, yellow, orange, red, pink, purple, indigo, brown, gray
}

/// The definition of a day type: how it looks and how it counts.
struct DayTypeDefinition: Identifiable, Hashable, Codable, Sendable {
    var id: DayTypeID
    var name: String
    var symbolName: String
    var tint: TypeTint
    var expectation: ExpectationPolicy
    /// Whether the editor shows start/end times for this type by default.
    /// Times can always be added manually — working a public holiday is a real
    /// thing and the app must not make it impossible.
    var showsTimesByDefault: Bool
    var isBuiltIn: Bool
    var sortOrder: Int

    init(
        id: DayTypeID,
        name: String,
        symbolName: String,
        tint: TypeTint,
        expectation: ExpectationPolicy,
        showsTimesByDefault: Bool,
        isBuiltIn: Bool = false,
        sortOrder: Int = 500
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.tint = tint
        self.expectation = expectation
        self.showsTimesByDefault = showsTimesByDefault
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
    }
}

extension DayTypeDefinition {
    /// What this type is called in an exported file.
    ///
    /// A type the app ships is translated; one the user made is not, and nor
    /// is a shipped one they have renamed — "Urlaub" is a translation of
    /// Vacation, but somebody who renamed it "Ferien" or "Site visit" meant
    /// that word, and turning it into another is a fabrication rather than a
    /// translation.
    func exportName(in language: ExportLanguage) -> String {
        guard let term = DayTypeDefinition.term(for: id),
              let shipped = DayTypeDefinition.builtIns.first(where: { $0.id == id }),
              shipped.name == name
        else { return name }
        return language(term)
    }

    private static func term(for id: DayTypeID) -> ExportTerm? {
        switch id {
        case .work: return .work
        case .weekend: return .weekend
        case .holiday: return .publicHoliday
        case .vacation: return .vacation
        case .sick: return .sickLeave
        case .personal: return .personalDay
        case .dayOff: return .dayOff
        case .other: return .otherDayType
        default: return nil
        }
    }

    static let builtIns: [DayTypeDefinition] = [
        DayTypeDefinition(
            id: .work, name: "Work", symbolName: "briefcase.fill", tint: .blue,
            expectation: .scheduled, showsTimesByDefault: true, isBuiltIn: true, sortOrder: 0
        ),
        DayTypeDefinition(
            id: .weekend, name: "Weekend", symbolName: "moon.stars.fill", tint: .gray,
            expectation: .zero, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 10
        ),
        DayTypeDefinition(
            id: .holiday, name: "Public holiday", symbolName: "flag.fill", tint: .purple,
            expectation: .creditedAbsence, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 20
        ),
        DayTypeDefinition(
            id: .vacation, name: "Vacation", symbolName: "beach.umbrella.fill", tint: .teal,
            expectation: .creditedAbsence, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 30
        ),
        DayTypeDefinition(
            id: .sick, name: "Sick leave", symbolName: "cross.case.fill", tint: .red,
            expectation: .creditedAbsence, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 40
        ),
        DayTypeDefinition(
            id: .personal, name: "Personal day", symbolName: "person.fill", tint: .indigo,
            expectation: .creditedAbsence, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 50
        ),
        DayTypeDefinition(
            id: .dayOff, name: "Day off", symbolName: "figure.walk", tint: .brown,
            expectation: .zero, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 60
        ),
        DayTypeDefinition(
            id: .other, name: "Other", symbolName: "square.dashed", tint: .gray,
            expectation: .zero, showsTimesByDefault: true, isBuiltIn: true, sortOrder: 70
        )
    ]
}

/// Built-in types merged with the user's custom ones. Resolution never fails:
/// an unknown id (a custom type deleted while entries still referenced it)
/// falls back to a synthesised placeholder so historical data stays readable.
struct DayTypeCatalog: Hashable, Sendable {
    var custom: [DayTypeDefinition]

    init(custom: [DayTypeDefinition] = []) {
        self.custom = custom
    }

    /// Built-ins, with any custom definition of the same id replacing it.
    /// That is what lets the user adjust a built-in type — "vacation is unpaid
    /// here" — without the app having to ship every policy variant.
    var all: [DayTypeDefinition] {
        var byID: [DayTypeID: DayTypeDefinition] = [:]
        for definition in DayTypeDefinition.builtIns { byID[definition.id] = definition }
        for definition in custom { byID[definition.id] = definition }
        return byID.values.sorted { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
        }
    }

    /// Whether `id` names one of the types the app ships with.
    static func isBuiltIn(_ id: DayTypeID) -> Bool {
        DayTypeDefinition.builtIns.contains { $0.id == id }
    }

    func definition(for id: DayTypeID) -> DayTypeDefinition {
        if let match = all.first(where: { $0.id == id }) { return match }
        return DayTypeDefinition(
            id: id,
            name: "Unknown",
            symbolName: "questionmark.square.dashed",
            tint: .gray,
            expectation: .zero,
            showsTimesByDefault: false,
            sortOrder: 999
        )
    }

    static let standard = DayTypeCatalog()
}
