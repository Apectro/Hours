import Foundation

/// The extra-work report as the boss gets it, every word the app writes
/// already in the export language: the PDF lays out these strings, the
/// workbook writes `materialTable()` and `jobsTable()`, the CSV
/// `linesTable()`. What the user typed — jobs, items, a typed unit, names —
/// is passed through untouched, and there is no money anywhere in it.
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
        /// "8 × Emergency light · 25 m Cable NYM 3×1.5".
        var material: String
        var items: [ExtraWorkItem]
        /// "Ivan 3h · Marko 3h"; empty when no hours were noted.
        var hours: String
        var minutes: Int?
        var photoIDs: [UUID]
        /// "signed" or "open".
        var client: String
        /// Drawn plain when signed for, in the accent colour when not.
        var isConfirmed: Bool
    }

    var language: ExportLanguage
    /// The site's name: the headline.
    var title: String
    /// "Extra work · 19 – 22 October 2026".
    var eyebrow: String
    /// The period alone, "19 – 22 October 2026".
    var period: String
    /// "Recorded by Marijo Mikša · Extra work report".
    var byline: String
    var tiles: [ReportTile]

    var materialHeading: String
    var materialHeadings: [String]
    var material: [MaterialRow]

    var jobsHeading: String
    var jobHeadings: [String]
    var jobs: [JobRow]
    var hasHours: Bool

    var legend: String
    /// The client's signature under the whole report, drawn in the footer.
    var clientSignature: ExtraWorkSignature?
    /// "Client · Ing. M. Horvat · 22 Oct 2026", under that signature.
    var clientSignatureLabel: String
    /// Labels under the empty lines left to sign on.
    var signatureLines: [String]

    /// "Extra work report — Trg Pravde Zagreb", for the file's metadata.
    var documentTitle: String
    /// "Trg Pravde Zagreb - Extra work 2026-10-19 to 2026-10-22".
    var fileName: String

    var isEmpty: Bool { jobs.isEmpty }

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
        table.eyebrow = language(.extraWork)
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

    /// The workbook's first sheet: a row per item and unit.
    func materialTable() -> ReportTable {
        let rows = material.enumerated().map { index, line in
            row(index, values: [line.name, line.quantity, line.unit], numbers: [nil, line.quantityValue, nil])
        }
        return table(columns: [.note, .note, .note], headings: materialHeadings, rows: rows)
    }

    /// The workbook's second sheet: a row per job, hours as durations.
    func jobsTable() -> ReportTable {
        let headings = [language(.date), language(ExtraWorkTerm.job), language(ExtraWorkTerm.workAndMaterial)]
            + (hasHours ? [language(.hours)] : [])
            + [language(.client)]
        let columns: [ReportColumn] = [.date, .note, .note] + (hasHours ? [.worked] : []) + [.note]
        let rows = jobs.enumerated().map { index, job -> ReportRow in
            var values = [job.dateText, job.description, job.material]
            var minutes: [Int?] = [nil, nil, nil]
            if hasHours {
                values.append(job.hours.isEmpty ? "" : durationText(job.minutes))
                minutes.append(job.minutes)
            }
            values.append(job.client)
            minutes.append(nil)
            return row(index, values: values, minutes: minutes)
        }
        return table(columns: columns, headings: headings, rows: rows)
    }

    /// The CSV: one table, a line per item. A job's hours are on its first
    /// line only, so adding the column up does not count them twice.
    func linesTable() -> ReportTable {
        let headings = [language(.date), language(ExtraWorkTerm.job), language(.item), language(.quantity), language(.unit)]
            + (hasHours ? [language(.hours)] : [])
            + [language(.client)]
        let columns: [ReportColumn] = [.date, .note, .note, .note, .note] + (hasHours ? [.worked] : []) + [.note]
        var rows: [ReportRow] = []
        for job in jobs {
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
                    values.append(first ? durationText(job.minutes) : "")
                    minutes.append(first ? job.minutes : nil)
                }
                values.append(job.client)
                minutes.append(nil)
                rows.append(row(rows.count, values: values, minutes: minutes))
            }
        }
        return table(columns: columns, headings: headings, rows: rows)
    }

    /// Both sheets, as one workbook.
    func workbook(preferences: ExportPreferences, generatedOn: Date? = nil) -> Data {
        XLSXWriter.data(
            sheets: [(materialHeading, materialTable()), (language(.jobs), jobsTable())],
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
        let reportTitle = language(.extraWorkReport)

        let material = report.totals.map { total in
            ExtraWorkDocument.MaterialRow(
                name: total.name,
                quantity: ExtraWorkQuantity.string(total.quantity, decimalSeparator: decimal),
                quantityValue: ExtraWorkQuantity.double(total.quantity),
                unit: total.unit.name(in: language)
            )
        }

        let jobs = report.jobs.map { job -> ExtraWorkDocument.JobRow in
            let cleaned = job.cleaned()
            let confirmed = report.isConfirmed(job)
            let hours = cleaned.hours.map { "\($0.name) \(duration.string($0.minutes))" }.joined(separator: " · ")
            return ExtraWorkDocument.JobRow(
                id: job.id,
                date: job.date,
                day: dayText(job.date, language: language),
                dateText: settings.export.dateStyle.string(for: job.date),
                description: cleaned.description,
                material: cleaned.items.map { $0.line(in: language, decimalSeparator: decimal) }.joined(separator: " · "),
                items: cleaned.items,
                hours: hours,
                minutes: cleaned.hasHours ? cleaned.totalMinutes : nil,
                photoIDs: photoIDs[job.id] ?? [],
                client: confirmed ? language(.confirmed) : language(.notConfirmed),
                isConfirmed: confirmed
            )
        }

        var tiles = [
            ReportTile(label: language(.jobs), value: "\(report.jobs.count)"),
            ReportTile(label: language(.items), value: "\(report.totals.count)"),
            ReportTile(
                label: language(.clientSigned),
                value: "\(report.confirmedCount) \(language(.of)) \(report.jobs.count)"
            )
        ]
        // Hours only where some were noted: most extra work bills material.
        if report.hasHours {
            tiles.append(ReportTile(label: language(.hours), value: duration.string(report.totalMinutes)))
        }

        var clientLabel = ""
        var lines: [String] = []
        if let signature = report.clientSignature {
            let signedOn = CalendarDate(signature.signedAt, calendar: calendar)
            clientLabel = [language(.client), signature.signerName.trimmingCharacters(in: .whitespacesAndNewlines),
                           formatting.dateWithYear(signedOn)]
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
        } else {
            lines.append(language(.clientSignatureLine))
        }
        lines.append(language(.supervisorSignature))

        let recorded = owner.isEmpty ? [] : ["\(language(.recordedBy)) \(owner)"]
        let word = language(.extraWork)
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
            byline: (recorded + [reportTitle]).joined(separator: " · "),
            tiles: tiles,
            materialHeading: language(.materialInTotal),
            materialHeadings: [language(.item), language(.quantity), language(.unit)],
            material: material,
            jobsHeading: language(.jobsDayByDay),
            jobHeadings: [language(.day), language(.workAndMaterial), language(.photos), language(.client)],
            jobs: jobs,
            hasHours: report.hasHours,
            legend: report.hasHours ? language(.legend) : language(.legendWithoutHours),
            clientSignature: report.clientSignature,
            clientSignatureLabel: clientLabel,
            signatureLines: lines,
            documentTitle: "\(reportTitle) — \(siteName)",
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
        // A day alone loses the full stop German, Croatian and Slovenian
        // write after it ("19. – 22. Oktober"); the full date shows whether
        // the language has one.
        if startTemplate == "d", end.hasPrefix("\(range.end.day).") {
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
