import Foundation

/// Turns computed days into a report.
///
/// Formatting happens exactly once, here, using the user's export preferences,
/// so no renderer has to know anything about dates, durations or separators.
struct ReportBuilder: Sendable {
    let settings: AppSettings
    let calendar: Calendar
    /// What to write where there is no value. Files want an empty cell; the
    /// on-screen preview and the PDF want a dash.
    let emptyPlaceholder: String

    init(settings: AppSettings, calendar: Calendar, emptyPlaceholder: String = "") {
        self.settings = settings
        self.calendar = calendar
        self.emptyPlaceholder = emptyPlaceholder
    }

    /// The language the file is written in, and the only thing in the
    /// builder that decides which words come out.
    private var language: ExportLanguage { settings.export.language }

    var duration: DurationFormatting {
        DurationFormatting.export(
            style: settings.export.durationStyle,
            decimalSeparator: settings.export.decimalSeparator.character
        )
    }

    /// Months and weekdays come from the export language rather than the
    /// phone, so a German timesheet says Montag even on an English handset.
    private var formatting: CalendarFormatting {
        CalendarFormatting(locale: language.locale, calendar: calendar)
    }

    /// - Parameter period: the range in words — "August 2026" — for the line
    ///   under a name on the printed page. The title says it already, so it
    ///   is only printed when the name has taken the title's place.
    /// - Parameter countingThrough: the last day that counts towards the
    ///   totals. Every day in the range still gets a row; only the summary
    ///   block stops at this date, so exporting a month in progress does not
    ///   report a deficit for days that have not happened yet.
    func makeTable(
        days: [DayComputation],
        range: CalendarDateRange,
        title: String,
        period: String = "",
        openingBalanceMinutes: Int = 0,
        countingThrough: CalendarDate? = nil
    ) -> ReportTable {
        let columns = settings.effectiveExportColumns
        func isShown(_ day: DayComputation) -> Bool {
            settings.export.includeEmptyDays || day.hasEntry || day.workedMinutes > 0 || day.creditedMinutes > 0
        }

        var running = openingBalanceMinutes
        var rows: [ReportRow] = []
        rows.reserveCapacity(days.count)

        // The running balance walks every day, shown or not. Leaving empty
        // days out of the file hides their rows, not their hours: a working
        // day nobody recorded is still short in the summary's balance, and
        // skipping it here left the running column and the "carried forward"
        // made from it disagreeing with that balance by a day's hours apiece.
        for day in days {
            if day.counts(through: countingThrough) { running += day.balanceMinutes }
            guard isShown(day) else { continue }
            rows.append(makeRow(day: day, columns: columns, runningBalance: running))
        }

        let summary = PeriodAggregator.summarize(days, range: range, countingThrough: countingThrough)
        let owner = settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
        let dates = subtitle(for: range)

        var table = ReportTable(
            title: title,
            subtitle: dates,
            ownerName: owner,
            language: language,
            columns: columns,
            rows: rows,
            totals: makeTotals(summary: summary, runningBalance: running, openingBalance: openingBalanceMinutes)
        )
        table.kind = .timesheet
        table.eyebrow = language(.timesheet)
        if !owner.isEmpty && !period.isEmpty {
            table.detail = "\(period) · \(dates)"
        }
        table.tiles = makeTiles(summary: summary)
        table.totalRow = makeTotalRow(columns: columns, summary: summary, runningBalance: running)
        table.signatures = [language(.employeeSignature), language(.employerSignature)]
        return table
    }

    // MARK: - Rows

    private func makeRow(day: DayComputation, columns: [ReportColumn], runningBalance: Int) -> ReportRow {
        var values: [String] = []
        var minutes: [Int?] = []
        values.reserveCapacity(columns.count)
        minutes.reserveCapacity(columns.count)

        for column in columns {
            let cell = value(for: column, day: day, runningBalance: runningBalance)
            values.append(cell.text)
            minutes.append(cell.minutes)
        }

        return ReportRow(
            id: day.date.key,
            values: values,
            minutes: minutes,
            isWorkingDay: day.isScheduledWorkingDay,
            balanceMinutes: day.balanceMinutes,
            hasEntry: day.hasEntry,
            isAbsence: isAbsence(day)
        )
    }

    /// Paid absence, and public holidays whether or not they are credited:
    /// both are days somebody was entitled to be away, which is not what a
    /// weekend is.
    private func isAbsence(_ day: DayComputation) -> Bool {
        day.dayType.expectation == .creditedAbsence || day.dayType.id == .holiday
    }

