import Foundation

/// The weather a diary records. Picked, never fetched: the app makes no
/// network calls, and the person standing on the site knows better anyway.
enum DiaryWeather: String, Codable, CaseIterable, Sendable {
    case sunny, cloudy, rain, snow, frost, wind, heat

    /// An SF Symbol name. The engine names it; the app draws it.
    var symbolName: String {
        switch self {
        case .sunny: return "sun.max.fill"
        case .cloudy: return "cloud.fill"
        case .rain: return "cloud.rain.fill"
        case .snow: return "cloud.snow.fill"
        case .frost: return "thermometer.snowflake"
        case .wind: return "wind"
        case .heat: return "thermometer.sun.fill"
        }
    }

    /// Its word on screen, in the language the app is shown in.
    func displayName(in language: ExportLanguage = .device) -> String {
        language(term)
    }

    /// Its word, in the export's languages and on screen.
    var term: ExportTerm {
        switch self {
        case .sunny: return .weatherSunny
        case .cloudy: return .weatherCloudy
        case .rain: return .weatherRain
        case .snow: return .weatherSnow
        case .frost: return .weatherFrost
        case .wind: return .weatherWind
        case .heat: return .weatherHeat
        }
    }
}

/// One site's diary for one day (Bautagebuch): the weather and four short
/// texts. The photos are `DiaryPhoto`s, kept apart so a list of diaries never
/// has to load an image.
///
/// Independent of the site day's hours: a diary can be written on a day
/// nobody's hours are, and deleting the hours leaves it. A blank one is not
/// stored at all.
struct SiteDiary: Hashable, Codable, Sendable {
    var siteID: UUID
    var date: CalendarDate
    var weather: DiaryWeather?
    /// Whole degrees Celsius, typed by hand.
    var temperatureCelsius: Int?
    var workDone: String
    var deliveries: String
    var problems: String
    var visitors: String

    init(
        siteID: UUID,
        date: CalendarDate,
        weather: DiaryWeather? = nil,
        temperatureCelsius: Int? = nil,
        workDone: String = "",
        deliveries: String = "",
        problems: String = "",
        visitors: String = ""
    ) {
        self.siteID = siteID
        self.date = date
        self.weather = weather
        self.temperatureCelsius = temperatureCelsius
        self.workDone = workDone
        self.deliveries = deliveries
        self.problems = problems
        self.visitors = visitors
    }

    /// The most photos one day keeps. Enough to show a day's work; few
    /// enough that a month of them still fits in a backup.
    static let maximumPhotos = 6

    /// Nothing typed or picked. Whitespace counts as nothing.
    var isBlank: Bool {
        weather == nil
            && temperatureCelsius == nil
            && [workDone, deliveries, problems, visitors].allSatisfy {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    /// The four texts with their export terms, in the order they are shown.
    var texts: [(term: ExportTerm, text: String)] {
        [(.diaryWorkDone, workDone), (.diaryDeliveries, deliveries), (.diaryProblems, problems), (.diaryVisitors, visitors)]
    }

    /// A heading for one of the texts on screen: the export's own word, so
    /// the app and the director's sheet call each part the same.
    static func label(for term: ExportTerm, in language: ExportLanguage = .device) -> String {
        language(term)
    }

    /// The closed weather row's grey line: "Rain, 8 °C", either part alone,
    /// or nothing when neither was set.
    func weatherPreview(in language: ExportLanguage = .device) -> String {
        var parts: [String] = []
        if let weather { parts.append(weather.displayName(in: language)) }
        if let temperatureCelsius { parts.append("\(temperatureCelsius) °C") }
        return parts.joined(separator: ", ")
    }

    /// A closed text row's grey line: the first line with something on it.
    static func preview(of text: String) -> String {
        text.split(whereSeparator: \.isNewline)
            .lazy
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
    }

    /// How many more photos a day with `existing` can take.
    static func photoSlotsLeft(existing: Int) -> Int {
        max(0, maximumPhotos - existing)
    }

    /// A temperature from what was typed: "12", "-3", "−3" with a real minus
    /// sign, "21°", "21 °C", "7,6" with a decimal comma. Rounded to a whole
    /// degree and held to −60…60, so a slip of the thumb cannot print 400 °C
    /// on a director's sheet. `nil` when there is no number in it.
    static func temperature(from text: String) -> Int? {
        var cleaned = text
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "°", with: "")
        cleaned = cleaned.filter { !$0.isWhitespace }
        if cleaned.hasSuffix("C") || cleaned.hasSuffix("c") { cleaned.removeLast() }
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return min(60, max(-60, Int(value.rounded())))
    }

    /// The dates with a diary worth showing: a non-blank diary, or a photo.
    static func datesWithEntries(diaries: [SiteDiary], photoDates: [CalendarDate]) -> Set<CalendarDate> {
        Set(diaries.filter { !$0.isBlank }.map(\.date)).union(photoDates)
    }

    /// Non-blank diaries, the most recent day first.
    static func newestFirst(_ diaries: [SiteDiary]) -> [SiteDiary] {
        diaries.filter { !$0.isBlank }.sorted { $0.date > $1.date }
    }

    private enum CodingKeys: String, CodingKey {
        case siteID, date, weather, temperatureCelsius, workDone, deliveries, problems, visitors
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            siteID: container.lenient(.siteID, UUID()),
            date: container.lenient(.date, CalendarDate(year: 1970, month: 1, day: 1)),
            weather: container.lenientOptional(.weather),
            temperatureCelsius: container.lenientOptional(.temperatureCelsius),
            workDone: container.lenient(.workDone, ""),
            deliveries: container.lenient(.deliveries, ""),
            problems: container.lenient(.problems, ""),
            visitors: container.lenient(.visitors, "")
        )
    }
}

/// A photo in a site's diary: a JPEG already made small and stripped of its
/// location by the app, which is the only place an image is ever decoded.
struct DiaryPhoto: Identifiable, Hashable, Codable, Sendable {
    var id: UUID
    var siteID: UUID
    var date: CalendarDate
    /// Position among the day's photos, in the order they were added.
    var sortOrder: Int
    /// In a backup, base64 — JSON's own way of writing bytes.
    var jpegData: Data

    init(id: UUID = UUID(), siteID: UUID, date: CalendarDate, sortOrder: Int, jpegData: Data) {
        self.id = id
        self.siteID = siteID
        self.date = date
        self.sortOrder = sortOrder
        self.jpegData = jpegData
    }

    private enum CodingKeys: String, CodingKey {
        case id, siteID, date, sortOrder, jpegData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: container.lenient(.id, UUID()),
            siteID: container.lenient(.siteID, UUID()),
            date: container.lenient(.date, CalendarDate(year: 1970, month: 1, day: 1)),
            sortOrder: container.lenient(.sortOrder, 0),
            jpegData: container.lenient(.jpegData, Data())
        )
    }
}
