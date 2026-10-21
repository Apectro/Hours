# Baustelle (job sites) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Sites area where a supervisor records a crew's daily hours per job site, with their own hours flowing into their calendar and a monthly per-site sheet for the director.

**Architecture:** All arithmetic and rules are pure value types in `HoursCore/Sites/` with XCTest coverage on Linux. A new SwiftData layer (`HoursSchemaV3`, `SiteRepository`) stores sites, crew and site days, and also rewrites the user's own calendar day through `WorkdayRepository` so the two stay in sync. SwiftUI screens in `Hours/Features/Sites/` only show resolved values. The director's sheet is a `ReportTable` fed to the existing CSV, XLSX and PDF writers.

**Tech Stack:** Swift 5 language mode, SwiftUI, SwiftData + CloudKit mirroring, XCTest, iOS 18; engine also builds with SwiftPM on Linux (Swift 6.0 toolchain).

**Spec:** `notes/superpowers/specs/2026-10-20-baustelle-design.md`. Mockups: https://claude.ai/artifact/EeWFcyrveYmq5EwBBt3DKv

## Global Constraints

- `HoursCore/` imports Foundation only; it must keep building and testing with `swift build && swift test` on Linux.
- Days are `CalendarDate`, times are `TimeOfDay` (minutes since local midnight). An end before the start is an overnight shift.
- Durations follow `settings.durationPolicy` and `settings.rounding`, as shifts already do.
- SwiftData models store primitives only (no enums, no `Date` for days, no relationships), no `@Attribute(.unique)`. One site day per (siteID, dateKey) is enforced and reconciled by the repository.
- Every write checks `MonthLock` and throws `MonthLock.Refusal.monthIsClosed` rather than silently doing nothing.
- Every user-facing string is translated into all ten languages (en, de, hr, sl, it, fr, es, pt, nl, pl). App strings go into `Scripts/translations.json` → `python3 Scripts/build-catalog.py`. Engine strings use `UITerm` (screens) or `ExportTerm` (documents).
- The English name is "Sites" / "Site"; German "Baustellen" / "Baustelle".
- Pro: one active site is free; a second active site needs `ProFeature.multipleSites`. Writing the sheet file needs the existing `.fileExport`. The preview is free. Lapsed Pro never hides data.
- The user's name on the sheet is `settings.export.ownerName`.
- No new third-party code. No network calls.

## Review Focus

