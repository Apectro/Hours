import SwiftUI
import SwiftData

/// The report for the boss (mockup 15): which jobs — not sent yet, this
/// week, or picked dates — the material they add up to, the jobs, the
/// client's optional signature under the lot, and "Send to boss · PDF", with
/// Excel and CSV beside it.
///
/// The jobs are marked sent only once the share sheet says the file went
/// somewhere (`ExtraWorkSending`); cancelling it leaves them as they were.
/// A CSV is data for an import rather than the report, so sharing one marks
/// nothing. Everything is written in the export language set in Settings.
struct ExtraWorkReportScreen: View {
    let site: Site
    /// False on a site that is read-only (archived, or Pro lapsed): its jobs
    /// can be reported and marked, not edited.
    var canEdit = true

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var choice: Choice = .notSent
    @State private var from: Date = Date()
    @State private var to: Date = Date()
    @State private var allJobs: [ExtraWorkJob] = []
    @State private var signature: ExtraWorkSignature?
    @State private var showsAllJobs = false
    @State private var sheet: ReportSheet?
    @State private var preparing: ExportFormat?
    @State private var notice: String?
    @State private var failure: String?

    private enum Choice: String, CaseIterable, Identifiable {
        case notSent, thisWeek, dates
        var id: String { rawValue }
    }

    private enum ReportSheet: Identifiable {
        case signature
        case job(ExtraWorkJob)

