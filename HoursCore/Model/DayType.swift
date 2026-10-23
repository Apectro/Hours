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
    /// Zeitausgleich: a working day taken off against overtime. Added in 1.1;
    /// an older version reading a day of this type shows it as Unknown.
    static let timeOffInLieu = DayTypeID("timeOffInLieu")
    /// A day the weather stopped work (Schlechtwetter). Added in 1.1; being
    /// built in, it appears for everyone with nothing stored or migrated.
    static let badWeather = DayTypeID("badWeather")

    static let builtInOrder: [DayTypeID] = [
        .work, .weekend, .holiday, .vacation, .sick, .dayOff, .personal, .timeOffInLieu, .badWeather, .other
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
    /// What a credited-absence day of this type pays, as a percentage of the
    /// credited hours at the rate: 0 to 100, 100 unless changed. Sick leave
    /// in Croatia is 70%. Money only — the hours credited and the balance are
    /// the same whatever it says. Added in 1.1; absent reads as 100.
    var paidPercent: Int
    /// The employer pays a run of this type for its first
    /// `employerPaidDays` calendar days only, and the health insurer after
    /// that (Croatian sick leave: HZZO from day 43), so the app counts
    /// nothing earned from then on. Added in 1.1; absent reads as off.
    var employerPaysFirst42Days: Bool

    /// The days of a run the employer pays when `employerPaysFirst42Days`.
    static let employerPaidDays = 42

    init(
        id: DayTypeID,
        name: String,
        symbolName: String,
        tint: TypeTint,
        expectation: ExpectationPolicy,
        showsTimesByDefault: Bool,
        isBuiltIn: Bool = false,
        sortOrder: Int = 500,
        paidPercent: Int = 100,
        employerPaysFirst42Days: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbolName = symbolName
        self.tint = tint
        self.expectation = expectation
        self.showsTimesByDefault = showsTimesByDefault
        self.isBuiltIn = isBuiltIn
        self.sortOrder = sortOrder
        self.paidPercent = min(100, max(0, paidPercent))
        self.employerPaysFirst42Days = employerPaysFirst42Days
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, symbolName, tint, expectation, showsTimesByDefault, isBuiltIn, sortOrder
        case paidPercent, employerPaysFirst42Days
    }

    /// Strict on what a type always had, as Swift's own decoder was, so a
    /// damaged definition still fails as it did; lenient on what 1.1 added,
    /// so a type stored before it reads as paid in full. Older decoders skip
    /// the two new keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(DayTypeID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            symbolName: try container.decode(String.self, forKey: .symbolName),
            tint: try container.decode(TypeTint.self, forKey: .tint),
            expectation: try container.decode(ExpectationPolicy.self, forKey: .expectation),
            showsTimesByDefault: try container.decode(Bool.self, forKey: .showsTimesByDefault),
            isBuiltIn: try container.decode(Bool.self, forKey: .isBuiltIn),
            sortOrder: try container.decode(Int.self, forKey: .sortOrder),
            paidPercent: container.lenient(.paidPercent, 100),
            employerPaysFirst42Days: container.lenient(.employerPaysFirst42Days, false)
        )
    }

    /// Whether a day of this type pays less than its credited hours at the
    /// rate: a percentage below 100, or the employer paying only so long.
    var paysReducedAbsence: Bool {
        expectation == .creditedAbsence && (paidPercent < 100 || employerPaysFirst42Days)
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

    /// What this type is called on screen. The built-ins are stored with
    /// their English names, so the screen translates them by the same rule as
    /// an export does; `.device` follows the language the app is shown in.
    func displayName(in language: ExportLanguage = .device) -> String {
        exportName(in: language)
    }

    /// The name inside a sentence or a count — "5 vacation" — lower-cased
    /// except in German, where a noun keeps its capital: "5 Urlaub".
    func nameInRunningText(in language: ExportLanguage = .device) -> String {
        let name = displayName(in: language)
        return language.resolved == .german ? name : name.lowercased()
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
        case .timeOffInLieu: return .timeOffInLieuDay
        case .badWeather: return .badWeather
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
        // A working day taken off against overtime. `scheduled`, exactly
        // like an ordinary working day with nothing worked: the day's hours
        // are expected and none are credited, so the balance goes down by
        // what the week in force expects of that day — and, because the day
        // is chosen explicitly, it is recorded rather than a gap.
        DayTypeDefinition(
            id: .timeOffInLieu, name: "Time off in lieu", symbolName: "clock.arrow.circlepath", tint: .orange,
            expectation: .scheduled, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 55
        ),
        DayTypeDefinition(
            id: .dayOff, name: "Day off", symbolName: "figure.walk", tint: .brown,
            expectation: .zero, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 60
        ),
        // Paid, like a holiday, because that is how a stop for weather is
        // usually settled on a German or Austrian site; editable like every
        // other built-in for an employer that settles it differently.
        DayTypeDefinition(
            id: .badWeather, name: "Bad weather", symbolName: "cloud.rain.fill", tint: .yellow,
            expectation: .creditedAbsence, showsTimesByDefault: false, isBuiltIn: true, sortOrder: 65
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

    /// The day types that say why someone was not at work, in the catalogue's
    /// order: Sick, Vacation, Personal day, Time off in lieu, Day off, and
    /// the user's own types that credit the day or expect nothing of it.
    /// Never Work, Weekend, Public holiday, Bad weather or Other, which are
    /// not reasons a person stays away.
    var absenceReasons: [DayTypeDefinition] {
        let shipped: Set<DayTypeID> = [.sick, .vacation, .dayOff, .personal, .timeOffInLieu]
        return all.filter { definition in
            if DayTypeCatalog.isBuiltIn(definition.id) { return shipped.contains(definition.id) }
            return definition.expectation != .scheduled
        }
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
