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

    /// What the UI tests tap. `export-target-site` is the crew sheet's
    /// segment, as it was when the second segment was the site.
    var identifier: String {
        switch self {
        case .myHours: return "export-target-personal"
        case .crewSheet: return "export-target-site"
        case .onePerson: return "export-target-person"
        }
    }
}

/// WHAT: My hours · Crew sheet · One person, at the top of the export screen
/// (Export board, phones 1 and 2).
///
/// A segmented control drawn by hand rather than a segmented `Picker`, so
/// each segment is a 44-point button with an identifier of its own.
struct ExportTargetPicker: View {
    @Binding var mode: ExportMode

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ExportMode.allCases) { option in
                let isSelected = option == mode
                Button {
                    mode = option
                } label: {
                    Text(option.title)
                        .font(.subheadline.weight(isSelected ? .bold : .regular))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                                    .fill(Color.hoursSurface)
                                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier(option.identifier)
            }
        }
        .padding(3)
        .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius + 2, style: .continuous))
    }
}
