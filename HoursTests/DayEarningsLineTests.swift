import XCTest
@testable import Hours

/// "Earned this day" (2026-11-24): the day's pay as plain lines, which are
/// the day's own earnings by another cut, so the days of a month add up to
/// the month.
final class DayEarningsLineTests: XCTestCase {
    private let calendar = Fixture.calendar()

    private func time(_ hour: Int, _ minute: Int = 0) -> TimeOfDay { TimeOfDay(hour: hour, minute: minute) }

    /// 12.50 an hour, overtime after the day's hours at 25%.
    private var rules: PayRules {
        var rules = PayRules(hourlyRateCents: 12_50)
        rules.overtimeMode = .afterDailyHours
        rules.overtimePercent = 25
        return rules
    }

    private func settings(_ rules: PayRules, configure: (inout AppSettings) -> Void = { _ in }) -> AppSettings {
        var settings = Fixture.settings()
        settings.changePay(forJob: Job.primaryID, to: rules, from: nil)
        configure(&settings)
        return settings
    }

    private func summary(_ settings: AppSettings, in range: CalendarDateRange, _ records: [DayRecord]) -> EarningsSummary? {
        Fixture.engine(settings: settings, calendar: calendar).earnings(
            in: range,
            records: Dictionary(records.map { ($0.date.key, $0) }, uniquingKeysWith: { _, last in last }),
            holidays: []
        )
    }

    private func day(_ settings: AppSettings, _ record: DayRecord) -> DayEarnings? {
        summary(settings, in: CalendarDateRange(single: record.date), [record])?.days.first
    }

    private func worked(_ date: CalendarDate, _ start: TimeOfDay, _ end: TimeOfDay, breakMinutes: Int = 0) -> DayRecord {
        DayRecord(date: date, shifts: [
            Shift(start: start, end: end, breaks: breakMinutes > 0 ? [.duration(breakMinutes)] : [])
        ])
    }

    // MARK: - The lines

    func testANormalDayIsOneLineHoursTimesTheRate() throws {
        let earned = try XCTUnwrap(day(settings(rules), worked(Fixture.workingTuesday, time(8), time(16, 30), breakMinutes: 30)))
        XCTAssertEqual(earned.lines, [
            DayEarningsLine(kind: .regular, minutes: 480, rateCents: 12_50, cents: 100_00)
        ])
    }

    func testOvertimeIsItsOwnLineAtTheRateWithTheSurchargeIn() throws {
        // 9h 30m on an 8h day: 8h at 12.50, 1h 30m at 15.63 (12.50 + 25%).
        let earned = try XCTUnwrap(day(settings(rules), worked(Fixture.workingTuesday, time(7), time(17), breakMinutes: 30)))
        XCTAssertEqual(earned.overtimeMinutes, 90)
        XCTAssertEqual(earned.lines.map(\.kind), [.regular, .overtime])
        XCTAssertEqual(earned.lines[0], DayEarningsLine(kind: .regular, minutes: 480, rateCents: 12_50, cents: 100_00))
        XCTAssertEqual(earned.lines[1].minutes, 90)
        XCTAssertEqual(earned.lines[1].rateCents, 15_63)
        XCTAssertEqual(earned.lines.reduce(0) { $0 + $1.cents }, earned.totalCents)
        XCTAssertEqual(earned.totalCents, earned.breakdown.baseCents + earned.breakdown.overtimeCents)
    }

    func testADayThatIsAllOvertimeHasNoRegularLine() throws {
        // A Saturday: nothing expected, so every hour is over the day's.
        let earned = try XCTUnwrap(day(settings(rules), worked(Fixture.saturday, time(8), time(12))))
        XCTAssertEqual(earned.lines.map(\.kind), [.overtime])
        XCTAssertEqual(earned.lines[0].minutes, 240)
        XCTAssertEqual(earned.lines[0].cents, earned.totalCents)
    }

    func testOvertimeAtTheSameRateStaysOneLine() throws {
        let earned = try XCTUnwrap(day(
            settings(PayRules(hourlyRateCents: 12_50)),
            worked(Fixture.workingTuesday, time(7), time(17), breakMinutes: 30)
        ))
        XCTAssertEqual(earned.lines, [DayEarningsLine(kind: .regular, minutes: 570, rateCents: 12_50, cents: 118_75)])
    }

