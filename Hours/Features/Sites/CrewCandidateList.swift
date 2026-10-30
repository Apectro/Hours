import SwiftUI

extension SiteRepository {
    /// The people on your other crews who could join `siteID`'s, worked out
    /// by `CrewCandidates`. A year of site days is enough to say who you
    /// worked with last; anyone older still comes, after them, by name.
    ///
    /// Reads collapse duplicates, which writes, so this is called from a
    /// task or an action and never while a view is being drawn.
    func crewCandidates(for siteID: UUID, today: CalendarDate, calendar: Calendar) -> [CrewCandidate] {
        let everyone = sites(includeArchived: true).flatMap { self.crew(for: $0.id, includeHidden: true) }
        let days = siteDays(
            siteID: nil,
            in: CalendarDateRange(start: today.adding(days: -366, in: calendar), end: today)
        )
        return CrewCandidates.candidates(for: siteID, crew: everyone, siteDays: days)
    }

    /// Adds the chosen people to `siteID`'s crew, after whoever is on it.
    func addCrew(_ chosen: [CrewCandidate], to siteID: UUID) {
        var next = (crew(for: siteID, includeHidden: true).map(\.sortOrder).max() ?? -1) + 1
        for candidate in chosen {
            upsert(candidate.member(on: siteID, sortOrder: next))
            next += 1
        }
    }
}

/// One name to tick, with the sites they are on under it, and the tick on
/// the right (1.2, mockup Crew). The whole row is the button, so the target
/// is the row rather than the circle.
struct CrewCandidateRow: View {
    let candidate: CrewCandidate
    let isSelected: Bool
    /// "Jarunski Dvori · Solarka": where they are on a crew now.
    var detail: String? = nil
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Metrics.medium) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.name)
                        .foregroundStyle(.primary)
                    if let detail, !detail.isEmpty {
                        Text(verbatim: detail)
                            .font(.footnote)
                            .foregroundStyle(.hoursSecondaryText)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("crew-candidate")
    }
}

/// "Add from other sites", from a site's crew screen (1.2, mockup Crew):
/// tick the people — or Tick all — then Add N.
struct CrewPickerSheet: View {
    let candidates: [CrewCandidate]
    /// Each candidate's sites, by `CrewCandidate.id`.
    var siteNames: [String: [String]] = [:]
    let onAdd: ([CrewCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { candidate in
                        CrewCandidateRow(
                            candidate: candidate,
                            isSelected: chosen.contains(candidate.id),
                            detail: siteNames[candidate.id]?.joined(separator: " · ")
                        ) {
                            toggle(candidate)
                        }
                    }
                } header: {
                    HStack {
                        Text("From your other sites")
                        Spacer(minLength: Metrics.small)
                        Button(allChosen ? String(localized: "Untick all") : String(localized: "Tick all")) {
                            chosen = allChosen ? [] : Set(candidates.map(\.id))
                        }
                        .font(.footnote.weight(.semibold))
                        .textCase(nil)
                        .accessibilityIdentifier("crew-picker-tick-all")
                    }
                } footer: {
                    Text("Someone with the same name on two sites is one person on a merged sheet. Each site keeps its own crew, so they are added to this one as new names; their days on other sites stay where they are.")
                }
            }
            .navigationTitle("Add people")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen-crew-picker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("crew-picker-cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onAdd(candidates.filter { chosen.contains($0.id) })
                        dismiss()
                    } label: {
                        if chosen.isEmpty {
                            Text("Add")
                        } else {
                            Text(String(localized: "Add \(chosen.count)", comment: "Add from other sites: add the people ticked; the value is how many"))
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("crew-picker-add")
                }
            }
        }
    }

    private var allChosen: Bool {
        !candidates.isEmpty && chosen.count == candidates.count
    }

    private func toggle(_ candidate: CrewCandidate) {
        if chosen.contains(candidate.id) {
            chosen.remove(candidate.id)
        } else {
            chosen.insert(candidate.id)
        }
    }
}
