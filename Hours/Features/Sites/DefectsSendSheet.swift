import SwiftUI
import UIKit

/// Send the list (Camera board, phone 21): the PDF's first page as it will
/// be sent — "<site> · Defects", the figures and the table by floor, with
/// half a page per open defect after it (`DefectsPDFRenderer`) — and "Only
/// open" (on), which leaves the fixed lines out.
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

/// The defects list on A4 pages (Polish pages 22–24). Page 1 is the whole
/// list: "<site> · Defects", the address, the day and your name, four
/// figures, and a table grouped by the site's floors in which a fixed
/// defect is one line. From the page after the table each open defect has
/// half a page: its number and an Open pill, what and where, its marked
/// photo across the page, who noted it, how long it has been open (red past
/// a week), who fixes it, and boxes to tick walking the site. Every page has
/// "<site> · Defects · as of <date>" and "Page N of M" at the foot. The
/// words are the export language's (`DefectsDocument`); the photos are
/// printed at print size, not as taken.
enum DefectsPDFRenderer {
    static let pageSize = CGSize(width: 595, height: 842)

    private static let margin: CGFloat = 40
    private static var width: CGFloat { pageSize.width - margin * 2 }
    /// Where the footer's rule is; nothing is drawn below it but the footer.
    private static var footerTop: CGFloat { pageSize.height - margin - 12 }
    private static var contentBottom: CGFloat { footerTop - 8 }

