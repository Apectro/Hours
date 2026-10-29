import SwiftUI

/// "Sites on this sheet" (1.2): the site the export is of, always on, and
/// the other sites to take in, each with the month's crew hours. Several
/// make one director's sheet with each person's hours a day added up
/// across them.
///
/// The order they are ticked in is the order the sheet names them.
struct ExportSheetSitesPicker: View {
    /// The export's own site, first on the sheet whatever else is chosen.
    let site: Site
    /// The other active sites, and archived ones with days in the month.
    let candidates: [Site]
    /// The month's crew hours by site; a site without days has none.
    let hours: [UUID: Int]
    /// The other sites chosen, in the order they were ticked.
    @Binding var chosen: [UUID]

    @Environment(\.dismiss) var dismiss
    @Environment(SettingsStore.self) var settingsStore

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    row(site, isChosen: true)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isSelected)
                } footer: {
                    Text("Each person's hours a day are added up across the sites you pick, on one sheet with a By site total.")
                }
                if !candidates.isEmpty {
                    Section {
                        ForEach(Array(candidates.enumerated()), id: \.element.id) { offset, other in
                            Button {
                                toggle(other.id)
                            } label: {
                                row(other, isChosen: chosen.contains(other.id))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(chosen.contains(other.id) ? .isSelected : [])
                            .accessibilityIdentifier("export-sheet-site-\(offset)")
                        }
                    } header: {
                        Text("Other sites")
                    }
                }
            }
            .navigationTitle("Sites on this sheet")
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
                if site.isArchived {
                    Text("Archived")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: Metrics.small)
            Text(verbatim: settingsStore.settings.displayFormatting.string(hours[site.id] ?? 0))
                .monospacedDigit()
                .foregroundStyle(.secondary)
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
