import XCTest
@testable import Hours

/// Extra work: the jobs done on a site beyond the contract, written down so
/// the boss knows what is done. Quantities only, never money.
final class ExtraWorkTests: XCTestCase {
    private let site = UUID()
    private let date = Fixture.date(2026, 10, 22)
    private let moment = Date(timeIntervalSince1970: 1_792_000_000)

    private func job(
        _ description: String = "Emergency lighting",
        items: [ExtraWorkItem] = [ExtraWorkItem(name: "Emergency light", quantity: 8, unit: .pieces)],
        status: ExtraWorkStatus = .open
    ) -> ExtraWorkJob {
        ExtraWorkJob(siteID: site, date: date, description: description, items: items, status: status, createdAt: moment, updatedAt: moment)
    }

    // MARK: - Units

    func testBuiltInUnitsKeepTheirCodesAndCustomUnitsTheirWords() {
        for unit in ExtraWorkUnit.builtIn {
            XCTAssertEqual(ExtraWorkUnit(code: unit.code), unit)
        }
        XCTAssertEqual(ExtraWorkUnit(code: ExtraWorkUnit.custom("Rolle").code), .custom("Rolle"))
        XCTAssertEqual(ExtraWorkUnit.custom("Rolle").name(in: .german), "Rolle")
        XCTAssertEqual(ExtraWorkUnit.custom("Rolle").name(in: .croatian), "Rolle")
    }

    /// A unit from a later version reads as its own word rather than failing.
    func testAnUnknownCodeReadsAsACustomUnit() {
        XCTAssertEqual(ExtraWorkUnit(code: "l"), .custom("l"))
    }

    func testACustomUnitThatSpellsABuiltInIsTheBuiltIn() {
        XCTAssertEqual(ExtraWorkUnit.typed("m"), .metres)
        XCTAssertEqual(ExtraWorkUnit.typed(" M² "), .squareMetres)
        XCTAssertEqual(ExtraWorkUnit.typed("Rolle"), .custom("Rolle"))
        XCTAssertNil(ExtraWorkUnit.typed("   "))
    }

    func testPiecesAndSetsAreTranslatedAndSymbolsAreNot() {
        XCTAssertEqual(ExtraWorkUnit.pieces.name(in: .english), "pcs")
        XCTAssertEqual(ExtraWorkUnit.pieces.name(in: .german), "Stk")
        XCTAssertEqual(ExtraWorkUnit.pieces.name(in: .croatian), "kom")
        XCTAssertEqual(ExtraWorkUnit.sets.name(in: .german), "Satz")
        XCTAssertEqual(ExtraWorkUnit.squareMetres.name(in: .german), "m²")
        XCTAssertEqual(ExtraWorkUnit.cubicMetres.name(in: .croatian), "m³")
        XCTAssertEqual(ExtraWorkUnit.hours.name(in: .polish), "h")
    }

    func testEveryUnitHasAWordInEveryLanguage() {
        for language in ExportLanguage.allCases {
            for unit in ExtraWorkUnit.builtIn {
                XCTAssertFalse(unit.name(in: language).isEmpty, "\(unit) in \(language)")
            }
        }
    }

    // MARK: - Quantities

    func testQuantitiesAreReadFromWhatWasTyped() {
        XCTAssertEqual(ExtraWorkQuantity.parse("12,5"), Decimal(string: "12.5"))
        XCTAssertEqual(ExtraWorkQuantity.parse("12.5"), Decimal(string: "12.5"))
        XCTAssertEqual(ExtraWorkQuantity.parse(" 8 "), 8)
        XCTAssertEqual(ExtraWorkQuantity.parse("0,25"), Decimal(string: "0.25"))
        XCTAssertNil(ExtraWorkQuantity.parse(""))
        XCTAssertNil(ExtraWorkQuantity.parse("abc"))
        XCTAssertNil(ExtraWorkQuantity.parse("-3"), "a negative amount of material is a slip")
    }

