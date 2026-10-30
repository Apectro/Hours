import SwiftUI
import SwiftData

/// Every diary written for a site, a month at a time, the most recent day
/// first (1.2 redesign, mockup 08 "The month's diary"): one card per day
/// with its weather and photos on the right — a day the weather stopped in
/// orange — and the first line written under it. Written on the site's own
/// day screen; this only reads. A card goes to its day: the sheet closes and
/// the site screen shows that date.
struct SiteDiaryListSheet: View {
    let site: Site
    /// Shows a date on the site screen underneath.
    var onSelect: (CalendarDate) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @State private var entries: [Entry] = []
    @State private var loaded = false

    struct Entry: Identifiable {
        var date: CalendarDate
        var diary: SiteDiary?
        var photoCount: Int
        /// The site day, when the weather stopped it.
        var stop: SiteDay?
        var id: Int { date.key }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loaded && entries.isEmpty {
                    ContentUnavailableView(
                        "No diary yet",
                        systemImage: "text.book.closed",
                        description: Text("Write one under a day's hours on the site screen.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Metrics.medium) {
                            ForEach(months, id: \.month) { group in
                                Text(verbatim: monthLine(group.month, count: group.entries.count))
                                    .font(.subheadline)
                                    .foregroundStyle(.hoursSecondaryText)
                                    .padding(.horizontal, Metrics.tiny)
                                    .padding(.top, Metrics.small)
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.entries) { entry in
                                    card(entry)
                                }
                            }
                            Text("Write one under a day's hours on the site screen.")
                                .font(.footnote)
                                .foregroundStyle(.hoursSecondaryText)
                                .padding(.horizontal, Metrics.small)
                        }
                        .padding(Metrics.large)
                    }
                    .background(Color.hoursCanvas)
                }
            }
            .navigationTitle("Site diary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("site-diary-list-done")
                }
            }
            .accessibilityIdentifier("screen-site-diary")
            .task { load() }
        }
    }

    // MARK: - A day

    private func card(_ entry: Entry) -> some View {
        Button {
            onSelect(entry.date)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                        dateText(entry)
                        Spacer(minLength: Metrics.small)
                        detailText(entry)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        dateText(entry)
                        detailText(entry)
                    }
                }
                if let first = firstLine(entry.diary) {
                    Text(verbatim: first)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.horizontal, Metrics.medium + 2)
            .padding(.vertical, Metrics.medium)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: SiteDayStyle.groupRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("site-diary-entry-\(entry.date.key)")
    }

    private func dateText(_ entry: Entry) -> some View {
        Text(verbatim: settingsStore.dateFormatting.dayTitle(entry.date))
            .font(.body.weight(.bold))
            .foregroundStyle(.primary)
    }

    @ViewBuilder
    private func detailText(_ entry: Entry) -> some View {
        if let stop = entry.stop {
            Text(verbatim: stopLine(stop, diary: entry.diary))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.hoursAttention)
        } else if let line = detailLine(entry) {
            Text(verbatim: line)
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
        }
    }

    /// "Sunny · 14 °C · Photos: 2".
    private func detailLine(_ entry: Entry) -> String? {
        var parts: [String] = []
        if let weather = entry.diary?.weather { parts.append(weather.displayName()) }
        if let degrees = entry.diary?.temperatureCelsius { parts.append("\(degrees) °C") }
        if entry.photoCount > 0 {
            parts.append(String(localized: "Photos: \(entry.photoCount)", comment: "VoiceOver, how many photos a diary day has"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "Bad weather · stopped 11:00", with the weather picked before it.
    private func stopLine(_ day: SiteDay, diary: SiteDiary?) -> String {
        let stop: String
        if day.start != nil, let end = day.end {
            stop = String(
                localized: "Bad weather · stopped \(settingsStore.dateFormatting.time(end, on: day.date))",
                comment: "A site day stopped by the weather part-way; the value is the time it stopped"
            )
        } else {
            stop = String(localized: "Bad weather · no work")
        }
        guard let weather = diary?.weather else { return stop }
        return "\(weather.displayName()) · \(stop)"
    }

    /// The first line written, from the first text with anything in it.
    private func firstLine(_ diary: SiteDiary?) -> String? {
        guard let diary else { return nil }
        for entry in diary.texts {
            let line = SiteDiary.preview(of: entry.text)
            if !line.isEmpty { return line }
        }
        return nil
    }

    // MARK: - Months

    private var months: [(month: YearMonth, entries: [Entry])] {
        var order: [YearMonth] = []
        var byMonth: [YearMonth: [Entry]] = [:]
        for entry in entries {
            let month = entry.date.yearMonth
            if byMonth[month] == nil { order.append(month) }
            byMonth[month, default: []].append(entry)
        }
        return order.map { ($0, byMonth[$0] ?? []) }
    }

    /// "12 days in October 2026 · printed with the site sheet".
    private func monthLine(_ month: YearMonth, count: Int) -> String {
        let days = String(inflected: "^[\(count) day](inflect: true)")
        return String(
            localized: "\(days) in \(settingsStore.dateFormatting.monthTitle(month)) · printed with the site sheet",
            comment: "Above a month of site diary days; the values are how many days and the month"
        )
    }

    /// Read outside `body`, as every repository read is.
    private func load() {
        let repository = SiteDiaryRepository(context: modelContext)
        let everything = CalendarDateRange(
            start: CalendarDate(year: 1, month: 1, day: 1),
            end: CalendarDate(year: 9999, month: 12, day: 31)
        )
        let diaries = repository.diaries(siteID: site.id, in: everything)
        let photos = repository.photoReferences(siteID: site.id, in: everything)
        let photoCounts = Dictionary(grouping: photos, by: \.date).mapValues(\.count)
        let byDate = Dictionary(diaries.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        let dates = SiteDiary.datesWithEntries(diaries: diaries, photoDates: photos.map(\.date))
        var stops: [CalendarDate: SiteDay] = [:]
        if let first = dates.min(), let last = dates.max() {
            let days = SiteRepository(context: modelContext)
                .siteDays(siteID: site.id, in: CalendarDateRange(start: first, end: last))
            for day in days where day.isBadWeatherStop && dates.contains(day.date) {
                stops[day.date] = day
            }
        }
        entries = dates.sorted(by: >).map { date in
            Entry(date: date, diary: byDate[date], photoCount: photoCounts[date] ?? 0, stop: stops[date])
        }
        loaded = true
    }
}
