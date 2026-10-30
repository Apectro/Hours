import StoreKit
import SwiftUI
import UIKit
import PDFKit

/// The first page of the PDF as it will be printed, and the way to read it
/// full size.
///
/// The real page rather than a table standing in for it: the PDF is a
/// document with a look, and the look is part of what is being checked
/// before it is sent.
struct ExportPagePreview: View {
    let image: UIImage?
    /// The sheet's title, read out after "First page of the PDF" (and how a
    /// UI test knows which sheet it is).
    var title: String = ""
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
        .accessibilityValue(Text(verbatim: title))
        .accessibilityHint(Text("Tap to open full size"))
        .accessibilityIdentifier("export-preview-page")
    }

    private var well: some View {
        ZStack {
            // The page is paper, white in both appearances, on a grey just
            // dark enough for its edge to show.
            RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemFill))
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .overlay {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5)
                    }
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                    .padding(Metrics.medium)
            } else {
                ProgressView()
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
    @State private var page = 1
    @State private var pageCount = 1

    var body: some View {
        NavigationStack {
            PDFDocumentView(data: data, page: $page, pageCount: $pageCount)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(Text(ExportReadySheet.pageTitle(page, of: pageCount)))
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

/// What the ready-to-send page shows and sends: the files written for one
/// format, and how to preview them.
struct ExportReadyItem: Identifiable {
    let id = UUID()
    let format: ExportFormat
    /// One file, or one per person for a crew's sheets.
    let files: [URL]
    /// The PDF's bytes, for the page view; nil for a workbook or a CSV.
    let pdfData: Data?
    /// The table a workbook or a CSV holds, for theirs.
    let table: ReportTable?
    /// A line under the page, such as whose sheet is shown when there is
    /// one per person.
    var note: String?
    /// The month to offer closing once the file has gone out
    /// (`ExportCloseOffer`).
    var closeMonth: YearMonth?
}

/// Ready to send (Export board, phone 4): the file as it will arrive, with
/// Send… and Save to Files under it, and once it has gone out, the offer to
/// close the month it covers so it cannot change by accident.
struct ExportReadySheet: View {
    let item: ExportReadyItem
    /// After a share or a save went through.
    var onSent: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(SettingsStore.self) private var settingsStore

    @State private var page = 1
    @State private var pageCount = 1
    @State private var sent = false
    @State private var closed = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(title))
                .navigationBarTitleDisplayMode(.inline)
                .accessibilityIdentifier("screen-export-ready")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                            .accessibilityIdentifier("export-full-page-done")
                    }
                }
                .safeAreaInset(edge: .bottom) { bar }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let data = item.pdfData {
            PDFDocumentView(data: data, page: $page, pageCount: $pageCount)
                .ignoresSafeArea(edges: .bottom)
        } else if let table = item.table {
            ScrollView {
                ExportPreviewTable(table: table, rowLimit: table.rows.count)
                    .padding(.vertical, Metrics.medium)
            }
            .background(Color.hoursCanvas)
        } else {
            Color.hoursCanvas
        }
    }

    private var title: String {
        if item.pdfData != nil { return Self.pageTitle(page, of: pageCount) }
        return item.files.first?.lastPathComponent ?? item.format.title
    }

    /// "Page 1 of 2".
    static func pageTitle(_ page: Int, of count: Int) -> String {
        String(
            localized: "Page \(page) of \(count)",
            comment: "Export: the full-page preview's title; the values are the page shown and how many there are"
        )
    }

    private var bar: some View {
        VStack(spacing: Metrics.small) {
            if let note = item.note {
                Text(verbatim: note)
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Metrics.medium) {
                Button {
                    ShareSheetPresenter.present(item.files) { outcome in
                        guard outcome == .completed else { return }
                        didSend()
                        ReviewPromptStore.askIfDue(requestReview)
                    }
                } label: {
                    Label("Send…", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("export-share")

                Button {
                    FilesExportPresenter.present(item.files) { saved in
                        if saved { didSend() }
                    }
                } label: {
                    Label("Save to Files", systemImage: "folder")
                }
                .buttonStyle(.bigAction(.secondary))
                .accessibilityIdentifier("export-save-files")
            }
            .disabled(item.files.isEmpty)
            if let month = closeOffer {
                closeLine(month)
            }
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(.bar)
    }

    /// The month still to close: offered after the file went out, while it
    /// is open.
    private var closeOffer: YearMonth? {
        guard sent, let month = item.closeMonth else { return nil }
        if closed { return month }
        return settingsStore.settings.monthLock.isLocked(month) ? nil : month
    }

    @ViewBuilder
    private func closeLine(_ month: YearMonth) -> some View {
        let name = settingsStore.dateFormatting.monthTitle(month)
        if closed {
            Label {
                Text(String(
                    localized: "\(name) is closed. Reopen it from the calendar if something was missed.",
                    comment: "Export, after closing the month just sent; the value is a month and year"
                ))
            } icon: {
                Image(systemName: "lock.fill")
                    .foregroundStyle(Color.hoursDone)
            }
            .font(.footnote)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Metrics.tiny) {
                Text(String(
                    localized: "Close \(name) so it can't change by accident?",
                    comment: "Export, after the sheet was sent; the value is a month and year"
                ))
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
                Button {
                    settingsStore.update { $0.monthLock.lock(month) }
                    closed = true
                } label: {
                    Label(
                        String(localized: "Close \(name)", comment: "Button; the value is a month and year"),
                        systemImage: "lock"
                    )
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                }
                .accessibilityIdentifier("export-close-month")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func didSend() {
        withAnimation(.snappy(duration: 0.25)) { sent = true }
        onSent()
    }
}

/// PDFKit's own viewer, which pages, zooms and scrolls the way the system's
/// does everywhere else, and says which page is showing.
private struct PDFDocumentView: UIViewRepresentable {
    let data: Data
    @Binding var page: Int
    @Binding var pageCount: Int

    func makeCoordinator() -> Coordinator { Coordinator(page: $page) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .secondarySystemBackground
        let document = PDFDocument(data: data)
        view.document = document
        let count = max(document?.pageCount ?? 1, 1)
        DispatchQueue.main.async { pageCount = count }
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {}

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject {
        var page: Binding<Int>

        init(page: Binding<Int>) {
            self.page = page
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = notification.object as? PDFView,
                  let current = view.currentPage,
                  let index = view.document?.index(for: current) else { return }
            page.wrappedValue = index + 1
        }
    }
}

/// Save to Files: the system's folder picker, copying the files where the
/// person chooses, with word of whether they were saved.
@MainActor
enum FilesExportPresenter {
    /// Held while the picker is up: its delegate is weak.
    private static var delegate: Delegate?

    static func present(_ urls: [URL], completion: @escaping (Bool) -> Void) {
        guard !urls.isEmpty, let presenter = frontMostController() else {
            completion(false)
            return
        }
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        let delegate = Delegate { saved in
            completion(saved)
            FilesExportPresenter.delegate = nil
        }
        self.delegate = delegate
        picker.delegate = delegate
        presenter.present(picker, animated: true)
    }

    @MainActor
    private final class Delegate: NSObject, UIDocumentPickerDelegate {
        let finished: (Bool) -> Void

        init(finished: @escaping (Bool) -> Void) {
            self.finished = finished
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            finished(true)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            finished(false)
        }
    }

    /// The controller on top of whatever is showing, a sheet over a sheet
    /// included, as the share sheet finds it.
    private static func frontMostController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }
}
