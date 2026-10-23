import XCTest
@testable import Hours

/// Crew sign-off: each person checks their month on your phone and signs, and
/// a signature whose hours changed afterwards says so.
final class CrewSignatureTests: XCTestCase {
    private let site = Site(name: "Bau Süd")
    private let calendar = Fixture.calendar()
    private let ivan = UUID()
    private let august = YearMonth(year: 2026, month: 8)
    private let signedOn = Fixture.date(2026, 8, 31)

    private func day(_ d: Int, month: Int = 8, ivanEnd: TimeOfDay? = nil, end: TimeOfDay = Fixture.time(16)) -> SiteDay {
        SiteDay(
            siteID: site.id,
            date: Fixture.date(2026, month, d),
            start: Fixture.time(7),
            end: end,
            breakMinutes: 30,
            present: [Attendance(memberID: CrewMember.youID), Attendance(memberID: ivan, end: ivanEnd)]
        )
    }

    private func results(_ days: [SiteDay]) -> [SiteDayResult] {
        let calculator = SiteDayCalculator(settings: Fixture.settings(), calendar: calendar)
        return days.map(calculator.compute)
    }

    private func fingerprint(_ member: UUID, _ days: [SiteDay]) -> String {
        SignatureFingerprint.make(memberID: member, results: results(days), month: august)
    }

    private func signature(_ member: UUID, over days: [SiteDay], on date: CalendarDate? = nil) -> CrewSignature {
        CrewSignature(
            siteID: site.id,
            memberID: member,
            month: august,
            signedOn: date ?? signedOn,
            fingerprint: fingerprint(member, days),
            strokes: [[SignaturePoint(x: 0.1, y: 0.5), SignaturePoint(x: 0.9, y: 0.4)]],
            aspectRatio: 3
        )
    }

    // MARK: - Fingerprint

    func testTheSameHoursGiveTheSameFingerprint() {
        XCTAssertEqual(fingerprint(ivan, [day(3), day(4)]), fingerprint(ivan, [day(4), day(3)]))
    }

    func testChangedHoursChangeTheFingerprint() {
        XCTAssertNotEqual(fingerprint(ivan, [day(3), day(4)]), fingerprint(ivan, [day(3), day(4, ivanEnd: Fixture.time(14))]))
    }

    func testAnAddedDayChangesTheFingerprint() {
        XCTAssertNotEqual(fingerprint(ivan, [day(3)]), fingerprint(ivan, [day(3), day(4)]))
    }

    func testSomeoneElsesChangeLeavesYourFingerprintAlone() {
        XCTAssertEqual(fingerprint(CrewMember.youID, [day(3)]), fingerprint(CrewMember.youID, [day(3, ivanEnd: Fixture.time(12))]))
    }

    func testAnotherMonthLeavesTheFingerprintAlone() {
        XCTAssertEqual(fingerprint(ivan, [day(3)]), fingerprint(ivan, [day(3), day(1, month: 9)]))
    }

    func testTheFingerprintIsStableAcrossRuns() {
        // Stored, and compared on another day and maybe another device, so it
        // must not depend on anything but the hours.
        XCTAssertEqual(fingerprint(ivan, [day(3)]), fingerprint(ivan, [day(3)]))
        XCTAssertTrue(fingerprint(ivan, [day(3)]).hasPrefix("v1:"))
    }

    // MARK: - State

    func testNoSignatureIsUnsigned() {
        let state = SignOff.state(for: ivan, signatures: [], results: results([day(3)]), month: august)
        XCTAssertEqual(state, .unsigned)
    }

    func testASignatureOverTheCurrentHoursIsSigned() {
        let days = [day(3), day(4)]
        let state = SignOff.state(for: ivan, signatures: [signature(ivan, over: days)], results: results(days), month: august)
        XCTAssertEqual(state, .signed(signedOn))
    }

    func testHoursChangedAfterSigningAreFlagged() {
        let signed = signature(ivan, over: [day(3), day(4)])
        let now = results([day(3), day(4, ivanEnd: Fixture.time(14))])
        XCTAssertEqual(SignOff.state(for: ivan, signatures: [signed], results: now, month: august), .changedAfterSigning(signedOn))
    }

    func testAnotherPersonsChangeDoesNotFlagYourSignature() {
        let signed = signature(CrewMember.youID, over: [day(3)])
        let now = results([day(3, ivanEnd: Fixture.time(12))])
        XCTAssertEqual(SignOff.state(for: CrewMember.youID, signatures: [signed], results: now, month: august), .signed(signedOn))
    }

    func testTheLatestSignatureCounts() {
        let days = [day(3), day(4, ivanEnd: Fixture.time(14))]
        let old = signature(ivan, over: [day(3), day(4)], on: Fixture.date(2026, 8, 30))
        let new = signature(ivan, over: days, on: Fixture.date(2026, 9, 1))
        let state = SignOff.state(for: ivan, signatures: [old, new], results: results(days), month: august)
        XCTAssertEqual(state, .signed(Fixture.date(2026, 9, 1)))
    }

