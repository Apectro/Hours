import SwiftUI

/// Where the share button stands, decided by the screen and drawn here.
enum ExportShareState: Equatable {
    /// Pro is needed to write the file; the button opens the paywall.
    case locked
    /// No name yet: the button asks for one first, once.
    case needsName
    case ready(URL)
    /// Several files for one share: a site's sheets, one per person.
    case readyFiles([URL])
    case preparing
    case failed(String)
    /// Nothing in the range or the month to share.
    case empty
}

/// The big "Share PDF" button, pinned under the form.
struct ExportShareBar: View {
    let format: ExportFormat
    let state: ExportShareState
    let onLocked: () -> Void
    let onNeedsName: () -> Void
    /// The file and the share sheet, which says how it ended.
    let onShare: (URL) -> Void
    /// The files of `readyFiles`, for the same share sheet.
    var onShareFiles: ([URL]) -> Void = { _ in }

    var body: some View {
        VStack(spacing: Metrics.small) {
            if case let .failed(message) = state {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(Color.hoursNegative)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            button
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("export-share")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.top, Metrics.small)
        .padding(.bottom, Metrics.small)
        .background(.bar)
    }

    @ViewBuilder
    private var button: some View {
        switch state {
        case let .ready(url):
            // The share sheet presented by hand rather than a `ShareLink`,
            // which does not say whether anything was shared.
            Button { onShare(url) } label: {
                label(systemImage: "square.and.arrow.up")
            }
        case let .readyFiles(urls):
            Button { onShareFiles(urls) } label: {
                label(systemImage: "square.and.arrow.up")
            }
        case .locked:
            // Stopped at the file, not at the door: everything above it is
            // what the person needs in order to know what they would buy.
            Button(action: onLocked) {
                label(systemImage: "lock.fill")
            }
            .accessibilityHint(Text(verbatim: "Zeitkonto Pro"))
        case .needsName:
            Button(action: onNeedsName) {
                label(systemImage: "square.and.arrow.up")
            }
        case .preparing:
            Button {} label: {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 24)
            }
            .disabled(true)
        case .failed, .empty:
            Button {} label: {
                label(systemImage: "square.and.arrow.up")
            }
            .disabled(true)
        }
    }

    private func label(systemImage: String) -> some View {
        Label(
            String(localized: "Share \(format.title)", comment: "The share button; the value is PDF, Excel or CSV"),
            systemImage: systemImage
        )
        .font(.headline)
        .frame(maxWidth: .infinity, minHeight: 24)
    }
}
