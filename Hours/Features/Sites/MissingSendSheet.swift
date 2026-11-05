import SwiftUI
import UIKit

/// Send the list (Missing board, phone 8): the message as it will be sent,
/// in the export language — "Trg Pravde Zagreb · missing, 4 Nov", a line per
/// item, your name — then "Barcodes in the list" and "Mark them as ordered"
/// (on), and two buttons: Send as message (the share sheet with the text)
/// and PDF (the same list on one page, with the codes, for the warehouse).
///
/// The needed items move to Ordered only once the share sheet says
/// something was sent, as extra work is marked sent; a cancelled share
/// changes nothing.
struct MissingSendSheet: View {
    let site: Site
    let items: [MissingItem]
    let catalog: [ExtraWorkCatalogItem]
    let onSent: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var includesCodes = false
    @State private var marksOrdered = true
    @State private var failed = false

    var body: some View {
        NavigationStack {
            List {
                Section("As a message") {
                    messagePreview
                }
                Section {
                    Toggle("Barcodes in the list", isOn: $includesCodes)
                        .accessibilityIdentifier("missing-send-codes")
                    if sent.contains(where: { $0.state == .needed }) {
                        Toggle("Mark them as ordered", isOn: $marksOrdered)
                            .accessibilityIdentifier("missing-send-mark")
                    }
                } footer: {
                    Text("The message goes through WhatsApp, Viber, Mail or any app you choose. The PDF is the same list with the codes, for the warehouse.")
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("screen-missing-send")
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
                    .accessibilityIdentifier("missing-send-close")
                }
            }
            .safeAreaInset(edge: .bottom) {
                buttons
            }
            .alert("The list couldn't be shared", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: - The message

    private var sent: [MissingItem] {
        MissingList.toSend(items)
    }

    private func message(withCodes: Bool) -> MissingMessage {
        let settings = settingsStore.settings
        return MissingMessage(
            siteName: site.name,
            date: CalendarDate.today(in: settingsStore.workCalendar),
            items: sent,
            catalog: catalog,
            includesCodes: withCodes,
            ownerName: settings.export.ownerName,
            language: settings.export.language,
            decimalSeparator: settings.export.decimalSeparator.character,
            calendar: settingsStore.workCalendar
        )
    }

    /// The heading in bold, a line per item, the name in grey: the text
    /// exactly as it goes, read out as one by VoiceOver.
    private var messagePreview: some View {
        let text = message(withCodes: includesCodes).text
        let lines = text.components(separatedBy: "\n")
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index == 0 {
                    Text(verbatim: line)
                        .font(.body.weight(.semibold))
                } else if line.isEmpty {
                    Spacer().frame(height: Metrics.tiny)
                } else if index == lines.count - 1 && lines.count >= 3 && lines[index - 1].isEmpty {
                    Text(verbatim: line)
                        .foregroundStyle(.hoursSecondaryText)
                } else {
                    Text(verbatim: line)
                        .monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Metrics.tiny)
        .textSelection(.enabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: text))
        .accessibilityIdentifier("missing-send-text")
    }

    private var buttons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.small))
        return layout {
            Button(action: sendMessage) {
                Text("Send as message")
            }
            .buttonStyle(.bigAction(.primary))
            .accessibilityIdentifier("missing-send-message")

            Button(action: sendPDF) {
                Text("PDF")
            }
            .buttonStyle(.bigAction(.secondary))
            .accessibilityIdentifier("missing-send-pdf")
        }
        .disabled(sent.isEmpty)
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color.hoursCanvas)
    }

    // MARK: - Sending

    private func sendMessage() {
        ShareSheetPresenter.present(text: message(withCodes: includesCodes).text, completion: finished)
    }

    /// Always with the codes: it is the warehouse's copy.
    private func sendPDF() {
        let document = message(withCodes: true)
        do {
            let url = try ExportFileFactory.write(
                data: MissingPDFRenderer.data(for: document),
                fileExtension: "pdf",
                baseName: document.fileName
            )
            ShareSheetPresenter.present(url, completion: finished)
        } catch {
            failed = true
        }
    }

    private func finished(_ outcome: ExtraWorkShareOutcome) {
        switch outcome {
        case .completed:
            if marksOrdered {
                MissingRepository(context: modelContext).markOrdered(sent, siteID: site.id)
            }
            onSent()
            dismiss()
        case .cancelled:
            break
        case .failed:
            failed = true
        }
    }
}

