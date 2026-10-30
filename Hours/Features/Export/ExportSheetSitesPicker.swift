import SwiftUI

/// WHICH SITES · TAP MORE THAN ONE TO MERGE (Export board, phone 1): the
/// active sites as chips, ticked ones with a checkmark, and archived sites
/// behind an "Other sites" chip.
///
/// Several ticked make one crew sheet with each person's hours a day added
/// up across them (1.2). The sheet names them in the order they were
/// ticked; the first is the one the sheet is filed under. At least one site
/// stays ticked.
struct ExportSiteChips: View {
    /// The chips, in the sites' own order: the active sites, and any
    /// archived one already on the sheet.
    let sites: [Site]
    /// The sites on the sheet, in the order ticked; the first is the sheet's
    /// own.
    let chosen: [UUID]
    /// Whether there are archived sites to offer behind "Other sites".
    let hasOtherSites: Bool
    let onToggle: (UUID) -> Void
    let onOtherSites: () -> Void

    var body: some View {
        ExtraWorkFlow(spacing: Metrics.small) {
            ForEach(sites) { site in
                chip(site)
            }
            if hasOtherSites {
                Button(action: onOtherSites) {
                    HStack(spacing: Metrics.tiny) {
                        Text("Other sites")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .chipLabel(isOn: false)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("export-sheet-sites")
            }
        }
    }

    private func chip(_ site: Site) -> some View {
        let isOn = chosen.contains(site.id)
        return Button {
            onToggle(site.id)
        } label: {
            HStack(spacing: Metrics.tiny) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .accessibilityHidden(true)
                }
                Text(verbatim: site.name)
                    .lineLimit(1)
            }
            .chipLabel(isOn: isOn)
        }
        .buttonStyle(.plain)
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

private extension View {
    /// The Export board's chip: 44 points tall, outlined; ticked, blue.
    func chipLabel(isOn: Bool) -> some View {
        self
            .font(.subheadline.weight(isOn ? .bold : .regular))
            .foregroundStyle(isOn ? Color.accentColor : Color.primary)
            .padding(.horizontal, Metrics.medium + 2)
            .frame(minHeight: 44)
            .background(isOn ? Color.accentColor.opacity(0.12) : Color.hoursSurface, in: Capsule())
            .overlay {
                Capsule().strokeBorder(isOn ? Color.accentColor : Color(uiColor: .systemGray3), lineWidth: 1.5)
            }
            .contentShape(Capsule())
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
                    .font(.caption)
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
