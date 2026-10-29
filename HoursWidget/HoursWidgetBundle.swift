import SwiftUI
import WidgetKit

/// The widget extension's entry point.
///
/// Everything the widgets show comes from a small JSON snapshot the app writes
/// into a shared container. A widget runs in its own short-lived process with a
/// hard memory limit, so opening the SwiftData store here would mean running
/// migrations and taking locks in a process the system is willing to kill
/// mid-write. A snapshot cannot corrupt anything and cannot be slow.
///
/// The Live Activity is the exception: the system hands it its state
/// directly, from the app, so it needs no snapshot at all.
///
/// The controls (Control Center, the Lock Screen, the Action Button) read the
/// snapshot like the widgets; see `Controls.swift`.
@main
struct HoursWidgetBundle: WidgetBundle {
    var body: some Widget {
        // A bundle's body takes ten at most, so the 1.2 widgets are a bundle
        // of their own, included here.
        TodayWidget()
        MonthWidget()
        WeekWidget()
        SiteWidget()
        FiguresWidgets().body
        ClockLiveActivity()
        ClockControl()
        SameAsYesterdayControl()
        WriteTodayControl()
    }
}

/// The widgets 1.2 added: the clock on the Lock Screen, the balance, leave
/// and what the month earned. The kinds of the four above are unchanged, so
/// widgets placed before the update stay where they are.
struct FiguresWidgets: WidgetBundle {
    var body: some Widget {
        ClockWidget()
        BalanceWidget()
        LeaveWidget()
        EarnedWidget()
    }
}
