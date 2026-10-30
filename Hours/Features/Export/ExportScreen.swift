import StoreKit
import SwiftUI
import SwiftData
import UIKit

/// Choose what to export and which days, see what will be produced, then
/// make the PDF or the Excel file (Export board, phones 1 and 2).
///
/// WHAT is My hours, a Crew sheet for one or more sites merged, or One
/// person's own sheet. Opened from the calendar it starts on your hours;
/// opened from a site's Sheet button (`SiteExportScreen`) on a crew sheet of
/// that site. The preview is the real first page of the PDF built from the
/// same `ReportTable` as the file, so what is on screen is what is sent.
///
/// PDF and Excel each write the file and open it ready to send
/// (`ExportReadySheet`), where Send… and Save to Files are, and after that
/// the offer to close the month. A CSV is under This sheet › CSV file, with
/// the columns, the language and the switches for this export.
struct ExportScreen: View {
    let initialRange: CalendarDateRange
    private let initialSiteID: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    // Every site rather than the active ones: a site opened from its own
    // screen may be archived, and its months are still the director's.
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var mode: ExportMode
    /// The crew sheet's own site: the first one ticked.
    @State private var primarySiteID: UUID?
    /// Other sites on the crew sheet (1.2), in the order ticked: one
    /// director's sheet with each person's hours a day added up across
    /// them. For this export only.
    @State private var sheetSiteIDs: [UUID] = []
    @State private var choosesOtherSites = false
    /// The person of One person, by `CrewCandidates.key`.
    @State private var personKey: String?

    @State private var rangeKind: ExportRangeKind = .month
    @State private var anchor: CalendarDate
    @State private var customStart: CalendarDate
    @State private var customEnd: CalendarDate
    /// `nil` until stepped: a crew sheet opens on last month, because that
    /// is the month the director asks for at the start of this one, and one
    /// person's sheet on this month, as from the crew list.
    @State private var siteMonth: YearMonth?
    @State private var personMonth: YearMonth?
    /// Your hours on one site only, for a range worked on more than one
    /// (1.2); nil is all sites.
    @State private var siteFilter: UUID?

    /// What the file will be called, without its extension. Follows the
    /// period until somebody types over it.
    @State private var fileName: String = ""
    @State private var fileNameEdited = false
    /// This export's columns, language and switches (This sheet); nil is
    /// the defaults in Settings › Sheets.
    @State private var sheetPreferences: ExportPreferences?

    @State private var tables: ExportTables?
    @State private var personSheets: [CrewSheetTables] = []
    @State private var personSheet: CrewSheetTables?
    @State private var pdfData: Data?
    @State private var pageImage: UIImage?
    @State private var summary = ""
    /// Working days in the period with nothing written: your own
    /// (`MissingDays`) or the sites' (`SiteDayStatus`).
    @State private var missingDates: [CalendarDate] = []
    @State private var showsMissing = false
    @State private var failureMessage: String?
    @State private var paywallReason: ProFeature?
    @State private var showsFullPage = false
    @State private var ready: ExportReadyItem?
    /// The format chosen before the name was asked for, opened once it is.
    @State private var pendingFormat: ExportFormat?

    /// The sheet carries your name, so it is asked for once when it is
    /// missing — at PDF or Excel, never in front of the preview. "Not now"
    /// is an answer too: the sheet then goes without.
    @State private var asksForName = false
    @State private var typedName = ""
    @State private var nameAnswered = false

    /// A site's diary follows its hours unless switched off.
    @State private var includesDiary = true
    /// Diary photos already made small for the PDF, kept between previews.
    @State private var printPhotos: [UUID: Data] = [:]
    /// Signing a sheet is optional. Remembered, because a crew that does
    /// not sign never does.
    @AppStorage("export.siteSignatures") private var includesSignatures = true
    /// Moved on by the sign-off screen, so a new signature redraws the preview.
    @State private var signOffRevision = 0
    /// A crew sheet as a sheet for each person instead of one for the
    /// director: their days on the sheet's sites, one file each.
    @State private var perPerson = false
    /// The month's crew hours by site: the summary's hours, the "Other
    /// sites" list, and which archived sites have days in the month.
    @State private var monthSiteHours: [UUID: Int] = [:]
    /// Everyone on a crew, once per name, for One person.
    @State private var people: [CrewMember] = []