1. **Overnight site day** (22:00–06:00, 30 min break): every ticked person gets 7:30, and your calendar shift sits on the start date. Test: Task 2.
2. **Bad per-person times** (an override end equal to start, or a break longer than the person's span): the result is 0 with a warning, never negative. Test: Task 2.
3. **Editing a site day in a locked month:** the edit is refused with `monthIsClosed`, and neither the site day nor your calendar day changes. Test: Task 8.
4. **Duplicate site days from sync** (two rows for the same site and date): they collapse to the most recently edited one, and your calendar gets exactly one shift for that site that day. Tests: Task 8 and Task 3.
5. **A coworker hidden from the crew, or with spreadsheet-like names** (`=SUM(A1)`, commas, quotes): they still appear on past sheets, and CSV escapes and defuses the name. Tests: Task 4.

---

### Task 0: Toolchain and baseline

**Files:** none.

- [ ] **Step 1: Get a Linux Swift 6.0 toolchain** so the engine tests run locally. The CI container is `swift:6.0`. If installing one isn't possible, every "Run" step below falls back to pushing and reading the `Engine (Linux)` CI job.
- [ ] **Step 2: Run** `swift build && swift test`. Expected: all tests pass, which is the baseline.
- [ ] **Step 3: Run** each `python3 Scripts/check-*.py` named in `.github/workflows/ci.yml`. Expected: all exit 0.

### Task 1: Site value types

**Files:**
- Create: `HoursCore/Sites/Site.swift`, `HoursCore/Sites/CrewMember.swift`, `HoursCore/Sites/SiteDay.swift`
- Test: `HoursTests/SiteModelTests.swift`

**Interfaces:**
- Produces:
  - `struct Site: Identifiable, Hashable, Codable, Sendable { var id: UUID; var name: String; var jobID: UUID?; var isArchived: Bool; var sortOrder: Int }`
  - `struct CrewMember: Identifiable, Hashable, Codable, Sendable { var id: UUID; var siteID: UUID; var name: String; var isHidden: Bool; var sortOrder: Int }`. "You" is not a `CrewMember`; it is `CrewMember.youID`, a fixed UUID like `Job.primaryID`.
  - `struct Attendance: Hashable, Codable, Sendable { var memberID: UUID; var start: TimeOfDay?; var end: TimeOfDay?; var breakMinutes: Int? }`. `nil` fields mean "use the site's".
  - `struct SiteDay: Hashable, Codable, Sendable { var siteID: UUID; var date: CalendarDate; var start: TimeOfDay?; var end: TimeOfDay?; var breakMinutes: Int; var present: [Attendance]; var note: String; var jobID: UUID? }`. `jobID` is frozen when the day is written. `func attendance(for memberID: UUID) -> Attendance?` and `func hasException(_ memberID: UUID) -> Bool`.
- All `init(from:)` use `container.lenient` / `lenientOptional`, as `Job` does.

- [ ] **Step 1: Write failing tests** `testSiteDayRoundTripsThroughJSON`, `testOldPayloadWithoutNoteOrJobDecodesWithDefaults` (expects `note == ""`, `jobID == nil`), `testAttendanceWithNoOverridesHasNoException`, and `testYouIDIsStable` (expects `CrewMember.youID.uuidString == "00000000-0000-4000-8000-0000000000B1"`).
- [ ] **Step 2: Run** `swift test --filter SiteModelTests`. Expected: FAIL, types not defined.
- [ ] **Step 3: Implement** the three files.
- [ ] **Step 4: Run** `swift test --filter SiteModelTests`. Expected: PASS.
- [ ] **Step 5: Commit** "Add the value types for job sites".

### Task 2: A person's hours on a site day

**Files:**
- Create: `HoursCore/Sites/SiteDayCalculator.swift`
- Modify: `HoursCore/Calculation/DayComputation.swift` (add `DayWarning.siteHoursNotCounted`, `isProblem == false`)
- Test: `HoursTests/SiteDayCalculatorTests.swift`

**Interfaces:**
- Consumes: Task 1 types; `WorkdayCalculator.shiftMinutes(record:on:definition:warnings:)`.
- Produces:
  - `struct PersonDay: Hashable, Sendable { var memberID: UUID; var start: TimeOfDay?; var end: TimeOfDay?; var breakMinutes: Int; var workedMinutes: Int; var isException: Bool; var warnings: [DayWarning] }`
  - `struct SiteDayResult: Hashable, Sendable { var day: SiteDay; var people: [PersonDay]; var crewTotalMinutes: Int }`
  - `struct SiteDayCalculator { init(settings: AppSettings, calendar: Calendar); func compute(_ day: SiteDay) -> SiteDayResult }`
- Approach: build a one-shift `DayRecord` per person (`BreakSpan` of `breakMinutes`) and run it through `WorkdayCalculator`'s shift path, then apply `settings.rounding`. That way DST, overnight and rounding rules are identical to the calendar's. `people` keeps the `present` order with you first.

- [ ] **Step 1: Write failing tests:**
  - `testEveryoneGetsSiteTimes`: 07:00–16:00, 30 min break, three present. Expects each `workedMinutes == 510` and `crewTotalMinutes == 1530`.
  - `testLeftEarlyOverridesOnlyThatPerson`: one person ends at 13:00. Expects 330 for them, `isException == true`, and 510 for the others.
  - `testNotTickedGetsNothing`: an absent member is not in `people`.
  - `testOvernightSiteDay`: 22:00–06:00, 30 min break. Expects 450.
  - `testZeroLengthOverrideIsZeroWithWarning`: expects 0 and `.zeroLengthShift`.
  - `testBreakLongerThanSpanIsZeroWithWarning`: expects 0 and `.breakLongerThanShift`.
  - `testQuarterHourRoundingAppliesPerPerson`.
- [ ] **Step 2: Run** `swift test --filter SiteDayCalculatorTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same filter, then the full `swift test`. Expected: PASS.
- [ ] **Step 5: Commit** "Work out each person's hours on a site day".

### Task 3: Your site hours in your calendar

**Files:**
- Modify: `HoursCore/Model/Shift.swift` (add `var siteID: UUID?`, a lenient decode, and include it in `CodingKeys`)
- Create: `HoursCore/Sites/SiteCalendarSync.swift`
- Modify: `HoursCore/Calculation/WorkdayCalculator.swift` (append `.siteHoursNotCounted`; see below)
- Test: `HoursTests/SiteCalendarSyncTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2.
- Produces:
  - `enum SiteCalendarSync { static func merged(personal: DayRecord?, siteDays: [SiteDay], on date: CalendarDate) -> DayRecord? }`. This removes every shift with a `siteID` and adds one shift per site day where `CrewMember.youID` is present. Each added shift carries your start/end, one `BreakSpan` of your break, `siteID`, and `jobID: day.jobID`. Shifts without a `siteID` and all other fields stay untouched. It returns `nil` when the result `isBlank`. If several site days share a `siteID` (sync duplicates), it uses only the first.
  - `static func rebuilt(days: [DayRecord], siteDays: [SiteDay]) -> [DayRecord]` runs `merged` for every date in either input. It drops site shifts whose site has no site day on that date.
- `WorkdayCalculator.compute` appends `.siteHoursNotCounted` when the record has a shift with `siteID != nil` and any of the following holds: worked time is manual (`!features.autoCalculateWorkedHours`), the day type's expectation is `.creditedAbsence`, or `isIncluded == false`.

- [ ] **Step 1: Write failing tests:**
  - `testTickingYouAddsOneSiteShift`
  - `testUntickingYouRemovesIt`
  - `testManualShiftsAndNoteSurvive`
  - `testTwoSitesSameDayGiveTwoShifts`
  - `testDuplicateSiteDaysGiveOneShift`
  - `testJobIsTheFrozenOneNotTheSitesCurrent`
  - `testOnlySiteShiftLeftAndUntickedReturnsNil`
  - `testRebuildDropsShiftForMissingSite`
  - `testVacationDayWithSiteShiftWarns` (on `WorkdayCalculator`)
  - `testShiftWithoutSiteIDDecodesFromOldJSON`
- [ ] **Step 2: Run** `swift test --filter SiteCalendarSyncTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full `swift test`. Expected: PASS, including the existing `ShiftTests` and `PersistenceCodingTests` (macOS only).
- [ ] **Step 5: Commit** "Carry your site hours into your calendar".

### Task 4: The director's sheet

**Files:**
- Create: `HoursCore/Sites/SiteSheetBuilder.swift`
- Modify: `HoursCore/Export/ReportTable.swift` (add `var headingOverrides: [String]? = nil`, `headerTitles()` returns it when its count matches `columns`, and add `func heading(at index: Int) -> String`)
- Modify: `HoursCore/Export/ExportLanguage.swift` (`ExportTerm`: `day`, `monthTotal`, `daysWorked`, `you`, `notHere`, `siteSheetTitle`, all ten languages)
- Modify: `Hours/Features/Export/PDFReportRenderer.swift:141-148,267-296`, `Hours/Features/Export/ExportPreviewTable.swift:40-62` so they use `table.heading(at:)` instead of `column.heading(in:)`
- Test: `HoursTests/SiteSheetTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2, `ReportTable`, `ReportRow`, `CSVExporter`, `XLSXWriter`.
- Produces: `struct SiteSheetBuilder { init(settings: AppSettings, calendar: Calendar, emptyPlaceholder: String = "—"); func makeTable(site: Site, crew: [CrewMember], results: [SiteDayResult], range: CalendarDateRange) -> ReportTable }`
- Shape (the spec's layout):
  - Columns are `[.date] + [.worked] × people + [.note]`, with `headingOverrides` set to `[day] + names + [notes]`.
  - People are everyone with at least one day in the range, you first, then crew `sortOrder`. Hidden members are included.
  - Your heading is `ownerName`, falling back to `ExportTerm.you`.
  - Each day cell is `"07:00–16:00 · 8:30"` (export duration style), with `minutes` nil, or the placeholder when absent.
  - Two final rows: `monthTotal` (each cell is that person's minutes, numeric) and `daysWorked` (count as text).
  - `title` is `site.name` and `ownerName` is `settings.export.ownerName`.

- [ ] **Step 1: Write failing tests:**
  - `testOneRowPerDayOneColumnPerPerson`
  - `testYouColumnUsesOwnerNameThenFallsBack`
  - `testAbsentCellIsPlaceholder`
  - `testTotalsRowSumsMinutesAndCountsDays`
  - `testHiddenMemberStillOnPastSheet`
  - `testPersonWithNoDaysInRangeHasNoColumn`
  - `testCSVDefusesFormulaNameAndQuotesComma` (a member named `=SUM(A1)`, another `Kovač, Ivan`)
  - `testXLSXHeaderUsesOverrides` (decode `sheet1.xml` from the archive, as `ExportTests` does)
  - `testNoteColumnCarriesDayNote`
- [ ] **Step 2: Run** `swift test --filter SiteSheetTests`. Expected: FAIL.
- [ ] **Step 3: Implement** the builder, `ReportTable` overrides and terms. Update the PDF renderer and the preview.
- [ ] **Step 4: Run** the full `swift test`. Expected: PASS, with existing `ExportTests` unchanged.
- [ ] **Step 5: Commit** "Build the director's sheet for a site".

### Task 5: Pro rule and the backup format

**Files:**
- Modify: `HoursCore/Settings/ProFeature.swift` (`case multipleSites`, symbol `"building.2"`, `UITerm.proMultipleSites` and `…Explained`)
- Modify: `HoursCore/Localization/AppVocabulary.swift` (the two terms, ten languages)
- Create: `HoursCore/Sites/SiteAccess.swift`
- Modify: `HoursCore/Export/BackupArchive.swift` (add optional `sites: [Site]?`, `crew: [CrewMember]?`, `siteDays: [SiteDay]?`; omitted when nil; lenient decode; `currentFormatVersion` stays 1)
- Test: `HoursTests/SiteAccessTests.swift`, and extend `HoursTests/EntitlementTests.swift`

**Interfaces:**
- Produces:
  - `enum SiteAccess { static func canAddSite(activeSites: Int, entitlement: Entitlement, at: Date) -> Bool; static func isReadOnly(_ site: Site, activeSites: [Site], entitlement: Entitlement, at: Date) -> Bool }`
  - Read-only means: without Pro, every active site except the lowest `sortOrder` is read-only.
  - `BackupArchive.sites/crew/siteDays`: `nil` means "this file predates Sites" (Task 9 relies on that distinction).

- [ ] **Step 1: Write failing tests:**
  - `testFirstSiteIsFree`
  - `testSecondSiteNeedsPro`
  - `testLapsedProKeepsFirstSiteWritableOthersReadOnly`
  - `testArchivedSitesDoNotCount`
  - `testAlwaysFreeListUnchanged` (the existing assertion still holds)
  - `testOldBackupDecodesWithNilSites`
  - `testBackupRoundTripsSites`
- [ ] **Step 2: Run** `swift test --filter "SiteAccessTests|EntitlementTests|PersistenceCoding"`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full `swift test`. Expected: PASS.
- [ ] **Step 5: Commit** "Price sites and carry them in the backup".

### Task 6: Reminder planning

**Files:**
- Modify: `HoursCore/Settings/ReminderPreferences.swift` (add `siteRemindersEnabled: Bool = true` and `siteReminderTime: TimeOfDay = 18:00`, decoded leniently)
- Create: `HoursCore/Sites/SiteReminderPlan.swift`
- Test: `HoursTests/SiteReminderPlanTests.swift`

**Interfaces:**
- Produces: `enum SiteReminderPlan { static func dates(siteDays: [SiteDay], today: CalendarDate, calendar: Calendar, lookBackDays: Int = 14, daysAhead: Int = 7) -> [CalendarDate] }`
  - Returns the dates from today through `today + daysAhead - 1` whose weekday matched any site day in the look-back window.
  - It excludes dates that already have a site day on every site worked in the window.

- [ ] **Step 1: Write failing tests:**
  - `testNoRecentSiteWorkNoReminders`
  - `testOnlyWeekdaysThatWereWorked`
  - `testTodayAlreadyRecordedIsSkipped`
  - `testOldPreferencesDecodeWithDefaults`
- [ ] **Step 2: Run** `swift test --filter SiteReminderPlanTests`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the full `swift test`. Expected: PASS.
- [ ] **Step 5: Commit** "Plan site reminders".

### Task 7: Storage models and migration

**Files:**
- Create: `Hours/Data/Models/SiteEntry.swift`, `Hours/Data/Models/CrewMemberEntry.swift`, `Hours/Data/Models/SiteDayEntry.swift`
- Modify: `Hours/Data/Store/HoursSchema.swift` (add `HoursSchemaV3` with the five current models and a lightweight `V2 → V3` stage in `HoursMigrationPlan`)
- Modify: `Hours/Data/Store/HoursModelContainer.swift` (the container uses V3)
- Test: `HoursTests/MigrationTests.swift` (macOS only)

**Interfaces:**
- Produces:
  - `SiteEntry`: `siteID: String`, `name`, `jobID: String?`, `isArchived`, `sortOrder`, `updatedAt`. It has `var site: Site` and `func apply(_ site: Site)`.
  - `CrewMemberEntry`: same pattern, with `siteID: String`.
  - `SiteDayEntry`: `siteID: String`, `dateKey: Int`, `startMinutes: Int?`, `endMinutes: Int?`, `breakMinutes: Int`, `presentData: Data?` (JSON `[Attendance]`), `note`, `jobID: String?`, `createdAt`, `updatedAt`. It has `var siteDay: SiteDay` and `func apply(_ day: SiteDay)`.
  - Every property has a default value, which CloudKit requires.

- [ ] **Step 1: Write failing tests:**
  - `testV2StoreOpensAsV3WithDaysIntact`
  - `testSiteDayEntryRoundTripsSiteDay`
- [ ] **Step 2: Run** them in Xcode: `xcodebuild test -scheme Hours -only-testing:HoursTests/MigrationTests`. In this environment, that means pushing and reading the `App and tests (iOS simulator)` CI job. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the same tests. Expected: PASS.
- [ ] **Step 5: Commit** "Store sites, crews and site days".

### Task 8: SiteRepository

**Files:**
- Create: `Hours/Data/Store/SiteRepository.swift`
- Modify: `Scripts/check-repository-lock.py` (also check `SiteRepository(` constructions on writing paths)
- Test: `HoursTests/SiteRepositoryTests.swift` (macOS only, in-memory container as in `DuplicateReconciliationTests`)

**Interfaces:**
- Consumes: Tasks 1, 3, 7; `WorkdayRepository(context:lock:)`.
- Produces: `struct SiteRepository { init(context: ModelContext, lock: MonthLock = .unlocked) }` with:
  - `sites(includeArchived: Bool) -> [Site]`, `upsert(_ site: Site)`
  - `crew(for siteID: UUID, includeHidden: Bool) -> [CrewMember]`, `upsert(_ member: CrewMember)`
  - `siteDay(siteID: UUID, on date: CalendarDate) -> SiteDay?`
  - `siteDays(siteID: UUID?, in range: CalendarDateRange) -> [SiteDay]`
  - `lastSiteDay(siteID: UUID, before date: CalendarDate) -> SiteDay?`
  - `save(_ day: SiteDay) throws`: checks the lock, upserts, then calls `WorkdayRepository(context:lock:).save(SiteCalendarSync.merged(...))` or deletes the record, all in one `context.save()`.
  - `delete(siteID: UUID, on date: CalendarDate) throws`
  - `reconcileDuplicates() -> Int`: keeps the last edited row per (siteID, dateKey), with the same tie-breaks as `WorkdayRepository`.
  - `replaceAll(sites:crew:siteDays:)`, used by restore.
- "Same as last day" copies `start`, `end`, `breakMinutes` and the present member ids (overrides cleared) from `lastSiteDay`, and adds today's date and the site's current `jobID`.

- [ ] **Step 1: Write failing tests:**
  - `testSaveWritesYourCalendarShift`
  - `testLockedMonthRefusesAndChangesNothing` (both stores are unchanged afterwards)
  - `testDuplicateSiteDaysCollapseToNewest`
  - `testSameAsLastDayCopiesTimesAndCrewNotExceptions`
  - `testDeletingSiteDayRemovesCalendarShift`
- [ ] **Step 2: Run** the macOS tests. Expected: FAIL.
- [ ] **Step 3: Implement** the repository and extend the lock check script.
- [ ] **Step 4: Run** the macOS tests and `python3 Scripts/check-repository-lock.py`. Expected: PASS and exit 0.
- [ ] **Step 5: Commit** "Save site days and keep your calendar in step".

### Task 9: Backup, restore and sync wiring

**Files:**
- Modify: `Hours/Features/Settings/DataSettingsScreen.swift` (backup writes `sites/crew/siteDays`. On restore, when the archive's `sites != nil`, call `SiteRepository.replaceAll`; when it is `nil`, leave site data alone. Then rebuild calendar site shifts with `SiteCalendarSync.rebuilt` and save.)
- Modify: the scene-phase hook that calls `WorkdayRepository.reconcileDuplicates()` so it also calls `SiteRepository.reconcileDuplicates()`
- Test: `HoursTests/SiteRestoreTests.swift` (macOS only)

- [ ] **Step 1: Write failing tests:**
  - `testRestoringOldBackupKeepsSites`
  - `testRestoringNewBackupReplacesSites`
  - `testRestoreRebuildsCalendarSiteShifts`
- [ ] **Step 2: Run** the tests. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** the tests. Expected: PASS.
- [ ] **Step 5: Commit** "Back up, restore and reconcile sites".

### Task 10: Sites tab, site list and crew

**Files:**
- Modify: `Hours/App/RootView.swift` (tab order Calendar, Sites, Insights, Settings; icon `"building.2"`)
- Create: `Hours/Features/Sites/SitesScreen.swift` (mockup screen 1), `SiteEditorSheet.swift` (name, job picker shown only if `settings.tracksMultipleJobs`, archive), `CrewScreen.swift` (add, rename, reorder, hide/unhide)
- Modify: `Hours/Features/Pro/ProPresentation.swift` (the `.multipleSites` gate when adding a site)
- UI test: `HoursUITests` adds `testCreateSiteAndAddCrew`

- [ ] **Step 1: Write the failing UI test.**
- [ ] **Step 2: Run** it. Expected: FAIL.
- [ ] **Step 3: Implement** the screens. Month figures on the cards come from `SiteDayCalculator` over `SiteRepository.siteDays`. Read-only sites use `SiteAccess.isReadOnly` and show a short line explaining why.
- [ ] **Step 4: Run** it. Expected: PASS.
- [ ] **Step 5: Commit** "Add the Sites tab and crew lists".

### Task 11: Writing a site day

**Files:**
- Create: `Hours/Features/Sites/SiteDayScreen.swift` (mockup screen 2: date arrows plus a picker, site times, break, crew ticks, per-person row with changed times highlighted, crew total, note, "Same as last day", warnings)
- Create: `Hours/Features/Sites/PersonTimesSheet.swift` (override start, end and break; "Use site times" resets)
- Modify: `Hours/Features/DayDetail/DayEditorForm.swift` (shifts with a `siteID` are read-only and labelled with the site name, with an "Open on site" button)
- UI tests: `testTickCrewAndSave`, `testLeftEarlyIsHighlighted`, `testLockedMonthShowsRefusal`

- [ ] **Step 1: Write the failing UI tests.**
- [ ] **Step 2: Run** them. Expected: FAIL.
- [ ] **Step 3: Implement.** Saves go through `SiteRepository(context:lock:settings.monthLock)`. A refusal shows the existing month-closed message.
- [ ] **Step 4: Run** them. Expected: PASS.
- [ ] **Step 5: Commit** "Write a crew's day on a site".

### Task 12: Site export screen

**Files:**
- Create: `Hours/Features/Sites/SiteExportScreen.swift` (month picker that defaults to last month, format CSV/XLSX/PDF, `ExportPreviewTable` preview, name prompt if `ownerName` is empty, then the `.fileExport` gate, then share)
- UI test: `testSiteExportPreviewShowsEveryone`

- [ ] **Step 1: Write the failing UI test.** **Step 2: Run** it. Expected: FAIL.
- [ ] **Step 3: Implement** with `SiteSheetBuilder` and the existing writers and `ExportFile`.
- [ ] **Step 4: Run** it. Expected: PASS. **Step 5: Commit** "Export a site's month for the director".

### Task 13: Site reminders

**Files:**
- Modify: `Hours/Data/Store/ReminderScheduler.swift` (`func scheduleSiteReminders(dates: [CalendarDate], time: TimeOfDay)` uses identifiers `"site-reminder-<yyyyMMdd>"` and replaces earlier ones; `cancelSiteReminder(on:)`)
- Modify: the app-open reschedule path, so `SiteRepository.save` cancels that date's reminder
- Modify: `Hours/Features/Settings/ReminderSettingsScreen.swift` (toggle and time)
- Test: `HoursTests/SiteReminderIdentifierTests.swift` (identifier format; macOS)

- [ ] Steps 1–5 as above. Commit "Remind about a missing site day".

### Task 14: Translations and repository checks

**Files:** `Scripts/translations.json`, the generated `*.xcstrings`

- [ ] **Step 1: Add** every new app string with all nine translations. Run `python3 Scripts/build-catalog.py`.
- [ ] **Step 2: Run** every `python3 Scripts/check-*.py` from CI. Expected: all exit 0.
- [ ] **Step 3: Commit** "Translate Sites".

### Task 15: Whole-branch verification

- [ ] **Step 1: Run** `swift build && swift test` (Linux). Expected: PASS.
- [ ] **Step 2: Push** and wait for every CI job on the head commit. Expected: green, including the iOS simulator app and UI tests.
- [ ] **Step 3:** Request a whole-branch code review (superpowers:requesting-code-review), then superpowers:finishing-a-development-branch.
