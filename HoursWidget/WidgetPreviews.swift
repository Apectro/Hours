import SwiftUI
import WidgetKit

// Every widget in every family, each with the states it can be in: the
// clock running, stopped before work, a day off, nothing set up (no rate,
// no leave allowance, overtime off, no site), and the app not yet opened.
// The figures are the design's own (`HoursEntry.sample`).

#Preview("Today · systemSmall", as: .systemSmall) {
    TodayWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Today · systemMedium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Today · accessoryCircular", as: .accessoryCircular) {
    TodayWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Today · accessoryRectangular", as: .accessoryRectangular) {
    TodayWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Today · accessoryInline", as: .accessoryInline) {
    TodayWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Week · systemSmall", as: .systemSmall) {
    WeekWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Week · systemMedium", as: .systemMedium) {
    WeekWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Week · systemLarge", as: .systemLarge) {
    WeekWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Week · accessoryRectangular", as: .accessoryRectangular) {
    WeekWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Month · systemSmall", as: .systemSmall) {
    MonthWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Month · systemMedium", as: .systemMedium) {
    MonthWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Month · accessoryRectangular", as: .accessoryRectangular) {
    MonthWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Month · accessoryInline", as: .accessoryInline) {
    MonthWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Site · systemMedium", as: .systemMedium) {
    SiteWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Clock · accessoryRectangular", as: .accessoryRectangular) {
    ClockWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Clock · accessoryCircular", as: .accessoryCircular) {
    ClockWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Clock · accessoryInline", as: .accessoryInline) {
    ClockWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Balance · systemSmall", as: .systemSmall) {
    BalanceWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Balance · accessoryCircular", as: .accessoryCircular) {
    BalanceWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Leave · accessoryRectangular", as: .accessoryRectangular) {
    LeaveWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Leave · accessoryCircular", as: .accessoryCircular) {
    LeaveWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}

#Preview("Earned · systemMedium", as: .systemMedium) {
    EarnedWidget()
} timeline: {
    HoursEntry.sample()
    HoursEntry.sampleIdle()
    HoursEntry.sampleDayOff()
    HoursEntry.sampleUnset()
    HoursEntry(date: Date(), snapshot: .empty, state: .waiting)
}
