import XCTest
@testable import Hours

/// The links a widget opens the app with. The widget writes them and the app
/// reads them, so both sides go through the one type.
final class AppLinkTests: XCTestCase {
    private let id = UUID(uuidString: "6F9A1C2E-1B7D-4E0A-9C3B-2D5E8F7A6B41")!

    func testEveryLinkReadsBackAsItself() {
        let october = YearMonth(year: 2026, month: 10)
        for link in [AppLink.sites, .site(id), .siteSameAsLastDay(id), .siteExport(id, october)] {
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