    func testTheAllowanceAndKilometresAreLinesOfTheirOwn() throws {
        let settings = settings(rules) {
            $0.allowance = AllowancePreferences(isEnabled: true, dailyAllowanceCents: 20_00, centsPerKilometre: 42)
        }
        var record = worked(Fixture.workingTuesday, time(8), time(16, 30), breakMinutes: 30)
        record.hasFieldAllowance = true
        record.kilometres = 10
        let earned = try XCTUnwrap(day(settings, record))
        XCTAssertEqual(earned.lines.map(\.kind), [.regular, .allowance, .mileage])
        XCTAssertEqual(earned.lines[1].cents, 20_00)
        XCTAssertEqual(earned.lines[2].kilometres, 10)
        XCTAssertEqual(earned.lines[2].cents, 4_20)
        XCTAssertEqual(earned.lines.reduce(0) { $0 + $1.cents }, earned.totalCents)
    }

    func testAPaidDayOffIsALineWithItsHours() throws {
        var record = DayRecord(date: Fixture.workingTuesday)
        record.dayTypeID = .vacation
        let earned = try XCTUnwrap(day(settings(rules), record))
        XCTAssertEqual(earned.lines, [DayEarningsLine(kind: .paidAbsence, minutes: 480, cents: 100_00)])
    }

    func testSurchargesAreLinesWithTheHoursTheyWerePaidOn() throws {
        var rules = PayRules(hourlyRateCents: 12_50)
        rules.saturdayPercent = 50
        let earned = try XCTUnwrap(day(settings(rules), worked(Fixture.saturday, time(8), time(12))))
        XCTAssertEqual(earned.lines, [
            DayEarningsLine(kind: .regular, minutes: 240, rateCents: 12_50, cents: 50_00),
            DayEarningsLine(kind: .saturday, minutes: 240, cents: 25_00)
        ])
    }

    func testTwoJobsAtDifferentRatesNameNoRate() throws {
        var settings = settings(rules)
        let side = Job(name: "Side")
        settings.addJob(side)
        settings.changePay(forJob: side.id, to: PayRules(hourlyRateCents: 20_00), from: nil)
        let record = DayRecord(date: Fixture.workingTuesday, shifts: [
            Shift(start: time(8), end: time(12), jobID: Job.primaryID),
            Shift(start: time(13), end: time(15), jobID: side.id)
        ])
        let earned = try XCTUnwrap(day(settings, record))
        XCTAssertNil(earned.hourlyRateCents)
        let regular = try XCTUnwrap(earned.lines.first)
        XCTAssertEqual(regular.kind, .regular)
        XCTAssertNil(regular.rateCents)
        XCTAssertEqual(regular.minutes, 360)
        XCTAssertEqual(earned.lines.reduce(0) { $0 + $1.cents }, earned.totalCents)
    }

    func testADayThatEarnedNothingHasNoLines() throws {
        let earned = try XCTUnwrap(summary(
            settings(rules),
            in: CalendarDateRange(single: Fixture.saturday),
            []
        )?.days.first)
        XCTAssertTrue(earned.lines.isEmpty)
        XCTAssertEqual(earned.totalCents, 0)
    }

    // MARK: - The invariant