    /// - Parameters:
    ///   - initialRange: the days your own timesheet starts on.
    ///   - site: the site to open a crew sheet on, when opened from one.
    ///   - month: the crew sheet's month; last month when `nil`.
    init(initialRange: CalendarDateRange, site: Site? = nil, month: YearMonth? = nil) {
        self.initialRange = initialRange
        self.initialSiteID = site?.id
        _mode = State(initialValue: site == nil ? .myHours : .crewSheet)
        _primarySiteID = State(initialValue: site?.id)
        _siteMonth = State(initialValue: month)
        _anchor = State(initialValue: initialRange.start)
        _customStart = State(initialValue: initialRange.start)
        _customEnd = State(initialValue: initialRange.end)
    }

    var body: some View {
        NavigationStack {
            form
                .navigationTitle("Export")
                // A screen the UI tests wait for. The title beside it is translated.
                .accessibilityIdentifier(mode == .crewSheet ? "screen-site-export" : "screen-export")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("export-done")
                    }
                }
                .safeAreaInset(edge: .bottom) { bottomBar }
                .task {
                    // Clear anything a previous export left in the temporary
                    // directory before writing a new file into it.
                    ExportFileFactory.clearPreviousExports()
                    let preferred = settings.export.defaultRange
                    if preferred == .day {
                        // A single day is Dates with the day at both ends.
                        rangeKind = .custom
                        customStart = initialRange.start
                        customEnd = initialRange.start
                    } else {
                        rangeKind = preferred
                    }
                    if primarySiteID == nil { primarySiteID = pickableSites.first?.id }
                    loadPeople()
                    regenerate()
                }
                .onChange(of: regenerationKey) { _, _ in regenerate() }
                .onChange(of: mode) { _, _ in showsMissing = false }
                .alert("Your name on the sheet", isPresented: $asksForName) {
                    TextField("Name and surname", text: $typedName)
                        .textInputAutocapitalization(.words)
                    Button("Save") { saveName(); resumePendingFile() }
                    Button("Not now", role: .cancel) { nameAnswered = true; resumePendingFile() }
                } message: {
                    nameMessage
                }
                .sheet(isPresented: $showsFullPage) {
                    ExportFullPageSheet(data: pdfData ?? Data())
                }
                .sheet(item: $ready) { item in
                    ExportReadySheet(item: item)
                }
                .sheet(isPresented: $choosesOtherSites) {
                    ExportSheetSitesPicker(
                        candidates: otherSiteCandidates,
                        hours: monthSiteHours,
                        chosen: $sheetSiteIDs
                    )
                }
                .paywall(for: $paywallReason)
        }
    }

    // MARK: - Sections

    private var form: some View {
        Form {
            if !pickableSites.isEmpty {
                Section {
                    ExportTargetPicker(mode: $mode)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("What")
                }
            }
            switch mode {
            case .myHours:
                ExportRangeSection(
                    rangeKind: $rangeKind,
                    customStart: dateBinding($customStart),
                    customEnd: dateBinding($customEnd),
                    title: periodTitle,
                    canStepForward: rangeKind.canStepForward(
                        from: anchor,
                        today: CalendarDate.today(in: calendar),
                        calendar: calendar
                    ),
                    onStep: step
                )
                sitesFilterSection
            case .crewSheet:
                sitesSection
                monthSection(monthBinding)
            case .onePerson:
                personSection
                monthSection(personMonthBinding)
            }
            missingSection
            previewSection
            Section {
                NavigationLink {
                    thisSheetScreen
                } label: {
                    Label("Columns, language and more", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("export-this-sheet")
            } footer: {
                proFooter
            }
        }
    }

    /// WHICH SITES · TAP MORE THAN ONE TO MERGE.
    private var sitesSection: some View {
        Section {
            ExportSiteChips(
                sites: chipSites,
                chosen: sheetSites.map(\.id),
                hasOtherSites: !otherSiteCandidates.isEmpty,
                onToggle: toggleSite,
                onOtherSites: { choosesOtherSites = true }
            )
            .listRowInsets(EdgeInsets(top: Metrics.tiny, leading: 0, bottom: Metrics.tiny, trailing: 0))
            .listRowBackground(Color.clear)
        } header: {
            Text("Which sites · tap more than one to merge")
        }
    }

    private func monthSection(_ month: Binding<YearMonth>) -> some View {
        Section {
            PeriodStepper(
                month: month,
                latest: currentMonth,
                title: formatting.monthTitle(month.wrappedValue),
                caption: ""
            )
        } header: {
            Text("Which month")
        }
    }

    /// One person: everyone on a crew, once per name.
    @ViewBuilder
    private var personSection: some View {
        Section {
            if people.isEmpty {
                Text("Nobody is on a crew yet.")
                    .foregroundStyle(.hoursSecondaryText)
            } else {
                Picker("Person", selection: personBinding) {
                    ForEach(people) { member in
                        Text(verbatim: member.name).tag(Optional(CrewCandidates.key(for: member.name)))
                    }
                }
                .accessibilityIdentifier("export-person")
            }
        } header: {
            Text("Who")
        }
    }

    /// "All sites" or one of them, only when the range has hours on more
    /// than one site.
    @ViewBuilder
    private var sitesFilterSection: some View {
        if let sites = tables?.sites, sites.count > 1 {
            Section {
                Picker("Sites", selection: $siteFilter) {
                    Text("All sites").tag(UUID?.none)
                    ForEach(sites) { site in
                        Text(verbatim: site.name).tag(UUID?.some(site.id))
                    }
                }
                .accessibilityIdentifier("export-sites")
            } footer: {
                if siteFilter != nil {
                    Text("Only the hours worked on this site. Expected hours, the balance and earnings belong to the whole day, so they are left out.")
                }
            }
        }
    }

    /// "Nothing written on 2 days · Show": orange, the colour of "look at
    /// this", and the days themselves under it once asked for.
    @ViewBuilder
    private var missingSection: some View {
        if mode != .onePerson, !missingDates.isEmpty {
            Section {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { showsMissing.toggle() }
                } label: {
                    HStack(spacing: Metrics.small) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(String(inflected: "Nothing written on ^[\(missingDates.count) day](inflect: true)"))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(showsMissing ? "Hide" : "Show")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.hoursAttention)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("export-missing-days")
                if showsMissing {
                    Text(verbatim: missingDates.map { formatting.mediumDate($0) }.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            .listRowBackground(Color.hoursAttentionFill.opacity(0.12))
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text("Preview")
                    .font(.subheadline.weight(.bold))
                Spacer(minLength: Metrics.small)
                Text(verbatim: summary)
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier("export-summary")
            }
            .accessibilityElement(children: .combine)
            if hasContent {
                ExportPagePreview(image: pageImage, title: previewTitle) { showsFullPage = pdfData != nil }
                    .listRowInsets(EdgeInsets(top: 0, leading: Metrics.small, bottom: Metrics.small, trailing: Metrics.small))
                if let note = personNote {
                    Text(verbatim: note)
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                }
            } else if tables == nil && personSheet == nil && mode != .onePerson {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else if mode == .myHours {
                ContentUnavailableView(
                    "Nothing in this range",
                    systemImage: "tray",
                    description: Text("Pick a different range, or switch on “Include days with no entry” under Columns, language and more.")
                )
            } else {
                ContentUnavailableView(
                    "Nothing recorded this month",
                    systemImage: "tray",
                    description: Text("Choose another month to see its days.")
                )
            }
        }
    }

    @ViewBuilder
    private var proFooter: some View {
        if !subscriptions.allows(.fileExport) {
            if mode == .myHours {
                Text("Timesheets are part of Zeitkonto Pro. Settings › Backup and data writes a file with every day you have ever recorded in it, and always will, free.")
            } else {
                Text("The site sheet is part of Zeitkonto Pro. The preview is free, and every site day stays in your backup.")
            }
        }
    }

    /// PDF and Excel, and what went wrong writing one, if anything did.
    private var bottomBar: some View {
        VStack(spacing: Metrics.small) {
            if let failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.hoursMissing)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ExportFormatCards(
                isEnabled: hasContent,
                isLocked: !subscriptions.allows(.fileExport),
                onChoose: makeFile
            )
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(.bar)
    }

    private var thisSheetScreen: some View {
        ExportThisSheetScreen(
            mode: mode,
            preferences: preferencesBinding,
            fileName: showsFileName ? fileNameBinding : nil,
            suggestedFileName: suggestedFileName,
            perPerson: $perPerson,
            offersDiary: tables?.hasDiary == true,
            includesDiary: $includesDiary,
            includesSignatures: $includesSignatures,
            signOffSite: mode == .crewSheet ? selectedSite : nil,
            month: month,
            onSigned: { signOffRevision += 1 },
            onCSV: { makeFile(.csv) }
        )
    }

    @ViewBuilder
    private var nameMessage: some View {
        if mode == .myHours {
            Text("Printed on every sheet you export, and kept in Settings › Sheets.")
        } else {
            Text("Printed above your column instead of “You”, and kept in Settings › Sheets.")
        }
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var currentMonth: YearMonth { CalendarDate.today(in: calendar).yearMonth }
    private var ownerName: String { settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// This export's preferences: This sheet's copy, or the defaults, with
    /// the name always yours as kept.
    private var exportPreferences: ExportPreferences {
        var preferences = sheetPreferences ?? settings.export
        preferences.ownerName = settings.export.ownerName
        return preferences
    }

    /// The settings the sheets are built with: everything as set, the
    /// export as This sheet has it.
    private var exportSettings: AppSettings {
        var copy = settings
        copy.export = exportPreferences
        return copy
    }

    private var preferencesBinding: Binding<ExportPreferences> {
        Binding(get: { exportPreferences }, set: { sheetPreferences = $0 })
    }

    /// For display only, so a duplicate row left by sync just means the first
    /// of the two is shown; `SiteRepository` collapses it on the next read.
    private var allSites: [Site] {
        var seen = Set<UUID>()
        return siteEntries.map(\.site).filter { seen.insert($0.id).inserted }
    }

    /// The active sites, and the one the screen was opened from even if it
    /// has been archived since.
    private var pickableSites: [Site] {
        allSites.filter { !$0.isArchived || $0.id == initialSiteID }
    }

    private var selectedSite: Site? {
        guard mode == .crewSheet, let id = primarySiteID else { return nil }
        return allSites.first { $0.id == id }
    }

    /// The sites the crew sheet takes in: its own, then the others ticked.
    private var sheetSites: [Site] {
        guard let site = selectedSite else { return [] }
        return [site] + sheetSiteIDs.compactMap { id in
            id == site.id ? nil : allSites.first { $0.id == id }
        }
    }

    /// The chips: the active sites, and any archived site on the sheet.
    private var chipSites: [Site] {
        let onSheet = Set(sheetSites.map(\.id))
        return allSites.filter { !$0.isArchived || $0.id == initialSiteID || onSheet.contains($0.id) }
    }

    /// Behind "Other sites": archived sites with days in the month, or
    /// already on the sheet.
    private var otherSiteCandidates: [Site] {
        let shown = Set(pickableSites.map(\.id))
        return allSites.filter { site in
            site.isArchived && !shown.contains(site.id) && site.id != primarySiteID
                && (monthSiteHours[site.id] != nil || sheetSiteIDs.contains(site.id))
        }
    }

    /// A crew sheet's month, or one person's.
    private var month: YearMonth {
        switch mode {
        case .onePerson: return personMonth ?? currentMonth
        default: return siteMonth ?? currentMonth.adding(months: -1)
        }
    }

    private var monthBinding: Binding<YearMonth> {
        Binding(get: { siteMonth ?? currentMonth.adding(months: -1) }, set: { siteMonth = $0 })
    }

    private var personMonthBinding: Binding<YearMonth> {
        Binding(get: { personMonth ?? currentMonth }, set: { personMonth = $0 })
    }

    private var personBinding: Binding<String?> {
        Binding(get: { personKey ?? people.first.map { CrewCandidates.key(for: $0.name) } }, set: { personKey = $0 })
    }

    private var selectedPerson: CrewMember? {
        guard let key = personBinding.wrappedValue else { return nil }
        return people.first { CrewCandidates.key(for: $0.name) == key }
    }

    private var needsName: Bool { mode != .onePerson && !nameAnswered && ownerName.isEmpty }

    /// One sheet per person is a crew sheet's option.
    private var showsPersonSheets: Bool { mode == .crewSheet && perPerson }

    private var hasContent: Bool {
        switch mode {
        case .onePerson: return personSheet?.tables.hasContent == true
        default: return tables?.hasContent == true
        }
    }

    /// The previewed sheet's title, which the UI tests read.
    private var previewTitle: String {
        if mode == .onePerson { return personSheet?.tables.file.title ?? "" }
        if showsPersonSheets, let first = personSheets.first { return first.tables.file.title }
        return tables?.file.title ?? ""
    }

    private var personNote: String? {
        guard showsPersonSheets, let first = personSheets.first else { return nil }
        return String(
            localized: "Preview: \(first.tables.preview.ownerName). Everyone on the sheet gets a file of their own.",
            comment: "Under the export preview with one sheet per person; the value is the first person's name"
        )
    }

    /// A file name to type over: not for a file per person.
    private var showsFileName: Bool { mode != .onePerson && !showsPersonSheets }

    private var resolvedRange: CalendarDateRange {
        switch rangeKind {
        case .day: return CalendarDateRange(single: anchor)
        case .week: return CalendarDateRange.week(containing: anchor, in: calendar)
        case .month: return anchor.yearMonth.range(in: calendar)
        case .year: return CalendarDateRange.year(anchor.year, in: calendar)
        case .custom: return CalendarDateRange(start: customStart, end: max(customStart, customEnd))
        }
    }

    /// "October 2026", "2026" or the week's two dates.
    private var periodTitle: String {
        switch rangeKind {
        case .month: return formatting.monthTitle(anchor.yearMonth)
        case .year: return String(anchor.year)
        default:
            let range = resolvedRange
            return range.start == range.end
                ? formatting.mediumDate(range.start)
                : "\(formatting.mediumDate(range.start)) – \(formatting.mediumDate(range.end))"
        }
    }

    private var exportNaming: ExportNaming {
        ExportNaming(settings: exportSettings, calendar: calendar)
    }

    /// The file's name when nobody has typed one.
    private var suggestedFileName: String {
        if mode == .crewSheet { return exportNaming.siteSheetFileName(sheetSites, month: month) }
        let name = exportNaming.timesheetFileName(rangeKind: rangeKind, range: resolvedRange)
        if let siteFilter, let site = tables?.sites.first(where: { $0.id == siteFilter }), (tables?.sites.count ?? 0) > 1 {
            return "\(name) - \(site.name)"
        }
        return name
    }

    /// Typing marks the name as the person's own; clearing the field hands it
    /// back to the period.
    private var fileNameBinding: Binding<String> {
        Binding(
            get: { fileName },
            set: { typed in
                fileName = typed
                fileNameEdited = !typed.trimmingCharacters(in: .whitespaces).isEmpty
            }
        )
    }

    private var fileBaseName: String {
        let typed = fileName.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty || !fileNameEdited ? suggestedFileName : typed
    }

    /// The month the file covers, for the offer to close it after sending.
    private var closeMonth: YearMonth? {
        let today = CalendarDate.today(in: calendar)
        let sent = mode == .myHours ? ExportCloseOffer.wholeMonth(resolvedRange, calendar: calendar) : month
        return ExportCloseOffer.month(sent: sent, today: today, lock: settings.monthLock)
    }

    /// Everything that changes what the sheet contains.
    private var regenerationKey: String {
        let range = resolvedRange
        let what: String
        switch mode {
        case .myHours: what = "me-\(range.start.key)-\(range.end.key)-\(siteFilter?.uuidString ?? "all")"
        case .crewSheet: what = "crew-\(month.year)-\(month.month)-\(sheetSites.map(\.id.uuidString).joined(separator: ","))"
        case .onePerson: what = "person-\(month.year)-\(month.month)-\(personBinding.wrappedValue ?? "")"
        }
        return "\(what)-\(exportPreferences.hashValue)-\(needsName)"
            + "-\(includesDiary)-\(includesSignatures)-\(signOffRevision)-\(perPerson)"
    }

    private func dateBinding(_ binding: Binding<CalendarDate>) -> Binding<Date> {
        Binding(
            get: { binding.wrappedValue.date(in: calendar) },
            set: { binding.wrappedValue = CalendarDate($0, calendar: calendar) }
        )
    }

    // MARK: - Generation

    private func regenerate() {
        if !fileNameEdited { fileName = suggestedFileName }
        failureMessage = nil
        let maker = ExportTableMaker(context: modelContext, settings: exportSettings, calendar: calendar)
        personSheets = []
        personSheet = nil
        tables = nil
        var first: ExportTables?

        switch mode {
        case .myHours:
            let built = maker.personal(
                range: resolvedRange,
                title: exportNaming.reportTitle(rangeKind: rangeKind, anchor: anchor, range: resolvedRange),
                period: exportNaming.period(rangeKind: rangeKind, anchor: anchor, range: resolvedRange),
                siteFilter: siteFilter
            )
            tables = built
            first = built
            readPersonal()
        case .crewSheet:
            monthSiteHours = maker.siteMonthHours(month: month)
            let built = maker.sites(sheetSites, month: month, includeDiary: includesDiary, includeSignatures: includesSignatures)
            tables = built
            first = built
            if perPerson, let site = selectedSite {
                personSheets = maker.crewSheets(site: site, month: month, includeSignatures: includesSignatures, sites: sheetSites)
                first = personSheets.first?.tables
            }
            readSites(sheet: built)
        case .onePerson:
            missingDates = []
            if let member = selectedPerson {
                let sheet = maker.crewSheet(for: member, month: month, includeSignatures: includesSignatures)
                personSheet = sheet
                first = sheet.tables
                let days = sheet.tables.file.rows.filter { $0.role == .day }.count
                summary = sheet.tables.hasContent ? String(inflected: "^[\(days) day](inflect: true)") : ""
            } else {
                summary = ""
            }
        }
        // Again, now the range's sites are known: a filtered sheet's name
        // carries its site.
        if !fileNameEdited { fileName = suggestedFileName }

        // The PDF is drawn for the preview whether or not it can be shared:
        // seeing the page is free. The same bytes become a PDF file.
        if let first, first.hasContent {
            var photos: [UUID: Data] = [:]
            if mode == .crewSheet, !showsPersonSheets, !first.photoIDs.isEmpty {
                photos = maker.printPhotos(ids: first.photoIDs, sites: sheetSites, month: month, cache: printPhotos)
                printPhotos.merge(photos) { _, new in new }
            }
            let data = PDFReportRenderer.data(for: first.file, photos: photos)
            pdfData = data
            pageImage = ExportPagePreview.thumbnail(of: data)
        } else {
            pdfData = nil
            pageImage = nil
        }

    }

    /// The file asked for before the name, made once the name is answered:
    /// from the alert's buttons, after the alert has gone, so the two
    /// sheets do not collide.
    private func resumePendingFile() {
        guard let pending = pendingFormat else { return }
        pendingFormat = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(600))
            makeFile(pending)
        }
    }

    /// Your hours in the range, with the balance, and the working days
    /// left unwritten (the gap reminder's rule).
    private func readPersonal() {
        let repository = WorkdayRepository(context: modelContext)
        let range = resolvedRange
        let today = CalendarDate.today(in: calendar)
        let engine = PeriodEngine(settings: settings, calendar: calendar, firstRecorded: repository.firstRecordedDate())
        let days = engine.days(in: range, records: repository.records(in: range), holidays: repository.holidayRules())
        missingDates = MissingDays.personal(days: days, today: today)
        let totals = PeriodAggregator.summarize(days, range: range, countingThrough: today)
        let durations = settings.displayFormatting
        let balance = String(
            localized: "balance \(durations.signedString(totals.balanceMinutes))",
            comment: "Export preview summary, after the hours; the value is a signed duration"
        )
        summary = "\(durations.string(totals.workedMinutes)) · \(balance)"
    }

    /// "5 people · 21 days · 382h", read off the sheet, and the days none of
    /// its sites has anything written for.
    private func readSites(sheet: ExportTables) {
        let table = sheet.preview
        if table.kind == .siteSheet, sheet.hasContent {
            let days = table.rows.count - table.trailingSummaryRows
            // A person is the one group of two columns; the date, the day
            // and the notes are a column each.
            let peopleCount = table.validGroups.filter { $0.span > 1 }.count
            let minutes = sheetSites.reduce(0) { $0 + (monthSiteHours[$1.id] ?? 0) }
            summary = [
                String(inflected: "^[\(peopleCount) person](inflect: true)"),
                String(inflected: "^[\(days) day](inflect: true)"),
                settings.displayFormatting.string(minutes)
            ].joined(separator: " · ")
        } else {
            summary = ""
        }

        let repository = SiteRepository(context: modelContext)
        let range = month.range(in: calendar)
        let lookBack = CalendarDateRange(
            start: range.start.adding(days: -SiteWorkDays.lookBackDays, in: calendar),
            end: range.end
        )
        let siteDays = repository.siteDays(siteID: nil, in: lookBack)
        var holidays = Set<Int>()
        if settings.features.trackHolidays {
            let rules = WorkdayRepository(context: modelContext).holidayRules()
            holidays = HolidayResolver(rules: rules, calendar: calendar, covering: range).daysOffKeys(in: range, calendar: calendar)
        }
        let today = CalendarDate.today(in: calendar)
        let statuses = sheetSites.map { site in
            SiteDayStatus.month(
                month, siteID: site.id, siteDays: siteDays, setup: settings.siteSetup(for: site.id),
                crew: [], today: today, calendar: calendar, holidays: holidays
            )
        }
        missingDates = SiteDayStatus.missingDays(merging: statuses)
    }

    /// Everyone on any crew, hidden people left out, once per name.
    private func loadPeople() {
        let repository = SiteRepository(context: modelContext)
        var seen = Set<String>()
        var list: [CrewMember] = []
        for site in repository.sites(includeArchived: false) {
            for member in repository.crew(for: site.id, includeHidden: false) {
                let key = CrewCandidates.key(for: member.name)
                if !key.isEmpty, seen.insert(key).inserted { list.append(member) }
            }
        }
        people = list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Making the file

    /// PDF, Excel or CSV: the file written now, in this export's
    /// preferences, and opened ready to send.
    private func makeFile(_ format: ExportFormat) {
        guard hasContent else { return }
        guard subscriptions.allows(.fileExport) else {
            paywallReason = .fileExport
            return
        }
        if needsName {
            pendingFormat = format
            typedName = ""
            asksForName = true
            return
        }
        let preferences = exportPreferences
        do {
            let item: ExportReadyItem
            switch mode {
            case .onePerson:
                guard let sheet = personSheet else { return }
                let urls = try CrewSheetFiles.write([sheet], format: format, preferences: preferences, firstPDF: format == .pdf ? pdfData : nil)
                item = ExportReadyItem(
                    format: format, files: urls,
                    pdfData: format == .pdf ? pdfData : nil,
                    table: sheet.tables.preview,
                    closeMonth: closeMonth
                )
            case .crewSheet where perPerson:
                let urls = try CrewSheetFiles.write(personSheets, format: format, preferences: preferences, firstPDF: format == .pdf ? pdfData : nil)
                item = ExportReadyItem(
                    format: format, files: urls,
                    pdfData: format == .pdf ? pdfData : nil,
                    table: personSheets.first?.tables.preview,
                    note: personNote,
                    closeMonth: closeMonth
                )
            default:
                guard let tables else { return }
                let url: URL
                if format == .pdf, let pdfData {
                    url = try ExportFileFactory.write(data: pdfData, format: .pdf, baseName: fileBaseName)
                } else {
                    url = try ExportFileFactory.write(table: tables.file, format: format, preferences: preferences, baseName: fileBaseName)
                }
                item = ExportReadyItem(
                    format: format, files: [url],
                    pdfData: format == .pdf ? pdfData : nil,
                    table: tables.preview,
                    closeMonth: closeMonth
                )
            }
            failureMessage = nil
            ready = item
        } catch {
            failureMessage = String(
                localized: "The file could not be prepared. \(error.localizedDescription)",
                comment: "Export failed; the value is the system's own description"
            )
        }
    }

    /// Ticking a chip puts its site on the sheet; unticking takes it off,
    /// and the next one ticked becomes the sheet's own. One stays.
    private func toggleSite(_ id: UUID) {
        if id == primarySiteID {
            guard let next = sheetSiteIDs.first else { return }
            primarySiteID = next
            sheetSiteIDs.removeFirst()
        } else if let index = sheetSiteIDs.firstIndex(of: id) {
            sheetSiteIDs.remove(at: index)
        } else {
            sheetSiteIDs.append(id)
        }
    }

    /// One period of the chosen kind back or forward.
    private func step(_ direction: Int) {
        anchor = rangeKind.step(anchor, by: direction, calendar: calendar)
    }

    private func saveName() {
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            settingsStore.update { $0.export.ownerName = name }
        }
        nameAnswered = true
    }
}
