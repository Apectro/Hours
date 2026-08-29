#if DEBUG
import SwiftUI
import SwiftData

/// Sample data for Xcode previews. Debug only — it is never compiled into a
/// release build, so a preview fixture can never reach real data.
@MainActor
enum PreviewSupport {
    static func seededContainer(reference: Date = Date()) -> ModelContainer {
        let container = HoursModelContainer.ephemeral()
        seed(container.mainContext, reference: reference)
        return container
    }

    static let settings = SettingsStore.ephemeral()
    static let clock = ActiveShiftStore.ephemeral()

    private static func seed(_ context: ModelContext, reference: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let today = CalendarDate(reference, calendar: calendar)
        let month = today.yearMonth.range(in: calendar)
        let repository = WorkdayRepository(context: context)

        repository.upsert(
            HolidayRule(name: "Sample holiday", recurrence: .annual(month: today.month, day: min(today.day + 3, 28)))
        )

        for date in month.days(in: calendar) where date <= today {
            let weekday = date.weekday(in: calendar)
            guard weekday != 1 && weekday != 7 else { continue }

            switch date.day % 7 {
            case 0:
                try? repository.save(DayRecord(date: date, dayTypeID: .vacation))
            case 3:
                try? repository.save(DayRecord(
                    date: date,
                    start: TimeOfDay(hour: 8, minute: 0),
                    end: TimeOfDay(hour: 18, minute: 15),
                    breaks: [.duration(30)],
                    note: "Release day"
                ))
            case 5:
                try? repository.save(DayRecord(
                    date: date,
                    start: TimeOfDay(hour: 8, minute: 30),
                    end: TimeOfDay(hour: 15, minute: 30),
                    breaks: [.duration(30)]
                ))
            default:
                try? repository.save(DayRecord(
                    date: date,
                    start: TimeOfDay(hour: 8, minute: 0),
                    end: TimeOfDay(hour: 16, minute: 30),
                    breaks: [.duration(30)]
                ))
            }
        }
    }
}

#Preview("Calendar") {
    CalendarScreen()
        .environment(PreviewSupport.settings)
        .environment(PreviewSupport.clock)
        .modelContainer(PreviewSupport.seededContainer())
}

#Preview("Insights") {
    StatisticsScreen()
        .environment(PreviewSupport.settings)
        .environment(PreviewSupport.clock)
        .modelContainer(PreviewSupport.seededContainer())
}

#Preview("Settings") {
    SettingsScreen()
        .environment(PreviewSupport.settings)
        .environment(PreviewSupport.clock)
        .modelContainer(PreviewSupport.seededContainer())
}

#Preview("Day editor") {
    DayEditorSheet(date: CalendarDate.today(in: .current))
        .environment(PreviewSupport.settings)
        .environment(PreviewSupport.clock)
        .modelContainer(PreviewSupport.seededContainer())
}

#Preview("Export") {
    ExportScreen(initialRange: CalendarDate.today(in: .current).yearMonth.range(in: .current))
        .environment(PreviewSupport.settings)
        .environment(PreviewSupport.clock)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
