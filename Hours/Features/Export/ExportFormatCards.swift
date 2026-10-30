import SwiftUI

/// PDF and Excel, the two big buttons side by side at the bottom of the
/// export screen (design v2, More board phone 1). PDF is the primary action;
/// Excel the secondary one beside it.
///
/// Each one writes the file in its format and opens it, ready to send. A CSV
/// is reached from This sheet › CSV file, which calls the same `onChoose`.
struct ExportFormatCards: View {
    /// Nothing to send (an empty month), or still reading.
    let isEnabled: Bool
    /// Pro is needed for the file: a lock on each button. The sheet still
    /// opens to be looked at; its Send… opens the paywall.
    var isLocked = false
    let onChoose: (ExportFormat) -> Void

    var body: some View {
        HStack(spacing: Metrics.medium) {
            button(.pdf, kind: .primary)
            button(.xlsx, kind: .secondary)
        }
        .disabled(!isEnabled)
    }

    private func button(_ format: ExportFormat, kind: BigActionKind) -> some View {
        Button {
            onChoose(format)
        } label: {
            HStack(spacing: Metrics.small) {
                if isLocked {
                    Image(systemName: "lock.fill")
                        .accessibilityHidden(true)
                }
                // A product name, the same in every language.
                Text(verbatim: format.title)
            }
        }
        .buttonStyle(.bigAction(kind))
        .accessibilityHint(Text(format.purpose))
        .accessibilityIdentifier("export-format-\(format.rawValue)")
    }
}
