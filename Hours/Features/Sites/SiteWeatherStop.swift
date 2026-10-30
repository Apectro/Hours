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
                        Text(stopTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.hoursAttention)
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

/// "Stopped for bad weather" (1.2 redesign, mockup 07): stopped at a time,
/// with the hours until then kept, or no work at all; what that means for
/// the sheet, and what the crew gets.
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
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.medium) {
                    Text("Stopped for bad weather")
                        .font(.title2.weight(.heavy))
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: 3) {
                        segment(String(localized: "Stopped at…"), isOn: !noWork, identifier: "site-weather-stop-at") { noWork = false }
                        segment(String(localized: "No work today"), isOn: noWork, identifier: "site-weather-stop-all") { noWork = true }
                    }
                    .padding(3)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                    if !noWork {
                        SiteGroup {
                            DatePicker(
                                String(localized: "Stopped at"),
                                selection: Binding(
                                    get: { OptionalTimeRow.date(from: stop, in: settingsStore.workCalendar) },
                                    set: { stop = OptionalTimeRow.time(from: $0, in: settingsStore.workCalendar) }
                                ),
                                displayedComponents: .hourAndMinute
                            )
                            .frame(minHeight: SiteDayStyle.rowHeight)
                            .accessibilityIdentifier("site-weather-stop-wheel")
                        }
                    }

                    Text(verbatim: explanation)
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, Metrics.small)

                    HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                        Text("Crew today")
                        Spacer(minLength: Metrics.small)
                        Text(verbatim: SiteDayStyle.figures(figures(noWork ? nil : stop), durations: settingsStore.settings.displayFormatting, prefersEach: true))
                            .font(.body.weight(.bold))
                            .multilineTextAlignment(.trailing)
                    }
                    .padding(.horizontal, Metrics.large)
                    .frame(minHeight: SiteDayStyle.rowHeight)
                    .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: SiteDayStyle.groupRadius, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("site-weather-crew")
                }
                .padding(Metrics.large)
            }
            .background(Color.hoursCanvas)
            .navigationTitle(Text(verbatim: settingsStore.dateFormatting.dayTitle(day.date)))
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("site-weather-sheet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("site-weather-stop-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(noWork ? nil : stop)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("site-weather-stop-save")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func segment(_ title: String, isOn: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(.subheadline.weight(isOn ? .bold : .regular))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    isOn ? Color.hoursSurface : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    /// What the stop writes, in the words of the sheet.
    private var explanation: String {
        guard !noWork else {
            return String(localized: "Nobody gets hours for this day. It is marked “Bad weather” on the sheet and counted in the tiles.")
        }
        let formatting = settingsStore.dateFormatting
        let start = day.start.map { formatting.time($0, on: day.date) } ?? "—"
        let range = "\(start)–\(formatting.time(stop, on: day.date))"
        return String(
            localized: "Everyone ticked gets \(range). The day is marked “Bad weather” on the sheet and counted in the tiles.",
            comment: "Bad weather sheet; the value is a time range such as 07:00–11:00"
        )
    }
}
