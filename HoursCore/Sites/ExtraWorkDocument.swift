import Foundation

/// The extra-work report as the boss gets it — what is done, day by day with
/// its photos; then, if the user included them, the jobs still in progress;
/// then the material used, as a summary — every word the app writes already
/// in the export language. The PDF lays out these strings, the workbook
/// writes `jobsTable()` and `materialTable()`, the CSV `linesTable()`. What
/// the user typed — jobs, items, a typed unit, names — is passed through
/// untouched. It tells the boss what is done; it is not a bill: there is no
/// money anywhere in it, and no empty lines for anyone to sign on.
struct ExtraWorkDocument: Hashable, Sendable {
    struct MaterialRow: Hashable, Sendable {
        var name: String
        var quantity: String
        /// The same quantity as a number, for a workbook cell.
        var quantityValue: Double
        var unit: String
    }

    struct JobRow: Hashable, Sendable {
        var id: UUID
        var date: CalendarDate
        /// "Thu 22".
        var day: String
        /// The export's own way of writing a date, for the workbook and CSV.
        var dateText: String
        var description: String
        /// One line per item, "8 × Emergency light", "25 m Cable NYM 3×1.5":
        /// the PDF prints them one under another.
        var materialLines: [String]
        /// The same lines in one text, a line break between them, for the
        /// workbook's cell (which wraps).
        var material: String
        var items: [ExtraWorkItem]
        /// "3h · Ivan, Marko": how long the job took, then who was on it;
        /// empty when no time was noted.
        var hours: String
        /// How long the job took (`ExtraWorkJob.duration`), never a sum of
        /// everyone on it; `nil` when no time was noted.
        var minutes: Int?
        /// "Ivan, Marko": who was on it, for the workbook's and CSV's column.
        var people: String
        var photoIDs: [UUID]
        var isDone: Bool
        /// "Confirmed on site by Ing. M. Horvat, 22 Oct 2026" when the client
        /// signed the job; empty, and nothing printed, when they did not.
        var confirmation: String
        /// The same without its words, for the workbook's column:
        /// "Ing. M. Horvat, 22 Oct 2026".
        var confirmedBy: String
        /// The job's own signature, drawn beside its confirmation.
        var signature: ExtraWorkSignature?
    }

    var language: ExportLanguage
    /// The site's name: the headline.
    var title: String
    /// "Extra work done · 19 – 22 October 2026".
    var eyebrow: String
    /// The period alone, "19 – 22 October 2026".
    var period: String
    /// "Recorded by Marijo Mikša"; empty without a name in Settings.
    var byline: String
    var tiles: [ReportTile]

    /// "Work done, day by day": the finished jobs, newest day first.
    var jobsHeading: String
    var jobHeadings: [String]
    var jobs: [JobRow]
    /// "Still in progress": only there when the user included such jobs.
    var inProgressHeading: String
    var inProgressJobs: [JobRow]
    var hasHours: Bool

    var materialHeading: String
    var materialHeadings: [String]
    var material: [MaterialRow]

    var legend: String
    /// The client's signature under the whole report, drawn at its foot
    /// when there is one; nothing is drawn when there is not.
    var clientSignature: ExtraWorkSignature?
    /// "Confirmed on site by Ing. M. Horvat, 22 Oct 2026"; empty unsigned.
    var clientSignatureLabel: String

    /// "Extra work done — Trg Pravde Zagreb", for the file's metadata.
    var documentTitle: String
    /// "Trg Pravde Zagreb - Extra work done 2026-10-19 to 2026-10-22".
    var fileName: String

    var isEmpty: Bool { jobs.isEmpty && inProgressJobs.isEmpty }

    /// Done first, then those still in progress: the order of every table.
    var allJobs: [JobRow] { jobs + inProgressJobs }

    /// A column saying done or in progress, only when both are there.
    private var showsProgress: Bool { !inProgressJobs.isEmpty }
    /// A column of who confirmed what, only when somebody did.
    private var showsConfirmation: Bool { allJobs.contains { !$0.confirmedBy.isEmpty } }

