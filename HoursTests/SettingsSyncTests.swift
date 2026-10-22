import XCTest
@testable import Hours

/// Settings across devices, through the iCloud key-value store.
///
/// Settings are not in the SwiftData store, and a second device computing
/// expected hours from a different contracted week would be wrong rather than
/// merely different, so they sync too. These are the rules for which copy
/// wins, and the two things a device joining must not lose.
final class SettingsSyncTests: XCTestCase {
    private func custom(_ id: String, _ name: String, _ policy: ExpectationPolicy = .creditedAbsence) -> DayTypeDefinition {
        DayTypeDefinition(
            id: DayTypeID(id), name: name, symbolName: "book", tint: .teal,
            expectation: policy, showsTimesByDefault: false
        )
    }

    private func settings(week hours: Int = 8, customTypes: [DayTypeDefinition] = []) -> AppSettings {
        var settings = Fixture.settings(customDayTypes: customTypes)
        settings.openingBalanceMinutes = hours * 60
        return settings
    }

    // MARK: - At launch

    func testTheFirstDeviceUploadsWhatItHas() {
        // Without this, the first device's settings stayed on it until the
        // next time something changed, and a second device joining found
        // nothing and kept its defaults.
        let mine = settings(week: 7)
        let outcome = SettingsSync.atLaunch(local: mine, remote: nil, hasJoined: false)
        XCTAssertEqual(outcome.settings, mine)
        XCTAssertTrue(outcome.pushes)
        XCTAssertFalse(outcome.writesLocally)
        XCTAssertFalse(outcome.hasJoined, "nothing came from iCloud yet, so there was nothing to join")
    }

    func testAFreshInstallWithNothingAnywhereHasNothingToSend() {
        let outcome = SettingsSync.atLaunch(local: nil, remote: nil, hasJoined: false)
        XCTAssertEqual(outcome.settings, AppSettings())
        XCTAssertFalse(outcome.pushes)
        XCTAssertFalse(outcome.writesLocally)
    }

    func testANewDeviceTakesTheSettingsAlreadyInICloud() {
        let theirs = settings(week: 6)
        let outcome = SettingsSync.atLaunch(local: nil, remote: theirs, hasJoined: false)
        XCTAssertEqual(outcome.settings, theirs)
        XCTAssertTrue(outcome.writesLocally, "kept here too, so switching sync off does not drop back to defaults")
        XCTAssertFalse(outcome.pushes)
        XCTAssertTrue(outcome.hasJoined)
    }

    func testJoiningKeepsTheDayTypesThisDeviceMadeItself() {
        // Days on this device carry the ids of its own custom types; taking
        // the other device's settings wholesale would turn them all Unknown
        // and change what they count.
        let school = custom("6F1D3B0A-0000-0000-0000-000000000001", "Berufsschule")
        let shared = custom("6F1D3B0A-0000-0000-0000-000000000002", "Schulung")
        let theirs = settings(week: 6, customTypes: [shared])
        let mine = settings(week: 7, customTypes: [shared, school])

        let outcome = SettingsSync.atLaunch(local: mine, remote: theirs, hasJoined: false)
        XCTAssertEqual(outcome.settings.openingBalanceMinutes, 6 * 60, "everything else is iCloud's")
        XCTAssertEqual(outcome.settings.customDayTypes.map(\.name), ["Schulung", "Berufsschule"])
        XCTAssertTrue(outcome.pushes, "the other devices need the joined list too")
        XCTAssertTrue(outcome.writesLocally)
        XCTAssertTrue(outcome.hasJoined)
    }

    func testOnTheSameIdICloudsVersionOfADayTypeWins() {
        let theirs = settings(customTypes: [custom("6F1D3B0A-0000-0000-0000-000000000002", "Schulung", .zero)])
        let mine = settings(customTypes: [custom("6F1D3B0A-0000-0000-0000-000000000002", "Training", .creditedAbsence)])
        let outcome = SettingsSync.atLaunch(local: mine, remote: theirs, hasJoined: false)
        XCTAssertEqual(outcome.settings.customDayTypes.map(\.name), ["Schulung"])
        XCTAssertFalse(outcome.pushes)
    }

