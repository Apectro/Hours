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

/// One name to tick. The whole row is the button, so the target is the row
/// rather than the circle.
struct CrewCandidateRow: View {
    let candidate: CrewCandidate
    let isSelected: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: Metrics.medium) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
                Text(candidate.name)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("crew-candidate")
    }
}

/// "Add from other sites", from a site's crew screen: tick the people, Add.
struct CrewPickerSheet: View {
    let candidates: [CrewCandidate]
    let onAdd: ([CrewCandidate]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(candidates) { candidate in
                        CrewCandidateRow(candidate: candidate, isSelected: chosen.contains(candidate.id)) {
                            toggle(candidate)
                        }
                    }
                } footer: {
                    Text("Each site keeps its own crew, so they are added to this one as new names. Their days on other sites stay where they are.")
                }
            }
            .navigationTitle("Add from other sites")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen-crew-picker")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(candidates.filter { chosen.contains($0.id) })
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(chosen.isEmpty)
                    .accessibilityIdentifier("crew-picker-add")
                }
            }
        }
    }

    private func toggle(_ candidate: CrewCandidate) {
        if chosen.contains(candidate.id) {
            chosen.remove(candidate.id)
        } else {
            chosen.insert(candidate.id)
        }
    }
}