    func testASignatureForAnotherMonthOrSiteDoesNotCount() {
        let days = [day(3)]
        var september = signature(ivan, over: days)
        september.month = YearMonth(year: 2026, month: 9)
        var elsewhere = signature(ivan, over: days)
        elsewhere.siteID = UUID()
        let state = SignOff.state(
            for: ivan, signatures: [september, elsewhere], results: results(days), month: august, siteID: site.id
        )
        XCTAssertEqual(state, .unsigned)
    }

    // MARK: - Coding

    func testASignatureRoundTrips() throws {
        let original = signature(ivan, over: [day(3)])
        let decoded = try JSONDecoder().decode(CrewSignature.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(decoded, original)
    }

    func testADamagedStrokeListCostsOnlyTheStrokes() throws {
        let json = #"{"siteID":"\#(site.id.uuidString)","memberID":"\#(ivan.uuidString)","month":{"year":2026,"month":8},"signedOn":20260831,"fingerprint":"v1:abc","strokes":"oops"}"#
        let decoded = try JSONDecoder().decode(CrewSignature.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.fingerprint, "v1:abc")
        XCTAssertEqual(decoded.signedOn, signedOn)
        XCTAssertTrue(decoded.strokes.isEmpty)
    }

    func testAnEmptyDrawingIsNotASignature() {
        XCTAssertFalse(CrewSignature.isSignature([]))
        XCTAssertFalse(CrewSignature.isSignature([[SignaturePoint(x: 0.5, y: 0.5)]]))
        XCTAssertTrue(CrewSignature.isSignature([[SignaturePoint(x: 0.1, y: 0.5), SignaturePoint(x: 0.6, y: 0.5)]]))
    }

    // MARK: - On the sheet

    private func sheet(
        _ days: [SiteDay],
        signatures: [CrewSignature],
        language: ExportLanguage = .english,
        includesSignatures: Bool = true
    ) -> ReportTable {
        let settings = Fixture.settings(export: ExportPreferences(language: language, ownerName: "Marijo"))
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        return SiteSheetBuilder(settings: settings, calendar: calendar).makeTable(
            site: site,
            crew: [CrewMember(id: ivan, siteID: site.id, name: "Ivan")],
            results: days.map(calculator.compute),
            range: august.range(in: calendar),
            signatures: signatures,
            includesSignatures: includesSignatures
        )
    }

    func testTheSheetHasABoxPerPersonOnceAnyoneHasSigned() {
        let days = [day(3)]
        let table = sheet(days, signatures: [signature(ivan, over: days)])
        XCTAssertEqual(table.signOff.map(\.name), ["Marijo", "Ivan"])
        XCTAssertEqual(table.signOff.map(\.status), ["", "signed 31 Aug 2026"])
        XCTAssertTrue(table.signOff[0].strokes.isEmpty)
        XCTAssertFalse(table.signOff[1].strokes.isEmpty)
        XCTAssertEqual(table.signOff[1].hours, "8h 30m")
    }

    func testASheetNobodySignedHasNoSignOff() {
        XCTAssertTrue(sheet([day(3)], signatures: []).signOff.isEmpty)
    }

    func testAChangedSignatureIsMarkedOnTheSheet() {
        let table = sheet([day(3, ivanEnd: Fixture.time(12))], signatures: [signature(ivan, over: [day(3)])], language: .german)
        let ivanBox = table.signOff.first { $0.name == "Ivan" }
        XCTAssertEqual(ivanBox?.isChanged, true)
        XCTAssertEqual(ivanBox?.status, "nach der Unterschrift geändert · unterschrieben am 31. Aug. 2026")
    }

    /// Signing is optional: with signatures switched off the sheet has no
    /// line to sign on and no sign-off boxes, even when someone has signed.
    func testASheetWithoutSignaturesHasNoLineAndNoBoxes() {
        let days = [day(3)]
        let table = sheet(days, signatures: [signature(ivan, over: days)], includesSignatures: false)
        XCTAssertTrue(table.signatures.isEmpty)
        XCTAssertTrue(table.signOff.isEmpty)
        XCTAssertFalse(table.rows.isEmpty, "the hours are still on the sheet")
    }

    func testASheetWithSignaturesKeepsItsLine() {
        XCTAssertEqual(sheet([day(3)], signatures: []).signatures, ["Checked · date, signature"])
    }
    // MARK: - Which month the sign-off opens on

    /// Crews sign at the end of the month, face to face on site, or in the
    /// first days of the next one when the sheet goes out: the first ten
    /// days still mean the month just gone.
    func testSignOffOpensOnLastMonthInTheFirstTenDays() {
        XCTAssertEqual(SignOff.defaultMonth(today: Fixture.date(2026, 11, 1)), YearMonth(year: 2026, month: 10))
        XCTAssertEqual(SignOff.defaultMonth(today: Fixture.date(2026, 11, 10)), YearMonth(year: 2026, month: 10))
        XCTAssertEqual(SignOff.defaultMonth(today: Fixture.date(2027, 1, 3)), YearMonth(year: 2026, month: 12))
    }

    func testSignOffOpensOnThisMonthFromTheEleventh() {
        XCTAssertEqual(SignOff.defaultMonth(today: Fixture.date(2026, 10, 11)), YearMonth(year: 2026, month: 10))
        XCTAssertEqual(SignOff.defaultMonth(today: Fixture.date(2026, 10, 31)), YearMonth(year: 2026, month: 10))
    }
}
