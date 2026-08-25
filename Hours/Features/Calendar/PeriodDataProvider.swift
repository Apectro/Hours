import SwiftUI
import SwiftData

/// Stored days and holiday rules for a span, ready for the engine.
struct PeriodData {
    var records: [Int: DayRecord]
    var holidays: [HolidayRule]
}

/// Fetches a range of days and hands them to its content.
///
/// The fetch lives in its own view so `@Query` can carry a predicate built from
/// the range: SwiftUI rebuilds this view when the range changes, and SwiftData
/// pushes updates back automatically when a day is edited anywhere in the app.
struct PeriodDataProvider<Content: View>: View {
    @Query private var entries: [DayEntry]
    @Query private var holidayRecords: [HolidayRecord]

    private let content: (PeriodData) -> Content

    init(range: CalendarDateRange, @ViewBuilder content: @escaping (PeriodData) -> Content) {
        let lower = range.start.key
        let upper = range.end.key
        _entries = Query(
            filter: #Predicate<DayEntry> { $0.dateKey >= lower && $0.dateKey <= upper },
            sort: \DayEntry.dateKey
        )
        _holidayRecords = Query(sort: \HolidayRecord.name)
        self.content = content
    }

    var body: some View {
        content(
            PeriodData(
                records: Dictionary(entries.map { ($0.dateKey, $0.record) }, uniquingKeysWith: { first, _ in first }),
                holidays: holidayRecords.map(\.rule)
            )
        )
    }
}
