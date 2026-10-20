import SwiftUI
import SwiftData

/// A site's month as the director gets it: one row per day, one column per
/// person, each person's total and days worked at the bottom.
///
/// Opens on last month, because that is the month the director asks for at
/// the start of this one. The preview is the same `ReportTable` the file is
/// built from, as on the timesheet export, and like there it is free: only
/// writing the file goes through `.fileExport`.
struct SiteExportScreen: View {
    let site: Site

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    @State private var month: YearMonth
    @State private var format: ExportFormat = .pdf

    @State private var previewTable: ReportTable?
    @State private var fileURL: URL?
    @State private var failureMessage: String?
    @State private var paywallReason: ProFeature?

    /// The sheet heads your column with your name, so it is asked for once
    /// when it is missing — at the share button, never in front of the
    /// preview. "Not now" is an answer too: the column then says "You".
    @State private var asksForName = false
    @State private var typedName = ""
    @State private var nameAnswered = false

    init(site: Site, month: YearMonth) {
        self.site = site
        _month = State(initialValue: month)
    }

    var body: some View {
        NavigationStack {
            Form {
                monthSection
                formatSection
                previewSection
                shareSection
            }
            .navigationTitle("Export")
            // A screen the UI tests wait for. The title beside it is translated.
            .accessibilityIdentifier("screen-site-export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // As the timesheet export does: nothing an earlier export
                // left behind stays in the temporary directory.
                ExportFileFactory.clearPreviousExports()
                regenerate()
            }
            .onChange(of: regenerationKey) { _, _ in regenerate() }
            .alert("Your name on the sheet", isPresented: $asksForName) {
                TextField("Name and surname", text: $typedName)
                    .textInputAutocapitalization(.words)
                Button("Save") { saveName() }
                Button("Not now", role: .cancel) { nameAnswered = true }
            } message: {
                Text("Printed above your column instead of “You”, and kept in Settings › Export options.")
            }
            .paywall(for: $paywallReason)
        }
    }

    // MARK: - Sections

    private var monthSection: some View {
        Section("Month") {
            HStack {
                Button {
                    month = month.adding(months: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous month")

                Spacer(minLength: Metrics.medium)
                Text(formatting.monthTitle(month))
                    .font(.headline)
                Spacer(minLength: Metrics.medium)

                Button {
                    month = month.adding(months: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next month")
                // Nothing has been worked after this month yet.
                .disabled(month >= currentMonth)
            }
            // Two buttons in one row: without this a tap anywhere in the row
            // presses both.
            .buttonStyle(.borderless)
        }
    }

    private var formatSection: some View {
        Section("Format") {
            Picker("Format", selection: $format) {
                ForEach(ExportFormat.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            if let previewTable, hasDays(previewTable) {
                // Every day of the month: there are never more than 31, and a
                // director's sheet missing its last week is not a preview of it.
                ExportPreviewTable(table: previewTable, rowLimit: 31)
                    .listRowInsets(EdgeInsets(top: Metrics.small, leading: 0, bottom: Metrics.small, trailing: 0))
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
    private var shareSection: some View {
        Section {
            if !subscriptions.allows(.fileExport) {
                // Stopped at the file, as the timesheet export is: the month,
                // the format and the preview are how the person knows what
                // they would be buying.
                Button {
                    paywallReason = .fileExport
                } label: {
                    shareLabel
                }
                .proLock(true)
            } else if needsName {
                Button {
                    typedName = ""
                    asksForName = true
                } label: {
                    shareLabel
                }
                .disabled(!hasDays(previewTable))
            } else if let fileURL {
                ShareLink(item: fileURL) {
                    Label(String(
                        localized: "Share \(fileURL.lastPathComponent)",
                        comment: "The share button; the value is a file name"
                    ), systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!hasDays(previewTable))
            } else if let failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.hoursNegative)
                    .font(.footnote)
            } else if hasDays(previewTable) {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else {
                shareLabel
                    .foregroundStyle(.secondary)
            }
        } footer: {
            if !subscriptions.allows(.fileExport) {
                Text("The director's sheet is part of Zeitkonto Pro. The preview is free, and every site day stays in your backup.")
            }
        }
    }

    private var shareLabel: some View {
        Label("Share site hours", systemImage: "square.and.arrow.up")
            .frame(maxWidth: .infinity)
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }
    private var currentMonth: YearMonth { CalendarDate.today(in: calendar).yearMonth }

    private var needsName: Bool {
        !nameAnswered && settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The sheet always ends with its two summary rows; a month with no site
    /// days has those and nothing else.
    private func hasDays(_ table: ReportTable?) -> Bool {
        guard let table else { return false }
        return table.rows.count > table.trailingSummaryRows
    }

    /// The site's name and the month, so a folder of them sorts by site and
    /// then by month. `ExportFileFactory` sanitises it as it does every export.
    private var fileBaseName: String {
        "\(site.name) \(String(format: "%04d-%02d", month.year, month.month))"
    }

    /// Everything that changes what the file contains, or whether one is
    /// written yet.
    private var regenerationKey: String {
        "\(month.year)-\(month.month)-\(format.rawValue)-\(settings.export.hashValue)-\(needsName)-\(subscriptions.allows(.fileExport))"
    }

    // MARK: - Generation

    private func regenerate() {
        let repository = SiteRepository(context: modelContext)
        let range = month.range(in: calendar)
        // Hidden people stay on the sheet: hiding only stops them being
        // offered for new days, and they worked the days they worked.
        let crew = repository.crew(for: site.id, includeHidden: true)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = repository.siteDays(siteID: site.id, in: range).map { calculator.compute($0) }

        // Two builds of the same sheet, as on the timesheet export: files want
        // empty cells, the preview reads better with a dash.
        let fileTable = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "")
            .makeTable(site: site, crew: crew, results: results, range: range)
        previewTable = SiteSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(site: site, crew: crew, results: results, range: range)

        // No file for the paywall to stand in front of, none for an empty
        // month, and none before the name is settled — it would only be
        // written again with the name in it.
        guard subscriptions.allows(.fileExport), hasDays(fileTable), !needsName else {
            fileURL = nil
            failureMessage = nil
            return
        }

        do {
            fileURL = try ExportFileFactory.write(
                table: fileTable,
                format: format,
                preferences: settings.export,
                baseName: fileBaseName
            )
            failureMessage = nil
        } catch {
            fileURL = nil
            failureMessage = String(
                localized: "The file could not be prepared. \(error.localizedDescription)",
                comment: "Export failed; the value is the system's own description"
            )
        }
    }

    private func saveName() {
        let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            settingsStore.update { $0.export.ownerName = name }
        }
        nameAnswered = true
    }
}
