import SwiftUI
import SwiftData
import UIKit

/// Choose whose hours and which days, see exactly what will be produced, then
/// share it.
///
/// One screen for your own timesheet and for a site's month: opened from the
/// calendar it starts on your hours, opened from a site on that site, and
/// when there are sites a switch at the top moves between them. The preview
/// is the same `ReportTable` the file is built from — for a PDF, the real
/// first page — so what is on screen is what lands in the file.
struct ExportScreen: View {
    let initialRange: CalendarDateRange
    private let initialTarget: ExportTarget

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    // Every site rather than the active ones: a site opened from its own
    // screen may be archived, and its months are still the director's.
    @Query(sort: \SiteEntry.sortOrder) private var siteEntries: [SiteEntry]

    @State private var target: ExportTarget
    @State private var rangeKind: ExportRangeKind = .month
    @State private var anchor: CalendarDate
    @State private var customStart: CalendarDate
    @State private var customEnd: CalendarDate
    /// `nil` until stepped: a site's sheet opens on last month, because that
    /// is the month the director asks for at the start of this one.
    @State private var siteMonth: YearMonth?
    @State private var format: ExportFormat = .pdf

    /// What the timesheet file will be called, without its extension.
    ///
    /// Follows the range until somebody types over it, and stops following
    /// the moment they do — changing the month after naming a file should not
    /// silently rename it back.
    @State private var fileName: String = ""
    @State private var fileNameEdited = false

    @State private var tables: ExportTables?
    @State private var pdfData: Data?
    @State private var pageImage: UIImage?
    @State private var fileURL: URL?
    @State private var failureMessage: String?
    @State private var paywallReason: ProFeature?
    @State private var showsFullPage = false

    /// The sheet carries your name, so it is asked for once when it is
    /// missing — at the share button, never in front of the preview. "Not
    /// now" is an answer too: the sheet then goes without.
    @State private var asksForName = false
    @State private var typedName = ""
    @State private var nameAnswered = false

    /// A site's diary follows its hours unless switched off here. The switch
    /// is only offered for a month that has a diary, so "on" is the default
    /// exactly when there is something to include.
    @State private var includesDiary = true
    /// Diary photos already made small for the PDF, kept between previews so
    /// stepping months or formats does not re-encode them every time.
    @State private var printPhotos: [UUID: Data] = [:]
    /// Signing a site's sheet is optional. Off, the sheet has no line to sign
    /// on and no sign-off page, and the sign-off screen is not offered.
    /// Remembered, because a crew that does not sign never does.
    @AppStorage("export.siteSignatures") private var includesSignatures = true
    /// Moved on by the sign-off screen, so a new signature redraws the preview.
    @State private var signOffRevision = 0

