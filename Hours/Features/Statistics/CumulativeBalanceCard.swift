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
    @Environment(\.modelContext) private var modelContext

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
        // A closed year behaves exactly as the opening balance always did: a
        // figure, and a date before which days do not count. So carry-over
        // arrives here as a different origin rather than as a second concept.
        //
        // The engine's `runningBalance` is the one rule for this, shared with
        // the export and with closing a year, so the three cannot drift apart.
        var records: [Int: DayRecord] = [:]
        for entry in entries { records[entry.dateKey] = entry.record }

        // The first recorded day from the store rather than from `entries`,
        // which holds only calendar days: a site day written before any of
        // them is where everything else starts the balance, so it starts here.
        return PeriodEngine(
            settings: settings,
            calendar: calendar,
            firstRecorded: WorkdayRepository(context: modelContext).firstRecordedDate()
        ).runningBalance(
            through: through,
            holidays: holidayRecords.map(\.rule),
            countingThrough: CalendarDate.today(in: calendar),
            records: { _ in records }
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