    private func value(for column: ReportColumn, day: DayComputation, runningBalance: Int) -> (text: String, minutes: Int?) {
        switch column {
        case .date:
            return (settings.export.dateStyle.string(for: day.date), nil)
        case .weekday:
            return (formatting.shortWeekdaySymbol(for: day.date.weekday(in: calendar)), nil)
        case .dayType:
            return (day.dayType.exportName(in: language), nil)
        case .job:
            let names = day.shifts
                .map { settings.job($0.jobID).name }
                .reduce(into: [String]()) { unique, name in
                    if !unique.contains(name) { unique.append(name) }
                }
            return (names.isEmpty ? emptyPlaceholder : names.joined(separator: ", "), nil)
        case .start:
            return (startText(day.start), nil)
        case .end:
            return (endText(day.end, crossesMidnight: day.crossesMidnight), nil)
        case .breakTime:
            guard day.breakMinutes > 0 else { return (emptyPlaceholder, nil) }
            return (duration.string(day.breakMinutes), day.breakMinutes)
        case .worked:
            return (duration.string(day.workedMinutes), day.workedMinutes)
        case .credited:
            guard day.creditedMinutes > 0 else { return (emptyPlaceholder, nil) }
            return (duration.string(day.creditedMinutes), day.creditedMinutes)
        case .expected:
            return (duration.string(day.expectedMinutes), day.expectedMinutes)
        case .overtime:
            return (duration.string(day.overtimeMinutes), day.overtimeMinutes)
        case .balance:
            return (duration.signedString(day.balanceMinutes), day.balanceMinutes)
        case .cumulativeBalance:
            return (duration.signedString(runningBalance), runningBalance)
        case .holiday:
            return (day.holidayName ?? emptyPlaceholder, nil)
        case .location:
            return (day.location.isEmpty ? emptyPlaceholder : day.location, nil)
        case .tags:
            return (day.tags.isEmpty ? emptyPlaceholder : day.tags.joined(separator: ", "), nil)
        case .note:
            return (day.note.isEmpty ? emptyPlaceholder : day.note, nil)
        case .times:
            guard day.start != nil || day.end != nil else { return (emptyPlaceholder, nil) }
            return (timesText(start: day.start, end: day.end, crossesMidnight: day.crossesMidnight), nil)
        }
    }

    /// "07:00–16:00", for a cell that holds both ends of a day.
    func timesText(start: TimeOfDay?, end: TimeOfDay?, crossesMidnight: Bool) -> String {
        "\(startText(start))–\(endText(end, crossesMidnight: crossesMidnight))"
    }

    /// How a start time is written, shared with the director's sheet so the
    /// two can never format the same clock time differently.
    func startText(_ start: TimeOfDay?) -> String {
        guard let start else { return emptyPlaceholder }
        return settings.export.timeStyle.string(for: start)
    }

    func endText(_ end: TimeOfDay?, crossesMidnight: Bool) -> String {
        guard let end else { return emptyPlaceholder }
        return settings.export.timeStyle.string(for: end) + (crossesMidnight ? " (+1)" : "")
    }

    // MARK: - The printed page's figures

    /// The boxes at the top of the page: what was worked, what was owed, the
    /// difference, and on how many days. A figure the person does not track
    /// has no box, rather than a zero that means nothing.
    private func makeTiles(summary: PeriodSummary) -> [ReportTile] {
        var tiles = [ReportTile(label: language(.worked), value: duration.string(summary.workedMinutes))]
        if settings.features.trackExpectedHours {
            tiles.append(ReportTile(label: language(.expected), value: duration.string(summary.expectedMinutes)))
        }
        if settings.features.showsBalance {
            tiles.append(ReportTile(
                label: language(.balance),
                value: duration.signedString(summary.balanceMinutes),
                isNegative: summary.balanceMinutes < 0
            ))
        }
        tiles.append(ReportTile(label: language(.daysWorked), value: "\(summary.daysWorked)"))
        return tiles
    }

    /// The ruled total under the days.
    ///
    /// Made from the summary rather than by adding up the column, so it says
    /// what the tiles and the summary say. The two differ on a month still in
    /// progress: the rows include days not yet reached, with their expected
    /// hours, and a total that counted those would report a deficit for days
    /// that have not happened — the thing `countingThrough` exists to stop.
    private func makeTotalRow(columns: [ReportColumn], summary: PeriodSummary, runningBalance: Int) -> ReportRow {
        var values: [String] = []
        var minutes: [Int?] = []
        for column in columns {
            let figure: (text: String, minutes: Int)?
            switch column {
            case .breakTime: figure = (duration.string(summary.breakMinutes), summary.breakMinutes)
            case .worked: figure = (duration.string(summary.workedMinutes), summary.workedMinutes)
            case .credited: figure = (duration.string(summary.creditedMinutes), summary.creditedMinutes)
            case .expected: figure = (duration.string(summary.expectedMinutes), summary.expectedMinutes)
            case .overtime: figure = (duration.string(summary.overtimeMinutes), summary.overtimeMinutes)
            case .balance: figure = (duration.signedString(summary.balanceMinutes), summary.balanceMinutes)
            case .cumulativeBalance: figure = (duration.signedString(runningBalance), runningBalance)
            default: figure = nil
            }
            values.append(figure?.text ?? "")
            minutes.append(figure?.minutes)
        }
        // The label goes in the first column, unless the person put a figure
        // there — a total is worth more than the word for it.
        if !values.isEmpty, minutes[0] == nil {
            values[0] = language(.total)
        }
        // Id -1 cannot collide with a date key.
        return ReportRow(
            id: -1,
            values: values,
            minutes: minutes,
            isWorkingDay: true,
            balanceMinutes: summary.balanceMinutes,
            hasEntry: true,
            role: .total
        )
    }