    func testQuantitiesAreWrittenWithoutNeedlessDecimals() {
        XCTAssertEqual(ExtraWorkQuantity.string(8, decimalSeparator: ","), "8")
        XCTAssertEqual(ExtraWorkQuantity.string(Decimal(string: "12.5")!, decimalSeparator: ","), "12,5")
        XCTAssertEqual(ExtraWorkQuantity.string(Decimal(string: "12.5")!, decimalSeparator: "."), "12.5")
        XCTAssertEqual(ExtraWorkQuantity.string(Decimal(string: "0.125")!, decimalSeparator: "."), "0.125")
        XCTAssertEqual(ExtraWorkQuantity.string(Decimal(string: "1.23456")!, decimalSeparator: "."), "1.235")
    }

    func testTheStepperMovesByOneAndStopsAtZero() {
        XCTAssertEqual(ExtraWorkQuantity.stepped(8, by: 1), 9)
        XCTAssertEqual(ExtraWorkQuantity.stepped(Decimal(string: "12.5")!, by: 1), Decimal(string: "13.5"))
        XCTAssertEqual(ExtraWorkQuantity.stepped(Decimal(string: "0.5")!, by: -1), 0)
        XCTAssertEqual(ExtraWorkQuantity.stepped(0, by: -1), 0)
    }

    func testAnItemReadsAsALine() {
        let lamps = ExtraWorkItem(name: "Emergency light", quantity: 8, unit: .pieces)
        let cable = ExtraWorkItem(name: "Cable NYM 3×1.5", quantity: Decimal(string: "25.5")!, unit: .metres)
        XCTAssertEqual(lamps.line(in: .english, decimalSeparator: "."), "8 × Emergency light")
        XCTAssertEqual(cable.line(in: .english, decimalSeparator: ","), "25,5 m Cable NYM 3×1.5")
        XCTAssertEqual(lamps.line(in: .german, decimalSeparator: ","), "8 × Emergency light", "the item's name is the user's own")
    }

    // MARK: - A job

    func testSavingDropsEmptyRowsAndTrimsTheDescription() {
        let typed = job("  Ceiling lamps  ", items: [
            ExtraWorkItem(name: "Lamp", quantity: 10, unit: .pieces),
            ExtraWorkItem(name: "  ", quantity: 3, unit: .pieces),
            ExtraWorkItem(name: "Box", quantity: 0, unit: .pieces)
        ])
        let cleaned = typed.cleaned()
        XCTAssertEqual(cleaned.description, "Ceiling lamps")
        XCTAssertEqual(cleaned.items.map(\.name), ["Lamp"])
    }

    func testHoursAreOptionalAndAddUpWhenThere() {
        var noted = job()
        XCTAssertFalse(noted.hasHours)
        XCTAssertEqual(noted.totalMinutes, 0)
        noted.hours = [ExtraWorkHours(memberID: UUID(), name: "Ivan", minutes: 180), ExtraWorkHours(name: "Marko", minutes: 180)]
        XCTAssertTrue(noted.hasHours)
        XCTAssertEqual(noted.totalMinutes, 360)
        noted.hours.append(ExtraWorkHours(name: "Luka", minutes: 0))
        XCTAssertEqual(noted.cleaned().hours.map(\.name), ["Ivan", "Marko"], "nobody with no time on the job")
    }

    func testABlankJobIsNotWorthKeeping() {
        XCTAssertTrue(job("  ", items: []).isBlank)
        XCTAssertFalse(job("Something", items: []).isBlank)
        XCTAssertFalse(job("", items: [ExtraWorkItem(name: "Lamp", quantity: 1, unit: .pieces)]).isBlank)
    }

    func testPhotosAreCappedAtSix() {
        XCTAssertEqual(ExtraWorkJob.maximumPhotos, 6)
        XCTAssertEqual(ExtraWorkJob.photoSlotsLeft(existing: 4), 2)
        XCTAssertEqual(ExtraWorkJob.photoSlotsLeft(existing: 9), 0)
    }

    // MARK: - Done

