import XCTest
@testable import Hours

/// The links a widget opens the app with. The widget writes them and the app
/// reads them, so both sides go through the one type.
final class AppLinkTests: XCTestCase {
    private let id = UUID(uuidString: "6F9A1C2E-1B7D-4E0A-9C3B-2D5E8F7A6B41")!

    func testEveryLinkReadsBackAsItself() {
        let october = YearMonth(year: 2026, month: 10)
        for link in [AppLink.sites, .site(id), .siteSameAsLastDay(id), .siteExport(id, october), .writeToday] {
            XCTAssertEqual(AppLink(url: link.url), link, "\(link.url)")
        }
    }

    func testTheLinksLookAsDocumented() {
        XCTAssertEqual(AppLink.sites.url.absoluteString, "zeitkonto://sites")
        XCTAssertEqual(AppLink.site(id).url.absoluteString, "zeitkonto://site/\(id.uuidString)")
        XCTAssertEqual(
            AppLink.siteSameAsLastDay(id).url.absoluteString,
            "zeitkonto://site/\(id.uuidString)/same-as-last"
        )
        XCTAssertEqual(
            AppLink.siteExport(id, YearMonth(year: 2026, month: 3)).url.absoluteString,
            "zeitkonto://site/\(id.uuidString)/export?month=2026-03"
        )
    }

    /// The Write today control and shortcut open today's day editor.
    func testWriteTodayLooksAsDocumented() {
        XCTAssertEqual(AppLink.writeToday.url.absoluteString, "zeitkonto://today")
        XCTAssertEqual(AppLink(url: URL(string: "Zeitkonto://TODAY")!), .writeToday)
        XCTAssertNil(AppLink(url: URL(string: "zeitkonto://today/extra")!))
    }

    /// The Same as yesterday control follows the site card: the most recent
    /// active site, filled from its last written day.
    func testSameAsYesterdayOpensTheSiteOnTheWidgetCard() {
        var snapshot = WidgetSnapshot.empty
        snapshot.site = WidgetSite(
            id: id, name: "Trg Pravde", isTodayWritten: false, lastDay: nil,
            lastDayPeople: 0, includesYou: true, initials: [], lastStart: nil, lastEnd: nil
        )

        XCTAssertEqual(AppLink.sameAsYesterday(from: snapshot), .siteSameAsLastDay(id))
    }

    /// No site, or no snapshot yet: the Sites tab, where one can be added,
    /// rather than a button that does nothing.
    func testSameAsYesterdayWithoutASiteOpensTheSites() {
        XCTAssertEqual(AppLink.sameAsYesterday(from: .empty), .sites)
        XCTAssertEqual(AppLink.sameAsYesterday(from: nil), .sites)
    }

    /// The monthly reminder opens a site's sheet on the month it names, so
    /// a month that cannot be one is refused rather than guessed at.
    func testAnExportLinkNeedsARealMonth() {
        let base = "zeitkonto://site/\(id.uuidString)/export"
        XCTAssertEqual(
            AppLink(url: URL(string: base + "?month=2026-12")!),
            .siteExport(id, YearMonth(year: 2026, month: 12))
        )
        for query in ["", "?month=", "?month=2026-13", "?month=2026-0", "?month=26-10", "?month=2026-10-01", "?other=2026-10"] {
            XCTAssertNil(AppLink(url: URL(string: base + query)!), query)
        }
    }

    /// Typed by hand, a link arrives in whatever case it was typed in.
    func testCaseInTheSchemeAndIdentifierDoesNotMatter() {
        let url = URL(string: "Zeitkonto://site/\(id.uuidString.lowercased())")!

        XCTAssertEqual(AppLink(url: url), .site(id))
    }

    func testAnythingElseIsNotALink() {
        let refused = [
            "https://zeitkonto.app/site/\(id.uuidString)",
            "zeitkonto://site/not-a-site",
            "zeitkonto://site",
            "zeitkonto://site/\(id.uuidString)/delete-everything",
            "zeitkonto://elsewhere",
        ]
        for string in refused {
            XCTAssertNil(AppLink(url: URL(string: string)!), string)
        }
    }
}
