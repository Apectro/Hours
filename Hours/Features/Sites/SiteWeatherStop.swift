import SwiftUI

/// A day the weather stopped, under the day card: what happened and a way to
/// take it back. One name for it throughout, "Bad weather", as the day type
/// and the sheet call it. Draws and reports only; the site screen writes, as
/// it does every other change, through the month lock and your calendar day.
/// Marking a day is "Bad weather…" among the day's links, which opens
/// `WeatherStopSheet`.
struct SiteWeatherStopRow: View {
    let day: SiteDay
    let canEdit: Bool
    let formatting: CalendarFormatting
    let onLift: () -> Void

    var body: some View {
        if day.isBadWeatherStop {
            HStack(spacing: Metrics.medium) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        // The colour is the symbol's; the words stay plain.
                        Text(stopTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(stopDetail)
                            .font(.footnote)
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "cloud.rain.fill")
                        .foregroundStyle(Color.hoursAttention)
                }
                Spacer(minLength: Metrics.small)
                if canEdit {
                    Button("Undo", action: onLift)
                        .buttonStyle(.borderless)
                        .font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel(String(localized: "Undo bad weather"))
                        .accessibilityIdentifier("site-weather-lift")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("site-weather-stopped")
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

/// "Stopped for bad weather" (1.2 redesign, mockup 07), as a form: stopped at
/// a time, with the hours until then kept, or no work at all; what the crew
/// gets, and in one sentence what that means for the sheet.
struct WeatherStopSheet: View {
    let day: SiteDay
    /// The crew's figures for a stop at a time, or nil for no work.
    let figures: (TimeOfDay?) -> SiteCrewFigures
    /// The time, or nil for no work today.
    let onSave: (TimeOfDay?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @State private var stop: TimeOfDay
    @State private var noWork = false

    init(
        day: SiteDay,
        suggested: TimeOfDay,
        figures: @escaping (TimeOfDay?) -> SiteCrewFigures,
        onSave: @escaping (TimeOfDay?) -> Void
    ) {
        self.day = day
        self.figures = figures
        self.onSave = onSave
        _stop = State(initialValue: suggested)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    choiceRow(String(localized: "Stopped at…"), isOn: !noWork, identifier: "site-weather-stop-at") { noWork = false }
                    choiceRow(String(localized: "No work today"), isOn: noWork, identifier: "site-weather-stop-all") { noWork = true }
                } header: {
                    Text("Stopped for bad weather")
                        .textCase(nil)
                }

                Section {
                    if !noWork {
                        DatePicker(
                            String(localized: "Stopped at"),
                            selection: Binding(
                                get: { OptionalTimeRow.date(from: stop, in: settingsStore.workCalendar) },
                                set: { stop = OptionalTimeRow.time(from: $0, in: settingsStore.workCalendar) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .accessibilityIdentifier("site-weather-stop-wheel")
                    }
                    LabeledContent {
                        Text(verbatim: SiteDayStyle.figures(figures(noWork ? nil : stop), durations: settingsStore.settings.displayFormatting, prefersEach: true))
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                    } label: {
                        Text("Crew today")
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("site-weather-crew")
                } footer: {
                    Text(verbatim: explanation)
                }
            }
            .accessibilityIdentifier("site-weather-sheet")
            .navigationTitle(Text(verbatim: settingsStore.dateFormatting.dayTitle(day.date)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("site-weather-stop-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onSave(noWork ? nil : stop)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(String(localized: "Save"))
                    .accessibilityIdentifier("site-weather-stop-save")
                }
            }
        }
        .presentationDetents([.large])
    }

    /// One of the two ways the weather stopped the day, ticked like a
    /// choice in Settings.
    private func choiceRow(_ title: String, isOn: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(verbatim: title)
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                if isOn {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// What the stop writes, in the words of the sheet.
    private var explanation: String {
        guard !noWork else {
            return String(localized: "Nobody gets hours, and the day is marked “Bad weather” on the sheet.")
        }
        let formatting = settingsStore.dateFormatting
        let start = day.start.map { formatting.time($0, on: day.date) } ?? "—"
        let range = "\(start) – \(formatting.time(stop, on: day.date))"
        return String(
            localized: "Everyone ticked gets \(range), and the day is marked “Bad weather” on the sheet.",
            comment: "Bad weather sheet; the value is a time range such as 07:00–11:00"
        )
    }
}