    /// - Parameters:
    ///   - initialRange: the days your own timesheet starts on.
    ///   - site: the site to open on, when opened from one.
    ///   - month: the site month to open on; last month when `nil`.
    init(initialRange: CalendarDateRange, site: Site? = nil, month: YearMonth? = nil) {
        self.initialRange = initialRange
        let target: ExportTarget = site.map { .site($0.id) } ?? .personal
        self.initialTarget = target
        _target = State(initialValue: target)
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
                .accessibilityIdentifier(selectedSite == nil ? "screen-export" : "screen-site-export")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("export-done")
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    ExportShareBar(
                        format: format,
                        state: shareState,
                        onLocked: { paywallReason = .fileExport },
                        onNeedsName: askForName
                    )
                }
                .task {
                    // Clear anything a previous export left in the temporary
                    // directory before writing a new file into it.
                    ExportFileFactory.clearPreviousExports()
                    rangeKind = settings.export.defaultRange
                    regenerate()
                }
                .onChange(of: regenerationKey) { _, _ in regenerate() }
                // A new name is a rename, not a re-export: the file already on
                // disk is the right one, and rebuilding it per keystroke is work
                // that arrives back where it started.
                .onChange(of: fileBaseName) { _, newName in
                    guard let url = fileURL else { return }
                    fileURL = (try? ExportFileFactory.rename(url, to: newName)) ?? url
                }
                .alert("Your name on the sheet", isPresented: $asksForName) {
                    TextField("Name and surname", text: $typedName)
                        .textInputAutocapitalization(.words)
                    Button("Save") { saveName() }
                    Button("Not now", role: .cancel) { nameAnswered = true }
                } message: {
                    nameMessage
                }
                .sheet(isPresented: $showsFullPage) {
                    ExportFullPageSheet(data: pdfData ?? Data())
                }
                .paywall(for: $paywallReason)
        }
    }

    // MARK: - Sections

    private var form: some View {
        Form {
            if !pickableSites.isEmpty {
                ExportTargetPicker(target: $target, sites: pickableSites)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            if let site = selectedSite {
                siteMonthSection(site)
            } else {
                ExportRangeSection(
                    rangeKind: $rangeKind,
                    customStart: dateBinding($customStart),
                    customEnd: dateBinding($customEnd),
                    description: rangeDescription,
                    footer: "\(dayCountText) · \(entryCountText)"
                )
            }
            previewSection
            Section {
                ExportFormatCards(selection: $format)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            nameSection
            if selectedSite == nil {
                fileSection
            }
        }
    }

    private func siteMonthSection(_ site: Site) -> some View {
        Section {
            ExportMonthStepper(
                month: monthBinding,
                latest: currentMonth,
                title: formatting.monthTitle(month),
                caption: siteCaption
            )
            if tables?.hasDiary == true {
                Toggle("Include site diary", isOn: $includesDiary)
                    .accessibilityIdentifier("export-include-diary")
            }
            Toggle("Signatures", isOn: $includesSignatures)
                .accessibilityIdentifier("export-include-signatures")
            // A link with its destination inline, as Export options below:
            // a value pushed onto this sheet's own stack. Always shown, so it
            // can be found; with Signatures off it stays, greyed, saying why.
            NavigationLink {
                SiteSignOffScreen(site: site, month: month) { signOffRevision += 1 }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Crew sign-off", systemImage: "signature")
                    if !includesSignatures {
                        Text("Turned off for this sheet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .disabled(!includesSignatures)
            .accessibilityIdentifier("export-sign-off")
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.small) {
                if tables?.hasDiary == true && includesDiary {
                    Text("The diary follows the hours: on pages of its own in the PDF, on a second sheet in Excel. A CSV holds the hours only.")
                }
                if !includesSignatures {
                    Text("No line to sign on and no sign-off page. Signatures already given are kept.")
                }
            }
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            if let tables, tables.hasContent {
                if format == .pdf {
                    ExportPagePreview(image: pageImage) { showsFullPage = pdfData != nil }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } else {
                    tablePreview(tables.preview)
                }
            } else if selectedSite != nil {
                ContentUnavailableView(
                    "Nothing recorded this month",
                    systemImage: "tray",
                    description: Text("Choose another month to see its days.")
                )
            } else {
                ContentUnavailableView(
                    "Nothing in this range",
                    systemImage: "tray",
                    description: Text("Pick a different range, or switch on “Include days with no entry” in export options.")
                )
            }
        }
    }

    /// The table the workbook or the CSV will hold. A site's month is shown
    /// whole — never more than 31 days, and a director's sheet missing its
    /// last week is not a preview of it — and a timesheet's first dozen days.
    @ViewBuilder
    private func tablePreview(_ table: ReportTable) -> some View {
        let limit = table.kind == .siteSheet ? 31 : 12
        ExportPreviewTable(table: table, rowLimit: limit)
            .listRowInsets(EdgeInsets(top: Metrics.small, leading: 0, bottom: Metrics.small, trailing: 0))
        if table.kind == .timesheet && table.rows.count > limit {
            Text(String(
                    localized: "Showing the first 12 of \(table.rows.count) rows.",
                    comment: "Under the export preview when the range is longer than the preview"
                ))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var nameSection: some View {
        Section {
            ExportNameRow(name: ownerName) {
                typedName = ownerName
                asksForName = true
            }
        } footer: {
            if !subscriptions.allows(.fileExport) {
                if selectedSite == nil {
                    Text("Timesheets are part of Zeitkonto Pro. Settings › Backup and data writes a file with every day you have ever recorded in it, and always will, free.")
                } else {
                    Text("The director's sheet is part of Zeitkonto Pro. The preview is free, and every site day stays in your backup.")
                }
            }
        }
    }

    private var fileSection: some View {
        Section {
            HStack {
                TextField(suggestedFileName, text: fileNameBinding)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                Text(verbatim: ".\(format.fileExtension)")
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("File name")

            NavigationLink {
                ExportSettingsScreen()
            } label: {
                Label("Export options", systemImage: "slider.horizontal.3")
            }
        }
    }

    @ViewBuilder
    private var nameMessage: some View {
        if selectedSite == nil {
            Text("Printed on every sheet you export, and kept in Settings › Export options.")
        } else {
            Text("Printed above your column instead of “You”, and kept in Settings › Export options.")
        }
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var currentMonth: YearMonth { CalendarDate.today(in: calendar).yearMonth }
    private var ownerName: String { settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// For display only, so a duplicate row left by sync just means the first
    /// of the two is shown; `SiteRepository` collapses it on the next read.
    private var allSites: [Site] {
        var seen = Set<UUID>()
        return siteEntries.map(\.site).filter { seen.insert($0.id).inserted }
    }

    /// The active sites, and the one the screen was opened from even if it
    /// has been archived since.
    private var pickableSites: [Site] {
        allSites.filter { !$0.isArchived || $0.id == initialTarget.siteID }
    }

    private var selectedSite: Site? {
        guard let id = target.siteID else { return nil }
        return allSites.first { $0.id == id }
    }

    private var month: YearMonth { siteMonth ?? currentMonth.adding(months: -1) }

    private var monthBinding: Binding<YearMonth> {
        Binding(get: { month }, set: { siteMonth = $0 })
    }

    /// "21 days · 5 people", read off the sheet itself.
    private var siteCaption: String {
        guard let table = tables?.preview, table.kind == .siteSheet, tables?.hasContent == true else { return "" }
        let days = table.rows.count - table.trailingSummaryRows
        let people = max(table.validGroups.count - 2, 0)
        // Two counts joined rather than one sentence: each agrees with its
        // own number, and the dot between them needs no translating.
        return [
            String(inflected: "^[\(days) day](inflect: true)"),
            String(inflected: "^[\(people) person](inflect: true)")
        ].joined(separator: " · ")
    }

    private var needsName: Bool { !nameAnswered && ownerName.isEmpty }

    private var shareState: ExportShareState {
        guard let tables, tables.hasContent else { return tables == nil ? .preparing : .empty }
        if !subscriptions.allows(.fileExport) { return .locked }
        if needsName { return .needsName }
        if let fileURL { return .ready(fileURL) }
        if let failureMessage { return .failed(failureMessage) }
        return .preparing
    }

    private var resolvedRange: CalendarDateRange {
        switch rangeKind {
        case .day: return CalendarDateRange(single: anchor)
        case .week: return CalendarDateRange.week(containing: anchor, in: calendar)
        case .month: return anchor.yearMonth.range(in: calendar)
        case .year: return CalendarDateRange.year(anchor.year, in: calendar)
        case .custom: return CalendarDateRange(start: customStart, end: customEnd)
        }
    }

    private var rangeDescription: String {
        let range = resolvedRange
        return range.start == range.end
            ? formatting.mediumDate(range.start)
            : "\(formatting.mediumDate(range.start)) – \(formatting.mediumDate(range.end))"
    }

    private var dayCountText: String {
        let count = resolvedRange.days(in: calendar).count
        return String(inflected: "^[\(count) day](inflect: true)")
    }

    private var entryCountText: String {
        let count = tables?.preview.rows.filter(\.hasEntry).count ?? 0
        return String(
            localized: "\(count) with hours recorded",
            comment: "How many days in the range actually have hours on them"
        )
    }

    private var exportNaming: ExportNaming {
        ExportNaming(settings: settings, calendar: calendar)
    }

    /// The file's name when nobody has typed one: a timesheet's follows its
    /// range, a site's is the site and the month.
    private var suggestedFileName: String {
        if let site = selectedSite { return exportNaming.siteFileName(site, month: month) }
        return exportNaming.timesheetFileName(rangeKind: rangeKind, range: resolvedRange)
    }

    /// Typing marks the name as the person's own; clearing the field hands it
    /// back to the range, so there is always a way to undo an edit.
    private var fileNameBinding: Binding<String> {
        Binding(
            get: { fileName },
            set: { typed in
                fileName = typed
                // Emptying the field hands the name back to the range rather
                // than snapping the suggestion in under the cursor — which
                // would make deleting the last character impossible.
                fileNameEdited = !typed.trimmingCharacters(in: .whitespaces).isEmpty
            }
        )
    }

    private var fileBaseName: String {
        guard selectedSite == nil else { return suggestedFileName }
        let typed = fileName.trimmingCharacters(in: .whitespaces)
        return typed.isEmpty ? suggestedFileName : typed
    }

    /// Everything that changes what the file contains, or whether one is
    /// written yet.
    private var regenerationKey: String {
        let range = resolvedRange
        let who = target.siteID.map { "\($0.uuidString)-\(month.year)-\(month.month)" } ?? "\(range.start.key)-\(range.end.key)"
        return "\(who)-\(format.rawValue)-\(settings.export.hashValue)-\(needsName)-\(subscriptions.allows(.fileExport))"
            + "-\(includesDiary)-\(includesSignatures)-\(signOffRevision)"
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

        let maker = ExportTableMaker(context: modelContext, settings: settings, calendar: calendar)
        let built: ExportTables
        if let site = selectedSite {
            built = maker.site(site, month: month, includeDiary: includesDiary, includeSignatures: includesSignatures)
        } else {
            built = maker.personal(
                range: resolvedRange,
                title: exportNaming.reportTitle(rangeKind: rangeKind, anchor: anchor, range: resolvedRange),
                period: exportNaming.period(rangeKind: rangeKind, anchor: anchor, range: resolvedRange)
            )
        }
        tables = built

        // The PDF is drawn for the preview whether or not it can be shared:
        // seeing the page is free. The same bytes become the file.
        if format == .pdf && built.hasContent {
            var photos: [UUID: Data] = [:]
            if let site = selectedSite, !built.photoIDs.isEmpty {
                photos = maker.printPhotos(ids: built.photoIDs, site: site, month: month, cache: printPhotos)
                printPhotos.merge(photos) { _, new in new }
            }
            let data = PDFReportRenderer.data(for: built.file, photos: photos)
            pdfData = data
            pageImage = ExportPagePreview.thumbnail(of: data)
        } else {
            pdfData = nil
            pageImage = nil
        }

        // No file for the paywall to stand in front of, none for an empty
        // range, and none before the name is settled — it would only be
        // written again with the name in it.
        guard subscriptions.allows(.fileExport), built.hasContent, !needsName else {
            fileURL = nil
            failureMessage = nil
            return
        }

        do {
            if let pdfData, format == .pdf {
                fileURL = try ExportFileFactory.write(data: pdfData, format: .pdf, baseName: fileBaseName)
            } else {
                fileURL = try ExportFileFactory.write(
                    table: built.file,
                    format: format,
                    preferences: settings.export,
                    baseName: fileBaseName
                )
            }
            failureMessage = nil
        } catch {
            fileURL = nil
            failureMessage = String(
                localized: "The file could not be prepared. \(error.localizedDescription)",
                comment: "Export failed; the value is the system's own description"
            )
        }
    }

    private func askForName() {
        typedName = ""
        asksForName = true
    }

    private func saveName() {
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            settingsStore.update { $0.export.ownerName = name }
        }
        nameAnswered = true
    }
}
