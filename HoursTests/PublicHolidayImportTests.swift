import XCTest
@testable import Hours

/// Adding a country's holidays, taking them away again, the one-time offer,
/// and what a public holiday you worked comes to.
final class PublicHolidayImportTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private var austria: PublicHolidaySet { PublicHolidayCatalog.set(country: .at, region: nil)! }

    private func plan(
        _ set: PublicHolidaySet,
        existing: [HolidayRule] = [],
        selection: Set<String>? = nil,
        language: ExportLanguage = .german
    ) -> PublicHolidayImport.Plan {
        PublicHolidayImport.plan(
            set: set,
            selection: selection ?? set.defaultSelection,
            existing: existing,
            language: language,
            calendar: calendar,
            fromYear: 2026
        )
    }

    // MARK: - Adding

    func testAddingASetCreatesOrdinaryPaidHolidayRules() {
        let result = plan(austria)

        XCTAssertEqual(result.rules.count, 13)
        XCTAssertTrue(result.skipped.isEmpty)
        XCTAssertTrue(result.rules.allSatisfy { !$0.countsAsWorkingDay && $0.isEnabled })
        XCTAssertTrue(result.rules.contains { $0.name == "Mariä Empfängnis" && $0.recurrence == .annual(month: 12, day: 8) })
        XCTAssertTrue(result.rules.contains { $0.name == "Fronleichnam" && $0.recurrence == .easter(offset: 60) })
    }

    func testNamesFollowThePhone() {
        let result = plan(austria, language: .english)
        XCTAssertTrue(result.rules.contains { $0.name == "Christmas Day" })
    }

    func testOnlyTheTickedHolidaysAreAdded() {
        let bavaria = PublicHolidayCatalog.set(country: .de, region: "BY")!
        XCTAssertEqual(plan(bavaria).rules.count, 12)
        XCTAssertEqual(plan(bavaria, selection: bavaria.defaultSelection.union(["assumption"])).rules.count, 13)
    }

    func testAHolidayAlreadyThereIsSkipped() {
        let mine = HolidayRule(name: "Weihnachten", recurrence: .annual(month: 12, day: 25))
        // Disabled on purpose is still there: adding it again would undo
        // the person's own choice.
        let alsoMine = HolidayRule(name: "Feiertag", recurrence: .annual(month: 1, day: 6), isEnabled: false)

        let result = plan(austria, existing: [mine, alsoMine])

        XCTAssertEqual(result.rules.count, 11)
        XCTAssertEqual(Set(result.skipped.map(\.id)), ["christmas", "epiphany"])
    }

    func testAOneOffOnTheSameDayDoesNotStandInForEveryYear() {
        let once = HolidayRule(name: "Ostermontag", recurrence: .once(on: Fixture.date(2026, 4, 6)))
        let result = plan(austria, existing: [once])
        XCTAssertTrue(result.rules.contains { $0.recurrence == .easter(offset: 1) })
    }

    func testAnEarlierEasterRuleIsADuplicate() {
        let mine = HolidayRule(name: "Ostermontag", recurrence: .easter(offset: 1))
        XCTAssertEqual(plan(austria, existing: [mine]).skipped.map(\.id), ["easterMonday"])
    }

    // MARK: - Remembering, removing, offering

    func testAddingIsRememberedAndRemovalTakesOnlyThoseRules() {
        let mine = HolidayRule(name: "Betriebsurlaub", recurrence: .annual(month: 8, day: 14))
        let result = plan(austria, existing: [mine])

        var preferences = PublicHolidayPreferences()
        preferences.recordAdded(set: austria, rules: result.rules)
        XCTAssertEqual(preferences.addedSetID, "AT")
        XCTAssertEqual(preferences.addedSet?.id, "AT")

        // One of them deleted by hand since.
        let onDevice = [mine] + result.rules.dropFirst()
        let removing = preferences.rulesToRemove(from: onDevice)
        XCTAssertEqual(Set(removing), Set(result.rules.dropFirst().map(\.id)))
        XCTAssertFalse(removing.contains(mine.id))

        preferences.forgetAdded()
        XCTAssertNil(preferences.addedSetID)
        XCTAssertTrue(preferences.addedRuleIDs.isEmpty)
    }

    func testTheOfferIsMadeOnceToSomeoneWithNoHolidays() {
        var preferences = PublicHolidayPreferences()
        XCTAssertTrue(preferences.shouldOffer(hasHolidayRules: false))
        XCTAssertFalse(preferences.shouldOffer(hasHolidayRules: true), "they keep their own")

        preferences.offerDismissed = true
        XCTAssertFalse(preferences.shouldOffer(hasHolidayRules: false))

        var added = PublicHolidayPreferences()
        added.recordAdded(set: austria, rules: plan(austria).rules)
        // Even after removing them again: the question was answered.
        added.forgetAdded()
        XCTAssertFalse(added.shouldOffer(hasHolidayRules: false))
    }

    // MARK: - Settings and backups

    func testOldSettingsReadAsNothingAdded() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.publicHolidays, PublicHolidayPreferences())
    }

    func testTheChoiceRoundTripsThroughABackup() throws {
        var settings = AppSettings()
        let rules = plan(austria).rules
        settings.publicHolidays.recordAdded(set: austria, rules: rules)

        let archive = BackupArchive(settings: settings, days: [], holidays: rules)
        let restored = try BackupArchive.decoded(from: try archive.encoded())

        XCTAssertEqual(restored.settings.publicHolidays, settings.publicHolidays)
        XCTAssertEqual(restored.holidays, rules)
    }

    /// An older backup's holidays read exactly as before.
    func testAnOldBackupStillRestoresItsHolidays() throws {
        let json = #"""
        {"formatVersion":1,"days":[],"holidays":[
          {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Christmas","countsAsWorkingDay":false,
           "isEnabled":true,"notes":"",
           "recurrence":{"kind":"annual","year":2000,"month":12,"day":25,"weekday":2,"ordinal":1}}
        ]}
        """#
        let archive = try BackupArchive.decoded(from: Data(json.utf8))
        XCTAssertEqual(archive.holidays.first?.recurrence, .annual(month: 12, day: 25))
    }

    /// What 1.0 sees of a 1.1 backup with Easter holidays in it: every rule
    /// still decodes with its strict, synthesised shape.
    func testA10AppCanStillReadTheHolidays() throws {
        let archive = BackupArchive(settings: AppSettings(), days: [], holidays: plan(austria).rules)
        let data = try archive.encoded()

        struct OneZeroArchive: Decodable {
            struct Rule: Decodable {
                struct Recurrence: Decodable {
                    enum Kind: String, Decodable { case once, annual, nthWeekday }
                    var kind: Kind
                    var year: Int
                    var month: Int
                    var day: Int
                    var weekday: Int
                    var ordinal: Int
                    var startYear: Int?
                    var endYear: Int?
                }
                var id: UUID
                var name: String
                var recurrence: Recurrence
                var countsAsWorkingDay: Bool
                var isEnabled: Bool
                var notes: String
            }
            var holidays: [Rule]
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let old = try decoder.decode(OneZeroArchive.self, from: data)
        XCTAssertEqual(old.holidays.count, 13)
    }

    // MARK: - Working a public holiday

    func testWorkingAPublicHolidayIsPaidHolidayPlusEveryHourWorked() {
        let holiday = HolidayRule(name: "Mariä Himmelfahrt", recurrence: .annual(month: 8, day: 4))
        let engine = Fixture.engine()
        let draft = engine.draftRecord(for: Fixture.workingTuesday, holidays: [holiday], working: true)

        XCTAssertEqual(draft.shifts.count, 1, "times prefilled from the week")
        XCTAssertEqual(draft.shifts.first?.start, Fixture.time(8))

        let day = engine.day(Fixture.workingTuesday, record: draft, holidays: [holiday])
        XCTAssertEqual(day.dayType.id, .holiday)
        XCTAssertEqual(day.holidayName, "Mariä Himmelfahrt")
        XCTAssertEqual(day.creditedMinutes, 480, "the holiday is still paid")
        XCTAssertEqual(day.workedMinutes, 480)
        XCTAssertEqual(day.expectedMinutes, 480)
        XCTAssertEqual(day.balanceMinutes, 480, "every hour worked is on top")
        XCTAssertTrue(day.isWorkedPublicHoliday)
    }

    func testADayOffOnAPublicHolidayIsNotAWorkedOne() {
        let holiday = HolidayRule(name: "Mariä Himmelfahrt", recurrence: .annual(month: 8, day: 4))
        let engine = Fixture.engine()
        let draft = engine.draftRecord(for: Fixture.workingTuesday, holidays: [holiday])
        XCTAssertTrue(draft.shifts.isEmpty, "the default is the paid day off")

        let day = engine.day(Fixture.workingTuesday, record: nil, holidays: [holiday])
        XCTAssertFalse(day.isWorkedPublicHoliday)
        XCTAssertEqual(day.balanceMinutes, 0)
    }

    func testAWorkedPublicHolidayEarnsTheHolidayPayTheHoursAndTheSurcharge() throws {
        var settings = Fixture.settings()
        var rules = PayRules(hourlyRateCents: 20_00)
        rules.sundayAndHolidayPercent = 100
        settings.changePay(forJob: Job.primaryID, to: rules, from: nil)
        let engine = Fixture.engine(settings: settings)
        let holiday = HolidayRule(name: "Mariä Himmelfahrt", recurrence: .annual(month: 8, day: 4))

        let draft = engine.draftRecord(for: Fixture.workingTuesday, holidays: [holiday], working: true)
        let earnings = try XCTUnwrap(
            engine.earnings(
                in: CalendarDateRange(single: Fixture.workingTuesday),
                records: [draft.date.key: draft],
                holidays: [holiday]
            )?.days.first
        )

        XCTAssertEqual(earnings.breakdown.paidAbsenceCents, 160_00, "8 h of paid holiday")
        XCTAssertEqual(earnings.breakdown.baseCents, 160_00, "8 h worked")
        XCTAssertEqual(earnings.breakdown.sundayAndHolidayCents, 160_00, "100 % on the 8 h worked")
        XCTAssertEqual(earnings.totalCents, 480_00)
    }

    func testAWorkedHolidayOnASaturdayIsStillAWorkedHoliday() {
        let holiday = HolidayRule(name: "Mariä Himmelfahrt", recurrence: .annual(month: 8, day: 8))
        let engine = Fixture.engine()
        let draft = engine.draftRecord(for: Fixture.saturday, holidays: [holiday], working: true)
        XCTAssertEqual(draft.shifts.count, 1)

        let day = engine.day(Fixture.saturday, record: draft, holidays: [holiday])
        XCTAssertTrue(day.isWorkedPublicHoliday)
        XCTAssertEqual(day.creditedMinutes, 0, "nothing was owed on a Saturday")
        XCTAssertEqual(day.balanceMinutes, 480)
    }
}
