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

    private var duration: DurationFormatting {
        DurationFormatting.export(
            style: settings.export.durationStyle,
            decimalSeparator: settings.export.decimalSeparator.character
        )
    }

    private var formatting: CalendarFormatting {
        CalendarFormatting(locale: .current, calendar: calendar)
    }

    /// - Parameter countingThrough: the last day that counts towards the
    ///   totals. Every day in the range still gets a row; only the summary
    ///   block stops at this date, so exporting a month in progress does not
    ///   report a deficit for days that have not happened yet.
    func makeTable(
        days: [DayComputation],
        range: CalendarDateRange,
        title: String,
        openingBalanceMinutes: Int = 0,
        countingThrough: CalendarDate? = nil
    ) -> ReportTable {
        let columns = settings.effectiveExportColumns
        let included = settings.export.includeEmptyDays
            ? days
            : days.filter { $0.hasEntry || $0.workedMinutes > 0 || $0.creditedMinutes > 0 }

        var running = openingBalanceMinutes
        var rows: [ReportRow] = []
        rows.reserveCapacity(included.count)

        for day in included {
            let counts = day.isIncluded
                && !(countingThrough.map { day.date > $0 && !day.hasEntry } ?? false)
            if counts { running += day.balanceMinutes }
            rows.append(makeRow(day: day, columns: columns, runningBalance: running))
        }

        let summary = PeriodAggregator.summarize(days, range: range, countingThrough: countingThrough)

        return ReportTable(
            title: title,
            subtitle: subtitle(for: range),
            columns: columns,
            rows: rows,
            totals: makeTotals(summary: summary, runningBalance: running, openingBalance: openingBalanceMinutes)
        )
    }

    // MARK: - Rows

    private func makeRow(day: DayComputation, columns: [ReportColumn], runningBalance: Int) -> ReportRow {
        var values: [String] = []
        var numbers: [Double?] = []
        values.reserveCapacity(columns.count)
        numbers.reserveCapacity(columns.count)

        for column in columns {
            let cell = value(for: column, day: day, runningBalance: runningBalance)
            values.append(cell.text)
            numbers.append(cell.number)
        }

        return ReportRow(
            id: day.date.key,
            values: values,
            numbers: numbers,
            isWorkingDay: day.isScheduledWorkingDay,
            balanceMinutes: day.balanceMinutes,
            hasEntry: day.hasEntry
        )
    }

    private func value(for column: ReportColumn, day: DayComputation, runningBalance: Int) -> (text: String, number: Double?) {
        switch column {
        case .date:
            return (settings.export.dateStyle.string(for: day.date), nil)
        case .weekday:
            return (formatting.shortWeekdaySymbol(for: day.date.weekday(in: calendar)), nil)
        case .dayType:
            return (day.dayType.name, nil)
        case .start:
            guard let start = day.start else { return (emptyPlaceholder, nil) }
            return (settings.export.timeStyle.string(for: start), nil)
        case .end:
            guard let end = day.end else { return (emptyPlaceholder, nil) }
            let suffix = day.crossesMidnight ? " (+1)" : ""
            return (settings.export.timeStyle.string(for: end) + suffix, nil)
        case .breakTime:
            guard day.breakMinutes > 0 else { return (emptyPlaceholder, nil) }
            return (duration.string(day.breakMinutes), DurationFormatting.decimalHours(day.breakMinutes))
        case .worked:
            return (duration.string(day.workedMinutes), DurationFormatting.decimalHours(day.workedMinutes))
        case .credited:
            guard day.creditedMinutes > 0 else { return (emptyPlaceholder, nil) }
            return (duration.string(day.creditedMinutes), DurationFormatting.decimalHours(day.creditedMinutes))
        case .expected:
            return (duration.string(day.expectedMinutes), DurationFormatting.decimalHours(day.expectedMinutes))
        case .overtime:
            return (duration.string(day.overtimeMinutes), DurationFormatting.decimalHours(day.overtimeMinutes))
        case .balance:
            return (duration.signedString(day.balanceMinutes), DurationFormatting.decimalHours(day.balanceMinutes))
        case .cumulativeBalance:
            return (duration.signedString(runningBalance), DurationFormatting.decimalHours(runningBalance))
        case .holiday:
            return (day.holidayName ?? emptyPlaceholder, nil)
        case .location:
            return (day.location.isEmpty ? emptyPlaceholder : day.location, nil)
        case .tags:
            return (day.tags.isEmpty ? emptyPlaceholder : day.tags.joined(separator: ", "), nil)
        case .note:
            return (day.note.isEmpty ? emptyPlaceholder : day.note, nil)
        }
    }

    // MARK: - Totals

    private func makeTotals(summary: PeriodSummary, runningBalance: Int, openingBalance: Int) -> [ReportTotal] {
        var totals: [ReportTotal] = [
            ReportTotal(label: "Total worked", value: duration.string(summary.workedMinutes), isEmphasised: true)
        ]

        if summary.creditedMinutes > 0 {
            totals.append(ReportTotal(
                label: "Paid absence",
                value: duration.string(summary.creditedMinutes),
                isEmphasised: false
            ))
            totals.append(ReportTotal(
                label: "Total paid",
                value: duration.string(summary.paidMinutes),
                isEmphasised: false
            ))
        }

        if settings.features.trackExpectedHours {
            totals.append(ReportTotal(
                label: "Total expected",
                value: duration.string(summary.expectedMinutes),
                isEmphasised: true
            ))
        }

        if settings.features.showsBalance {
            totals.append(ReportTotal(
                label: "Balance",
                value: duration.signedString(summary.balanceMinutes),
                isEmphasised: true
            ))
            if summary.overtimeMinutes > 0 {
                totals.append(ReportTotal(label: "Overtime", value: duration.string(summary.overtimeMinutes), isEmphasised: false))
            }
            if summary.deficitMinutes > 0 {
                totals.append(ReportTotal(label: "Short", value: duration.string(summary.deficitMinutes), isEmphasised: false))
            }
            if openingBalance != 0 {
                totals.append(ReportTotal(
                    label: "Balance carried forward",
                    value: duration.signedString(runningBalance),
                    isEmphasised: false
                ))
            }
        }

        totals.append(ReportTotal(label: "Days worked", value: "\(summary.daysWorked)", isEmphasised: false))
        if settings.features.trackExpectedHours {
            totals.append(ReportTotal(label: "Scheduled working days", value: "\(summary.scheduledWorkingDays)", isEmphasised: false))
        }
        if summary.daysOff > 0 {
            totals.append(ReportTotal(label: "Days off", value: "\(summary.daysOff)", isEmphasised: false))
        }

        for definition in settings.dayTypeCatalog.all where definition.expectation == .creditedAbsence {
            let count = summary.count(of: definition.id)
            if count > 0 {
                totals.append(ReportTotal(label: definition.name, value: "\(count)", isEmphasised: false))
            }
        }

        if settings.features.trackBreaks && summary.breakMinutes > 0 {
            totals.append(ReportTotal(label: "Total breaks", value: duration.string(summary.breakMinutes), isEmphasised: false))
        }

        return totals
    }

    private func subtitle(for range: CalendarDateRange) -> String {
        let start = settings.export.dateStyle.string(for: range.start)
        let end = settings.export.dateStyle.string(for: range.end)
        return range.start == range.end ? start : "\(start) – \(end)"
    }
}
