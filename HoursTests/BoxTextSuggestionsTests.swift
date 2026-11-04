import XCTest
@testable import Hours

/// Reading an item's name off the box: the text the camera saw around a new
/// barcode, cleaned into at most four names to offer, the most prominent
/// first; and the Scan text tray, which joins the lines tapped.
final class BoxTextSuggestionsTests: XCTestCase {
    private let code = "4015081677891"

    private func line(_ text: String, area: Double = 1, distance: Double = 0) -> RecognisedLine {
        RecognisedLine(text: text, area: area, distanceToCode: distance)
    }

    private func names(_ lines: [RecognisedLine]) -> [String] {
        BoxTextSuggestions.names(from: lines, code: code)
    }

    // MARK: - What is dropped

    func testDigitsAndCodesAreDropped() {
        XCTAssertEqual(names([
            line("4015081677891"),
            line("4 015081 677891"),
            line("12345-678"),
            line("AB12-345X"),
            line("12ABC IP65"),
            line("Junction box IP65"),
        ]), ["Junction box IP65"])
    }

    func testTheBarcodeNumberItselfIsDropped() {
        XCTAssertEqual(names([line("EAN 4015081677891"), line("Cable tie")]), ["Cable tie"])
    }

    func testVeryShortAndVeryLongLinesAreDropped() {
        let long = "Junction box for surface mounting, grey, with seven entries"
        XCTAssertGreaterThan(long.count, 40)
        XCTAssertEqual(names([line("Ab"), line("X 1"), line(long), line("LED")]), ["LED"])
    }

    func testAFortyCharacterLineIsKept() {
        let forty = String(repeating: "a", count: 35) + " box1"
        XCTAssertEqual(forty.count, 40)
        XCTAssertEqual(names([line(forty)]), [forty])
    }

    func testPricesAreDropped() {
        XCTAssertEqual(names([
            line("4,99 €"),
            line("€ 12.50"),
            line("Price 3,20 EUR"),
            line("CHF 9.90"),
            line("$5"),
            line("Wago 221"),
        ]), ["Wago 221"])
    }

    func testURLsAndEmailsAreDropped() {
        XCTAssertEqual(names([
            line("www.example.com"),
            line("https://example.com/item"),
            line("Visit example.de"),
            line("info@example.com"),
            line("Cable NYM-J 3x1,5"),
        ]), ["Cable NYM-J 3x1,5"])
    }

    func testAWeightAloneIsDroppedButKeptWithAWord() {
        XCTAssertEqual(names([
            line("0,5 kg"),
            line("500 ml"),
            line("230 V 50 Hz"),
            line("Silicone 300 ml"),
        ]), ["Silicone 300 ml"])
    }

    func testCodeLabelsAloneAreNotNames() {
        XCTAssertEqual(names([line("Art. Nr. 12345"), line("REF 99812"), line("LOT 2026A"), line("Screws")]), ["Screws"])
    }

    // MARK: - Cleaning and order

    func testLinesAreTrimmedAndSpacesCollapsed() {
        XCTAssertEqual(names([line("  Junction   box \n")]), ["Junction box"])
    }

    func testDuplicatesAreDroppedIgnoringCase() {
        XCTAssertEqual(names([
            line("JUNCTION BOX", area: 9),
            line("Junction box", area: 3),
            line("junction  box", area: 1),
        ]), ["JUNCTION BOX"])
    }

    func testTheLargestLineComesFirstThenTheOneNearestTheCode() {
        XCTAssertEqual(names([
            line("Small near", area: 2, distance: 1),
            line("Big far", area: 10, distance: 50),
            line("Small far", area: 2, distance: 9),
            line("Medium", area: 5, distance: 3),
        ]), ["Big far", "Medium", "Small near", "Small far"])
    }

    func testLinesMostlyOfLettersComeBeforeOnesMostlyOfNumbers() {
        XCTAssertEqual(names([
            line("Box 100 x 100 x 50", area: 9),
            line("Junction box", area: 2),
        ]), ["Junction box", "Box 100 x 100 x 50"])
    }

    func testAtMostFourAreOffered() {
        let lines = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"].enumerated().map { index, text in
            line(text, area: Double(10 - index))
        }
        XCTAssertEqual(names(lines), ["Alpha", "Bravo", "Charlie", "Delta"])
    }

    func testNothingSeenOffersNothing() {
        XCTAssertEqual(names([]), [])
        XCTAssertEqual(names([line("   "), line("4015081677891")]), [])
    }

    func testLettersWithAccentsCount() {
        XCTAssertEqual(names([line("Kabelbinder schwarz"), line("Abzweigdose grün"), line("Šuko utičnica")]),
                       ["Kabelbinder schwarz", "Abzweigdose grün", "Šuko utičnica"])
    }

    // MARK: - The Scan text tray

    func testTheTrayJoinsLinesWithASpace() {
        var tray = ""
        tray = BoxTextSuggestions.appending("  Junction box ", to: tray)
        XCTAssertEqual(tray, "Junction box")
        tray = BoxTextSuggestions.appending("IP65", to: tray)
        XCTAssertEqual(tray, "Junction box IP65")
        tray = BoxTextSuggestions.appending("   ", to: tray)
        XCTAssertEqual(tray, "Junction box IP65", "an empty line adds nothing")
        XCTAssertEqual(BoxTextSuggestions.appending("grey\nsurface", to: "Box"), "Box grey surface")
    }
}
