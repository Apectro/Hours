import XCTest
@testable import Hours

/// Closing a year, and where the next one starts counting from.
final class CarryOverTests: XCTestCase {
    private let uncapped = CarryOverPolicy(isEnabled: true, capMinutes: nil)
    private func capped(at minutes: Int, then surplus: YearEndSurplus = .paidOut) -> CarryOverPolicy {
        CarryOverPolicy(isEnabled: true, capMinutes: minutes, surplusAbove: surplus)
    }

    // MARK: - Closing

    func testAnUncappedYearCarriesEverything() {
        let close = CarryOver.close(year: 2026, balance: 4_800, policy: uncapped)

        XCTAssertEqual(close.carriedMinutes, 4_800)
        XCTAssertEqual(close.closingMinutes, 4_800)
        XCTAssertEqual(close.surplusMinutes, 0)
        XCTAssertEqual(close.surplus, .none, "nothing was above a cap there is not")
    }

    func testABalanceUnderTheCapCarriesWhole() {
        let close = CarryOver.close(year: 2026, balance: 1_200, policy: capped(at: 3_000))

        XCTAssertEqual(close.carriedMinutes, 1_200)
        XCTAssertEqual(close.surplusMinutes, 0)
        XCTAssertEqual(close.surplus, .none)
    }

    func testTheCapTakesOnlyWhatIsAboveIt() {
        let close = CarryOver.close(year: 2026, balance: 5_000, policy: capped(at: 3_000))

        XCTAssertEqual(close.carriedMinutes, 3_000)
        XCTAssertEqual(close.closingMinutes, 5_000, "the close records what the balance was")
        XCTAssertEqual(close.surplusMinutes, 2_000)
        XCTAssertEqual(close.surplus, .paidOut)
    }

    func testWhatHappensAboveTheCapIsRecorded() {
        let forfeited = CarryOver.close(year: 2026, balance: 5_000, policy: capped(at: 3_000, then: .forfeited))

        XCTAssertEqual(forfeited.surplus, .forfeited)
        XCTAssertEqual(forfeited.surplusMinutes, 2_000, "the hours are the same either way")
    }

    /// The rule most worth stating out loud.
    ///
    /// A cap on a working-time account is a ceiling on hours owed *to* you.
    /// Applying it to a deficit would quietly forgive hours still owed — the
    /// app inventing time nobody worked, which is the one thing the rest of
    /// the engine refuses to do.
    func testADeficitIsNeverCapped() {
        for cap in [0, 600, 3_000] {
            let close = CarryOver.close(year: 2026, balance: -2_400, policy: capped(at: cap))

            XCTAssertEqual(close.carriedMinutes, -2_400, "a cap of \(cap) touched a deficit")
            XCTAssertEqual(close.surplusMinutes, 0)
            XCTAssertEqual(close.surplus, .none)
        }
    }

    /// A cap of zero is a real setting — the contract that says the account
    /// resets every January — and it must not be confused with no cap at all.
    func testACapOfZeroCarriesNothingButStillKeepsADeficit() {
        let credit = CarryOver.close(year: 2026, balance: 3_000, policy: capped(at: 0))
        XCTAssertEqual(credit.carriedMinutes, 0)
        XCTAssertEqual(credit.surplusMinutes, 3_000)

        let deficit = CarryOver.close(year: 2026, balance: -3_000, policy: capped(at: 0))
        XCTAssertEqual(deficit.carriedMinutes, -3_000, "a zero cap is not an amnesty")
    }

    func testAPolicyThatIsOffCarriesEverythingRegardless() {
        let off = CarryOverPolicy(isEnabled: false, capMinutes: 60, surplusAbove: .forfeited)
        let close = CarryOver.close(year: 2026, balance: 5_000, policy: off)

        XCTAssertEqual(close.carriedMinutes, 5_000, "a cap that is switched off is not a cap")
        XCTAssertEqual(close.surplus, .none)
    }

    /// A negative cap is not a setting anybody means. It must not be read as
    /// "carry minus ten hours" — the guard treats it as no cap at all.
    func testANegativeCapIsIgnoredRatherThanApplied() {
        let close = CarryOver.close(year: 2026, balance: 5_000, policy: capped(at: -600))

        XCTAssertEqual(close.carriedMinutes, 5_000)
        XCTAssertEqual(close.surplus, .none)
    }

    // MARK: - Where a balance starts

    private let opening = 900

    /// Mid-year, so nothing here can pass by accident on a boundary.
    private func day(_ year: Int) -> CalendarDate {
        CalendarDate(year: year, month: 6, day: 15)
    }

    func testWithNoClosesTheOpeningBalanceStillGoverns() {
        let origin = CarryOver.origin(
            for: day(2026), closes: [], openingMinutes: opening, balanceStartDate: nil
        )

        XCTAssertEqual(origin.openingMinutes, opening)
        XCTAssertNil(origin.startDate)
    }

    /// Closing 2026 governs 2027 onwards, not 2026 — which is the year the
    /// close was computed *from*. Getting this off by one would make the
    /// closed year start from its own result, doubling it.
    func testACloseGovernsTheYearAfterItAndNotItsOwn() {
        let closes = [CarryOver.close(year: 2026, balance: 5_000, policy: capped(at: 3_000))]

        let during = CarryOver.origin(
            for: day(2026), closes: closes, openingMinutes: opening, balanceStartDate: nil
        )
        XCTAssertEqual(during.openingMinutes, opening, "2026 must not start from its own close")
        XCTAssertNil(during.startDate)

        let after = CarryOver.origin(
            for: day(2027), closes: closes, openingMinutes: opening, balanceStartDate: nil
        )
        XCTAssertEqual(after.openingMinutes, 3_000)
        XCTAssertEqual(after.startDate, CalendarDate(year: 2027, month: 1, day: 1))
    }

