import SwiftUI

/// Who gets the field allowance today (1.2 redesign, mockup 07 "Field
/// allowance · 4 people ›"): everyone ticked present, each with a switch.
/// Each switch writes at once through the site screen, as the row's menu
/// used to; Done only closes.
struct SiteAllowanceSheet: View {
    let people: [PersonReference]
    let onToggle: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var given: Set<UUID>

    init(people: [PersonReference], given: Set<UUID>, onToggle: @escaping (UUID) -> Void) {
        self.people = people
        self.onToggle = onToggle
        _given = State(initialValue: given)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if people.isEmpty {
                        Text("Nobody is ticked for this day yet.")
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    ForEach(people) { person in
                        Toggle(isOn: binding(for: person.id)) {
                            Text(verbatim: person.name)
                        }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("site-allowance-\(SiteDayStyle.key(person))")
                    }
                } footer: {
                    Text("Who gets the field allowance for this day. Only people ticked here are listed.")
                }
            }
            .navigationTitle("Field allowance")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("site-allowance-done")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func binding(for memberID: UUID) -> Binding<Bool> {
        Binding(
            get: { given.contains(memberID) },
            set: { isOn in
                guard isOn != given.contains(memberID) else { return }
                if isOn { given.insert(memberID) } else { given.remove(memberID) }
                onToggle(memberID)
            }
        )
    }
}
