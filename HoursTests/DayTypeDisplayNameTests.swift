import XCTest
@testable import Hours

/// The built-in types are stored with English names, so the screen has to
/// translate them the same way an export does — or a German phone shows
/// "5 vacation" under a German calendar.
final class DayTypeDisplayNameTests: XCTestCase {
    private func builtIn(_ id: DayTypeID) -> DayTypeDefinition {
        DayTypeDefinition.builtIns.first { $0.id == id }!
    }

    func testAShippedTypeIsShownInTheLanguageAsked() {
        XCTAssertEqual(builtIn(.vacation).displayName(in: .german), "Urlaub")
        XCTAssertEqual(builtIn(.holiday).displayName(in: .croatian), "Državni praznik")
        XCTAssertEqual(builtIn(.vacation).displayName(in: .english), "Vacation")
    }

    func testARenamedOrCustomTypeKeepsTheUsersWord() {
        var renamed = builtIn(.vacation)
        renamed.name = "Ferien"
        XCTAssertEqual(renamed.displayName(in: .english), "Ferien")
        let custom = DayTypeDefinition(
            id: DayTypeID("x"), name: "Site visit", symbolName: "car", tint: .blue,
            expectation: .scheduled, showsTimesByDefault: true
        )
        XCTAssertEqual(custom.displayName(in: .german), "Site visit")
    }

    func testRunningTextLowercasesExceptWhereNounsAreCapitalised() {
        XCTAssertEqual(builtIn(.vacation).nameInRunningText(in: .english), "vacation")
        XCTAssertEqual(builtIn(.holiday).nameInRunningText(in: .french), builtIn(.holiday).displayName(in: .french).lowercased())
        XCTAssertEqual(builtIn(.vacation).nameInRunningText(in: .german), "Urlaub")
    }
}
