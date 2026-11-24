import SwiftUI
import SwiftData

/// "Write today's hours" on the Today tab (2026-11-24, mockup 4): one
/// question, "Where did you work today?". Each active site with what is
/// written on it today (`WriteToday`), then "Not on a site". A site opens
/// its day for today; "Not on a site" opens your own day in the editor.
///
/// The choice of tab is what people got lost on: hours for the crew are
/// written on the site, and only hours that are on no site are written in
/// your own calendar. This asks, and goes to the right place.
struct WriteTodaySheet: View {
    let today: CalendarDate
    /// A site's day for today; the caller closes the sheet and pushes it.
    let onOpenSite: (UUID) -> Void
    /// Your own day in the editor; the caller swaps the sheet for it.
    let onOwnHours: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    /// Watched rather than read, as on the Today tab: the rows come from
    /// `SiteRepository`, which owns the duplicate rules.
    @Query private var siteEntries: [SiteEntry]
    @Query private var siteDayEntries: [SiteDayEntry]

    @State private var rows: [WriteToday.Row] = []

    init(today: CalendarDate, onOpenSite: @escaping (UUID) -> Void, onOwnHours: @escaping () -> Void) {
        self.today = today
        self.onOpenSite = onOpenSite
        self.onOwnHours = onOwnHours
        let key = today.key
        _siteEntries = Query(sort: \SiteEntry.sortOrder)
        _siteDayEntries = Query(
            filter: #Predicate<SiteDayEntry> { $0.dateKey == key },
            sort: \SiteDayEntry.dateKey
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        Button {
                            onOpenSite(row.siteID)
                        } label: {
                            siteLabel(row)
                        }
                        .accessibilityIdentifier("write-today-site-\(index)")
                    }
                    Button(action: onOwnHours) {
                        ownLabel
                    }
                    .accessibilityIdentifier("write-today-own")
                } footer: {
                    Text("Hours on a site go to everyone in the crew and into your own calendar.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Where did you work today?")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen-write-today")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("write-today-cancel")
                }
            }
            // Read outside of `body`: the repository's reads collapse
            // duplicates, which writes, and a view must not write while drawn.
            .onChange(of: changeToken, initial: true) { _, _ in reload() }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Rows

    private var colors: SiteColors { SiteColors(sites: siteEntries.map(\.site)) }

    /// The site in its colour, what is written on it today under its name,
    /// and a green check once it is written.
    private func siteLabel(_ row: WriteToday.Row) -> some View {
        HStack(alignment: .center, spacing: Metrics.medium) {
            SourceDot(color: colors.color(for: row.siteID))
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: row.siteName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(verbatim: stateText(row.state))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
            }
            Spacer(minLength: Metrics.small)
            if case .written = row.state {
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.hoursDone)
                    .accessibilityHidden(true)
            } else {
                chevron
            }
        }
        .padding(.vertical, Metrics.tiny)
        .contentShape(Rectangle())
    }

    private var ownLabel: some View {
        HStack(alignment: .center, spacing: Metrics.medium) {
            SourceDot(color: nil)
            VStack(alignment: .leading, spacing: 1) {
                Text("Not on a site")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Only my own hours")
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
            }
            Spacer(minLength: Metrics.small)
            chevron
        }
        .padding(.vertical, Metrics.tiny)
        .contentShape(Rectangle())
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    /// "Written · 5 people · 7:00 – 12:00", "No work", "Not written yet".
    private func stateText(_ state: WriteToday.State) -> String {
        switch state {
        case let .written(people, start, end):
            var parts = [String(localized: "Written")]
            if people > 0 {
                parts.append(String(inflected: "^[\(people) person](inflect: true)"))
            }
            if let start, let end {
                let formatting = settingsStore.dateFormatting
                parts.append("\(formatting.time(start, on: today)) – \(formatting.time(end, on: today))")
            }
            return parts.joined(separator: " · ")
        case .noWork:
            return String(localized: "No work")
        case .notWritten:
            return String(localized: "Not written yet")
        }
    }

    // MARK: - Data

    private var changeToken: [Date] {
        siteEntries.map(\.updatedAt) + siteDayEntries.map(\.updatedAt)
    }

    private func reload() {
        let settings = settingsStore.settings
        let repository = SiteRepository(context: modelContext, lock: settings.monthLock)
        rows = WriteToday.rows(
            sites: repository.sites(includeArchived: false),
            siteDays: repository.siteDays(siteID: nil, in: CalendarDateRange(single: today)),
            settings: settings,
            today: today
        )
    }
}
