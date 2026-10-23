import SwiftUI
import UIKit
import PDFKit

/// The first page of the PDF as it will be printed, on a dark well, and the
/// way to read it full size.
///
/// The real page rather than a table standing in for it: the PDF is a
/// document with a look, and the look is part of what is being checked
/// before it is sent.
struct ExportPagePreview: View {
    let image: UIImage?
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            ZStack(alignment: .bottomTrailing) {
                well
                Text("Tap to open full size")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Metrics.small)
                    .padding(.vertical, Metrics.tiny)
                    .background(Color.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                    .padding(Metrics.small)
            }
        }
        .buttonStyle(.plain)
        .disabled(image == nil)
        .accessibilityLabel(Text("First page of the PDF"))
        .accessibilityHint(Text("Tap to open full size"))
        .accessibilityIdentifier("export-preview-page")
    }

    private var well: some View {
        ZStack {
            // Dark in both appearances: the page is paper and reads as paper
            // against it.
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .fill(Color(white: 0.17))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .shadow(color: .black.opacity(0.45), radius: 9, y: 6)
                    .padding(Metrics.large)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1.3, contentMode: .fit)
    }

    /// The first page drawn into an image `width` points wide.
    static func thumbnail(of data: Data, width: CGFloat = 640) -> UIImage? {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return nil }
        let size = CGSize(width: width, height: bounds.height * width / bounds.width)
        return page.thumbnail(of: size, for: .mediaBox)
    }
}

/// The whole PDF, full size, to read before sharing it.
struct ExportFullPageSheet: View {
    let data: Data

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            PDFDocumentView(data: data)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("export-full-page-done")
                    }
                }
        }
    }
}

/// PDFKit's own viewer, which pages, zooms and scrolls the way the system's
/// does everywhere else.
private struct PDFDocumentView: UIViewRepresentable {
    let data: Data

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        view.document = PDFDocument(data: data)
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}
}
