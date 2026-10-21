import SwiftUI
import SwiftData

/// Stored days and holiday rules for a span, ready for the engine.
struct PeriodData {
    var records: [Int: DayRecord]
    var holidays: [HolidayRule]
    /// The first day anything was recorded on, anywhere: where the balance
    /// starts unless a start date is set. See `WorkdayRepository.firstRecordedDate()`.
    var firstRecorded: CalendarDate?
}

/// Fetches a range of days and hands them to its content.
///
/// The fetch lives in its own view so `@Query` can carry a predicate built from
/// the range: SwiftUI rebuilds this view when the range changes, and SwiftData
/// pushes updates back automatically when a day is edited anywhere in the app.
struct PeriodDataProvider<Content: View>: View {
    @Query private var entries: [DayEntry]
    @Query private var holidayRecords: [HolidayRecord]
    /// One row each, the earliest: queried rather than fetched so that
    /// writing an earlier day moves the balance start straight away.
    @Query private var firstDay: [DayEntry]
    @Query private var firstSiteDay: [SiteDayEntry]

    private let content: (PeriodData) -> Content

    init(range: CalendarDateRange, @ViewBuilder content: @escaping (PeriodData) -> Content) {
        let lower = range.start.key
        let upper = range.end.key
        _entries = Query(
            filter: #Predicate<DayEntry> { $0.dateKey >= lower && $0.dateKey <= upper },
            sort: \DayEntry.dateKey
        )
        _holidayRecords = Query(sort: \HolidayRecord.name)
        var firstDay = FetchDescriptor<DayEntry>(sortBy: [SortDescriptor(\DayEntry.dateKey, order: .forward)])
        firstDay.fetchLimit = 1
        _firstDay = Query(firstDay)
        var firstSiteDay = FetchDescriptor<SiteDayEntry>(sortBy: [SortDescriptor(\SiteDayEntry.dateKey, order: .forward)])
        firstSiteDay.fetchLimit = 1
        _firstSiteDay = Query(firstSiteDay)
        self.content = content
    }

    var body: some View {
        content(
            PeriodData(
                records: Dictionary(entries.map { ($0.dateKey, $0.record) }, uniquingKeysWith: { first, _ in first }),
                holidays: holidayRecords.map(\.rule),
                firstRecorded: [firstDay.first?.dateKey, firstSiteDay.first?.dateKey]
                    .compactMap { $0 }
                    .min()
                    .flatMap { CalendarDate(key: $0) }
            )
        )
    }
}