    // MARK: - Totals

    private func makeTotals(summary: PeriodSummary, runningBalance: Int, openingBalance: Int) -> [ReportTotal] {
        var totals: [ReportTotal] = [
            ReportTotal(label: language(.totalWorked), value: duration.string(summary.workedMinutes), isEmphasised: true, minutes: summary.workedMinutes)
        ]

        if summary.creditedMinutes > 0 {
            totals.append(ReportTotal(
                label: language(.paidAbsence),
                value: duration.string(summary.creditedMinutes),
                isEmphasised: false,
                minutes: summary.creditedMinutes
            ))
            totals.append(ReportTotal(
                label: language(.totalPaid),
                value: duration.string(summary.paidMinutes),
                isEmphasised: false,
                minutes: summary.paidMinutes
            ))
        }

        if settings.features.trackExpectedHours {
            totals.append(ReportTotal(
                label: language(.totalExpected),
                value: duration.string(summary.expectedMinutes),
                isEmphasised: true,
                minutes: summary.expectedMinutes
            ))
        }

        if settings.features.showsBalance {
            totals.append(ReportTotal(
                label: language(.balance),
                value: duration.signedString(summary.balanceMinutes),
                isEmphasised: true,
                minutes: summary.balanceMinutes
            ))
            if summary.overtimeMinutes > 0 {
                totals.append(ReportTotal(label: language(.overtime), value: duration.string(summary.overtimeMinutes), isEmphasised: false, minutes: summary.overtimeMinutes))
            }
            if summary.deficitMinutes > 0 {
                totals.append(ReportTotal(label: language(.short), value: duration.string(summary.deficitMinutes), isEmphasised: false, minutes: summary.deficitMinutes))
            }
            if openingBalance != 0 {
                totals.append(ReportTotal(
                    label: language(.carriedForward),
                    value: duration.signedString(runningBalance),
                    isEmphasised: false,
                    minutes: runningBalance
                ))
            }
        }

        // Named separately so a reader can see where the balance went. Payouts
        // and time off in lieu are the two ways overtime leaves without being
        // un-worked, and a bare negative correction explains neither.
        for reason in AdjustmentReason.allCases where reason != .correction {
            let minutes = summary.adjustment(for: reason)
            if minutes != 0 {
                totals.append(ReportTotal(
                    label: reason.label(in: language),
                    value: duration.signedString(minutes),
                    isEmphasised: false,
                    minutes: minutes
                ))
            }
        }

        totals.append(ReportTotal(label: language(.daysWorked), value: "\(summary.daysWorked)", isEmphasised: false, count: summary.daysWorked))
        if settings.features.trackExpectedHours {
            totals.append(ReportTotal(label: language(.scheduledDays), value: "\(summary.scheduledWorkingDays)", isEmphasised: false, count: summary.scheduledWorkingDays))
        }
        if summary.daysOff > 0 {
            totals.append(ReportTotal(label: language(.daysOff), value: "\(summary.daysOff)", isEmphasised: false, count: summary.daysOff))
        }

        for definition in settings.dayTypeCatalog.all where definition.expectation == .creditedAbsence {
            let count = summary.count(of: definition.id)
            if count > 0 {
                totals.append(ReportTotal(label: definition.exportName(in: language), value: "\(count)", isEmphasised: false, count: count))
            }
        }

        if settings.features.trackBreaks && summary.breakMinutes > 0 {
            totals.append(ReportTotal(label: language(.totalBreaks), value: duration.string(summary.breakMinutes), isEmphasised: false, minutes: summary.breakMinutes))
        }

        return totals
    }

    func subtitle(for range: CalendarDateRange) -> String {
        let start = settings.export.dateStyle.string(for: range.start)
        let end = settings.export.dateStyle.string(for: range.end)
        return range.start == range.end ? start : "\(start) – \(end)"
    }
}
