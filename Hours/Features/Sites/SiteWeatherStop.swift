import SwiftUI

/// "Rained off": the whole crew stopped by the weather, under the day card.
///
/// On an ordinary day, a menu: no work at all, or stopped at a time with the
/// hours until then kept. On a day already stopped, what happened and a way
/// to take it back. Draws and reports only; the site screen writes, as it
/// does every other change, through the month lock and your calendar day.
struct SiteWeatherStopRow: View {
    let day: SiteDay
    let canEdit: Bool
    let onStopAll: () -> Void
    let onStopAt: () -> Void
    let onLift: () -> Void

    var body: some View {
        if day.isBadWeatherStop {
            HStack(spacing: Metrics.medium) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rained off")
                            .font(.subheadline.weight(.semibold))
                        Text(stopDetail)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "cloud.rain.fill")
                        .foregroundStyle(Color.hoursNegative)
                }
                Spacer(minLength: Metrics.small)
                if canEdit {
                    Button("Undo", action: onLift)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(String(localized: "Undo rained off"))
                        .accessibilityIdentifier("site-weather-lift")
                }
            }
            .padding(Metrics.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("site-weather-stopped")
        } else if canEdit {
            Menu {
                Button(action: onStopAll) {
                    Label("No work today", systemImage: "cloud.rain")
                }
                .accessibilityIdentifier("site-weather-stop-all")
                Button(action: onStopAt) {
                    Label("Stopped at…", systemImage: "clock")
                }
                .accessibilityIdentifier("site-weather-stop-at")
            } label: {
                Label("Rained off / bad weather", systemImage: "cloud.rain")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, Metrics.medium)
                    .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
            }
            .accessibilityIdentifier("site-weather-menu")
        }
    }

    private var stopDetail: String {
        if day.start != nil, day.end != nil {
            return String(localized: "Hours kept until the stop. Your own day counts them as worked.")
        }
        return String(localized: "No hours for anyone. Your own day becomes Bad weather if nothing else is on it.")
    }
}

/// Picks the time the weather stopped work. The hours up to it stay.
struct WeatherStopSheet: View {
    let day: SiteDay
    let onSave: (TimeOfDay) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @State private var stop: TimeOfDay

    init(day: SiteDay, suggested: TimeOfDay, onSave: @escaping (TimeOfDay) -> Void) {
        self.day = day
        self.onSave = onSave
        _stop = State(initialValue: suggested)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Metrics.large) {
                DatePicker(
                    String(localized: "Stopped at"),
                    selection: Binding(
                        get: { OptionalTimeRow.date(from: stop, in: settingsStore.workCalendar) },
                        set: { stop = OptionalTimeRow.time(from: $0, in: settingsStore.workCalendar) }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("site-weather-stop-wheel")

                Text("Everyone on this day stops at this time. Anyone who had already left keeps the time they left.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .padding(Metrics.large)
            .background(Color.hoursCanvas)
            .navigationTitle("Stopped at")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-weather-stop-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(stop)
                        dismiss()
                    }
                    .accessibilityIdentifier("site-weather-stop-done")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
