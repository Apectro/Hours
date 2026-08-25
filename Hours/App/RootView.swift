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
        .overlay(alignment: .top) {
            if let storeFailure {
                StoreFailureBanner(message: storeFailure)
            }
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
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .foregroundStyle(Color.hoursNegative)
            .padding(.horizontal, Metrics.medium)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

#Preview {
    RootView()
        .environment(SettingsStore.ephemeral())
        .modelContainer(HoursModelContainer.ephemeral())
}
