import XCTest
@testable import Hours

/// The countries' public holidays. The dates asserted here were checked by
/// hand against each country's own 2026 list; a test that disagrees with the
/// table is a question about the table first.
final class PublicHolidayCatalogTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func dates(_ set: PublicHolidaySet, _ year: Int, includingOptional: Bool = false) -> [CalendarDate] {
        set.holidays
            .filter { includingOptional || !$0.isOptional }
            .compactMap { $0.recurrence.occurrence(inYear: year, calendar: calendar) }
            .sorted()
    }

    private func set(_ country: HolidayCountry, _ region: String? = nil) throws -> PublicHolidaySet {
        try XCTUnwrap(PublicHolidayCatalog.set(country: country, region: region), "\(country) \(region ?? "")")
    }

    private func d(_ month: Int, _ day: Int, _ year: Int = 2026) -> CalendarDate {
        Fixture.date(year, month, day)
    }

    // MARK: - Every set

    func testEverySetHasDatesIn2026To2030WithoutTwoOnOneDay() {
        XCTAssertFalse(PublicHolidayCatalog.allSets.isEmpty)
        for set in PublicHolidayCatalog.allSets {
            XCTAssertGreaterThanOrEqual(set.checkedFor, 2026, set.id)
            XCTAssertFalse(set.source.isEmpty, set.id)
            for year in 2026...2030 {
                let all = dates(set, year, includingOptional: true)
                XCTAssertFalse(all.isEmpty, "\(set.id) \(year)")
                XCTAssertEqual(Set(all).count, all.count, "\(set.id) \(year) has two holidays on one day")
            }
            let ids = set.holidays.map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(set.id) repeats a holiday")
            for holiday in set.holidays {
                XCTAssertFalse(holiday.localName.isEmpty, "\(set.id) \(holiday.id)")
                XCTAssertFalse(holiday.englishName.isEmpty, "\(set.id) \(holiday.id)")
            }
        }
    }

    func testEveryCountryAndRegionHasASet() {
        for country in HolidayCountry.allCases {
            if country.regions.isEmpty {
                XCTAssertNotNil(PublicHolidayCatalog.set(country: country, region: nil), "\(country)")
            } else {
                for region in country.regions {
                    XCTAssertNotNil(PublicHolidayCatalog.set(country: country, region: region.code), region.code)
                }
            }
        }
        XCTAssertEqual(HolidayCountry.de.regions.count, 16)
        let cantons = Set(HolidayCountry.ch.regions.map(\.code))
        for canton in ["ZH", "BE", "LU", "BS", "BL", "AG", "SG", "ZG", "TI", "VD", "GE", "VS"] {
            XCTAssertTrue(cantons.contains(canton), canton)
        }
    }

    // MARK: - Germany

    func testGermanyNationwideIn2026() throws {
        // Berlin has one extra; everything else is the nationwide nine.
        let berlin = try set(.de, "BE")
        XCTAssertEqual(dates(berlin, 2026), [
            d(1, 1), d(3, 8), d(4, 3), d(4, 6), d(5, 1), d(5, 14), d(5, 25), d(10, 3), d(12, 25), d(12, 26),
        ])
    }

    func testBavariaIn2026() throws {
        let bavaria = try set(.de, "BY")
        XCTAssertEqual(dates(bavaria, 2026), [
            d(1, 1), d(1, 6), d(4, 3), d(4, 6), d(5, 1), d(5, 14), d(5, 25), d(6, 4),
            d(10, 3), d(11, 1), d(12, 25), d(12, 26),
        ], "twelve across the whole state")
        // Assumption is a holiday only in municipalities with a mainly
        // Catholic population (most of them, not all), and the Augsburg
        // peace festival only in the city of Augsburg: offered, not ticked.
        let optional = bavaria.holidays.filter(\.isOptional)
        XCTAssertEqual(Set(optional.map(\.id)), ["assumption", "augsburgPeace"])
        XCTAssertTrue(optional.allSatisfy { $0.note == .partOfRegion })
        XCTAssertEqual(dates(bavaria, 2026, includingOptional: true).count, 14)
    }

    func testSaxonyHasBussUndBettagOn18November2026() throws {
        let saxony = try set(.de, "SN")
        XCTAssertTrue(dates(saxony, 2026).contains(d(11, 18)))
        XCTAssertTrue(dates(saxony, 2026).contains(d(10, 31)))
        XCTAssertEqual(dates(saxony, 2026).count, 11)
    }

    func testTheStatesExtras() throws {
        let extras: [(String, [CalendarDate])] = [
            ("BW", [d(1, 6), d(6, 4), d(11, 1)]),
            ("BB", [d(4, 5), d(5, 24), d(10, 31)]),
            ("HB", [d(10, 31)]),
            ("HH", [d(10, 31)]),
            ("HE", [d(6, 4)]),
            ("MV", [d(3, 8), d(10, 31)]),
            ("NI", [d(10, 31)]),
            ("NW", [d(6, 4), d(11, 1)]),
            ("RP", [d(6, 4), d(11, 1)]),
            ("SL", [d(6, 4), d(8, 15), d(11, 1)]),
            ("ST", [d(1, 6), d(10, 31)]),
            ("SH", [d(10, 31)]),
            ("TH", [d(9, 20), d(10, 31)]),
        ]
        for (state, expected) in extras {
            let all = dates(try set(.de, state), 2026)
            XCTAssertEqual(all.count, 9 + expected.count, state)
            for date in expected { XCTAssertTrue(all.contains(date), "\(state) \(date)") }
        }
    }

    // MARK: - Austria

    func testAustriaIn2026() throws {
        let austria = try set(.at)
        XCTAssertEqual(dates(austria, 2026), [
            d(1, 1), d(1, 6), d(4, 6), d(5, 1), d(5, 14), d(5, 25), d(6, 4), d(8, 15),
            d(10, 26), d(11, 1), d(12, 8), d(12, 25), d(12, 26),
        ])
        XCTAssertFalse(dates(austria, 2026, includingOptional: true).contains(d(4, 3)), "Good Friday is not one any more")
        XCTAssertTrue(austria.tips.contains(.christmasEveAndNewYearsEve))
    }

    // MARK: - Switzerland

    func testZurichIn2026() throws {
        let zurich = try set(.ch, "ZH")
        XCTAssertEqual(dates(zurich, 2026), [
            d(1, 1), d(4, 3), d(4, 6), d(5, 1), d(5, 14), d(5, 25), d(8, 1), d(12, 25), d(12, 26),
        ])
    }

    func testEveryCantonHasTheFederalDay() throws {
        for region in HolidayCountry.ch.regions {
            XCTAssertTrue(dates(try set(.ch, region.code), 2026).contains(d(8, 1)), region.code)
        }
    }

    func testVaudHasTheFastMondayAndGenevaItsOwnFast() throws {
        XCTAssertTrue(dates(try set(.ch, "VD"), 2026).contains(d(9, 21)))
        let geneva = dates(try set(.ch, "GE"), 2026)
        XCTAssertTrue(geneva.contains(d(9, 10)))
        XCTAssertTrue(geneva.contains(d(12, 31)))
    }

    func testOtherCantonsGetTheCommonFourAndATip() throws {
        let other = try set(.ch, HolidayCountry.otherSwissCanton)
        XCTAssertEqual(dates(other, 2026), [d(1, 1), d(5, 14), d(8, 1), d(12, 25)])
        XCTAssertTrue(other.tips.contains(.cantonalHolidaysMissing))
    }

    // MARK: - The other countries

    func testCroatiaIn2026() throws {
        XCTAssertEqual(dates(try set(.hr), 2026), [
            d(1, 1), d(1, 6), d(4, 5), d(4, 6), d(5, 1), d(5, 30), d(6, 4), d(6, 22),
            d(8, 5), d(8, 15), d(11, 1), d(11, 18), d(12, 25), d(12, 26),
        ])
    }

    func testCroatiasStatehoodDayMovedIn2020() throws {
        let croatia = try set(.hr)
        XCTAssertFalse(dates(croatia, 2019).contains(d(5, 30, 2019)))
        XCTAssertFalse(dates(croatia, 2019).contains(d(11, 18, 2019)))
    }

    func testSloveniaIn2026() throws {
        XCTAssertEqual(dates(try set(.si), 2026), [
            d(1, 1), d(1, 2), d(2, 8), d(4, 5), d(4, 6), d(4, 27), d(5, 1), d(5, 2), d(5, 24),
            d(6, 25), d(8, 15), d(10, 31), d(11, 1), d(12, 25), d(12, 26),
        ])
    }

    func testTheRestIn2026() throws {
        XCTAssertEqual(dates(try set(.it), 2026), [
            d(1, 1), d(1, 6), d(4, 5), d(4, 6), d(4, 25), d(5, 1), d(6, 2), d(8, 15), d(11, 1),
            d(12, 8), d(12, 25), d(12, 26),
        ])
        XCTAssertEqual(dates(try set(.fr), 2026), [
            d(1, 1), d(4, 6), d(5, 1), d(5, 8), d(5, 14), d(5, 25), d(7, 14), d(8, 15), d(11, 1),
            d(11, 11), d(12, 25),
        ])
        XCTAssertEqual(dates(try set(.es), 2026), [
            d(1, 1), d(1, 6), d(4, 3), d(5, 1), d(8, 15), d(10, 12), d(11, 1), d(12, 6), d(12, 8), d(12, 25),
        ])
        XCTAssertEqual(dates(try set(.pt), 2026), [
            d(1, 1), d(4, 3), d(4, 5), d(4, 25), d(5, 1), d(6, 4), d(6, 10), d(8, 15), d(10, 5),
            d(11, 1), d(12, 1), d(12, 8), d(12, 25),
        ])
        XCTAssertEqual(dates(try set(.nl), 2026), [
            d(1, 1), d(4, 5), d(4, 6), d(4, 27), d(5, 14), d(5, 24), d(5, 25), d(12, 25), d(12, 26),
        ])
        XCTAssertEqual(dates(try set(.pl), 2026), [
            d(1, 1), d(1, 6), d(4, 5), d(4, 6), d(5, 1), d(5, 3), d(5, 24), d(6, 4), d(8, 15),
            d(11, 1), d(11, 11), d(12, 24), d(12, 25), d(12, 26),
        ])
    }

    func testPolandsChristmasEveStartedIn2025() throws {
        let poland = try set(.pl)
        XCTAssertFalse(dates(poland, 2024).contains(d(12, 24, 2024)))
        XCTAssertTrue(dates(poland, 2025).contains(d(12, 24, 2025)))
    }

    // MARK: - Names

    func testTheNameFollowsThePhoneWhereTheSetHasIt() throws {
        let austria = try set(.at)
        let christmas = try XCTUnwrap(austria.holidays.first { $0.id == "christmas" })
        XCTAssertEqual(christmas.name(in: .german, setLanguage: austria.language), "Christtag")
        XCTAssertEqual(christmas.name(in: .english, setLanguage: austria.language), "Christmas Day")
        // No Croatian name for an Austrian holiday: the local one, as it is
        // printed on the site's calendar.
        XCTAssertEqual(christmas.name(in: .croatian, setLanguage: austria.language), "Christtag")
    }
}
