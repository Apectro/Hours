import StoreKit
import SwiftUI
import SwiftData

/// The Extra-work report for the boss (mockup 15): the site and what the
/// report carries first, then which jobs — not sent yet, this week, or
/// picked dates — what is done, if asked for what is still in progress, the
/// material used and the client's optional signature under the lot. One
/// button sends it ("Send to boss · PDF"); the picture for a chat, Excel and
/// CSV are under "More formats" beside it.
///
/// Jobs in progress on the site, whatever their date, are one line under the
/// title ("2 extra jobs in progress · Mark finished"), opening in place to a list with
/// checkmarks: the place they are easy to find and tick.
///
/// A report tells the boss what is done; it is not a bill. Only finished
/// jobs are in it unless "Include jobs still in progress" is on, and those
/// then have a section of their own. A new job starts in progress, so a
/// report left empty only by jobs in progress says so, with "Include them"
/// and "Mark finished…" right there instead of "Nothing to report".
///
/// The jobs are marked sent only once the share sheet says the file went
/// somewhere (`ExtraWorkSending`); cancelling it leaves them as they were.
/// The picture is the PDF's report drawn for a chat, so sharing it marks
/// them sent as the PDF does. A CSV is data for an import rather than the
/// report, so sharing one marks nothing. Everything is written in the
/// export language set in Settings.
struct ExtraWorkReportScreen: View {
    let site: Site
    /// False on a site that is read-only (archived, or Pro lapsed): its jobs
    /// can be reported, not edited or ticked.
    var canEdit = true

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview

    @State private var choice: Choice = .notSent
    @State private var from: Date = Date()
    @State private var to: Date = Date()
    @State private var includeInProgress = false
    @State private var allJobs: [ExtraWorkJob] = []
    @State private var signature: ExtraWorkSignature?
    @State private var showsAllJobs = false
    /// The jobs in progress, opened in place under their line (or under an
    /// empty report's "Mark finished…").
    @State private var showsInProgress = false
    @State private var sheet: ReportSheet?
    @State private var preparing: ReportOutput?
    @State private var notice: String?
    @State private var failure: String?

    /// What the share bar can send: the three export formats, and the
    /// report as one tall picture for a chat (`ExtraWorkPictureRenderer`).
    private enum ReportOutput: Hashable {
        case pdf, picture, xlsx, csv