    /// A month with every kind of day in it: odd minutes, overtime, a
    /// Saturday, a night, a day off sick at 70%, allowance and kilometres.
    /// Each day's lines are its total, and the days are the month.
    func testTheDaysOfAMonthAddUpToTheMonth() throws {
        var rules = self.rules
        rules.saturdayPercent = 50
        rules.sundayAndHolidayPercent = 100
        rules.nightPercent = 30
        var settings = settings(rules) {
            $0.allowance = AllowancePreferences(isEnabled: true, dailyAllowanceCents: 20_00, centsPerKilometre: 42)
        }
        var sick = settings.dayTypeCatalog.definition(for: .sick)
        sick.paidPercent = 70
        settings.customDayTypes = [sick]

        let month = YearMonth(year: 2026, month: 8).range(in: calendar)
        var records: [DayRecord] = []
        for (offset, date) in month.days(in: calendar).enumerated() {
            switch offset % 7 {
            case 0:
                records.append(worked(date, time(7, 3), time(16, 41), breakMinutes: 37))
            case 1:
                var record = worked(date, time(6), time(18, 17), breakMinutes: 45)
                record.hasFieldAllowance = true
                record.kilometres = 13 + offset
                records.append(record)
            case 2:
                records.append(worked(date, time(20), time(4, 11)))
            case 3:
                var record = DayRecord(date: date)
                record.dayTypeID = offset > 15 ? .sick : .vacation
                records.append(record)
            case 4:
                records.append(worked(date, time(8), time(12, 1)))
            default:
                break
            }
        }

        let earned = try XCTUnwrap(summary(settings, in: month, records))
        XCTAssertFalse(earned.days.isEmpty)
        var kinds = Set<DayEarningsLine.Kind>()
        var total = 0
        for day in earned.days {
            let lines = day.lines
            XCTAssertEqual(lines.reduce(0) { $0 + $1.cents }, day.totalCents, "day \(day.date.key)")
            XCTAssertTrue(lines.allSatisfy { $0.cents >= 0 }, "day \(day.date.key)")
            kinds.formUnion(lines.map(\.kind))
            total += lines.reduce(0) { $0 + $1.cents }
        }
        XCTAssertEqual(total, earned.totalCents, "the month Insights shows")
        XCTAssertEqual(total, earned.months.first?.totalCents)
        XCTAssertEqual(
            kinds,
            [.regular, .overtime, .saturday, .sundayAndHoliday, .night, .paidAbsence, .allowance, .mileage],
            "the month has every kind of line in it"
        )
    }

    // MARK: - Hidden amounts and the settings

    func testAHiddenAmountIsThreeDotsWhateverItIs() {
        let money = MoneyFormatting(currencyCode: "EUR", locale: Locale(identifier: "en_IE"))
        XCTAssertEqual(money.string(143_45, hidden: true), "•••")
        XCTAssertEqual(money.string(0, showsCents: false, hidden: true), "•••")
        XCTAssertEqual(money.string(143_45, hidden: false), money.string(143_45))
        XCTAssertEqual(money.string(143_45, showsCents: false, hidden: false), money.string(143_45, showsCents: false))
    }

    func testDayMoneyInTheCalendarIsOnByDefaultAndNeedsPay() {
        XCTAssertTrue(AppSettings().showDayEarningsInCalendar)
        XCTAssertFalse(AppSettings().hideAmounts)
        XCTAssertFalse(Fixture.settings().showsDayEarningsInCalendar, "no rate: nothing to show")
        var settings = settings(rules)
        XCTAssertTrue(settings.showsDayEarningsInCalendar)
        settings.showDayEarningsInCalendar = false
        XCTAssertFalse(settings.showsDayEarningsInCalendar)
    }

    func testTheTwoSwitchesRoundTripAndAreWrittenOnlyWhenChanged() throws {
        let untouched = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AppSettings())) as? [String: Any]
        XCTAssertNil(untouched?["showDayEarningsInCalendar"])
        XCTAssertNil(untouched?["hideAmounts"])

        var settings = AppSettings()
        settings.showDayEarningsInCalendar = false
        settings.hideAmounts = true
        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertFalse(decoded.showDayEarningsInCalendar)
        XCTAssertTrue(decoded.hideAmounts)
        XCTAssertEqual(decoded, settings)
    }

    func testOlderSettingsAndJunkReadAsTheDefaults() throws {
        let older = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(older.showDayEarningsInCalendar)
        XCTAssertFalse(older.hideAmounts)
        let junk = try JSONDecoder().decode(
            AppSettings.self,
            from: Data(#"{"showDayEarningsInCalendar": "no", "hideAmounts": 7}"#.utf8)
        )
        XCTAssertTrue(junk.showDayEarningsInCalendar)
        XCTAssertFalse(junk.hideAmounts)
    }
}
