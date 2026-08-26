import SwiftUI
import SwiftData

/// Choose a range and a format, see exactly what will be produced, then share.
///
/// The preview is the same `ReportTable` the file is built from, so what is on
/// screen is what lands in the file — not an approximation of it.
struct ExportScreen: View {
    let initialRange: CalendarDateRange

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    @State private var rangeKind: ExportRangeKind = .month
    @State private var anchor: CalendarDate
    @State private var customStart: CalendarDate
    @State private var customEnd: CalendarDate
    @State private var format: ExportFormat = .csv

    @State private var previewTable: ReportTable?
    @State private var fileURL: URL?
    @State private var failureMessage: String?
    @State private var paywallReason: ProFeature?

    init(initialRange: CalendarDateRange) {
        self.initialRange = initialRange
        _anchor = State(initialValue: initialRange.start)
        _customStart = State(initialValue: initialRange.start)
        _customEnd = State(initialValue: initialRange.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                rangeSection
                formatSection
                previewSection
                shareSection
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                // Clear anything a previous export left in the temporary
                // directory before writing a new file into it.
                ExportFileFactory.clearPreviousExports()
                rangeKind = settingsStore.settings.export.defaultRange
                regenerate()
            }
            .onChange(of: regenerationKey) { _, _ in regenerate() }
            .paywall(for: $paywallReason)
        }
    }

    // MARK: - Sections

    private var rangeSection: some View {
        Section {
            Picker("Range", selection: $rangeKind) {
                ForEach(ExportRangeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if rangeKind == .custom {
                DatePicker("From", selection: dateBinding($customStart), displayedComponents: .date)
                DatePicker("To", selection: dateBinding($customEnd), displayedComponents: .date)
            } else {
                LabeledContent(rangeKind.title) {
                    Text(rangeDescription)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Range")
        } footer: {
            Text("\(dayCountText) · \(entryCountText)")
        }
    }

    private var formatSection: some View {
        Section {
            Picker("Format", selection: $format) {
                // Plain text, not labels: a segmented control shows one or the
                // other, and the words are what identify a file format.
                ForEach(ExportFormat.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Format")
        } footer: {
            Text(format.explanation)
        }
    }

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            if let previewTable, !previewTable.isEmpty {
                ExportPreviewTable(table: previewTable, rowLimit: 12)
                    .listRowInsets(EdgeInsets(top: Metrics.small, leading: 0, bottom: Metrics.small, trailing: 0))
                if previewTable.rows.count > 12 {
                    Text("Showing the first 12 of \(previewTable.rows.count) rows.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                ContentUnavailableView(
                    "Nothing in this range",
                    systemImage: "tray",
                    description: Text("Pick a different range, or switch on “Include days with no entry” in export options.")
                )
            }
        }
    }

    @ViewBuilder
    private var shareSection: some View {
        Section {
            if !subscriptions.allows(.fileExport) {
                // Stopped at the file, not at the door. Everything above —
                // the range, the columns, the preview — is what the person
                // needs in order to know what they would be buying.
                Button {
                    paywallReason = .fileExport
                } label: {
                    Label("Share timesheet", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .proLock(true)
            } else if let fileURL {
                ShareLink(item: fileURL) {
                    Label("Share \(fileURL.lastPathComponent)", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .disabled(previewTable?.isEmpty ?? true)
            } else if let failureMessage {
                Label(failureMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(Color.hoursNegative)
                    .font(.footnote)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }

            NavigationLink {
                ExportSettingsScreen()
            } label: {
                Label("Export options", systemImage: "slider.horizontal.3")
            }
        } footer: {
            if !subscriptions.allows(.fileExport) {
                Text("Timesheets are part of Hours Pro. Settings › Backup and data writes a file with every day you have ever recorded in it, and always will, free.")
            }
        }
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var formatting: CalendarFormatting { settingsStore.dateFormatting }

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
        return String(localized: "^[\(count) day](inflect: true)")
    }

    private var entryCountText: String {
        let count = previewTable?.rows.filter(\.hasEntry).count ?? 0
        return "\(count) with hours recorded"
    }

    private var reportTitle: String {
        switch rangeKind {
        case .day: return "Hours — \(formatting.mediumDate(anchor))"
        case .week: return "Hours — week of \(formatting.mediumDate(resolvedRange.start))"
        case .month: return "Hours — \(formatting.monthTitle(anchor.yearMonth))"
        case .year: return "Hours — \(anchor.year)"
        case .custom: return "Hours — \(rangeDescription)"
        }
    }

    private var fileBaseName: String {
        let range = resolvedRange
        switch rangeKind {
        case .day: return "Hours \(range.start)"
        case .month: return "Hours \(String(format: "%04d-%02d", range.start.year, range.start.month))"
        case .year: return "Hours \(range.start.year)"
        default: return "Hours \(range.start) to \(range.end)"
        }
    }

    /// Everything that changes what the file contains.
    private var regenerationKey: String {
        "\(resolvedRange.start.key)-\(resolvedRange.end.key)-\(format.rawValue)-\(settings.export.hashValue)"
    }

    private func dateBinding(_ binding: Binding<CalendarDate>) -> Binding<Date> {
        Binding(
            get: { binding.wrappedValue.date(in: calendar) },
            set: { binding.wrappedValue = CalendarDate($0, calendar: calendar) }
        )
    }

    // MARK: - Generation

    private func regenerate() {
        let repository = WorkdayRepository(context: modelContext)
        let range = resolvedRange
        let holidays = repository.holidayRules()
        let engine = PeriodEngine(settings: settings, calendar: calendar)
        let days = engine.days(in: range, records: repository.records(in: range), holidays: holidays)
        let opening = carriedBalance(before: range, repository: repository, holidays: holidays, engine: engine)

        // Two builds of the same table: files want empty cells, the preview
        // reads better with a dash.
        let today = CalendarDate.today(in: calendar)
        let fileTable = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "")
            .makeTable(
                days: days,
                range: range,
                title: reportTitle,
                openingBalanceMinutes: opening,
                countingThrough: today
            )
        previewTable = ReportBuilder(settings: settings, calendar: calendar, emptyPlaceholder: "—")
            .makeTable(
                days: days,
                range: range,
                title: reportTitle,
                openingBalanceMinutes: opening,
                countingThrough: today
            )

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
            failureMessage = "The file could not be prepared. \(error.localizedDescription)"
        }
    }

    /// The balance carried into the range, so a running-balance column starts
    /// from the truth rather than from zero.
    private func carriedBalance(
        before range: CalendarDateRange,
        repository: WorkdayRepository,
        holidays: [HolidayRule],
        engine: PeriodEngine
    ) -> Int {
        let opening = settings.openingBalanceMinutes
        guard settings.effectiveExportColumns.contains(.cumulativeBalance) else { return opening }

        let earliest = settings.balanceStartDate ?? repository.recordedDateBounds()?.first
        guard let earliest, earliest < range.start else { return opening }

        let priorRange = CalendarDateRange(start: earliest, end: range.start.adding(days: -1, in: calendar))
        let priorDays = engine.days(
            in: priorRange,
            records: repository.records(in: priorRange),
            holidays: holidays
        )
        return BalanceLedger.cumulative(
            over: priorDays,
            openingMinutes: opening,
            startDate: settings.balanceStartDate,
            countingThrough: CalendarDate.today(in: calendar)
        )
    }
}
