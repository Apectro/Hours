import SwiftUI
import UIKit

/// Send the list (Camera board, phone 21): the PDF as it will be sent —
/// "<site> · Defects", the address, the date and how many are open, then a
/// numbered row per defect with its marked photo — and "Only open" (on).
/// Send shares the PDF; Send as message the same lines as text, without
/// the photos. In the export language.
struct DefectsSendSheet: View {
    let site: Site
    let defects: [Defect]
    let thumbnails: [UUID: DefectPhoto]

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var onlyOpen = true
    @State private var pdfData: Data?
    @State private var pageImage: UIImage?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let pageImage {
                        Image(uiImage: pageImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .border(Color(uiColor: .separator), width: 0.5)
                            .accessibilityLabel(String(localized: "The first page of the PDF"))
                            .accessibilityIdentifier("defects-send-page")
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                } footer: {
                    Text("Each photo keeps its marks. They are drawn over the photo, so the original is never changed.")
                }
                Section {
                    Toggle("Only open", isOn: $onlyOpen)
                        .accessibilityIdentifier("defects-send-only-open")
                }
                Section("As a message") {
                    messagePreview
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("screen-defects-send")
            .navigationTitle("Send the list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Close"))
                    .accessibilityIdentifier("defects-send-close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                buttons
            }
            .task(id: onlyOpen) { render() }
            .alert("The list couldn't be shared", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - The document

    private var document: DefectsDocument {
        let settings = settingsStore.settings
        let setup = settings.siteSetup(for: site.id)
        return DefectsDocument(
            siteName: site.name,
            address: SiteAddress.singleLine(site.address),
            date: CalendarDate.today(in: settingsStore.workCalendar),
            defects: defects,
            floors: setup.floorList(defaults: SiteFloorNames.defaults),
            onlyOpen: onlyOpen,
            showsAssignee: setup.assignsDefects,
            ownerName: settings.export.ownerName,
            language: settings.export.language,
            calendar: settingsStore.workCalendar
        )
    }

    private var messagePreview: some View {
        let text = document.text
        return Text(verbatim: text)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .accessibilityLabel(Text(verbatim: text))
            .accessibilityIdentifier("defects-send-text")
    }

    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.small))
        return layout {
            Button(action: sendPDF) {
                Text("Send")
            }
            .buttonStyle(.bigAction(.primary))
            .accessibilityIdentifier("defects-send-pdf")

            Button(action: sendMessage) {
                Text("Send as message")
            }
            .buttonStyle(.bigAction(.secondary))
            .accessibilityIdentifier("defects-send-message")
        }
        .disabled(document.rows.isEmpty)
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color.hoursCanvas)
    }

    // MARK: - Sending

    private func render() {
        let data = DefectsPDFRenderer.data(for: document, photos: thumbnails)
        pdfData = data
        pageImage = ExportPagePreview.thumbnail(of: data)
    }

    private func sendPDF() {
        let document = self.document
        do {
            let url = try ExportFileFactory.write(
                data: pdfData ?? DefectsPDFRenderer.data(for: document, photos: thumbnails),
                fileExtension: "pdf",
                baseName: document.fileName
            )
            ShareSheetPresenter.present(url, completion: finished)
        } catch {
            failed = true
        }
    }

    private func sendMessage() {
        ShareSheetPresenter.present(text: document.text, completion: finished)
    }

    private func finished(_ outcome: ExtraWorkShareOutcome) {
        if case .failed = outcome { failed = true }
    }
}

