import SwiftUI

/// What the export is of: your own hours, a crew sheet for one or more
/// sites, or one person's own sheet.
enum ExportMode: String, CaseIterable, Hashable, Identifiable {
    case myHours
    case crewSheet
    case onePerson

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .myHours: return "My hours"
        case .crewSheet: return "Crew sheet"
        case .onePerson: return "One person"
        }
    }

}

/// My hours · Crew sheet · One person, the system's segmented control at
/// the top of the export screen (design v2, More board phone 1).
struct ExportTargetPicker: View {
    @Binding var mode: ExportMode

    var body: some View {
        Picker("What", selection: $mode) {
            ForEach(ExportMode.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityIdentifier("export-target")
    }
}