    func testANewJobIsInProgress() {
        let fresh = ExtraWorkJob(siteID: site, date: date)
        XCTAssertFalse(fresh.isDone)
        XCTAssertNil(fresh.doneAt)
        XCTAssertEqual(fresh.progress, .inProgress)
    }

    func testMarkingDoneRecordsWhenAndCanBeTakenBack() {
        let done = job().markingDone(at: moment)
        XCTAssertTrue(done.isDone)
        XCTAssertEqual(done.doneAt, moment)
        XCTAssertEqual(done.progress, .done)
        XCTAssertEqual(done.markingDone(at: moment.addingTimeInterval(60)).doneAt, moment, "done twice keeps the first time")

        let back = done.markingInProgress()
        XCTAssertFalse(back.isDone)
        XCTAssertNil(back.doneAt)
    }

    func testTogglingFlipsDone() {
        let toggled = job().togglingDone(at: moment)
        XCTAssertTrue(toggled.isDone)
        XCTAssertFalse(toggled.togglingDone(at: moment).isDone)
    }

    /// Done is the work, not the report: it never touches whether the boss
    /// has it.
    func testDoneLeavesTheSentMarkAlone() {
        let sent = job().markingSent(at: moment, reportID: UUID())
        let done = sent.markingDone(at: moment.addingTimeInterval(60))
        XCTAssertEqual(done.status, .sent)
        XCTAssertEqual(done.sentAt, moment)
    }

    // MARK: - Sent to the boss

    func testTheChipsAreProgressAndAtMostOneMore() {
        var work = job()
        XCTAssertEqual(work.progress, .inProgress)
        XCTAssertNil(work.chip, "nothing to say beyond In progress")
        work.clientSignature = ExtraWorkSignature(signerName: "Ing. Horvat", signedAt: moment, strokes: [[SignaturePoint(x: 0, y: 0), SignaturePoint(x: 1, y: 1)]])
        XCTAssertEqual(work.chip, .signed)
        work = work.markingSent(at: moment, reportID: UUID())
        XCTAssertEqual(work.chip, .sent)
    }

    func testSendingMarksSentWithTheReport() {
        let report = UUID()
        let sent = job().markingSent(at: moment, reportID: report)
        XCTAssertEqual(sent.status, .sent)
        XCTAssertEqual(sent.sentAt, moment)
        XCTAssertEqual(sent.sentReportID, report)
    }

    func testSendingAgainRecordsTheLatestReport() {
        let first = UUID()
        let second = UUID()
        let later = moment.addingTimeInterval(3600)
        let resent = job().markingSent(at: moment, reportID: first).markingSent(at: later, reportID: second)
        XCTAssertEqual(resent.sentReportID, second)
        XCTAssertEqual(resent.sentAt, later)
    }

    /// Sent while still in progress, then finished: the boss has heard it
    /// was under way, not that it is done, so it waits for the next report.
    func testAJobFinishedAfterItWasSentWaitsForTheNextReport() {
        let sentInProgress = job().markingSent(at: moment, reportID: UUID())
        XCTAssertFalse(sentInProgress.awaitsReport)
        let finished = sentInProgress.markingDone(at: moment.addingTimeInterval(3600))
        XCTAssertTrue(finished.awaitsReport)
        XCTAssertNil(finished.chip, "not Sent: the boss does not know it is done")
        let reported = finished.markingSent(at: moment.addingTimeInterval(7200), reportID: UUID())
        XCTAssertFalse(reported.awaitsReport)
        XCTAssertEqual(reported.chip, .sent)
    }

    func testAJobSentDoneNeedsNoOtherReport() {
        let done = job().markingDone(at: moment)
        XCTAssertTrue(done.awaitsReport)
        XCTAssertFalse(done.markingSent(at: moment.addingTimeInterval(60), reportID: UUID()).awaitsReport)
    }

