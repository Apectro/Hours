import SwiftUI
import SwiftData

/// Every diary written for a site, the most recent day first: the weather,
/// what was written and how many photos, to read back through. Written on
/// the site's own day screen; this only reads.
struct SiteDiaryListSheet: View {
    let site: Site

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @State private var entries: [Entry] = []
    @State private var loaded = false

    struct Entry: Identifiable {
        var date: CalendarDate
        var diary: SiteDiary?
        var photoCount: Int
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
                    List(entries) { entry in
                        row(entry)
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Site diary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("site-diary-list-done")
                }
            }
            .accessibilityIdentifier("screen-site-diary")
            .task { load() }
        }
    }

    private func row(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: Metrics.tiny) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: settingsStore.dateFormatting.fullDate(entry.date))
                    .font(.headline)
                Spacer(minLength: Metrics.small)
                if entry.photoCount > 0 {
                    Label {
                        Text(verbatim: "\(entry.photoCount)")
                    } icon: {
                        Image(systemName: "photo")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(String(
                        localized: "Photos: \(entry.photoCount)",
                        comment: "VoiceOver, how many photos a diary day has"
                    ))
                }
            }
            if let weather = weatherLine(entry.diary) {
                Text(verbatim: weather)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(texts(entry.diary), id: \.self) { item in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: item.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(verbatim: item.text)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, Metrics.tiny)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("site-diary-entry-\(entry.date.key)")
    }

    private func weatherLine(_ diary: SiteDiary?) -> String? {
        guard let diary else { return nil }
        var parts: [String] = []
        if let weather = diary.weather { parts.append(weather.displayName()) }
        if let degrees = diary.temperatureCelsius { parts.append("\(degrees) °C") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func texts(_ diary: SiteDiary?) -> [SiteDiaryBlock.Line] {
        (diary?.texts ?? []).compactMap { entry in
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : SiteDiaryBlock.Line(label: SiteDiary.label(for: entry.term), text: text)
        }
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
        entries = dates.sorted(by: >).map { date in
            Entry(date: date, diary: byDate[date], photoCount: photoCounts[date] ?? 0)
        }
        loaded = true
    }
}
