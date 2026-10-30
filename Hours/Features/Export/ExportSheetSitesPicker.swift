import SwiftUI

/// Sites (design v2, More board phone 1): a row per active site with the
/// month's crew hours and a blue checkmark when it is on the sheet, and the
/// archived sites behind an "Other sites" row.
///
/// Several ticked make one crew sheet with each person's hours a day added
/// up across them (1.2). The sheet names them in the order they were
/// ticked; the first is the one the sheet is filed under. At least one site
/// stays ticked.
struct ExportSitesSection: View {
    /// The rows, in the sites' own order: the active sites, and any
    /// archived one already on the sheet.
    let sites: [Site]
    /// The sites on the sheet, in the order ticked; the first is the sheet's
    /// own.
    let chosen: [UUID]
    /// The month's crew hours by site; a site without days has none.
    let hours: [UUID: Int]
    /// How many archived sites there are to offer behind "Other sites".
    let otherSitesCount: Int
    let onToggle: (UUID) -> Void
    let onOtherSites: () -> Void

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Section {
            ForEach(sites) { site in
                row(site)
            }
            if otherSitesCount > 0 {
                Button(action: onOtherSites) {
                    HStack(spacing: Metrics.small) {
                        Text("Other sites")
                            .foregroundStyle(.primary)
                        Spacer(minLength: Metrics.small)
                        Text(verbatim: "\(otherSitesCount)")
                            .monospacedDigit()
                            .foregroundStyle(.hoursSecondaryText)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("export-sheet-sites")
            }
        } header: {
            Text("Sites")
        }
    }

    private func row(_ site: Site) -> some View {
        let isOn = chosen.contains(site.id)
        return Button {
            onToggle(site.id)
        } label: {
            HStack(spacing: Metrics.small) {
                Text(verbatim: site.name)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: Metrics.small)
                if let minutes = hours[site.id], minutes > 0 {
                    Text(verbatim: settingsStore.settings.displayFormatting.string(minutes))
                        .monospacedDigit()
                        .foregroundStyle(.hoursSecondaryText)
                }
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .opacity(isOn ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier(for: site))
    }

    /// The sheet's own site is `export-sheet-site-this`; the others count
    /// from 0 in the order shown, as the rows of the old list did.
    private func identifier(for site: Site) -> String {
        if site.id == chosen.first { return "export-sheet-site-this" }
        let others = sites.filter { $0.id != chosen.first }
        let offset = others.firstIndex { $0.id == site.id } ?? 0
        return "export-sheet-site-\(offset)"
    }
}

/// "Other sites": the archived sites, each with the month's crew hours, to
/// take onto the sheet. Opened from the chip of that name.
struct ExportSheetSitesPicker: View {
    /// Archived sites, those with days in the month first.
    let candidates: [Site]
    /// The month's crew hours by site; a site without days has none.
    let hours: [UUID: Int]
    /// The sites on the sheet besides its own, in the order ticked.
    @Binding var chosen: [UUID]

    @Environment(\.dismiss) var dismiss
    @Environment(SettingsStore.self) var settingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(Array(candidates.enumerated()), id: \.element.id) { offset, other in
                        Button {
                            toggle(other.id)
                        } label: {
                            row(other, isChosen: chosen.contains(other.id))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(chosen.contains(other.id) ? .isSelected : [])
                        .accessibilityIdentifier("export-other-site-\(offset)")
                    }
                } footer: {
                    Text("Each person's hours a day are added up across the sites you pick, on one sheet with a By site total.")
                }
            }
            .navigationTitle("Other sites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("export-sheet-sites-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ site: Site, isChosen: Bool) -> some View {
        HStack(spacing: Metrics.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: site.name)
                    .foregroundStyle(.primary)
                Text("Archived")
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
            }
            Spacer(minLength: Metrics.small)
            Text(verbatim: settingsStore.settings.displayFormatting.string(hours[site.id] ?? 0))
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .opacity(isChosen ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func toggle(_ id: UUID) {
        if let index = chosen.firstIndex(of: id) {
            chosen.remove(at: index)
        } else {
            chosen.append(id)
        }
    }
}
