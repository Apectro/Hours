import XCTest
@testable import Hours

/// The site diary (Bautagebuch): one short log per site and day.
final class SiteDiaryTests: XCTestCase {
    private let siteID = UUID()
    private let tuesday = Fixture.workingTuesday

    private func diary(on date: CalendarDate? = nil, _ fill: (inout SiteDiary) -> Void = { _ in }) -> SiteDiary {
        var diary = SiteDiary(siteID: siteID, date: date ?? tuesday)
        fill(&diary)
        return diary
    }

    // MARK: - Blank

    func testANewDiaryIsBlank() {
        XCTAssertTrue(diary().isBlank)
    }

    func testWhitespaceAloneIsStillBlank() {
        XCTAssertTrue(diary { $0.workDone = "  \n " }.isBlank)
    }

    func testAnyOneFieldMakesItWorthKeeping() {
        XCTAssertFalse(diary { $0.weather = .rain }.isBlank)
        XCTAssertFalse(diary { $0.temperatureCelsius = 0 }.isBlank)
        XCTAssertFalse(diary { $0.workDone = "Formwork, ground floor" }.isBlank)
        XCTAssertFalse(diary { $0.deliveries = "12 m³ concrete" }.isBlank)
        XCTAssertFalse(diary { $0.problems = "Crane down until 10:00" }.isBlank)
        XCTAssertFalse(diary { $0.visitors = "Site manager" }.isBlank)
    }

    // MARK: - Coding

    func testADiaryRoundTrips() throws {
        let original = diary {
            $0.weather = .frost
            $0.temperatureCelsius = -4
            $0.workDone = "Rebar"
            $0.visitors = "Inspector"
        }
        let decoded = try JSONDecoder().decode(SiteDiary.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testAWeatherThisVersionDoesNotKnowReadsAsNoWeather() throws {
        let json = #"{"siteID":"\#(siteID.uuidString)","date":20260804,"weather":"hail","workDone":"Rebar"}"#
        let decoded = try JSONDecoder().decode(SiteDiary.self, from: Data(json.utf8))
        XCTAssertNil(decoded.weather)
        XCTAssertEqual(decoded.workDone, "Rebar")
        XCTAssertEqual(decoded.deliveries, "")
    }

    func testAPhotoRoundTripsWithItsBytes() throws {
        let photo = DiaryPhoto(siteID: siteID, date: tuesday, sortOrder: 2, jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))
        let decoded = try JSONDecoder().decode(DiaryPhoto.self, from: JSONEncoder().encode(photo))
        XCTAssertEqual(decoded, photo)
    }

    // MARK: - Temperature typed by hand

    func testTemperatureIsReadFromWhatWasTyped() {
        XCTAssertEqual(SiteDiary.temperature(from: "12"), 12)
        XCTAssertEqual(SiteDiary.temperature(from: " -3 "), -3)
        XCTAssertEqual(SiteDiary.temperature(from: "−5"), -5)
        XCTAssertEqual(SiteDiary.temperature(from: "21°"), 21)
        XCTAssertEqual(SiteDiary.temperature(from: "21 °C"), 21)
        XCTAssertEqual(SiteDiary.temperature(from: "7,6"), 8)
    }

    func testNothingOrNonsenseIsNoTemperature() {
        XCTAssertNil(SiteDiary.temperature(from: ""))
        XCTAssertNil(SiteDiary.temperature(from: "warm"))
        XCTAssertNil(SiteDiary.temperature(from: "-"))
    }

    func testAnImpossibleTemperatureIsHeldToARealOne() {
        XCTAssertEqual(SiteDiary.temperature(from: "400"), 60)
        XCTAssertEqual(SiteDiary.temperature(from: "-90"), -60)
    }

    // MARK: - Which days have one

    func testDaysWithADiaryAreThoseWithTextOrPhotos() {
        let wednesday = Fixture.date(2026, 8, 5)
        let thursday = Fixture.date(2026, 8, 6)
        let diaries = [
            diary { $0.workDone = "Rebar" },
            diary(on: wednesday),
        ]
        let dates = SiteDiary.datesWithEntries(diaries: diaries, photoDates: [thursday, thursday])
        XCTAssertEqual(dates, [tuesday, thursday])
    }

    func testTheDiaryListIsNewestFirst() {
        let older = diary(on: Fixture.date(2026, 8, 3)) { $0.workDone = "a" }
        let newer = diary(on: Fixture.date(2026, 8, 5)) { $0.workDone = "b" }
        let blank = diary(on: Fixture.date(2026, 8, 6))
        XCTAssertEqual(SiteDiary.newestFirst([older, blank, newer]).map(\.date), [newer.date, older.date])
    }

    // MARK: - Photos

    func testUpToSixPhotosADay() {
        XCTAssertEqual(SiteDiary.maximumPhotos, 6)
        XCTAssertEqual(SiteDiary.photoSlotsLeft(existing: 0), 6)
        XCTAssertEqual(SiteDiary.photoSlotsLeft(existing: 4), 2)
        XCTAssertEqual(SiteDiary.photoSlotsLeft(existing: 9), 0)
    }

    func testEveryWeatherHasASymbolAndAWord() {
        XCTAssertEqual(DiaryWeather.allCases.count, 7)
        for weather in DiaryWeather.allCases {
            XCTAssertFalse(weather.symbolName.isEmpty)
            XCTAssertFalse(ExportLanguage.german(weather.term).isEmpty)
        }
        XCTAssertEqual(ExportLanguage.german(DiaryWeather.rain.term), "Regen")
    }

    /// On screen the weather and the four headings use the export's words,
    /// so the diary reads the same in the app and on the director's sheet.
    func testOnScreenNamesFollowTheExportWords() {
        XCTAssertEqual(DiaryWeather.snow.displayName(in: .german), "Schnee")
        XCTAssertEqual(SiteDiary.label(for: .diaryProblems, in: .german), "Behinderungen / Verzögerungen")
    }

    // MARK: - Previews on a closed row

    /// A closed diary row says what is inside in one grey line.
    func testTheWeatherRowPreviewsWeatherAndTemperature() {
        XCTAssertEqual(diary { $0.weather = .rain; $0.temperatureCelsius = 8 }.weatherPreview(in: .english), "Rain, 8 °C")
        XCTAssertEqual(diary { $0.weather = .rain }.weatherPreview(in: .english), "Rain")
        XCTAssertEqual(diary { $0.temperatureCelsius = -3 }.weatherPreview(in: .english), "-3 °C")
        XCTAssertEqual(diary().weatherPreview(in: .english), "", "nothing picked, nothing said")
    }

    func testATextRowPreviewsItsFirstLine() {
        XCTAssertEqual(SiteDiary.preview(of: "Formwork, ground floor\nRebar on the first"), "Formwork, ground floor")
        XCTAssertEqual(SiteDiary.preview(of: "\n  \n  Crane down until 10:00  \nmore"), "Crane down until 10:00")
        XCTAssertEqual(SiteDiary.preview(of: "  \n "), "")
    }
}