    // MARK: - Tables

    private func table(columns: [ReportColumn], headings: [String], rows: [ReportRow]) -> ReportTable {
        var table = ReportTable(
            title: title,
            subtitle: period,
            language: language,
            columns: columns,
            rows: rows,
            totals: [],
            headingOverrides: headings
        )
        table.kind = .extraWork
        table.eyebrow = language(.extraWorkDone)
        table.detail = byline
        table.legend = legend
        return table
    }

    private func row(_ index: Int, values: [String], minutes: [Int?]? = nil, numbers: [Double?] = []) -> ReportRow {
        var row = ReportRow(
            id: index,
            values: values,
            minutes: minutes ?? Array(repeating: nil, count: values.count),
            isWorkingDay: true,
            balanceMinutes: 0,
            hasEntry: true
        )
        row.numbers = numbers
        return row
    }

    private func progressText(_ job: JobRow) -> String {
        job.isDone ? language(.progressDone) : language(.progressInProgress)
    }

    /// The trailing columns every job table shares: status, then who
    /// confirmed it, each only when it has something to say.
    private var trailingHeadings: [String] {
        (showsProgress ? [language(.progress)] : []) + (showsConfirmation ? [language(.confirmedOnSite)] : [])
    }

    private var trailingColumns: [ReportColumn] {
        Array(repeating: .note, count: trailingHeadings.count)
    }

    private func trailingValues(_ job: JobRow) -> [String] {
        (showsProgress ? [progressText(job)] : []) + (showsConfirmation ? [job.confirmedBy] : [])
    }

    /// The workbook's material sheet: a row per item and unit.
    func materialTable() -> ReportTable {
        let rows = material.enumerated().map { index, line in
            row(index, values: [line.name, line.quantity, line.unit], numbers: [nil, line.quantityValue, nil])
        }
        return table(columns: [.note, .note, .note], headings: materialHeadings, rows: rows)
    }

    /// The time columns, when any job has its time noted: how long the job
    /// took, then who was on it.
    private var timeHeadings: [String] {
        hasHours ? [language(.hours), language(ExtraWorkTerm.who)] : []
    }

    private var timeColumns: [ReportColumn] {
        hasHours ? [.worked, .note] : []
    }

    /// The workbook's first sheet: a row per job, done first; the job's time
    /// as a duration (how long it took, never added up), and who.
    func jobsTable() -> ReportTable {
        let headings = [language(.date), language(ExtraWorkTerm.job), language(.workAndMaterial)]
            + timeHeadings
            + trailingHeadings
        let columns: [ReportColumn] = [.date, .note, .note] + timeColumns + trailingColumns
        let rows = allJobs.enumerated().map { index, job -> ReportRow in
            var values = [job.dateText, job.description, job.material]
            var minutes: [Int?] = [nil, nil, nil]
            if hasHours {
                values += [durationText(job.minutes), job.people]
                minutes += [job.minutes, nil]
            }
            let trailing = trailingValues(job)
            values += trailing
            minutes += Array(repeating: nil, count: trailing.count)
            return row(index, values: values, minutes: minutes)
        }
        return table(columns: columns, headings: headings, rows: rows)
    }