    // The page's own type and colours, in the look of the mockup: plain
    // black titles, grey detail, red open, green fixed.
    private static let titleFont = UIFont.systemFont(ofSize: 20, weight: .bold)
    private static let bylineFont = UIFont.systemFont(ofSize: 9)
    private static let figureFont = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .semibold)
    private static let figureLabelFont = UIFont.systemFont(ofSize: 7.5)
    private static let columnFont = UIFont.systemFont(ofSize: 7, weight: .semibold)
    private static let groupFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
    private static let cellFont = UIFont.systemFont(ofSize: 8.5)
    private static let cellBoldFont = UIFont.systemFont(ofSize: 8.5, weight: .semibold)
    private static let pillFont = UIFont.systemFont(ofSize: 7.5, weight: .semibold)
    private static let noteFont = UIFont.systemFont(ofSize: 8.5)
    private static let runningFont = UIFont.systemFont(ofSize: 11, weight: .semibold)
    private static let runningDetailFont = UIFont.systemFont(ofSize: 8)
    private static let numberFont = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .semibold)
    private static let cardTitleFont = UIFont.systemFont(ofSize: 15, weight: .bold)
    private static let placeFont = UIFont.systemFont(ofSize: 9)
    private static let infoFont = UIFont.systemFont(ofSize: 8.5)
    private static let footerFont = UIFont.systemFont(ofSize: 7)

    private static let ink = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    private static let secondary = UIColor(red: 0.39, green: 0.39, blue: 0.40, alpha: 1)
    private static let faint = UIColor(red: 0.68, green: 0.68, blue: 0.70, alpha: 1)
    private static let rule = UIColor(red: 0.88, green: 0.88, blue: 0.90, alpha: 1)
    private static let openRed = UIColor(red: 0.78, green: 0.16, blue: 0.16, alpha: 1)
    private static let openWash = UIColor(red: 0.99, green: 0.93, blue: 0.92, alpha: 1)
    private static let fixedGreen = UIColor(red: 0.18, green: 0.49, blue: 0.20, alpha: 1)
    private static let fixedWash = UIColor(red: 0.91, green: 0.96, blue: 0.91, alpha: 1)

    /// The photo across the page: 515 × 215 points, filled and rounded.
    private static let photoHeight: CGFloat = 215
    private static let cellPadding: CGFloat = 5

    /// The table's columns, left to right; Fixes only while the site
    /// assigns defects.
    private struct Columns {
        let x: [CGFloat]
        let widths: [CGFloat]
        let showsFixes: Bool

        init(showsFixes: Bool) {
            self.showsFixes = showsFixes
            let widths: [CGFloat] = showsFixes
                ? [30, 160, 110, 52, 70, 93]
                : [30, 190, 140, 52, 103]
            self.widths = widths
            var x: [CGFloat] = []
            var running = DefectsPDFRenderer.margin
            for width in widths {
                x.append(running)
                running += width
            }
            self.x = x
        }

        var status: Int { widths.count - 1 }
    }

    /// One thing in the table: a floor's heading or a defect's line.
    private enum TableItem {
        case floor(String)
        case row(DefectsDocument.TableRow)
    }

    static func data(for document: DefectsDocument, photos: [UUID: DefectPhoto]) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: document.title,
            kCGPDFContextCreator as String: "Zeitkonto"
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize), format: format)
        let columns = Columns(showsFixes: document.showsAssignee)
        let cards = document.cards
        // Print size, not the photo as taken, and only the ones printed.
        let printed = Set(cards.map(\.defectID))
        let images = photos.filter { printed.contains($0.key) }.compactMapValues { photo -> (UIImage, [DefectMark])? in
            guard let small = DiaryPhotoProcessor.printJPEG(from: photo.jpegData),
                  let image = DiaryPhotoProcessor.printableImage(from: small) else { return nil }
            return (image, photo.marks)
        }

        let tablePages = paginate(document.table, document: document, columns: columns)
        let cardPages = stride(from: 0, to: cards.count, by: 2).map { Array(cards[$0..<min($0 + 2, cards.count)]) }
        let pageCount = tablePages.count + cardPages.count

        return renderer.pdfData { context in
            var page = 0
            for (index, items) in tablePages.enumerated() {
                context.beginPage()
                page += 1
                var y = index == 0 ? drawFirstHeader(document) : drawRunningHeader(document, detail: "")
                y = drawColumnHeadings(document.columns, columns: columns, at: y)
                for item in items {
                    y = draw(item, columns: columns, at: y)
                }
                if index == tablePages.count - 1, !cards.isEmpty {
                    let note = document.tableNote(firstCardPage: tablePages.count + 1)
                    PDFReportStyle.drawWrapping(
                        note,
                        in: CGRect(x: margin, y: y + 12, width: width, height: height(of: note, width: width, font: noteFont) + 2),
                        font: noteFont,
                        color: secondary
                    )
                }
                drawFooter(document, page: page, of: pageCount)
            }
            for pair in cardPages {
                context.beginPage()
                page += 1
                var seen = Set<String>()
                let floors = pair.map(\.floor).filter { !$0.isEmpty && seen.insert($0).inserted }
                let top = drawRunningHeader(document, detail: floors.joined(separator: " · "))
                let slot = (contentBottom - top) / 2
                for (index, card) in pair.enumerated() {
                    let slotTop = top + slot * CGFloat(index)
                    if index > 0 {
                        PDFReportStyle.line(from: CGPoint(x: margin, y: slotTop), to: CGPoint(x: margin + width, y: slotTop), width: 0.6, color: rule)
                    }
                    drawCard(card, document: document, image: images[card.defectID], at: slotTop + 14, context: context.cgContext)
                }
                drawFooter(document, page: page, of: pageCount)
            }
        }
    }

    /// The photo cropped to its frame, its marks over it, clipped there.
    static func drawPhoto(_ image: UIImage, marks: [DefectMark], in frame: CGRect, context: CGContext, cornerRadius: CGFloat = 6) {
        context.saveGState()
        UIBezierPath(roundedRect: frame, cornerRadius: cornerRadius).addClip()
        let drawn = DefectMarkPainter.filled(image.size, in: frame)
        image.draw(in: drawn)
        DefectMarkPainter.draw(marks, in: drawn, context: context)
        context.restoreGState()
    }

    // MARK: - Laying out the table

    /// Where page 1's table starts, under the title, the byline and the
    /// figures.
    private static var firstTableTop: CGFloat { margin + 104 }
    /// Where a later page's table starts, under the running header.
    private static var runningTop: CGFloat { margin + 22 }
    private static let headingsHeight: CGFloat = 20
    private static let floorHeight: CGFloat = 22

    /// The table's items on as many pages as they need: a floor's heading
    /// is never left at the foot of a page without a line under it, and the
    /// line about the half pages fits under the last.
    private static func paginate(_ groups: [DefectsDocument.TableGroup], document: DefectsDocument, columns: Columns) -> [[TableItem]] {
        var pages: [[TableItem]] = [[]]
        var y = firstTableTop + headingsHeight
        let top = runningTop + headingsHeight
        for group in groups {
            let first = group.rows.first.map { rowHeight($0, columns: columns) } ?? 0
            if y + floorHeight + first > contentBottom, !(pages.last?.isEmpty ?? true) {
                pages.append([])
                y = top
            }
            pages[pages.count - 1].append(.floor(group.floor))
            y += floorHeight
            for row in group.rows {
                let height = rowHeight(row, columns: columns)
                if y + height > contentBottom {
                    pages.append([])
                    y = top
                }
                pages[pages.count - 1].append(.row(row))
                y += height
            }
        }
        // The note under the table, which names the page the half pages
        // start on: on a page of its own if it does not fit.
        if y + 40 > contentBottom, !document.cards.isEmpty {
            pages.append([])
        }
        return pages
    }

    private static func rowHeight(_ row: DefectsDocument.TableRow, columns: Columns) -> CGFloat {
        var tallest = height(of: row.what, width: columns.widths[1] - cellPadding * 2, font: cellBoldFont)
        tallest = max(tallest, height(of: row.room, width: columns.widths[2] - cellPadding * 2, font: cellFont))
        if columns.showsFixes, let fixes = row.fixes {
            tallest = max(tallest, height(of: fixes, width: columns.widths[4] - cellPadding * 2, font: cellFont))
        }
        return max(tallest, pillFont.lineHeight + 4) + 12
    }

    // MARK: - Drawing the table

    /// "<site> · Defects", the byline, the four figures. Returns where the
    /// table starts.
    private static func drawFirstHeader(_ document: DefectsDocument) -> CGFloat {
        var y = margin
        PDFReportStyle.draw(document.title, in: CGRect(x: margin, y: y, width: width, height: 26), font: titleFont, color: ink)
        y += 28
        PDFReportStyle.draw(document.byline, in: CGRect(x: margin, y: y, width: width, height: 13), font: bylineFont, color: secondary)
        y += 24
        var x = margin
        for figure in document.figureTexts {
            let color: UIColor
            switch figure.tone {
            case .open: color = openRed
            case .fixed: color = fixedGreen
            case .plain: color = ink
            }
            let figureWidth = min(
                max(PDFReportStyle.width(of: figure.value, font: figureFont), PDFReportStyle.width(of: figure.label, font: figureLabelFont)),
                margin + width - x
            )
            guard figureWidth > 0 else { break }
            PDFReportStyle.draw(figure.value, in: CGRect(x: x, y: y, width: figureWidth, height: 22), font: figureFont, color: color)
            PDFReportStyle.draw(figure.label, in: CGRect(x: x, y: y + 23, width: figureWidth, height: 10), font: figureLabelFont, color: secondary)
            x += figureWidth + 28
        }
        y = firstTableTop - 8
        PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.8, color: ink)
        return firstTableTop
    }

    /// "<site> · Defects" on the left, the floors on the right, a rule.
    private static func drawRunningHeader(_ document: DefectsDocument, detail: String) -> CGFloat {
        let detailWidth = detail.isEmpty ? 0 : min(PDFReportStyle.width(of: detail, font: runningDetailFont) + 2, width / 2)
        PDFReportStyle.draw(document.title, in: CGRect(x: margin, y: margin, width: width - detailWidth - 8, height: 14), font: runningFont, color: ink)
        if !detail.isEmpty {
            PDFReportStyle.draw(detail, in: CGRect(x: margin + width - detailWidth, y: margin, width: detailWidth, height: 14),
                                font: runningDetailFont, color: secondary, alignment: .right)
        }
        let y = margin + 20
        PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.8, color: ink)
        return runningTop
    }

    private static func drawColumnHeadings(_ headings: [String], columns: Columns, at top: CGFloat) -> CGFloat {
        for (index, heading) in headings.enumerated() where index < columns.x.count {
            PDFReportStyle.draw(
                heading,
                in: CGRect(x: columns.x[index] + cellPadding, y: top, width: columns.widths[index] - cellPadding * 2, height: 14),
                font: columnFont,
                color: secondary
            )
        }
        let y = top + headingsHeight - 3
        PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.5, color: rule)
        return top + headingsHeight
    }

    private static func draw(_ item: TableItem, columns: Columns, at top: CGFloat) -> CGFloat {
        switch item {
        case let .floor(name):
            PDFReportStyle.draw(name, in: CGRect(x: margin + cellPadding, y: top + 6, width: width, height: 12), font: groupFont, color: ink)
            let y = top + floorHeight - 1
            PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.6, color: ink)
            return top + floorHeight
        case let .row(row):
            let rowHeight = rowHeight(row, columns: columns)
            let textTop = top + 6
            func cell(_ text: String, _ column: Int, font: UIFont) {
                PDFReportStyle.drawWrapping(
                    text,
                    in: CGRect(
                        x: columns.x[column] + cellPadding,
                        y: textTop,
                        width: columns.widths[column] - cellPadding * 2,
                        height: rowHeight - 8
                    ),
                    font: font,
                    color: ink
                )
            }
            cell(String(row.number), 0, font: cellFont)
            cell(row.what, 1, font: cellBoldFont)
            cell(row.room, 2, font: cellFont)
            cell(row.since, 3, font: cellFont)
            if columns.showsFixes, let fixes = row.fixes {
                cell(fixes, 4, font: cellFont)
            }
            let isFixed: Bool
            if case .fixed = row.status { isFixed = true } else { isFixed = false }
            drawPill(
                row.statusText,
                at: CGPoint(x: columns.x[columns.status] + cellPadding, y: textTop - 1),
                maxWidth: columns.widths[columns.status] - cellPadding * 2,
                isFixed: isFixed
            )
            let y = top + rowHeight
            PDFReportStyle.line(from: CGPoint(x: margin, y: y), to: CGPoint(x: margin + width, y: y), width: 0.5, color: rule)
            return y
        }
    }

    /// "Open" on light red, "Fixed 2 Nov" on light green.
    @discardableResult
    private static func drawPill(_ text: String, at origin: CGPoint, maxWidth: CGFloat, isFixed: Bool, alignRight: Bool = false) -> CGRect {
        let textWidth = min(PDFReportStyle.width(of: text, font: pillFont), maxWidth - 10)
        let frame = CGRect(
            x: alignRight ? origin.x - textWidth - 10 : origin.x,
            y: origin.y,
            width: textWidth + 10,
            height: pillFont.lineHeight + 4
        )
        (isFixed ? fixedWash : openWash).setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: frame.height / 2).fill()
        PDFReportStyle.draw(text, in: frame.insetBy(dx: 5, dy: 0), font: pillFont, color: isFixed ? fixedGreen : openRed)
        return frame
    }

    // MARK: - An open defect's half page

    private static func drawCard(_ card: DefectsDocument.Card, document: DefectsDocument, image: (UIImage, [DefectMark])?, at top: CGFloat, context: CGContext) {
        let textX = margin + 54
        PDFReportStyle.draw(String(card.number), in: CGRect(x: margin, y: top, width: 50, height: 28), font: numberFont, color: ink)
        let pill = drawPill(
            document.statusText(.open),
            at: CGPoint(x: margin + width, y: top + 4),
            maxWidth: 120,
            isFixed: false,
            alignRight: true
        )
        PDFReportStyle.draw(card.what, in: CGRect(x: textX, y: top + 2, width: pill.minX - textX - 8, height: 20), font: cardTitleFont, color: ink)
        var y = top + 24
        if !card.place.isEmpty {
            PDFReportStyle.draw(card.place, in: CGRect(x: textX, y: y, width: width - 54, height: 12), font: placeFont, color: ink)
        }
        y += 20
        if let image {
            drawPhoto(image.0, marks: image.1, in: CGRect(x: margin, y: y, width: width, height: photoHeight), context: context, cornerRadius: 4)
            y += photoHeight + 10
        }

        // Noted · Open for (red past a week) · Fixes, on one line or two.
        let info = NSMutableAttributedString()
        let gap = NSAttributedString(string: "     ", attributes: [.font: infoFont])
        info.append(NSAttributedString(string: card.noted, attributes: [.font: infoFont, .foregroundColor: secondary]))
        info.append(gap)
        info.append(NSAttributedString(string: card.openFor, attributes: [
            .font: infoFont,
            .foregroundColor: card.isLongOpen ? openRed : secondary,
        ]))
        if let fixes = card.fixes {
            info.append(gap)
            info.append(NSAttributedString(string: fixes, attributes: [.font: infoFont, .foregroundColor: secondary]))
        }
        let infoHeight = ceil(info.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        ).height)
        info.draw(with: CGRect(x: margin, y: y, width: width, height: infoHeight + 1), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += infoHeight + 10

        drawWalkRound(document.walkRound, at: y)
    }

    /// "☐ Fixed   Date ________   Initials ______": ticked on paper.
    private static func drawWalkRound(_ words: [String], at top: CGFloat) {
        guard words.count == 3 else { return }
        let box = CGRect(x: margin, y: top + 1.5, width: 8, height: 8)
        ink.setStroke()
        let square = UIBezierPath(rect: box)
        square.lineWidth = 0.7
        square.stroke()
        var x = box.maxX + 5
        let fixedWidth = PDFReportStyle.width(of: words[0], font: infoFont)
        PDFReportStyle.draw(words[0], in: CGRect(x: x, y: top, width: fixedWidth + 2, height: 11), font: infoFont, color: ink)
        x += fixedWidth + 24
        for (word, line) in [(words[1], CGFloat(100)), (words[2], CGFloat(70))] {
            let wordWidth = PDFReportStyle.width(of: word, font: infoFont)
            PDFReportStyle.draw(word, in: CGRect(x: x, y: top, width: wordWidth + 2, height: 11), font: infoFont, color: ink)
            x += wordWidth + 5
            PDFReportStyle.line(from: CGPoint(x: x, y: top + 10), to: CGPoint(x: x + line, y: top + 10), width: 0.5, color: secondary)
            x += line + 20
        }
    }

    // MARK: - Every page

    private static func drawFooter(_ document: DefectsDocument, page: Int, of count: Int) {
        PDFReportStyle.line(from: CGPoint(x: margin, y: footerTop), to: CGPoint(x: margin + width, y: footerTop), width: 0.5, color: rule)
        let pageText = document.pageText(page, of: count)
        let pageWidth = PDFReportStyle.width(of: pageText, font: footerFont) + 2
        PDFReportStyle.draw(document.footer, in: CGRect(x: margin, y: footerTop + 4, width: width - pageWidth - 12, height: 10),
                            font: footerFont, color: faint)
        PDFReportStyle.draw(pageText, in: CGRect(x: margin + width - pageWidth, y: footerTop + 4, width: pageWidth, height: 10),
                            font: footerFont, color: faint, alignment: .right)
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