    /// The rule the report screen follows: only a share that went through
    /// marks anything, and then every job in the report.
    func testOnlyACompletedShareMarksTheJobsAsSent() {
        let jobs = [job("a"), job("b", status: .sent)]
        let report = UUID()
        XCTAssertTrue(ExtraWorkSending.marked(jobs, after: .cancelled, reportID: report, at: moment).isEmpty)
        XCTAssertTrue(ExtraWorkSending.marked(jobs, after: .failed, reportID: report, at: moment).isEmpty)

        let marked = ExtraWorkSending.marked(jobs, after: .completed, reportID: report, at: moment)
        XCTAssertEqual(marked.map(\.description), ["a", "b"])
        XCTAssertTrue(marked.allSatisfy { $0.status == .sent && $0.sentReportID == report && $0.sentAt == moment })
    }

    /// Before 1.1 shipped, a sent job could be marked invoiced. There is no
    /// such step any more: what was invoiced had been sent.
    func testAnInvoicedJobReadsAsSent() throws {
        XCTAssertEqual(ExtraWorkStatus(storedValue: "invoiced"), .sent)
        XCTAssertEqual(ExtraWorkStatus(storedValue: "sent"), .sent)
        XCTAssertEqual(ExtraWorkStatus(storedValue: "open"), .open)
        XCTAssertEqual(ExtraWorkStatus(storedValue: "nonsense"), .open)
        XCTAssertEqual(ExtraWorkStatus.allCases, [.open, .sent])
        let json = #"{"id":"\#(UUID().uuidString)","siteID":"\#(site.uuidString)","date":20261022,"status":"invoiced"}"#
        XCTAssertEqual(try JSONDecoder().decode(ExtraWorkJob.self, from: Data(json.utf8)).status, .sent)
    }

    // MARK: - Coding

    func testAJobRoundTripsThroughJSON() throws {
        var original = job(items: [
            ExtraWorkItem(name: "Cable", quantity: Decimal(string: "12.5")!, unit: .metres),
            ExtraWorkItem(name: "Tape", quantity: 2, unit: .custom("Rolle"))
        ]).markingSent(at: moment, reportID: UUID()).markingDone(at: moment.addingTimeInterval(60))
        original.hours = [ExtraWorkHours(memberID: UUID(), name: "Ivan", minutes: 150)]
        original.clientSignature = ExtraWorkSignature(
            signerName: "Ing. M. Horvat", signedAt: moment, strokes: [[SignaturePoint(x: 0.1, y: 0.2), SignaturePoint(x: 1, y: 0.5)]]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ExtraWorkJob.self, from: encoder.encode(original))
        XCTAssertEqual(decoded, original)
    }