    func testTheMostRecentCloseWins() {
        let closes = [
            CarryOver.close(year: 2024, balance: 1_000, policy: uncapped),
            CarryOver.close(year: 2026, balance: 5_000, policy: capped(at: 3_000)),
            CarryOver.close(year: 2025, balance: 2_000, policy: uncapped),
        ]

        let origin = CarryOver.origin(
            for: day(2027), closes: closes, openingMinutes: opening, balanceStartDate: nil
        )

        XCTAssertEqual(origin.openingMinutes, 3_000, "the 2026 close is the one that applies")
        XCTAssertEqual(origin.startDate, CalendarDate(year: 2027, month: 1, day: 1))
    }

    func testAYearClosedTwiceKeepsTheLastAnswer() {
        let closes = [
            CarryOver.close(year: 2026, balance: 5_000, policy: capped(at: 3_000)),
            CarryOver.close(year: 2026, balance: 4_000, policy: uncapped),
        ]

        let origin = CarryOver.origin(
            for: day(2027), closes: closes, openingMinutes: opening, balanceStartDate: nil
        )

        XCTAssertEqual(origin.openingMinutes, 4_000)
    }

    /// Someone who set a start date *and* closed a year means the later of the
    /// two. Taking the earlier would count days they had deliberately left out.
    func testAStartDateAfterACloseStillApplies() {
        let closes = [CarryOver.close(year: 2026, balance: 3_000, policy: uncapped)]
        let march = CalendarDate(year: 2027, month: 3, day: 1)

        let origin = CarryOver.origin(
            for: day(2027), closes: closes, openingMinutes: opening, balanceStartDate: march
        )

        XCTAssertEqual(origin.startDate, march)
        XCTAssertEqual(origin.openingMinutes, 3_000)
    }

    func testAStartDateBeforeACloseIsSupersededByIt() {
        let closes = [CarryOver.close(year: 2026, balance: 3_000, policy: uncapped)]
        let longAgo = CalendarDate(year: 2020, month: 1, day: 1)

        let origin = CarryOver.origin(
            for: day(2027), closes: closes, openingMinutes: opening, balanceStartDate: longAgo
        )

        XCTAssertEqual(
            origin.startDate,
            CalendarDate(year: 2027, month: 1, day: 1),
            "counting from 2020 would add the closed years back on top of the carry-over"
        )
    }

    /// The whole point, stated as arithmetic: closing a year and carrying it
    /// forward must give the same running balance as never having closed it,
    /// whenever nothing was capped. A carry-over that quietly changes the
    /// figure is worse than no carry-over.
    func testAnUncappedCloseChangesNoTotal() {
        // A real January, built the way the rest of the suite builds days:
        // four nine-hour Mondays against an eight-hour schedule.
        let calendar = Fixture.calendar()
        let worked = [5, 12, 19, 26].map { CalendarDate(year: 2027, month: 1, day: $0) }
        let records = Dictionary(uniqueKeysWithValues: worked.map { date in
            (date.key, DayRecord(date: date, start: Fixture.time(8), end: Fixture.time(17)))
        })
        let days = Fixture.engine(calendar: calendar).days(
            in: CalendarDateRange(
                start: CalendarDate(year: 2027, month: 1, day: 1),
                end: CalendarDate(year: 2027, month: 1, day: 31)
            ),
            records: records,
            holidays: []
        )

        let closes = [CarryOver.close(year: 2026, balance: 3_000, policy: uncapped)]
        let origin = CarryOver.origin(
            for: worked[0], closes: closes, openingMinutes: 0, balanceStartDate: nil
        )

        let withClose = BalanceLedger.cumulative(
            over: days, openingMinutes: origin.openingMinutes, startDate: origin.startDate
        )
        let withoutClose = BalanceLedger.cumulative(
            over: days, openingMinutes: 3_000, startDate: nil
        )

        XCTAssertEqual(withClose, withoutClose)

        // Not "greater than 3000", which is what this asserted first and is
        // simply untrue: a full January holds about eighteen working days and
        // only four of them were worked, so the month is a large deficit. The
        // claim worth making is that the carried figure is added to whatever
        // the period came to, whichever way that went.
        let periodAlone = BalanceLedger.cumulative(
            over: days, openingMinutes: 0, startDate: nil
        )
        XCTAssertEqual(withClose, periodAlone + 3_000)
        XCTAssertLessThan(periodAlone, 0, "the unworked weekdays should make January negative")
    }

    func testLatestCloseIsTheHighestYear() {
        XCTAssertNil(CarryOver.latest(in: []))

        let closes = [
            CarryOver.close(year: 2024, balance: 1_000, policy: uncapped),
            CarryOver.close(year: 2026, balance: 2_000, policy: uncapped),
            CarryOver.close(year: 2025, balance: 3_000, policy: uncapped),
        ]
        XCTAssertEqual(CarryOver.latest(in: closes)?.year, 2026)
    }
}
