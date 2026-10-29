import XCTest
@testable import Hours

/// A site's address (1.2): typed or filled in from its saved place, kept with
/// the site and in a backup, and printed in one small line under the site's
/// name on the sheets that show the site.
final class SiteAddressTests: XCTestCase {
    private let calendar = Fixture.calendar()
    private let august = CalendarDateRange(start: Fixture.date(2026, 8, 1), end: Fixture.date(2026, 8, 31))
    private let berlin = "Kaiserstraße 12, 10115 Berlin"

    private func settings(language: ExportLanguage = .english, columns: [ReportColumn]? = nil) -> AppSettings {
        var settings = Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
        if let columns {
            settings.features.trackLocation = true
            settings.export.columns = columns
        }
        return settings
    }

    private func site(_ name: String = "Bau Süd", address: String = "", sortOrder: Int = 0) -> Site {
        var site = Site(name: name, sortOrder: sortOrder)
        site.address = address
        return site
    }

    private func day(_ site: Site, _ d: Int, present: [UUID] = [CrewMember.youID]) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, 8, d),
            start: Fixture.time(7),
            end: Fixture.time(16),
            breakMinutes: 30,
            present: present.map { Attendance(memberID: $0) }
        )
    }

    // MARK: - The site

    func testANewSiteHasNoAddress() {
        XCTAssertEqual(Site(name: "Bau Süd").address, "")
    }

    func testAnAddressRoundTripsAndIsWrittenOnlyWhenSet() throws {
        let with = site(address: "Kaiserstraße 12\n10115 Berlin")
        let decoded = try JSONDecoder().decode(Site.self, from: JSONEncoder().encode(with))
        XCTAssertEqual(decoded.address, "Kaiserstraße 12\n10115 Berlin")
        XCTAssertEqual(decoded, with)

        let without = String(decoding: try JSONEncoder().encode(site()), as: UTF8.self)
        XCTAssertFalse(without.contains("address"), "a site without one is written exactly as before")
    }

    func testASiteFromBeforeAddressesReadsWithNone() throws {
        let json = #"{"id":"6F1B7C1E-6C1B-4C59-9B0A-0D1E2F3A4B5C","name":"Halle 3","isArchived":false,"sortOrder":2}"#
        let site = try JSONDecoder().decode(Site.self, from: Data(json.utf8))
        XCTAssertEqual(site.address, "")
        XCTAssertEqual(site.name, "Halle 3")
    }

    func testAnUnreadableAddressIsNone() throws {
        let json = #"{"id":"6F1B7C1E-6C1B-4C59-9B0A-0D1E2F3A4B5C","name":"Halle 3","address":12}"#
        XCTAssertEqual(try JSONDecoder().decode(Site.self, from: Data(json.utf8)).address, "")
    }

    // MARK: - Backups

    func testABackupCarriesTheAddressAndAnOlderAppStillReadsIt() throws {
        let archive = BackupArchive(
            exportedAt: Date(timeIntervalSince1970: 1_792_000_000),
            settings: Fixture.settings(),
            days: [],
            holidays: [],
            sites: [site(address: "Kaiserstraße 12\n10115 Berlin"), site("Halle 3", sortOrder: 1)],
            crew: [],
            siteDays: []
        )
        let data = try archive.encoded()
        let restored = try BackupArchive.decoded(from: data)
        XCTAssertEqual(restored.sites?.map(\.address), ["Kaiserstraße 12\n10115 Berlin", ""])

        // 1.0 and 1.1 decode a site by its keys and skip this one.
        struct OldArchive: Decodable {
            struct Site: Decodable {
                var id: UUID
                var name: String
                var isArchived: Bool
                var sortOrder: Int
            }
            var formatVersion: Int
            var sites: [Site]
        }
        let old = try JSONDecoder().decode(OldArchive.self, from: data)
        XCTAssertEqual(old.sites.map(\.name), ["Bau Süd", "Halle 3"])
        XCTAssertEqual(old.formatVersion, 1)
    }

    // MARK: - Lines

    func testTwoTypedLinesPrintAsOne() {
        XCTAssertEqual(SiteAddress.singleLine("Kaiserstraße 12\n10115 Berlin"), berlin)
        XCTAssertEqual(SiteAddress.singleLine("  Kaiserstraße 12 ,\n\n 10115 Berlin \n"), berlin)
        XCTAssertEqual(SiteAddress.singleLine("Kaiserstraße 12,\n10115 Berlin"), berlin, "no doubled comma")
        XCTAssertEqual(SiteAddress.singleLine(" \n "), "")
    }

    func testAPlaceIsWrittenStreetAndNumberThenPostcodeAndCity() {
        XCTAssertEqual(
            SiteAddress.compose(street: "Kaiserstraße", number: "12", postcode: "10115", city: "Berlin"),
            "Kaiserstraße 12\n10115 Berlin"
        )
        XCTAssertEqual(SiteAddress.compose(street: "Ilica", number: nil, postcode: "10000", city: "Zagreb"), "Ilica\n10000 Zagreb")
        XCTAssertEqual(SiteAddress.compose(street: nil, number: "4", postcode: nil, city: "Graz"), "Graz", "a number with no street says nothing")
        XCTAssertEqual(SiteAddress.compose(street: " ", number: nil, postcode: nil, city: nil), "")
    }

    // MARK: - The site sheet

    private func siteSheet(_ site: Site, crew: [CrewMember] = []) -> ReportTable {
        let settings = settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let present = [CrewMember.youID] + crew.map(\.id)
        return SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(site: site, crew: crew, results: [day(site, 3, present: present)].map(calculator.compute), range: august)
    }

    func testTheSiteSheetCarriesTheAddressOnOneLine() {
        XCTAssertEqual(siteSheet(site(address: "Kaiserstraße 12\n10115 Berlin")).address, berlin)
        XCTAssertEqual(siteSheet(site()).address, "")
    }

    func testEverySplitPartKeepsTheAddress() {
        let site = site(address: berlin)
        let crew = (0..<6).map { CrewMember(siteID: site.id, name: "P\($0)", sortOrder: $0) }
        let parts = SiteSheetBuilder.split(siteSheet(site, crew: crew), peoplePerPage: 3)
        XCTAssertGreaterThan(parts.count, 1)
        for part in parts {
            XCTAssertEqual(part.address, berlin)
        }
    }

    // MARK: - A person's own sheet

    private func crewSheet(_ days: [SiteDay], sites: [Site]) -> ReportTable {
        let settings = settings()
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return CrewMemberSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(person: .you(name: "Marijo"), sites: sites, results: days.map(calculator.compute), range: august)
    }

    func testOnePersonsSheetFromOneSiteCarriesThatAddress() {
        let south = site("Bau Süd", address: berlin)
        let hall = site("Halle 3", address: "Ilica 5, 10000 Zagreb", sortOrder: 1)
        XCTAssertEqual(crewSheet([day(south, 3), day(south, 4)], sites: [south, hall]).address, berlin)
    }

    func testOnePersonsSheetFromSeveralSitesCarriesNone() {
        let south = site("Bau Süd", address: berlin)
        let hall = site("Halle 3", address: "Ilica 5, 10000 Zagreb", sortOrder: 1)
        XCTAssertEqual(crewSheet([day(south, 3), day(hall, 4)], sites: [south, hall]).address, "")
    }

    // MARK: - Extra work

    func testTheExtraWorkReportCarriesTheAddress() {
        let site = site("Trg Pravde Zagreb", address: "Trg pravde 1\n10000 Zagreb")
        let job = ExtraWorkJob(siteID: site.id, date: Fixture.date(2026, 10, 19), description: "Lamps", items: [])
        let report = ExtraWorkReport(siteID: site.id, jobs: [job])
        let builder = ExtraWorkDocumentBuilder(settings: settings(), calendar: calendar)
        let page = builder.make(report: report, siteName: site.name, siteAddress: site.address)
        XCTAssertEqual(page.address, "Trg pravde 1, 10000 Zagreb")
        XCTAssertEqual(page.jobsTable().address, "Trg pravde 1, 10000 Zagreb")
        XCTAssertEqual(page.linesTable().address, "Trg pravde 1, 10000 Zagreb")
        XCTAssertEqual(builder.make(report: report, siteName: site.name).address, "")
    }

    // MARK: - Workbook and CSV

    private func table(address: String, language: ExportLanguage = .english) -> ReportTable {
        var table = ReportTable(title: "Bau Süd", subtitle: "August 2026", language: language, columns: [.date, .worked], rows: [], totals: [])
        table.kind = .siteSheet
        table.address = address
        return table
    }

    func testTheCSVHasAnAddressLineOnlyWhenThereIsOne() {
        let csv = CSVExporter.string(for: table(address: berlin, language: .german), preferences: ExportPreferences())
        XCTAssertTrue(csv.contains("Adresse,\"Kaiserstraße 12, 10115 Berlin\"\r\n"), csv)
        XCTAssertTrue(csv.hasPrefix("Datum,"), "the data block still opens the file")
        let none = CSVExporter.string(for: table(address: ""), preferences: ExportPreferences())
        XCTAssertFalse(none.contains("Address"))
    }

    func testTheWorkbookHasAnAddressRowOnlyWhenThereIsOne() {
        let xlsx = String(decoding: XLSXWriter.data(for: table(address: berlin), preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertTrue(xlsx.contains("Address"))
        XCTAssertTrue(xlsx.contains(berlin))
        let none = String(decoding: XLSXWriter.data(for: table(address: ""), preferences: ExportPreferences()), as: UTF8.self)
        XCTAssertFalse(none.contains("Address"))
    }

    func testAddressIsAnExportTermInEveryLanguage() {
        XCTAssertEqual(ExportLanguage.english(.address), "Address")
        XCTAssertEqual(ExportLanguage.german(.address), "Adresse")
        XCTAssertEqual(ExportLanguage.croatian(.address), "Adresa")
        for language in ExportLanguage.allCases {
            XCTAssertFalse(language(.address).isEmpty, language.rawValue)
        }
    }

    // MARK: - The personal timesheet's Location column

    func testADayFromASiteWithNoLocationOfItsOwnShowsTheSitesAddress() {
        let south = site("Bau Süd", address: "Kaiserstraße 12\n10115 Berlin")
        let settings = settings(columns: [.date, .worked, .location])
        let engine = Fixture.engine(settings: settings)
        let date = Fixture.date(2026, 8, 4)
        var fromSite = DayRecord(date: date)
        fromSite.shifts = [Shift(start: Fixture.time(7), end: Fixture.time(16), siteID: south.id)]
        var typed = DayRecord(date: date.adding(days: 1, in: calendar))
        typed.shifts = [Shift(start: Fixture.time(7), end: Fixture.time(16), siteID: south.id)]
        typed.location = "Werkstatt"
        let range = CalendarDateRange(start: date, end: date.adding(days: 1, in: calendar))
        let days = engine.days(in: range, records: [fromSite.date.key: fromSite, typed.date.key: typed], holidays: [])

        var builder = ReportBuilder(settings: settings, calendar: calendar)
        builder.siteAddresses = [south.id: south.address]
        let table = builder.makeTable(days: days, range: range, title: "August")
        let location = table.columns.firstIndex(of: .location)!
        XCTAssertEqual(table.rows.map { $0.values[location] }, [berlin, "Werkstatt"], "a location typed on the day is the day's own")

        let plain = ReportBuilder(settings: settings, calendar: calendar).makeTable(days: days, range: range, title: "August")
        XCTAssertEqual(plain.rows.map { $0.values[location] }, ["", "Werkstatt"], "without addresses, as before")
    }
}
