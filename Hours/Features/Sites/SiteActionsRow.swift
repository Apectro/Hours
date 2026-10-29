import SwiftUI

/// What a site has, on view under its name (1.2, mockup SiteHome): the
/// address, then four buttons of one height — Crew, Diary, Sheet and Extra
/// work — each with a one-line count, so nothing about a site hides in a
/// "…" menu. At accessibility text sizes they go two by two.
struct SiteActionsRow: View {
    let address: String
    let crewCount: Int
    /// Days with a diary this month; nil when the site's settings leave the
    /// diary out and there is none, so the button is not offered.
    let diaryCount: Int?
    let sheetMonth: String
    let openExtraWork: Int
    let onCrew: () -> Void
    let onDiary: () -> Void
    let onSheet: () -> Void
    let onExtraWork: () -> Void

    // Not private: a private property would make the memberwise initializer
    // the site screen calls private too.
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            if !address.isEmpty {
                Text(verbatim: SiteAddress.singleLine(address))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("site-address-line")
            }
            if dynamicTypeSize.isAccessibilitySize {
                Grid(horizontalSpacing: Metrics.small, verticalSpacing: Metrics.small) {
                    let all = buttons
                    ForEach(Array(stride(from: 0, to: all.count, by: 2)), id: \.self) { start in
                        GridRow {
                            all[start]
                            if start + 1 < all.count { all[start + 1] } else { Color.clear }
                        }
                    }
                }
            } else {
                HStack(spacing: Metrics.small) {
                    ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in button }
                }
            }
        }
    }

    private var buttons: [ActionButton] {
        var list = [
            ActionButton(
                title: String(localized: "Crew"),
                detail: String(inflected: "^[\(crewCount) person](inflect: true)"),
                systemImage: "person.2",
                identifier: "site-crew",
                action: onCrew
            ),
        ]
        if let diaryCount {
            list.append(ActionButton(
                title: String(localized: "Diary"),
                detail: diaryCount == 0
                    ? String(localized: "None this month")
                    : String(localized: "\(diaryCount) this month", comment: "Site button: how many days this month have a diary"),
                systemImage: "text.book.closed",
                identifier: "site-diary-list",
                action: onDiary
            ))
        }
        list.append(ActionButton(
            title: String(localized: "Sheet"),
            detail: sheetMonth,
            systemImage: "doc.richtext",
            identifier: "site-export",
            action: onSheet
        ))
        list.append(ActionButton(
            title: String(localized: "Extra work"),
            detail: openExtraWork == 0
                ? String(localized: "None open")
                : String(localized: "\(openExtraWork) open", comment: "Site button: how many extra-work jobs are not finished or not sent yet"),
            systemImage: "hammer",
            identifier: "site-extra-work-report",
            action: onExtraWork
        ))
        return list
    }
}

/// One of the site's four buttons: a symbol, the name and a count, all of
/// it the button.
private struct ActionButton: View {
    let title: String
    let detail: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Metrics.tiny) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.vertical, Metrics.small)
            .padding(.horizontal, Metrics.tiny)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        // A Button already reads its texts as one label: "Crew, 5 people".
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
