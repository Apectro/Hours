import SwiftUI

/// Bad weather: the whole crew stopped by the weather, under the day card.
///
/// On an ordinary day, a menu: no work that day, or stopped at a time with
/// the hours until then kept. One name for it throughout, "Bad weather", as
/// the day type and the sheet call it. On a day already stopped, what happened and a way
/// to take it back. Draws and reports only; the site screen writes, as it
/// does every other change, through the month lock and your calendar day.
struct SiteWeatherStopRow: View {
    let day: SiteDay
    let canEdit: Bool
    let formatting: CalendarFormatting
    let onStopAll: () -> Void
    let onStopAt: () -> Void
    let onLift: () -> Void

    var body: some View {
        if day.isBadWeatherStop {
            HStack(spacing: Metrics.medium) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stopTitle)
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
                        .accessibilityLabel(String(localized: "Undo bad weather"))
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
                    Label("No work this day", systemImage: "cloud.rain")
                }
                .accessibilityIdentifier("site-weather-stop-all")
                Button(action: onStopAt) {
                    Label("Stopped at…", systemImage: "clock")
                }
                .accessibilityIdentifier("site-weather-stop-at")
            } label: {
                Label("Bad weather", systemImage: "cloud.rain")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, Metrics.medium)
                    .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
            }
            .accessibilityIdentifier("site-weather-menu")
        }
    }

    /// "Bad weather · stopped 11:30", or "Bad weather · no work". A partial
    /// stop keeps the site's start and ends everyone at the stop.
    private var stopTitle: String {
        if day.start != nil, let end = day.end {
            return String(
                localized: "Bad weather · stopped \(formatting.time(end, on: day.date))",
                comment: "A site day stopped by the weather part-way; the value is the time it stopped"
            )
        }
        return String(localized: "Bad weather · no work")
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
                    Button("Save") {
                        onSave(stop)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("site-weather-stop-save")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