    /// Quantities are written as text so 12.5 stays 12.5 on every platform,
    /// and a number typed by hand into a backup still reads.
    func testAQuantityIsWrittenAsTextAndReadFromEither() throws {
        let item = ExtraWorkItem(name: "Cable", quantity: Decimal(string: "12.5")!, unit: .metres)
        let text = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        XCTAssertTrue(text.contains(#""quantity":"12.5""#), text)
        XCTAssertTrue(text.contains(#""unit":"m""#), text)
        let typed = try JSONDecoder().decode(ExtraWorkItem.self, from: Data(#"{"name":"Cable","quantity":7.25,"unit":"m2"}"#.utf8))
        XCTAssertEqual(typed.quantity, Decimal(string: "7.25"))
        XCTAssertEqual(typed.unit, .squareMetres)
    }

    func testDamageCostsTheFieldNotTheJob() throws {
        let json = #"{"id":"\#(UUID().uuidString)","siteID":"\#(site.uuidString)","date":20261022,"description":"Lamps","items":"garbage","status":"nonsense"}"#
        let decoded = try JSONDecoder().decode(ExtraWorkJob.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.description, "Lamps")
        XCTAssertEqual(decoded.items, [])
        XCTAssertEqual(decoded.status, .open)
        XCTAssertEqual(decoded.siteID, site)
    }

    /// Written before a job could be in progress, so written as finished
    /// work: a job without the field is done.
    func testAJobFromBeforeDoneReadsAsDone() throws {
        let json = #"{"id":"\#(UUID().uuidString)","siteID":"\#(site.uuidString)","date":20261022,"description":"Lamps","status":"open"}"#
        let decoded = try JSONDecoder().decode(ExtraWorkJob.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.isDone)
        XCTAssertNil(decoded.doneAt)
        XCTAssertTrue(decoded.awaitsReport)
    }

    func testAJobInProgressRoundTripsAsInProgress() throws {
        let original = job()
        let text = String(decoding: try JSONEncoder().encode(original), as: UTF8.self)
        XCTAssertTrue(text.contains(#""isDone":false"#), text)
        XCTAssertFalse(text.contains("doneAt"), "no date until it is done")
        XCTAssertFalse(try JSONDecoder().decode(ExtraWorkJob.self, from: Data(text.utf8)).isDone)
    }
}

/// The remembered items: what was used before, offered again first.
final class ExtraWorkCatalogTests: XCTestCase {
    private let monday = Date(timeIntervalSince1970: 1_791_000_000)
    private var tuesday: Date { monday.addingTimeInterval(86_400) }

    func testUsingAnItemRemembersItWithItsUnit() {
        let catalog = ExtraWorkCatalog.recording(
            [ExtraWorkItem(name: "Emergency light", quantity: 8, unit: .pieces)],
            into: [],
            at: monday
        )
        XCTAssertEqual(catalog.count, 1)
        XCTAssertEqual(catalog[0].name, "Emergency light")
        XCTAssertEqual(catalog[0].unit, .pieces)
        XCTAssertEqual(catalog[0].useCount, 1)
        XCTAssertEqual(catalog[0].lastUsed, monday)
    }

    func testUsingItAgainCountsAndKeepsTheNewestSpellingAndUnit() {
        let first = ExtraWorkCatalog.recording([ExtraWorkItem(name: "Kabel", quantity: 1, unit: .pieces)], into: [], at: monday)
        let second = ExtraWorkCatalog.recording([ExtraWorkItem(name: "kabel ", quantity: 5, unit: .metres)], into: first, at: tuesday)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].id, first[0].id)
        XCTAssertEqual(second[0].name, "kabel")
        XCTAssertEqual(second[0].unit, .metres)
        XCTAssertEqual(second[0].useCount, 2)
        XCTAssertEqual(second[0].lastUsed, tuesday)
    }

    func testTheSameItemTwiceInOneJobCountsOnce() {
        let catalog = ExtraWorkCatalog.recording(
            [ExtraWorkItem(name: "Box", quantity: 1, unit: .pieces), ExtraWorkItem(name: "box", quantity: 2, unit: .pieces)],
            into: [],
            at: monday
        )
        XCTAssertEqual(catalog.map(\.useCount), [1])
    }

    func testSuggestionsAreMostRecentFirstThenMostUsedAndSkipWhatIsAlreadyOnTheJob() {
        let catalog = [
            ExtraWorkCatalogItem(name: "Socket", unit: .pieces, useCount: 9, lastUsed: monday),
            ExtraWorkCatalogItem(name: "Junction box", unit: .pieces, useCount: 2, lastUsed: tuesday),
            ExtraWorkCatalogItem(name: "Ceiling lamp LED", unit: .pieces, useCount: 5, lastUsed: tuesday),
            ExtraWorkCatalogItem(name: "Emergency light", unit: .pieces, useCount: 1, lastUsed: tuesday)
        ]
        let suggested = ExtraWorkCatalog.suggestions(from: catalog, excluding: ["emergency LIGHT"])
        XCTAssertEqual(suggested.map(\.name), ["Ceiling lamp LED", "Junction box", "Socket"])
    }

    func testNamesMatchWithoutCaseOrAccents() {
        XCTAssertEqual(ExtraWorkCatalog.key("  Kabelkanal  Ä "), ExtraWorkCatalog.key("kabelkanal a"))
        XCTAssertNotEqual(ExtraWorkCatalog.key("Kabel"), ExtraWorkCatalog.key("Kabelkanal"))
    }
}
