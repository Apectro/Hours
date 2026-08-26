import XCTest
@testable import Hours

/// Settings and backups have to survive the app changing under them.
final class PersistenceCodingTests: XCTestCase {

    private func decodeSettings(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }

    func testAnEmptyObjectDecodesToTheDefaults() throws {
        let settings = try decodeSettings("{}")
        XCTAssertEqual(settings, AppSettings())
    }

    func testAPartialObjectKeepsEveryOtherDefault() throws {
        let settings = try decodeSettings(#"{"features":{"trackBreaks":false},"appearance":"dark"}"#)

        XCTAssertFalse(settings.features.trackBreaks)
        XCTAssertTrue(settings.features.trackNotes, "an unmentioned field keeps its default")
        XCTAssertEqual(settings.appearance, .dark)
        XCTAssertEqual(settings.schedule.weeklyTargetMinutes, 5 * 480)
    }

    func testAnUnreadableValueFallsBackRatherThanFailingTheWholeLoad() throws {
        // A future version storing a richer type here must not brick the app.
        let settings = try decodeSettings(#"{"rounding":{"unexpected":true},"openingBalanceMinutes":120}"#)

        XCTAssertEqual(settings.rounding, .exact)
        XCTAssertEqual(settings.openingBalanceMinutes, 120)
    }

    func testAnUnknownEnumCaseFallsBackToTheDefault() throws {
        let settings = try decodeSettings(#"{"durationPolicy":"quantumTime"}"#)
        XCTAssertEqual(settings.durationPolicy, .wallClock)
    }

    func testSettingsRoundTrip() throws {
        var settings = AppSettings()
        settings.features.trackLocation = true
        settings.schedule.setContractedMinutes(300, forWeekday: 7)
        settings.calendar.firstWeekdayOverride = 1
        settings.export.durationStyle = .decimal
        settings.customDayTypes = [
            DayTypeDefinition(
                id: DayTypeID("training"),
                name: "Training",
                symbolName: "book.fill",
                tint: .green,
                expectation: .creditedAbsence,
                showsTimesByDefault: false
            )
        ]
        settings.balanceStartDate = Fixture.date(2026, 1, 1)

        let data = try JSONEncoder().encode(settings)
        let restored = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(restored, settings)
        XCTAssertEqual(restored.dayTypeCatalog.definition(for: DayTypeID("training")).name, "Training")
    }

    func testACustomTypeOverridesTheBuiltInOfTheSameName() {
        var settings = AppSettings()
        settings.customDayTypes = [
            DayTypeDefinition(
                id: .vacation,
                name: "Unpaid leave",
                symbolName: "airplane",
                tint: .gray,
                expectation: .zero,
                showsTimesByDefault: false
            )
        ]

        let catalog = settings.dayTypeCatalog
        XCTAssertEqual(catalog.definition(for: .vacation).name, "Unpaid leave")
        XCTAssertEqual(catalog.definition(for: .vacation).expectation, .zero)
        XCTAssertEqual(
            catalog.all.filter { $0.id == .vacation }.count,
            1,
            "an override replaces the built-in rather than sitting beside it"
        )
    }

    func testAnUnpaidVacationOverrideChangesTheBalance() {
        var settings = Fixture.settings()
        settings.customDayTypes = [
            DayTypeDefinition(
                id: .vacation,
                name: "Unpaid leave",
                symbolName: "airplane",
                tint: .gray,
                expectation: .zero,
                showsTimesByDefault: false
            )
        ]
        let record = DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)
        let result = Fixture.calculator(settings: settings).compute(record: record, on: Fixture.workingTuesday)

        XCTAssertEqual(result.creditedMinutes, 0)
        XCTAssertEqual(result.expectedMinutes, 0)
        XCTAssertEqual(result.balanceMinutes, 0)
    }

    // MARK: - Day records

    func testADayRecordRoundTrips() throws {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            dayTypeID: .work,
            start: Fixture.time(8),
            end: Fixture.time(16, 30),
            breaks: [.duration(30), .timed(from: Fixture.time(12), to: Fixture.time(12, 15))],
            adjustmentMinutes: -15,
            note: "Quarter end",
            location: "Office",
            tags: ["billable"]
        )

        let data = try JSONEncoder().encode(record)
        let restored = try JSONDecoder().decode(DayRecord.self, from: data)

        XCTAssertEqual(restored, record)
    }

    func testDatesAndTimesArePersistedAsPlainNumbers() throws {
        // Wrapped in an array only so the JSON has a container; the point is
        // that a date is one integer and a time is one integer.
        let dateJSON = String(decoding: try JSONEncoder().encode([Fixture.workingTuesday]), as: UTF8.self)
        XCTAssertEqual(dateJSON, "[20260804]")

        let timeJSON = String(decoding: try JSONEncoder().encode([Fixture.time(16, 30)]), as: UTF8.self)
        XCTAssertEqual(timeJSON, "[990]")
    }

    func testABlankRecordIsRecognisedSoItCanBeDeletedRatherThanStored() {
        XCTAssertTrue(DayRecord(date: Fixture.workingTuesday).isBlank)
        XCTAssertTrue(DayRecord(date: Fixture.workingTuesday, breaks: [.duration(0)]).isBlank)
        XCTAssertFalse(DayRecord(date: Fixture.workingTuesday, start: Fixture.time(8)).isBlank)
        XCTAssertFalse(DayRecord(date: Fixture.workingTuesday, note: "x").isBlank)
        XCTAssertFalse(DayRecord(date: Fixture.workingTuesday, isIncluded: false).isBlank)
    }

    // MARK: - Backups

    func testABackupRoundTrips() throws {
        let archive = BackupArchive(
            settings: AppSettings(),
            days: [
                DayRecord(date: Fixture.workingMonday, start: Fixture.time(8), end: Fixture.time(16, 30)),
                DayRecord(date: Fixture.workingTuesday, dayTypeID: .vacation)
            ],
            holidays: [
                HolidayRule(name: "Christmas", recurrence: .annual(month: 12, day: 25))
            ]
        )

        let restored = try BackupArchive.decoded(from: try archive.encoded())

        XCTAssertEqual(restored.days.count, 2)
        XCTAssertEqual(restored.holidays.first?.name, "Christmas")
        XCTAssertEqual(restored.settings, archive.settings)
        XCTAssertEqual(restored.formatVersion, BackupArchive.currentFormatVersion)
    }

    func testABackupIsStoredInDateOrder() {
        let archive = BackupArchive(
            settings: AppSettings(),
            days: [
                DayRecord(date: Fixture.date(2026, 8, 20)),
                DayRecord(date: Fixture.date(2026, 8, 1)),
                DayRecord(date: Fixture.date(2026, 8, 10))
            ],
            holidays: []
        )
        XCTAssertEqual(archive.days.map(\.date.day), [1, 10, 20])
    }

    /// A backup missing its optional parts still loads, as long as it says
    /// what it is. The version marker is what identifies it as ours.
    func testAnIncompleteBackupStillLoads() throws {
        let archive = try BackupArchive.decoded(from: Data(#"{"formatVersion":1,"days":[]}"#.utf8))
        XCTAssertTrue(archive.holidays.isEmpty)
        XCTAssertEqual(archive.settings, AppSettings())
    }

    // MARK: - Refusing to restore from something that is not a backup
    //
    // Restoring erases everything on the device before writing what it read.
    // Decoding used to be lenient about every field, `try?` included, so any
    // JSON object at all decoded successfully — as an archive holding no days,
    // no holidays and default settings. Picking the wrong file, or a backup
    // truncated by a bad copy, deleted everything and put nothing back. The
    // importer's catch block could not fire, because nothing ever threw.

    func testAFileThatIsNotABackupIsRefused() {
        // All valid JSON, none of it a backup. This is what wiped the device.
        for json in [#"{}"#, #"{"days":[]}"#, #"{"hello":"world"}"#, #"{"formatVersion":"1"}"#] {
            XCTAssertThrowsError(
                try BackupArchive.decoded(from: Data(json.utf8)),
                "\(json) was accepted as a backup"
            ) { error in
                XCTAssertEqual(error as? BackupArchive.BackupError, .notABackup)
            }
        }
    }

    func testABackupFromANewerVersionIsRefused() {
        XCTAssertThrowsError(
            try BackupArchive.decoded(from: Data(#"{"formatVersion":99,"days":[]}"#.utf8))
        ) { error in
            XCTAssertEqual(error as? BackupArchive.BackupError, .fromANewerVersion(99))
        }
    }

    /// Damage in the records is damage, not an empty backup.
    func testADamagedListOfDaysIsRefused() {
        XCTAssertThrowsError(
            try BackupArchive.decoded(from: Data(#"{"formatVersion":1,"days":[{"date":"not a date"}]}"#.utf8))
        ) { error in
            XCTAssertEqual(error as? BackupArchive.BackupError, .unreadable("list of days"))
        }
    }

    /// Truncation is the realistic form of damage: a copy that stopped early.
    func testATruncatedBackupIsRefused() throws {
        let complete = try BackupArchive(
            settings: AppSettings(),
            days: [DayRecord(date: Fixture.workingMonday, start: Fixture.time(9), end: Fixture.time(17))],
            holidays: []
        ).encoded()

        XCTAssertThrowsError(
            try BackupArchive.decoded(from: Data(complete.prefix(complete.count / 2))),
            "half a backup file was accepted as a whole one"
        )
    }

    /// And a real one still loads, which is the point of all of it.
    func testARealBackupIsStillAccepted() throws {
        let archive = BackupArchive(
            settings: AppSettings(),
            days: [DayRecord(date: Fixture.workingMonday, start: Fixture.time(9), end: Fixture.time(17))],
            holidays: []
        )
        let restored = try BackupArchive.decoded(from: try archive.encoded())
        XCTAssertEqual(restored.days.count, 1)
        XCTAssertEqual(restored.formatVersion, BackupArchive.currentFormatVersion)
    }

    // MARK: - Entity mapping

    func testAnEntityRoundTripsThroughItsValueType() {
        let record = DayRecord(
            date: Fixture.workingTuesday,
            dayTypeID: .sick,
            start: Fixture.time(9),
            end: Fixture.time(17),
            breaks: [.duration(45)],
            adjustmentMinutes: 30,
            note: "Half day",
            location: "Home",
            tags: ["remote", "billable"],
            isIncluded: false
        )

        let entry = DayEntry(dateKey: record.date.key)
        entry.apply(record)

        XCTAssertEqual(entry.record, record)
        XCTAssertEqual(entry.dateKey, 20260804)
    }

    func testNewlinesInTagsCannotCorruptTheStoredList() {
        var record = DayRecord(date: Fixture.workingTuesday)
        record.tags = ["one\ntwo", "three"]

        let entry = DayEntry(dateKey: record.date.key)
        entry.apply(record)

        XCTAssertEqual(entry.record.tags, ["one two", "three"])
    }

    func testAHolidayRecordRoundTrips() {
        let rule = HolidayRule(
            name: "Thanksgiving",
            recurrence: .nthWeekday(ordinal: 4, weekday: 5, month: 11),
            countsAsWorkingDay: false,
            notes: "US"
        )
        let record = HolidayRecord(rule: rule)
        XCTAssertEqual(record.rule, rule)
    }
}
