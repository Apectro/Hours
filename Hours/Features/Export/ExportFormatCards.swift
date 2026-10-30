import SwiftUI

/// PDF and Excel, the two big buttons side by side at the bottom of the
/// export screen (Export board, phones 1 and 2). PDF is the primary action;
/// Excel is green, as on the board.
///
/// Each one writes the file in its format and opens it, ready to send. A CSV
/// is reached from This sheet › CSV file, which calls the same `onChoose`.
struct ExportFormatCards: View {
    /// Nothing to send (an empty month), or still reading.
    let isEnabled: Bool
    /// Pro is needed for the file: a lock on each button, which then opens
    /// the paywall.
    var isLocked = false
    let onChoose: (ExportFormat) -> Void

    var body: some View {
        HStack(spacing: Metrics.medium) {
            button(.pdf, kind: .primary)
            button(.xlsx, kind: .positive)
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
