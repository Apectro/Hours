import SwiftUI

/// Three tabs, calendar first.
///
/// The calendar is where the work happens, so it is the landing surface and
/// keeps its own navigation stack. Insights and Settings are destinations you
/// visit, not places you live.
struct RootView: View {
    var storeFailure: String? = nil

    @State private var selection: Destination = .calendar

    enum Destination: Hashable {
        case calendar
        case insights
        case settings
    }

    var body: some View {
        VStack(spacing: 0) {
            // Above the tabs rather than floating over them: a warning that
            // covers the navigation bar is worse than the problem it reports.
            if let storeFailure {
                StoreFailureBanner(message: storeFailure)
            }
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Destination.calendar)

            StatisticsScreen()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(Destination.insights)

            SettingsScreen()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Destination.settings)
        }
    }
}

private struct StoreFailureBanner: View {
    let message: String
    @State private var isVisible = true

    var body: some View {
        if isVisible {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .font(.footnote)
                Spacer(minLength: 0)
                Button {
                    withAnimation { isVisible = false }
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(Metrics.medium)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .foregroundStyle(Color.hoursNegative)
            .padding(.horizontal, Metrics.medium)
            .padding(.bottom, Metrics.small)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#if DEBUG
#Preview {
    RootView()
        .environment(PreviewSupport.settings)
        .environment(PreviewSupport.clock)
        .modelContainer(PreviewSupport.seededContainer())
}
#endif
