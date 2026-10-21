import SwiftUI

/// Whose hours the export is of: yours, or one site's crew.
enum ExportTarget: Hashable {
    case personal
    case site(UUID)

    var siteID: UUID? {
        if case let .site(id) = self { return id }
        return nil
    }
}

/// "My hours" beside the sites, at the top of the export screen.
///
/// With one site it is two segments. With more, the second segment is a
/// menu of them, showing whichever is chosen — a segment per site stops
/// fitting on a phone at three.
struct ExportTargetPicker: View {
    @Binding var target: ExportTarget
    let sites: [Site]

    var body: some View {
        HStack(spacing: 2) {
            segment(isSelected: target == .personal) {
                Button {
                    target = .personal
                } label: {
                    Text("My hours").frame(maxWidth: .infinity, minHeight: 44)
                }
                .accessibilityIdentifier("export-target-personal")
            }
            segment(isSelected: target != .personal) {
                if sites.count == 1, let site = sites.first {
                    Button {
                        target = .site(site.id)
                    } label: {
                        Text(verbatim: site.name)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .accessibilityIdentifier("export-target-site")
                } else {
                    siteMenu
                }
            }
        }
        .padding(2)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.smallCornerRadius))
        .buttonStyle(.plain)
    }

    private var siteMenu: some View {
        Menu {
            ForEach(sites) { site in
                Button {
                    target = .site(site.id)
                } label: {
                    if target == .site(site.id) {
                        Label(site.name, systemImage: "checkmark")
                    } else {
                        Text(verbatim: site.name)
                    }
                }
            }
        } label: {
            HStack(spacing: Metrics.tiny) {
                Text(verbatim: selectedSiteName ?? String(localized: "Sites"))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityIdentifier("export-target-site")
    }

    private var selectedSiteName: String? {
        guard let id = target.siteID else { return nil }
        return sites.first { $0.id == id }?.name
    }

    /// One segment's background: raised when it is the chosen one.
    private func segment<Content: View>(isSelected: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Metrics.smallCornerRadius - 2)
                        .fill(Color(uiColor: .tertiarySystemFill))
                }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