        /// A CSV is data, not the report the boss reads.
        var marksSent: Bool { self != .csv }
    }

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
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: site.name)
                            .font(.title2.weight(.bold))
                        Text(verbatim: summaryLine)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("extra-work-report-summary")
                    }
                    .padding(.leading, Metrics.tiny)

                    // An empty report held back by jobs in progress lists
                    // them itself, below; the line would say it twice.
                    if !jobsInProgress.isEmpty && !isHeldBackByJobsInProgress {
                        inProgressOnSiteSection
                    }

                    rangeSection

                    if report.isEmpty {
                        if isHeldBackByJobsInProgress {
                            heldBackSection
                        } else {
                            Text("Nothing to report for these dates.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(Metrics.large)
                                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                        }
                    } else {
                        if !report.done.isEmpty { doneSection }
                        if !report.inProgress.isEmpty { reportedInProgressSection }
                        materialSection
                        signatureSection
                        Text("Marked as sent after you share the PDF, the picture or the Excel file.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, Metrics.tiny)
                    }
                }
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.medium)
            }
            .background(Color.hoursCanvas)
            // On the scroll view alone, before the inset: set on a modifier
            // that wraps the share bar too, it is handed down to the bar's
            // buttons and replaces their own identifiers.
            .accessibilityIdentifier("screen-extra-work-report")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: Metrics.small) {
                    if let notice {
                        sentBanner(notice)
                    }
                    shareBar
                }
            }
            .navigationTitle("Extra-work report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // The report only shows and shares: Done, top right.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("extra-work-report-done")
                }
            }
            .onAppear(perform: load)
            .onChange(of: choice) { _, _ in showsAllJobs = false }
            // "Marked as sent: 3" is news, not a fixture: it goes after a
            // few seconds.
            .task(id: notice) {
                guard notice != nil else { return }
                try? await Task.sleep(for: .seconds(4))
                withAnimation(.easeOut(duration: 0.3)) { notice = nil }
            }
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

    // MARK: - Which jobs

    private var rangeSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
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

            Toggle("Include jobs still in progress", isOn: $includeInProgress)
                .frame(minHeight: 44)
                .padding(.horizontal, Metrics.large)
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                .accessibilityIdentifier("extra-work-report-include-in-progress")
        }
    }

    // MARK: - In progress

    /// The site's jobs not finished yet, whatever their date, as one line
    /// that opens in place to the list with checkmarks.
    private var inProgressOnSiteSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showsInProgress.toggle() }
            } label: {
                HStack(spacing: Metrics.small) {
                    Image(systemName: "hourglass")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.hoursNegative)
                        .accessibilityHidden(true)
                    Text(String(
                        inflected: "^[\(jobsInProgress.count) extra job](inflect: true) in progress · Mark finished"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(showsInProgress ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Metrics.large)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .accessibilityAddTraits(showsInProgress ? .isSelected : [])
            .accessibilityIdentifier("extra-work-report-in-progress-line")

            if showsInProgress {
                inProgressList(jobsInProgress)
                    .transition(.opacity)
            }
        }
    }

    /// A report left empty only because its jobs are in progress: how many,
    /// "Include them" (the switch above, turned on), and "Mark finished…",
    /// which lists them with their checkmarks.
    private var heldBackSection: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                Text(String(
                    inflected: "^[\(heldBack.count) extra job](inflect: true) still in progress"
                ))
                .font(.body.weight(.semibold))
                .accessibilityIdentifier("extra-work-report-held-back")
                Text("Finished jobs go in the extra-work report.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    withAnimation(.snappy(duration: 0.2)) { includeInProgress = true }
                } label: {
                    Text("Include them")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("extra-work-report-include-them")
                if canEdit {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) { showsInProgress = true }
                    } label: {
                        Text("Mark finished…")
                            .frame(maxWidth: .infinity, minHeight: 28)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(showsInProgress)
                    .accessibilityIdentifier("extra-work-report-mark-finished")
                }
            }
            .padding(Metrics.large)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

            if showsInProgress {
                inProgressList(heldBack)
                    .transition(.opacity)
            }
        }
    }

    /// Jobs in progress, each with its checkmark, and opening in the editor.
    private func inProgressList(_ jobs: [ExtraWorkJob]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                HStack(spacing: 0) {
                    ExtraWorkDoneButton(job: job, canEdit: canEdit) { toggleDone(job) }
                        .accessibilityIdentifier("extra-work-in-progress-tick-\(index)")
                        .padding(.leading, Metrics.small)
                    Button {
                        sheet = .job(job)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: title(of: job))
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Text(verbatim: jobDetail(job))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.leading, Metrics.small)
                        .padding(.trailing, Metrics.large)
                        .padding(.vertical, Metrics.small)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("extra-work-in-progress-\(index)")
                }
                if index < jobs.count - 1 {
                    Divider().padding(.leading, Metrics.large)
                }
            }
        }
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    // MARK: - Work done

    private static let collapsedCount = 3

    private var shownJobs: [ExtraWorkJob] {
        showsAllJobs ? report.done : Array(report.done.prefix(ExtraWorkReportScreen.collapsedCount))
    }

    private var hiddenCount: Int { report.done.count - shownJobs.count }

    private var doneSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            SectionHeading("Work done")
            VStack(spacing: 0) {
                ForEach(Array(shownJobs.enumerated()), id: \.element.id) { index, job in
                    Button {
                        sheet = .job(job)
                    } label: {
                        jobRow(job)
                    }
                    .buttonStyle(.plain)
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
        }
    }

    /// The jobs in progress the user chose to include: after the done ones,
    /// as the PDF has them.
    private var reportedInProgressSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            SectionHeading("Still in progress")
            VStack(spacing: 0) {
                ForEach(Array(report.inProgress.enumerated()), id: \.element.id) { index, job in
                    Button {
                        sheet = .job(job)
                    } label: {
                        jobRow(job)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("extra-work-report-in-progress-\(index)")
                    if index < report.inProgress.count - 1 {
                        Divider().padding(.leading, Metrics.large)
                    }
                }
            }
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
    }

    private func jobRow(_ job: ExtraWorkJob) -> some View {
        HStack(spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: title(of: job))
                    .font(.subheadline.weight(.semibold))
                    .multilineTextAlignment(.leading)
                Text(verbatim: jobDetail(job))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // A signature is shown when there is one, and nothing is said
            // when there is not: it is optional. Signed is the grey chip, as
            // on the site day, not a word in green.
            VStack(alignment: .trailing, spacing: Metrics.tiny) {
                if report.isConfirmed(job) {
                    ExtraWorkChipView(chip: .signed)
                }
                if job.chip == .sent {
                    ExtraWorkChipView(chip: .sent)
                }
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func title(of job: ExtraWorkJob) -> String {
        job.description.isEmpty ? String(localized: "Extra work") : job.description
    }

    /// "Thu 22 Oct · 1h · Marijo Mikša, Dusko Bajlović": the job's own time
    /// and who; nothing on this screen adds hours up across jobs.
    private func jobDetail(_ job: ExtraWorkJob) -> String {
        var parts = [settingsStore.dateFormatting.mediumDate(job.date)]
        let time = job.timeLine(settingsStore.settings.displayFormatting)
        if !time.isEmpty { parts.append(time) }
        return parts.joined(separator: " · ")
    }

    // MARK: - Material

    private var materialSection: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            SectionHeading("Material used")
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

    // MARK: - Client's signature

    private var signatureSection: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
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

    /// One button sends the report; the other formats are in a menu beside
    /// it, so the bar stays one row high over the jobs.
    private var shareBar: some View {
        HStack(spacing: Metrics.small) {
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

            Menu {
                // For a chat: an A4 PDF opens zoomed in and cut off there, a
                // picture opens full width.
                Button {
                    share(.picture)
                } label: {
                    Label("Send as picture", systemImage: "photo")
                }
                .accessibilityIdentifier("extra-work-send-picture")
                Button {
                    share(.xlsx)
                } label: {
                    Label {
                        Text(verbatim: ExportFormat.xlsx.title)
                    } icon: {
                        Image(systemName: "tablecells")
                    }
                }
                .accessibilityIdentifier("extra-work-report-share-xlsx")
                Button {
                    share(.csv)
                } label: {
                    Label {
                        Text(verbatim: ExportFormat.csv.title)
                    } icon: {
                        Image(systemName: "doc.plaintext")
                    }
                }
                .accessibilityIdentifier("extra-work-report-share-csv")
            } label: {
                Group {
                    if preparing != nil && preparing != .pdf {
                        ProgressView()
                    } else {
                        Image(systemName: "ellipsis.circle")
                            .font(.title2)
                    }
                }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .disabled(report.isEmpty || preparing != nil)
            .accessibilityLabel(String(localized: "More formats"))
            .accessibilityIdentifier("extra-work-report-more-formats")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(.bar)
    }

    /// "Marked as sent: 3", for a few seconds over the bar.
    private func sentBanner(_ text: String) -> some View {
        Label {
            Text(verbatim: text)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.hoursPositive)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(.regularMaterial, in: Capsule())
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("extra-work-report-notice")
    }

    private func share(_ output: ReportOutput) {
        let report = self.report
        guard !report.isEmpty else { return }
        preparing = output
        notice = nil
        let repository = ExtraWorkRepository(context: modelContext)
        // Every format gets the photo ids: the PDF and the picture draw them,
        // and the count is one of the tiles.
        let photoIDs = repository.photoIDs(siteID: site.id, jobIDs: Set(report.jobs.map(\.id)))
        let document = ExtraWorkDocumentBuilder(settings: settingsStore.settings, calendar: settingsStore.workCalendar)
            .make(report: report, siteName: site.name, photoIDs: photoIDs)

        Task { @MainActor in
            // A turn of the run loop, so the spinner shows before a PDF with
            // photos is drawn.
            await Task.yield()
            let data: Data
            let fileExtension: String
            switch output {
            case .pdf:
                data = ExtraWorkPDFRenderer.data(for: document, photos: smallPhotos(photoIDs, repository: repository))
                fileExtension = ExportFormat.pdf.fileExtension
            case .picture:
                let picture = ExtraWorkPictureRenderer.picture(for: document, photos: smallPhotos(photoIDs, repository: repository))
                data = picture.data
                fileExtension = picture.fileExtension
            case .xlsx:
                data = document.workbook(preferences: settingsStore.settings.export, generatedOn: Date())
                fileExtension = ExportFormat.xlsx.fileExtension
            case .csv:
                data = CSVExporter.data(for: document.linesTable(), preferences: settingsStore.settings.export)
                fileExtension = ExportFormat.csv.fileExtension
            }
            preparing = nil
            let url: URL
            do {
                url = try ExportFileFactory.write(data: data, fileExtension: fileExtension, baseName: document.fileName)
            } catch {
                failure = error.localizedDescription
                return
            }
            ShareSheetPresenter.present(url) { outcome in
                finishSharing(report, output: output, outcome: outcome)
                if outcome == .completed { ReviewPromptStore.askIfDue(requestReview) }
            }
        }
    }

    /// The photos as the PDF and the picture draw them: small JPEGs.
    private func smallPhotos(_ photoIDs: [UUID: [UUID]], repository: ExtraWorkRepository) -> [UUID: Data] {
        let stored = repository.photoData(ids: Set(photoIDs.values.flatMap { $0 }), siteID: site.id)
        return stored.compactMapValues { DiaryPhotoProcessor.thumbnailPrintJPEG(from: $0) }
    }

    /// The jobs become sent here and only here: after a PDF, the picture or
    /// a workbook was really shared, and only the jobs that were in it.
    private func finishSharing(_ report: ExtraWorkReport, output: ReportOutput, outcome: ExtraWorkShareOutcome) {
        guard output.marksSent, outcome == .completed else { return }
        let record = ExtraWorkReportRecord(
            siteID: site.id,
            sentAt: Date(),
            jobIDs: report.jobs.map(\.id),
            clientSignature: report.clientSignature
        )
        let marked = ExtraWorkSending.marked(report.jobs, after: outcome, reportID: record.id, at: record.sentAt)
        ExtraWorkRepository(context: modelContext).recordSent(record, jobs: marked)
        withAnimation(.snappy(duration: 0.25)) {
            notice = String(
                localized: "Marked as sent: \(marked.count)",
                comment: "Extra work report, after sharing; the value is how many jobs were marked sent"
            )
        }
        load()
        refreshUnsentWorkReminder()
    }

    /// The checkmark: written at once, not under the month lock.
    private func toggleDone(_ job: ExtraWorkJob) {
        guard canEdit else { return }
        ExtraWorkRepository(context: modelContext).storeProgress(of: job.togglingDone(at: Date()))
        load()
        refreshUnsentWorkReminder()
    }

    /// Sent, or finished: what the weekly "extra work not sent" note says,
    /// or whether there is one, has changed.
    private func refreshUnsentWorkReminder() {
        let context = modelContext
        let settings = settingsStore
        Task { await ExtraWorkReminderRefresher.refresh(context: context, settingsStore: settings) }
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
        let chosen = range.select(
            allJobs,
            siteID: site.id,
            today: CalendarDate.today(in: calendar),
            calendar: calendar,
            includeInProgress: includeInProgress
        )
        return ExtraWorkReport(siteID: site.id, jobs: chosen, clientSignature: signature)
    }

    /// The site's jobs not finished yet, whatever their date, oldest first.
    private var jobsInProgress: [ExtraWorkJob] {
        allJobs.filter { !$0.isDone }
    }

    /// The jobs in progress the chosen range leaves out while "Include jobs
    /// still in progress" is off.
    private var heldBack: [ExtraWorkJob] {
        guard !includeInProgress else { return [] }
        let calendar = settingsStore.workCalendar
        return range.leftInProgress(allJobs, siteID: site.id, today: CalendarDate.today(in: calendar), calendar: calendar)
    }

    /// Empty only because what it would carry is still in progress.
    private var isHeldBackByJobsInProgress: Bool {
        report.isEmpty && !heldBack.isEmpty
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

    private func load() {
        allJobs = ExtraWorkRepository(context: modelContext).jobs(siteID: site.id)
    }
}

/// A stored signature drawn back, on the white of paper, as mockup 15
/// shows it.
///
/// The pad stays light in Dark mode on purpose: it is the paper the
/// signature goes on, and dark ink is how it prints. A hairline border keeps
/// it from reading as a glaring box on a dark screen.
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
        .background(Color(white: 0.95), in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                .strokeBorder(Color.hoursHairline, lineWidth: 1)
        }
    }
}