/// The Missing list on one A4 page, in the look of the app's other exports:
/// the site, what it is and the date, who it is from, then
/// Quantity · Item · Code · Note over thin rules. A list too long for one
/// page carries on over the next.
enum MissingPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)

    private static let margin: CGFloat = 40
    private static let rowPadding: CGFloat = 6

    static func data(for message: MissingMessage) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: "\(message.title) — \(message.siteName)",
            kCGPDFContextCreator as String: "Zeitkonto"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let width = pageSize.width - margin * 2
        // Quantity, item, code, note.
        let columns: [CGFloat] = [width * 0.16, width * 0.38, width * 0.22, width * 0.24]
        let font = UIFont.systemFont(ofSize: 10.5)
        let bottom = pageSize.height - margin - 24

        return renderer.pdfData { context in
            var page = 1
            context.beginPage()
            var y = drawHeader(message, at: margin, width: width)
            y = drawHeadings(message.headings, columns: columns, at: y)
            for row in message.rows {
                let values = [row.quantity, row.name, row.code, row.note]
                let height = values.enumerated().map { index, value in
                    textHeight(value, width: columns[index] - rowPadding, font: font)
                }.max() ?? font.lineHeight
                let rowHeight = height + rowPadding * 2
                if y + rowHeight > bottom {
                    drawFooter(page: page, language: message.language)
                    context.beginPage()
                    page += 1
                    y = drawHeadings(message.headings, columns: columns, at: margin)
                }
                var x = margin
                for (index, value) in values.enumerated() {
                    let cellFont = index == 0 ? UIFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold) : font
                    PDFReportStyle.drawWrapping(
                        value,
                        in: CGRect(x: x, y: y + rowPadding, width: columns[index] - rowPadding, height: height + 1),
                        font: cellFont,
                        color: index == 3 ? PDFReportStyle.secondary : PDFReportStyle.ink
                    )
                    x += columns[index]
                }
                y += rowHeight
                PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.5, color: PDFReportStyle.rule)
            }
            drawFooter(page: page, language: message.language)
        }
    }

    /// The site as the title, "Missing material · 3 Nov 2026" under it and
    /// who it is from in grey: the report header's look, without orange
    /// capitals (polish, 2026-11).
    private static func drawHeader(_ message: MissingMessage, at top: CGFloat, width: CGFloat) -> CGFloat {
        var y = top
        PDFReportStyle.draw(
            message.siteName,
            in: CGRect(x: margin, y: y, width: width, height: 30),
            font: PDFReportStyle.titleFont,
            color: PDFReportStyle.ink
        )
        y += 32
        PDFReportStyle.draw(
            "\(message.title) · \(message.dateText)",
            in: CGRect(x: margin, y: y, width: width, height: 14),
            font: PDFReportStyle.headerKindFont,
            color: PDFReportStyle.ink
        )
        y += 16
        if !message.byline.isEmpty {
            PDFReportStyle.draw(
                message.byline,
                in: CGRect(x: margin, y: y, width: width, height: 14),
                font: PDFReportStyle.bylineFont,
                color: PDFReportStyle.secondary
            )
            y += 16
        }
        return y + 14
    }

    private static func drawHeadings(_ headings: [String], columns: [CGFloat], at top: CGFloat) -> CGFloat {
        var x = margin
        for (index, heading) in headings.enumerated() {
            PDFReportStyle.draw(
                heading,
                in: CGRect(x: x, y: top, width: columns[index] - rowPadding, height: 14),
                font: PDFReportStyle.headingFont,
                color: PDFReportStyle.secondary
            )
            x += columns[index]
        }
        let y = top + 16
        PDFReportStyle.line(
            from: CGPoint(x: margin, y: y),
            to: CGPoint(x: pageSize.width - margin, y: y),
            width: 0.8,
            color: PDFReportStyle.faint
        )
        return y
    }

    private static func drawFooter(page: Int, language: ExportLanguage) {
        let pageText = [language(.page), String(page)].joined(separator: " ")
        let text = ["Zeitkonto", pageText].joined(separator: " · ")
        PDFReportStyle.draw(
            text,
            in: CGRect(x: margin, y: pageSize.height - margin, width: pageSize.width - margin * 2, height: 12),
            font: PDFReportStyle.footerFont,
            color: PDFReportStyle.faint
        )
    }

    private static func textHeight(_ text: String, width: CGFloat, font: UIFont) -> CGFloat {
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
