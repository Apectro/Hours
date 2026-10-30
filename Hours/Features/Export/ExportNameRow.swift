import SwiftUI

/// "Name on the sheet", with the name, as a row that opens the editor.
///
/// The same `ExportPreferences.ownerName` Settings › Sheets edits: one name,
/// whichever screen it was typed on.
struct ExportNameRow: View {
    let name: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.small) {
                Text("Name on the sheet")
                    .foregroundStyle(.primary)
                Spacer(minLength: Metrics.small)
                if name.isEmpty {
                    Text("Add your name")
                        .foregroundStyle(Color.accentColor)
                } else {
                    Text(verbatim: name)
                        .foregroundStyle(.hoursSecondaryText)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("export-owner-name")
    }
}
