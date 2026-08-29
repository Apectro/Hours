import SwiftUI
import SwiftData

/// The running balance, from the opening figure to a given day.
///
/// Always recomputed from the days themselves, never stored, so correcting a
/// day recorded months ago fixes this number too.
struct CumulativeBalanceCard: View {
    let through: CalendarDate
    let settings: AppSettings
    let calendar: Calendar

    @Query private var entries: [DayEntry]
    @Query private var holidayRecords: [HolidayRecord]

    init(through: CalendarDate, settings: AppSettings, calendar: Calendar) {
        self.through = through
        self.settings = settings
        self.calendar = calendar
        let upper = through.key
        _entries = Query(
            filter: #Predicate<DayEntry> { $0.dateKey <= upper },
            sort: \DayEntry.dateKey
        )
        _holidayRecords = Query(sort: \HolidayRecord.name)
    }

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.small) {
                Text("Running balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)

                BalanceText(
                    minutes: balance,
                    formatting: settings.displayFormatting,
                    font: .hoursFigure(.largeTitle)
                )

                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var balance: Int {
        guard let first = entries.first, let firstDate = CalendarDate(key: first.dateKey) else {
            return settings.openingBalanceMinutes
        }
        let start = settings.balanceStartDate.map { max($0, firstDate) } ?? firstDate
        guard start <= through else { return settings.openingBalanceMinutes }

        let engine = PeriodEngine(settings: settings, calendar: calendar)
        var records: [Int: DayRecord] = [:]
        for entry in entries { records[entry.dateKey] = entry.record }

        let days = engine.days(
            in: CalendarDateRange(start: start, end: through),
            records: records,
            holidays: holidayRecords.map(\.rule)
        )
        return BalanceLedger.cumulative(
            over: days,
            openingMinutes: settings.openingBalanceMinutes,
            startDate: settings.balanceStartDate,
            countingThrough: CalendarDate.today(in: calendar)
        )
    }

    private var caption: String {
        let formatting = CalendarFormatting(locale: .current, calendar: calendar)
        if let start = settings.balanceStartDate {
            return String(
                localized: "Since \(formatting.mediumDate(start)), through \(formatting.mediumDate(through)).",
                comment: "What span the running balance covers"
            )
        }
        return String(
                localized: "Everything recorded through \(formatting.mediumDate(through)).",
                comment: "The running balance covers everything up to this date"
            )
    }
}