        var id: String {
            switch self {
            case .signature: return "signature"
            case let .job(job): return job.id.uuidString
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.large) {
                    Picker(selection: $choice) {
                        Text("Not sent yet").tag(Choice.notSent)
                        Text("This week").tag(Choice.thisWeek)
                        Text("Pick dates").tag(Choice.dates)
                    } label: {
                        Text("Jobs")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("extra-work-report-range")

                    if choice == .dates {
                        VStack(spacing: 0) {
                            DatePicker("From", selection: $from, displayedComponents: .date)
                                .frame(minHeight: 44)
                            Divider()
                            DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                                .frame(minHeight: 44)
                        }
                        .padding(.horizontal, Metrics.large)
                        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: site.name)
                            .font(.title2.weight(.bold))
                        Text(verbatim: summaryLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("extra-work-report-summary")
                    }
                    .padding(.leading, Metrics.tiny)

                    if report.isEmpty {
                        Text("Nothing to report for these dates.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Metrics.large)
                            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                    } else {
                        materialSection
                        jobsSection
                        signatureSection
                    }
                }
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.medium)
            }
            .background(Color.hoursCanvas)
            .safeAreaInset(edge: .bottom) { shareBar }
            .navigationTitle("Extra work report")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen-extra-work-report")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("extra-work-report-done")
                }
            }
            .onAppear(perform: load)
            .onChange(of: choice) { _, _ in showsAllJobs = false }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .signature:
                    ExtraWorkSignSheet(prompt: String(localized: "Sign to confirm these jobs")) { signed in
                        signature = signed
                    }
                case let .job(job):
                    ExtraWorkEditorSheet(site: site, date: job.date, job: job, canEdit: canEdit, onDone: load)
                }
            }
            .alert("Could not share", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) { failure = nil }
            } message: {
                Text(verbatim: failure ?? "")
            }
        }
    }

    // MARK: - Material

    private var materialSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Material in total")
            VStack(spacing: 0) {
                ForEach(Array(report.totals.enumerated()), id: \.offset) { index, total in
                    HStack {
                        Text(verbatim: total.name)
                        Spacer(minLength: Metrics.small)
                        Text(verbatim: "\(ExtraWorkFormatting.quantity(total.quantity)) \(total.unit.name(in: .device))")
                            .font(.body.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, Metrics.large)
                    .frame(minHeight: 44)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("extra-work-total-\(index)")
                    if index < report.totals.count - 1 {
                        Divider().padding(.leading, Metrics.large)
                    }
                }
            }
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
    }

    // MARK: - Jobs

    private static let collapsedCount = 3

    private var shownJobs: [ExtraWorkJob] {
        showsAllJobs ? report.jobs : Array(report.jobs.prefix(ExtraWorkReportScreen.collapsedCount))
    }

    private var jobsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Jobs")
            VStack(spacing: 0) {
                ForEach(Array(shownJobs.enumerated()), id: \.element.id) { index, job in
                    Button {
                        sheet = .job(job)
                    } label: {
                        jobRow(job)
                    }
                    .buttonStyle(.plain)
                    .contextMenu { statusActions(for: job) }
                    .accessibilityIdentifier("extra-work-report-job-\(index)")
                    if index < shownJobs.count - 1 || hiddenCount > 0 {
                        Divider().padding(.leading, Metrics.large)
                    }
                }
                if hiddenCount > 0 {
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { showsAllJobs = true }
                    } label: {
                        Text(String(
                            localized: "Show \(hiddenCount) more",
                            comment: "Extra work report: shows the jobs not listed yet; the value is how many"
                        ))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, Metrics.large)
                    }
                    .accessibilityIdentifier("extra-work-report-more")
                }
            }
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

            let sent = report.jobs.filter { $0.status == .sent }
            if !sent.isEmpty {
                Button {
                    markInvoiced(sent)
                } label: {
                    Text(String(
                        localized: "Mark the sent ones as invoiced (\(sent.count))",
                        comment: "Extra work report: marks every sent job in the report invoiced; the value is how many"
                    ))
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("extra-work-report-mark-invoiced")
            }
        }
    }

    private var hiddenCount: Int { report.jobs.count - shownJobs.count }

    private func jobRow(_ job: ExtraWorkJob) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: job.description.isEmpty ? String(localized: "Extra work") : job.description)
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(verbatim: jobDetail(job))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                if report.isConfirmed(job) {
                    Text("Signed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.hoursPositive)
                } else {
                    Text("Not signed")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.hoursNegative)
                }
                if job.status != .open {
                    ExtraWorkChipView(chip: job.chip)
                }
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Thu 22 Oct · 6h".
    private func jobDetail(_ job: ExtraWorkJob) -> String {
        var parts = [settingsStore.dateFormatting.mediumDate(job.date)]
        if job.hasHours { parts.append(settingsStore.settings.displayFormatting.string(job.totalMinutes)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusActions(for job: ExtraWorkJob) -> some View {
        switch job.status {
        case .sent:
            Button("Mark as invoiced") { markInvoiced([job]) }
        case .invoiced:
            Button("Not invoiced after all") { setStatus([job.reopening()]) }
        case .open:
            EmptyView()
        }
    }

    // MARK: - Client's signature

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Client confirms")
                    .font(.body.weight(.semibold))
                Spacer()
                Text("optional")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let signature {
                SignaturePreview(strokes: signature.strokes, aspectRatio: signature.aspectRatio)
                    .frame(height: 84)
                    .accessibilityLabel(String(localized: "Client's signature"))
                Text(verbatim: signedLine(signature))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Remove signature", role: .destructive) { self.signature = nil }
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("extra-work-report-remove-signature")
            } else {
                Text("The client's site manager can sign for all of these jobs at once. It is printed under the report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Sign") { sheet = .signature }
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("extra-work-report-sign")
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    /// "Ing. M. Horvat · 22 Oct, 15:40".
    private func signedLine(_ signature: ExtraWorkSignature) -> String {
        let calendar = settingsStore.workCalendar
        let day = CalendarDate(signature.signedAt, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: signature.signedAt)
        let time = settingsStore.dateFormatting.time(TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0), on: day)
        let when = "\(settingsStore.dateFormatting.shortDate(day)), \(time)"
        let name = signature.signerName.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? when : "\(name) · \(when)"
    }

    // MARK: - Sharing

    private var shareBar: some View {
        VStack(spacing: Metrics.small) {
            Button {
                share(.pdf)
            } label: {
                Group {
                    if preparing == .pdf {
                        ProgressView()
                    } else {
                        Label("Send to boss · PDF", systemImage: "square.and.arrow.up")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(report.isEmpty || preparing != nil)
            .accessibilityIdentifier("extra-work-report-share-pdf")

            HStack(spacing: Metrics.small) {
                Button {
                    share(.xlsx)
                } label: {
                    Text(verbatim: ExportFormat.xlsx.title)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .accessibilityIdentifier("extra-work-report-share-xlsx")
                Button {
                    share(.csv)
                } label: {
                    Text(verbatim: ExportFormat.csv.title)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .accessibilityIdentifier("extra-work-report-share-csv")
            }
            .buttonStyle(.bordered)
            .disabled(report.isEmpty || preparing != nil)

            Text(verbatim: notice ?? String(localized: "Marked as sent after you share the PDF or the Excel file."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("extra-work-report-notice")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(.bar)
    }

    private func share(_ format: ExportFormat) {
        let report = self.report
        guard !report.isEmpty else { return }
        preparing = format
        notice = nil
        let repository = ExtraWorkRepository(context: modelContext)
        let photoIDs = format == .pdf ? repository.photoIDs(siteID: site.id, jobIDs: Set(report.jobs.map(\.id))) : [:]
        let document = ExtraWorkDocumentBuilder(settings: settingsStore.settings, calendar: settingsStore.workCalendar)
            .make(report: report, siteName: site.name, photoIDs: photoIDs)

        Task { @MainActor in
            // A turn of the run loop, so the spinner shows before a PDF with
            // photos is drawn.
            await Task.yield()
            let data: Data
            switch format {
            case .pdf:
                let stored = repository.photoData(ids: Set(photoIDs.values.flatMap { $0 }), siteID: site.id)
                let small = stored.compactMapValues { DiaryPhotoProcessor.thumbnailPrintJPEG(from: $0) }
                data = ExtraWorkPDFRenderer.data(for: document, photos: small)
            case .xlsx:
                data = document.workbook(preferences: settingsStore.settings.export, generatedOn: Date())
            case .csv:
                data = CSVExporter.data(for: document.linesTable(), preferences: settingsStore.settings.export)
            }
            preparing = nil
            let url: URL
            do {
                url = try ExportFileFactory.write(data: data, format: format, baseName: document.fileName)
            } catch {
                failure = error.localizedDescription
                return
            }
            ShareSheetPresenter.present(url) { outcome in
                finishSharing(report, format: format, outcome: outcome)
            }
        }
    }

    /// The jobs become sent here and only here: after a PDF or a workbook
    /// was really shared.
    private func finishSharing(_ report: ExtraWorkReport, format: ExportFormat, outcome: ExtraWorkShareOutcome) {
        guard format != .csv, outcome == .completed else { return }
        let record = ExtraWorkReportRecord(
            siteID: site.id,
            sentAt: Date(),
            jobIDs: report.jobs.map(\.id),
            clientSignature: report.clientSignature
        )
        let marked = ExtraWorkSending.marked(report.jobs, after: outcome, reportID: record.id, at: record.sentAt)
        ExtraWorkRepository(context: modelContext).recordSent(record, jobs: marked)
        notice = String(
            localized: "Marked as sent: \(marked.count)",
            comment: "Extra work report, after sharing; the value is how many jobs were marked sent"
        )
        load()
    }

    private func markInvoiced(_ jobs: [ExtraWorkJob]) {
        setStatus(jobs.map { $0.markingInvoiced() })
    }

    private func setStatus(_ jobs: [ExtraWorkJob]) {
        ExtraWorkRepository(context: modelContext).storeStatus(of: jobs)
        load()
    }

    // MARK: - Derived

    private var range: ExtraWorkRange {
        switch choice {
        case .notSent: return .notSentYet
        case .thisWeek: return .thisWeek
        case .dates:
            let calendar = settingsStore.workCalendar
            let start = CalendarDate(from, calendar: calendar)
            let end = max(start, CalendarDate(to, calendar: calendar))
            return .dates(CalendarDateRange(start: start, end: end))
        }
    }

    private var report: ExtraWorkReport {
        let calendar = settingsStore.workCalendar
        let chosen = range.select(allJobs, siteID: site.id, today: CalendarDate.today(in: calendar), calendar: calendar)
        return ExtraWorkReport(siteID: site.id, jobs: chosen, clientSignature: signature)
    }

    /// "5 jobs · 19–22 Oct", without a plural to agree.
    private var summaryLine: String {
        let count = String(localized: "Jobs: \(report.jobs.count)", comment: "Extra work report: how many jobs it carries")
        guard let period = report.period else { return count }
        let formatting = settingsStore.dateFormatting
        let dates = period.start == period.end
            ? formatting.shortDate(period.start)
            : "\(formatting.shortDate(period.start)) – \(formatting.shortDate(period.end))"
        return "\(count) · \(dates)"
    }

    private func sectionLabel(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .padding(.leading, Metrics.tiny)
            .accessibilityAddTraits(.isHeader)
    }

    private func load() {
        allJobs = ExtraWorkRepository(context: modelContext).jobs(siteID: site.id)
    }
}

/// A stored signature drawn back, on the white of paper, as mockup 15
/// shows it.
struct SignaturePreview: View {
    let strokes: [[SignaturePoint]]
    let aspectRatio: Double

    var body: some View {
        Canvas { context, size in
            let aspect = CGFloat(max(aspectRatio, 0.1))
            let scale = min(size.width / aspect, size.height) * 0.9
            let origin = CGPoint(x: (size.width - aspect * scale) / 2, y: (size.height - scale) / 2)
            var path = Path()
            for stroke in strokes {
                guard let first = stroke.first else { continue }
                path.move(to: CGPoint(x: origin.x + CGFloat(first.x) * scale, y: origin.y + CGFloat(first.y) * scale))
                for point in stroke.dropFirst() {
                    path.addLine(to: CGPoint(x: origin.x + CGFloat(point.x) * scale, y: origin.y + CGFloat(point.y) * scale))
                }
            }
            context.stroke(path, with: .color(Color(white: 0.11)), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
        }
        .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