/// The defects list on A4 pages, in the look of the app's other exports:
/// the orange eyebrow, "<site> · Defects", "address · date · N open", then
/// a row per defect — its marked photo on the left, "1. Socket loose",
/// where, and "Fixes: Ivan · since 3 Nov" or "fixed 4 Nov" — over thin
/// rules, running on over as many pages as it needs.
enum DefectsPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)

    private static let margin: CGFloat = 40
    private static let photoSide: CGFloat = 72
    private static let rowPadding: CGFloat = 8
    private static let titleFont = UIFont.systemFont(ofSize: 11.5, weight: .semibold)
    private static let lineFont = UIFont.systemFont(ofSize: 10)

    static func data(for document: DefectsDocument, photos: [UUID: DefectPhoto]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextCreator as String: "Zeitkonto"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let width = pageSize.width - margin * 2
        let bottom = pageSize.height - margin - 24
        let images = photos.compactMapValues { photo -> (UIImage, [DefectMark])? in
            guard let small = DiaryPhotoProcessor.thumbnailPrintJPEG(from: photo.jpegData),
                  let image = DiaryPhotoProcessor.printableImage(from: small) else { return nil }
            return (image, photo.marks)
        }

        return renderer.pdfData { context in
            var page = 1
            context.beginPage()
            var y = drawHeader(document, at: margin, width: width)
            for row in document.rows {
                let textWidth = width - photoSide - 12
                let detailHeight = height(of: row.detail, width: textWidth, font: lineFont)
                let textHeight = titleFont.lineHeight + 3 + (row.whereLine.isEmpty ? 0 : lineFont.lineHeight + 2) + detailHeight
                let rowHeight = max(photoSide, textHeight) + rowPadding * 2
                if y + rowHeight > bottom {
                    drawFooter(page: page, language: document.language)
                    context.beginPage()
                    page += 1
                    y = margin
                }
                let photoFrame = CGRect(x: margin, y: y + rowPadding, width: photoSide, height: photoSide)
                if let printed = images[row.defectID] {
                    drawPhoto(printed.0, marks: printed.1, in: photoFrame, context: context.cgContext)
                } else {
                    PDFReportStyle.tile.setFill()
                    UIBezierPath(roundedRect: photoFrame, cornerRadius: 6).fill()
                }
                var textY = y + rowPadding
                let textX = margin + photoSide + 12
                PDFReportStyle.draw(row.title, in: CGRect(x: textX, y: textY, width: textWidth, height: titleFont.lineHeight + 2),
                                    font: titleFont, color: PDFReportStyle.ink)
                textY += titleFont.lineHeight + 3
                if !row.whereLine.isEmpty {
                    PDFReportStyle.draw(row.whereLine, in: CGRect(x: textX, y: textY, width: textWidth, height: lineFont.lineHeight + 1),
                                        font: lineFont, color: PDFReportStyle.ink)
                    textY += lineFont.lineHeight + 2
                }
                PDFReportStyle.drawWrapping(
                    row.detail,
                    in: CGRect(x: textX, y: textY, width: textWidth, height: detailHeight + 1),
                    font: lineFont,
                    color: row.isFixed ? PDFReportStyle.positive : PDFReportStyle.secondary
                )
                y += rowHeight
                PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.5, color: PDFReportStyle.rule)
            }
            drawFooter(page: page, language: document.language)
        }
    }

    /// The photo cropped to its square, its marks over it, clipped there.
    static func drawPhoto(_ image: UIImage, marks: [DefectMark], in frame: CGRect, context: CGContext) {
        context.saveGState()
        UIBezierPath(roundedRect: frame, cornerRadius: 6).addClip()
        let drawn = DefectMarkPainter.filled(image.size, in: frame)
        image.draw(in: drawn)
        DefectMarkPainter.draw(marks, in: drawn, context: context)
        context.restoreGState()
    }

    private static func drawHeader(_ document: DefectsDocument, at top: CGFloat, width: CGFloat) -> CGFloat {
        var y = top
        PDFReportStyle.draw(
            document.language(.defects).uppercased(with: document.language.locale),
            in: CGRect(x: margin, y: y, width: width, height: 12),
            font: PDFReportStyle.eyebrowFont,
            color: PDFReportStyle.accent,
            kern: 0.6
        )
        y += 16
        PDFReportStyle.draw(
            document.title,
            in: CGRect(x: margin, y: y, width: width, height: 30),
            font: PDFReportStyle.titleFont,
            color: PDFReportStyle.ink
        )
        y += 32
        PDFReportStyle.draw(
            document.subtitle,
            in: CGRect(x: margin, y: y, width: width, height: 14),
            font: PDFReportStyle.bylineFont,
            color: PDFReportStyle.secondary
        )
        y += 22
        PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.8, color: PDFReportStyle.faint)
        return y
    }

    private static func drawFooter(page: Int, language: ExportLanguage) {
        let pageText = [language(.page), String(page)].joined(separator: " ")
        PDFReportStyle.draw(
            ["Zeitkonto", pageText].joined(separator: " · "),
            in: CGRect(x: margin, y: pageSize.height - margin, width: pageSize.width - margin * 2, height: 12),
            font: PDFReportStyle.footerFont,
            color: PDFReportStyle.faint
        )
    }

    private static func height(of text: String, width: CGFloat, font: UIFont) -> CGFloat {
        guard !text.isEmpty, width > 0 else { return font.lineHeight }
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.height)
    }
}