    /// The CSV: one table, a line per item. A job's time and who was on it
    /// are on its first line only, so adding the column up does not count
    /// them twice.
    func linesTable() -> ReportTable {
        let headings = [language(.date), language(ExtraWorkTerm.job), language(.item), language(.quantity), language(.unit)]
            + timeHeadings
            + trailingHeadings
        let columns: [ReportColumn] = [.date, .note, .note, .note, .note] + timeColumns + trailingColumns
        var rows: [ReportRow] = []
        for job in allJobs {
            let lines: [ExtraWorkItem?] = job.items.isEmpty ? [nil] : job.items
            for (offset, item) in lines.enumerated() {
                var values = [
                    job.dateText,
                    job.description,
                    item?.name ?? "",
                    item.map { quantityText($0.quantity) } ?? "",
                    item.map { $0.unit.name(in: language) } ?? ""
                ]
                var minutes: [Int?] = [nil, nil, nil, nil, nil]
                if hasHours {
                    let first = offset == 0 && job.minutes != nil
                    values += [first ? durationText(job.minutes) : "", first ? job.people : ""]
                    minutes += [first ? job.minutes : nil, nil]
                }
                let trailing = trailingValues(job)
                values += trailing
                minutes += Array(repeating: nil, count: trailing.count)
                rows.append(row(rows.count, values: values, minutes: minutes))
            }
        }
        return table(columns: columns, headings: headings, rows: rows)
    }

    /// Both sheets, as one workbook: the jobs first, the material after.
    func workbook(preferences: ExportPreferences, generatedOn: Date? = nil) -> Data {
        XLSXWriter.data(
            sheets: [(language(.jobs), jobsTable()), (materialHeading, materialTable())],
            preferences: preferences,
            generatedOn: generatedOn
        )
    }

    // MARK: - Formatting kept with the document

    /// Set by the builder: how this export writes a duration and a decimal.
    var durationFormatting: DurationFormatting
    var decimalSeparator: String

    private func durationText(_ minutes: Int?) -> String {
        minutes.map { durationFormatting.string($0) } ?? ""
    }

    private func quantityText(_ quantity: Decimal) -> String {
        ExtraWorkQuantity.string(quantity, decimalSeparator: decimalSeparator)
    }
}

/// Builds an `ExtraWorkDocument` from a report, in the language and formats
/// set under Export in Settings.
struct ExtraWorkDocumentBuilder: Sendable {
    let settings: AppSettings
    let calendar: Calendar

    /// - Parameter photoIDs: each job's photos, in order, by job id. Their
    ///   bytes are the app's business.
    func make(report: ExtraWorkReport, siteName: String, photoIDs: [UUID: [UUID]] = [:]) -> ExtraWorkDocument {
        let language = settings.export.language
        let reportBuilder = ReportBuilder(settings: settings, calendar: calendar)
        let duration = reportBuilder.duration
        let decimal = settings.export.decimalSeparator.character
        let formatting = CalendarFormatting(locale: language.locale, calendar: calendar)
        let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)

        let period = report.period.map { periodText($0, language: language) } ?? ""
        let word = language(.extraWorkDone)

        let material = report.totals.map { total in
            ExtraWorkDocument.MaterialRow(
                name: total.name,
                quantity: ExtraWorkQuantity.string(total.quantity, decimalSeparator: decimal),
                quantityValue: ExtraWorkQuantity.double(total.quantity),
                unit: total.unit.name(in: language)
            )
        }

        func confirmedBy(_ signature: ExtraWorkSignature) -> (sentence: String, short: String) {
            let name = signature.signerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let day = formatting.dateWithYear(CalendarDate(signature.signedAt, calendar: calendar))
            if name.isEmpty { return ("\(language(.confirmedOnSite)), \(day)", day) }
            return ("\(language(.confirmedOnSiteBy)) \(name), \(day)", "\(name), \(day)")
        }

        func row(_ job: ExtraWorkJob) -> ExtraWorkDocument.JobRow {
            let cleaned = job.cleaned()
            let lines = cleaned.items.map { $0.line(in: language, decimalSeparator: decimal) }
            // The job's own signature; one under the report is drawn once,
            // at its foot, and its name goes in the workbook's column.
            let own = job.clientSignature.map(confirmedBy)
            let covering = report.clientSignature.map(confirmedBy)
            return ExtraWorkDocument.JobRow(
                id: job.id,
                date: job.date,
                day: dayText(job.date, language: language),
                dateText: settings.export.dateStyle.string(for: job.date),
                description: cleaned.description,
                materialLines: lines,
                material: lines.joined(separator: "\n"),
                items: cleaned.items,
                hours: cleaned.timeLine(duration),
                minutes: cleaned.hasHours ? cleaned.duration : nil,
                people: cleaned.people.joined(separator: ", "),
                photoIDs: photoIDs[job.id] ?? [],
                isDone: job.isDone,
                confirmation: own?.sentence ?? "",
                confirmedBy: own?.short ?? covering?.short ?? "",
                signature: job.clientSignature
            )
        }

