import SwiftUI

/// The words for floors in the app's language: what a site without its own
/// list offers (Ground, 1st floor, 2nd floor, Roof) and how "Add floors 1
/// to N" names each.
enum SiteFloorNames {
    static var ground: String { String(localized: "Ground", comment: "A building's ground floor, as a chip on a new defect") }
    static var roof: String { String(localized: "Roof", comment: "A building's roof, as a chip on a new defect") }

    /// "1st floor", "1. OG", "1. kat".
    static func numbered(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        formatter.locale = Locale.current
        let boxed = NSNumber(value: number)
        let ordinal = formatter.string(from: boxed) ?? String(number)
        return String(localized: "\(ordinal) floor", comment: "A floor of a building; the value is an ordinal number such as 1st or 1.")
    }

    static var defaults: [String] {
        [ground, numbered(1), numbered(2), roof]
    }
}

/// A site's floors (site settings › Floors, 1.3): the list a defect's floor
/// is picked from, in order from the bottom, and the order the defects are
/// grouped in. Reorder, delete, add one, or "Add floors 1 to N" at once.
struct SiteFloorsScreen: View {
    @Binding var floors: [String]?
    let isReadOnly: Bool

    @State private var newFloor = ""
    @State private var upTo = 6
    @FocusState private var fieldFocused: Bool

    var body: some View {
        List {
            Section {
                ForEach(Array(list.enumerated()), id: \.offset) { index, floor in
                    Text(verbatim: floor)
                        .accessibilityIdentifier("site-floors-row-\(index)")
                }
                .onMove { from, to in
                    var next = list
                    next.move(fromOffsets: from, toOffset: to)
                    floors = next
                }
                .onDelete { offsets in
                    var next = list
                    next.remove(atOffsets: offsets)
                    floors = next
                }
                .deleteDisabled(isReadOnly)
                .moveDisabled(isReadOnly)
                if !isReadOnly {
                    HStack(spacing: Metrics.small) {
                        TextField(String(localized: "New floor, e.g. Basement"), text: $newFloor)
                            .focused($fieldFocused)
                            .submitLabel(.done)
                            .onSubmit(addFloor)
                            .accessibilityLabel(String(localized: "New floor"))
                            .accessibilityIdentifier("site-floors-field")
                        Button("Add", action: addFloor)
                            .fontWeight(.semibold)
                            .disabled(DefectList.tidy(newFloor).isEmpty)
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityIdentifier("site-floors-add")
                    }
                }
            } footer: {
                Text("From the bottom up. Defects are grouped in this order.")
            }

            if !isReadOnly {
                Section {
                    Stepper(value: $upTo, in: 1...60) {
                        Text(String(localized: "Floors 1 to \(upTo)", comment: "Site floors: how many numbered floors to add"))
                            .monospacedDigit()
                    }
                    .accessibilityIdentifier("site-floors-count")
                    Button {
                        floors = SiteFloors.addingNumbered(
                            upTo: upTo,
                            to: list,
                            name: SiteFloorNames.numbered,
                            above: [SiteFloorNames.roof]
                        )
                    } label: {
                        Text(String(localized: "Add floors 1 to \(upTo)", comment: "Site floors: adds the numbered floors at once"))
                    }
                    .accessibilityIdentifier("site-floors-add-numbered")
                } footer: {
                    Text("Added under the roof; floors already there are left as they are.")
                }
            }
        }
        .environment(\.editMode, .constant(isReadOnly ? .inactive : .active))
        .accessibilityIdentifier("screen-site-floors")
        .navigationTitle("Floors")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: [String] {
        floors ?? SiteFloorNames.defaults
    }

    private func addFloor() {
        let floor = DefectList.tidy(newFloor)
        guard !floor.isEmpty else { return }
        floors = SiteFloors.normalised(list + [floor])
        newFloor = ""
    }
}
