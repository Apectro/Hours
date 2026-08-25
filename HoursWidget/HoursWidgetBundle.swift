import SwiftUI
import WidgetKit

/// The widget extension's entry point.
///
/// Everything the widgets show comes from a small JSON snapshot the app writes
/// into a shared container. A widget runs in its own short-lived process with a
/// hard memory limit, so opening the SwiftData store here would mean running
/// migrations and taking locks in a process the system is willing to kill
/// mid-write. A snapshot cannot corrupt anything and cannot be slow.
@main
struct HoursWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        MonthWidget()
    }
}