        let done = report.done.map(row)
        let inProgress = report.inProgress.map(row)

        // Useful numbers only: what is done, what is not yet, what there is
        // to see. Never money, and no hours added up across jobs: each job
        // says how long it took.
        var tiles = [ReportTile(label: language(.jobsDone), value: "\(done.count)")]
        if !inProgress.isEmpty {
            tiles.append(ReportTile(label: language(.inProgress), value: "\(inProgress.count)"))
        }
        let photoCount = report.jobs.reduce(0) { $0 + (photoIDs[$1.id]?.count ?? 0) }
        if photoCount > 0 {
            tiles.append(ReportTile(label: language(.photos), value: "\(photoCount)"))
        }

        let fileName: String
        if let range = report.period {
            fileName = range.start == range.end
                ? "\(siteName) - \(word) \(range.start)"
                : "\(siteName) - \(word) \(range.start) to \(range.end)"
        } else {
            fileName = "\(siteName) - \(word)"
        }

        return ExtraWorkDocument(
            language: language,
            title: siteName,
            eyebrow: period.isEmpty ? word : "\(word) · \(period)",
            period: period,
            byline: owner.isEmpty ? "" : "\(language(.recordedBy)) \(owner)",
            tiles: tiles,
            jobsHeading: language(.workDoneDayByDay),
            jobHeadings: [language(.day), language(.workAndMaterial), language(.photos)],
            jobs: done,
            inProgressHeading: language(.stillInProgress),
            inProgressJobs: inProgress,
            hasHours: report.hasHours,
            materialHeading: language(.materialUsed),
            materialHeadings: [language(.item), language(.quantity), language(.unit)],
            material: material,
            legend: report.hasHours ? language(.legend) : language(.legendWithoutHours),
            clientSignature: report.clientSignature,
            clientSignatureLabel: report.clientSignature.map { confirmedBy($0).sentence } ?? "",
            documentTitle: "\(word) — \(siteName)",
            fileName: fileName,
            durationFormatting: duration,
            decimalSeparator: decimal
        )
    }

    // MARK: - Dates

    private func formatter(_ template: String, language: ExportLanguage) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter
    }

    /// "19 – 22 October 2026", "28 September – 3 October 2026", or with both
    /// years when the report spans New Year.
    private func periodText(_ range: CalendarDateRange, language: ExportLanguage) -> String {
        let full = formatter("dMMMMy", language: language)
        let end = full.string(from: range.end.date(in: calendar))
        guard range.start != range.end else { return end }
        let startTemplate: String
        if range.start.year != range.end.year {
            startTemplate = "dMMMMy"
        } else if range.start.month != range.end.month {
            startTemplate = "dMMMM"
        } else {
            startTemplate = "d"
        }
        var start = formatter(startTemplate, language: language).string(from: range.start.date(in: calendar))
        // A day alone can lose the full stop German writes after it
        // ("19. – 22. Oktober"); the full date shows whether the language has
        // one. Croatian and Slovenian already keep it on the day alone, so it
        // is added only when missing — never "19.. – 22."
        if startTemplate == "d", end.hasPrefix("\(range.end.day)."), !start.hasSuffix(".") {
            start += "."
        }
        return "\(start) – \(end)"
    }

    /// "Thu 22": the page is headed by the period, so the month goes
    /// without saying on every line.
    private func dayText(_ date: CalendarDate, language: ExportLanguage) -> String {
        formatter("EEEd", language: language).string(from: date.date(in: calendar))
    }
}