    func testJoiningKeepsTheRulesOfTheSameCountrysHolidaysFromBothDevices() {
        // Both devices added Austria. Whichever rules survive the holiday
        // collapse, "Remove these holidays" has to find them.
        let austria = PublicHolidayCatalog.set(country: .at, region: nil)!
        let phoneRules = [UUID(), UUID()]
        let iPadRules = [UUID(), UUID()]
        var theirs = settings()
        theirs.publicHolidays.recordAdded(set: austria, rules: phoneRules.map { HolidayRule(id: $0, name: "x", recurrence: .annual(month: 1, day: 1)) })
        var mine = settings()
        mine.publicHolidays.recordAdded(set: austria, rules: iPadRules.map { HolidayRule(id: $0, name: "x", recurrence: .annual(month: 1, day: 1)) })

        let outcome = SettingsSync.atLaunch(local: mine, remote: theirs, hasJoined: false)
        XCTAssertEqual(outcome.settings.publicHolidays.addedRuleIDs, phoneRules + iPadRules)
    }

    func testADifferentCountrysRulesAreNotAddedToTheList() {
        // "Remove these holidays" names one set; it must not take another
        // set's rules with it.
        let austria = PublicHolidayCatalog.set(country: .at, region: nil)!
        let other = PublicHolidayCatalog.set(country: .nl, region: nil)!
        var theirs = settings()
        theirs.publicHolidays.recordAdded(set: austria, rules: [HolidayRule(name: "x", recurrence: .annual(month: 1, day: 1))])
        var mine = settings()
        mine.publicHolidays.recordAdded(set: other, rules: [HolidayRule(name: "y", recurrence: .annual(month: 1, day: 2))])

        let outcome = SettingsSync.atLaunch(local: mine, remote: theirs, hasJoined: false)
        XCTAssertEqual(outcome.settings.publicHolidays, theirs.publicHolidays)
    }

    func testOnceJoinedICloudsCopyIsTheAnswer() {
        // A custom type deleted on another device must stay deleted: joining
        // happens once, not at every launch.
        let gone = custom("6F1D3B0A-0000-0000-0000-000000000003", "Alt")
        let theirs = settings(week: 6)
        let mine = settings(week: 6, customTypes: [gone])
        let outcome = SettingsSync.atLaunch(local: mine, remote: theirs, hasJoined: true)
        XCTAssertEqual(outcome.settings, theirs)
        XCTAssertTrue(outcome.writesLocally)
        XCTAssertFalse(outcome.pushes)
    }

    func testNothingIsWrittenWhenBothAlreadyAgree() {
        let same = settings(week: 6)
        let outcome = SettingsSync.atLaunch(local: same, remote: same, hasJoined: true)
        XCTAssertFalse(outcome.writesLocally)
        XCTAssertFalse(outcome.pushes)
    }

    // MARK: - A change arriving from another device

    func testAChangeFromAnotherDeviceIsTakenAsItIs() {
        let current = settings(week: 8, customTypes: [custom("6F1D3B0A-0000-0000-0000-000000000003", "Alt")])
        let incoming = settings(week: 7)
        let outcome = SettingsSync.incoming(incoming, current: current, hasJoined: true)
        XCTAssertEqual(outcome.settings, incoming)
        XCTAssertTrue(outcome.writesLocally)
        XCTAssertFalse(outcome.pushes)
    }

    func testTheFirstCopyToArriveAfterLaunchIsJoinedNotTaken() {
        // A new device often launches before the key-value store has
        // downloaded anything; iCloud's copy then arrives as a change, and
        // that is the moment of joining.
        let school = custom("6F1D3B0A-0000-0000-0000-000000000001", "Berufsschule")
        let current = settings(week: 7, customTypes: [school])
        let incoming = settings(week: 6)
        let outcome = SettingsSync.incoming(incoming, current: current, hasJoined: false)
        XCTAssertEqual(outcome.settings.openingBalanceMinutes, 6 * 60)
        XCTAssertEqual(outcome.settings.customDayTypes, [school])
        XCTAssertTrue(outcome.pushes)
        XCTAssertTrue(outcome.hasJoined)
    }
}
