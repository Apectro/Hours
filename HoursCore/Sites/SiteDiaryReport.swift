import Foundation

/// Where a diary photo sits, without its bytes: enough to place it in a
/// report, which the app then fills from the store.
struct DiaryPhotoReference: Hashable, Sendable {
    var id: UUID
    var date: CalendarDate
    var sortOrder: Int
}

extension DiaryPhoto {
    var reference: DiaryPhotoReference {
        DiaryPhotoReference(id: id, date: date, sortOrder: sortOrder)
    }
}

/// One day of the diary as the director's PDF prints it.
struct SiteDiaryBlock: Hashable, Sendable {
    struct Line: Hashable, Sendable {
        var label: String
        var text: String
    }

    var date: CalendarDate
    /// "Tuesday, 4 August 2026".
    var heading: String
    /// "Rain · 7 °C · Bad weather"; empty when none of it was recorded.
    var weatherLine: String
    /// Only the texts that were written, each under its label.
    var lines: [Line]
    /// In the order they were added.
    var photoIDs: [UUID]
}

/// The diary pages that follow a site's hours on the director's sheet.
///
/// Built in the engine, translated in the export's language, so the PDF only
/// has to lay out text it is handed and the photos it looks up by id.
struct SiteDiaryReport: Hashable, Sendable {
    /// "Site diary" in the export's language.
    var title: String
    var blocks: [SiteDiaryBlock]
    /// The words for the workbook's columns, in the export's language.
    var headings: [String]

    var isEmpty: Bool { blocks.isEmpty }

    /// The diary as a table, for the workbook's second sheet: a row per day
    /// and a column per text. Photos stay in the PDF.
    func table(language: ExportLanguage) -> ReportTable {
        let rows = blocks.enumerated().map { index, block -> ReportRow in
            var values = [block.heading, block.weatherLine]
            for label in headings.dropFirst(2) {
                values.append(block.lines.first { $0.label == label }?.text ?? "")
            }
            return ReportRow(
                id: index,
                values: values,
                minutes: Array(repeating: nil, count: values.count),
                isWorkingDay: true,
                balanceMinutes: 0,
                hasEntry: true
            )
        }
        var table = ReportTable(
            title: title,
            subtitle: "",
            language: language,
            columns: [.date] + Array(repeating: ReportColumn.note, count: max(0, headings.count - 1)),
            rows: rows,
            totals: [],
            headingOverrides: headings
        )
        table.kind = .siteDiary
        return table
    }
}

/// Turns a month's diaries into a `SiteDiaryReport`.
struct SiteDiaryReportBuilder: Sendable {
    let settings: AppSettings
    let calendar: Calendar

    /// - Parameters:
    ///   - photos: where each photo of the site sits; their bytes are not needed.
    ///   - badWeatherStops: the dates the site day was rained off, which the
    ///     block names beside the weather.
    func make(
        diaries: [SiteDiary],
        photos: [DiaryPhotoReference],
        badWeatherStops: Set<CalendarDate>,
        range: CalendarDateRange
    ) -> SiteDiaryReport {
        let language = settings.export.language
        let formatting = CalendarFormatting(locale: language.locale, calendar: calendar)

        // Sync can deliver the same diary twice; the first one wins, as for site days.
        var byDate: [CalendarDate: SiteDiary] = [:]
        for diary in diaries where range.contains(diary.date) && !diary.isBlank && byDate[diary.date] == nil {
            byDate[diary.date] = diary
        }
        var photosByDate: [CalendarDate: [DiaryPhotoReference]] = [:]
        for photo in photos where range.contains(photo.date) {
            photosByDate[photo.date, default: []].append(photo)
        }

        let dates = Set(byDate.keys).union(photosByDate.keys).sorted()
        let blocks = dates.map { date -> SiteDiaryBlock in
            let diary = byDate[date]
            var weather: [String] = []
            if let kind = diary?.weather { weather.append(language(kind.term)) }
            if let degrees = diary?.temperatureCelsius { weather.append("\(degrees) °C") }
            if badWeatherStops.contains(date) { weather.append(language(.badWeather)) }

            let lines = (diary?.texts ?? []).compactMap { entry -> SiteDiaryBlock.Line? in
                let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
                return text.isEmpty ? nil : SiteDiaryBlock.Line(label: language(entry.term), text: text)
            }
            let photoIDs = (photosByDate[date] ?? [])
                .sorted { $0.sortOrder != $1.sortOrder ? $0.sortOrder < $1.sortOrder : $0.id.uuidString < $1.id.uuidString }
                .map(\.id)

            return SiteDiaryBlock(
                date: date,
                heading: formatting.fullDate(date),
                weatherLine: weather.joined(separator: " · "),
                lines: lines,
                photoIDs: photoIDs
            )
        }

        return SiteDiaryReport(
            title: language(.siteDiary),
            blocks: blocks,
            headings: [language(.day), language(.weather)]
                + SiteDiary(siteID: UUID(), date: range.start).texts.map { language($0.term) }
        )
    }
}
