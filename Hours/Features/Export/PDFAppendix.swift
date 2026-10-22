import UIKit

/// The pages after the table on a director's sheet: the crew's sign-off,
/// then the site diary with its photos.
///
/// Laid out before anything is drawn, like the table, so the footer's
/// "page 4 of 6" counts these pages too. A table with neither — every
/// timesheet, and a site month nobody signed and with no diary included —
/// has no pages here and prints exactly as before.
struct PDFAppendix {
    let table: ReportTable
    /// Printable images by photo id (see `DiaryPhotoProcessor.printableImage`).
    let photos: [UUID: UIImage]

    enum Page: Hashable {
        /// A run of sign-off boxes; the first page of them carries the heading.
        case signOff(Range<Int>, isFirst: Bool)
        /// A run of diary days; the first page of them carries the heading.
        case diary(Range<Int>, isFirst: Bool)
    }

    // MARK: - Measurements

    private static let headingHeight: CGFloat = 34
    private static let boxColumns = 3
    private static let boxGap: CGFloat = 16
    private static let boxHeight: CGFloat = 100
    private static let blockGap: CGFloat = 14
    private static let photoColumns = 3
    private static let photoGap: CGFloat = 8
    private static let photoHeight: CGFloat = 120

    private static let dayFont = UIFont.systemFont(ofSize: 10, weight: .semibold)
    private static let labelFont = UIFont.systemFont(ofSize: 7, weight: .bold)
    private static let textFont = UIFont.systemFont(ofSize: 8.5)

    private var top: CGFloat { PDFReportStyle.topMargin }
    private var bottom: CGFloat { PDFReportStyle.contentBottom }
    private var left: CGFloat { PDFReportStyle.margin }
    private var width: CGFloat { PDFReportStyle.contentWidth }

    private var blocks: [SiteDiaryBlock] { table.diary?.blocks ?? [] }

    // MARK: - Pages

    func pages() -> [Page] {
        var pages: [Page] = []

        let signOff = table.signOff
        if !signOff.isEmpty {
            let rowHeight = PDFAppendix.boxHeight + PDFAppendix.boxGap
            var next = 0
            var isFirst = true
            while next < signOff.count {
                let available = bottom - top - (isFirst ? PDFAppendix.headingHeight : 0)
                let rows = max(1, Int(available / rowHeight))
                let end = min(signOff.count, next + rows * PDFAppendix.boxColumns)
                pages.append(.signOff(next..<end, isFirst: isFirst))
                next = end
                isFirst = false
            }
        }

        if !blocks.isEmpty {
            var first = 0
            var y = top + PDFAppendix.headingHeight
            var isFirst = true
            for index in blocks.indices {
                let height = blockHeight(blocks[index])
                // A day starts a new page when it does not fit, unless it is
                // alone on the page already: a day longer than a page is cut
                // at the foot rather than pushed on forever.
                if y + height > bottom && index > first {
                    pages.append(.diary(first..<index, isFirst: isFirst))
                    first = index
                    y = top
                    isFirst = false
                }
                y += height + PDFAppendix.blockGap
            }
            pages.append(.diary(first..<blocks.count, isFirst: isFirst))
        }
        return pages
    }

    func draw(_ page: Page) {
        switch page {
        case let .signOff(range, isFirst):
            var y = top
            if isFirst {
                y = drawHeading(table.language(.signOff), at: y)
            }
            drawSignOff(range, from: y)
        case let .diary(range, isFirst):
            var y = top
            if isFirst, let title = table.diary?.title {
                y = drawHeading(title, at: y)
            }
            // Nothing is drawn past the content area, so a day longer than a
            // page is cut there rather than running into the footer.
            UIGraphicsGetCurrentContext()?.saveGState()
            UIRectClip(CGRect(x: 0, y: 0, width: PDFReportStyle.pageSize.width, height: bottom))
            for index in range {
                y = drawBlock(blocks[index], at: y) + PDFAppendix.blockGap
            }
            UIGraphicsGetCurrentContext()?.restoreGState()
        }
    }

    // MARK: - Heading

    /// "SIGN-OFF" over "Bau Süd · August 2026", ruled off.
    private func drawHeading(_ title: String, at y: CGFloat) -> CGFloat {
        PDFReportStyle.draw(
            title.uppercased(with: table.language.locale),
            in: CGRect(x: left, y: y, width: width, height: 11),
            font: PDFReportStyle.eyebrowFont,
            color: PDFReportStyle.accent,
            kern: 0.8
        )
        PDFReportStyle.draw(
            [table.title, table.subtitle].filter { !$0.isEmpty }.joined(separator: " · "),
            in: CGRect(x: left, y: y + 12, width: width, height: 14),
            font: PDFAppendix.dayFont,
            color: PDFReportStyle.ink
        )
        PDFReportStyle.line(
            from: CGPoint(x: left, y: y + 29),
            to: CGPoint(x: left + width, y: y + 29),
            width: 1.2,
            color: PDFReportStyle.ink
        )
        return y + PDFAppendix.headingHeight
    }

    // MARK: - Sign-off

    private func drawSignOff(_ range: Range<Int>, from top: CGFloat) {
        let columns = PDFAppendix.boxColumns
        let gap = PDFAppendix.boxGap
        let boxWidth = (width - CGFloat(columns - 1) * gap) / CGFloat(columns)
        for (offset, index) in range.enumerated() {
            let column = offset % columns
            let row = offset / columns
            let frame = CGRect(
                x: left + CGFloat(column) * (boxWidth + gap),
                y: top + CGFloat(row) * (PDFAppendix.boxHeight + gap),
                width: boxWidth,
                height: PDFAppendix.boxHeight
            )
            drawBox(table.signOff[index], in: frame)
        }
    }

    /// Name and hours on top, the signature on its line, and under the line
    /// when it was signed — or that the hours changed after it was.
    private func drawBox(_ person: ReportSignOff, in frame: CGRect) {
        PDFReportStyle.tile.setFill()
        UIBezierPath(roundedRect: frame, cornerRadius: 6).fill()
        let inner = frame.insetBy(dx: 10, dy: 8)

        PDFReportStyle.draw(person.name, in: CGRect(x: inner.minX, y: inner.minY, width: inner.width * 0.65, height: 13),
                            font: PDFReportStyle.cellBoldFont, color: PDFReportStyle.ink)
        PDFReportStyle.draw(person.hours, in: CGRect(x: inner.minX + inner.width * 0.65, y: inner.minY, width: inner.width * 0.35, height: 13),
                            font: PDFReportStyle.cellBoldFont, color: PDFReportStyle.ink, alignment: .right)

        let lineY = inner.maxY - 14
        let signatureArea = CGRect(x: inner.minX, y: inner.minY + 16, width: inner.width, height: lineY - inner.minY - 18)
        PDFAppendix.drawStrokes(person.strokes, aspectRatio: person.aspectRatio, in: signatureArea)

        PDFReportStyle.line(from: CGPoint(x: inner.minX, y: lineY), to: CGPoint(x: inner.maxX, y: lineY),
                            width: 0.6, color: PDFReportStyle.signatureRule)
        PDFReportStyle.draw(person.status, in: CGRect(x: inner.minX, y: lineY + 2, width: inner.width, height: 11),
                            font: PDFReportStyle.smallFont,
                            color: person.isChanged ? PDFReportStyle.accent : PDFReportStyle.secondary)
    }

    /// The signature scaled to fit its area, keeping its proportions, set on
    /// the line as a signature is. Shared with the extra-work report, which
    /// prints the client's signature the same way.
    static func drawStrokes(_ strokes: [[SignaturePoint]], aspectRatio: Double, in area: CGRect) {
        guard !strokes.isEmpty, area.width > 0, area.height > 0 else { return }
        let aspect = CGFloat(max(aspectRatio, 0.1))
        let scale = min(area.width / aspect, area.height)
        let origin = CGPoint(x: area.minX, y: area.maxY - scale)
        let path = UIBezierPath()
        for stroke in strokes {
            guard let first = stroke.first else { continue }
            path.move(to: CGPoint(x: origin.x + CGFloat(first.x) * scale, y: origin.y + CGFloat(first.y) * scale))
            for point in stroke.dropFirst() {
                path.addLine(to: CGPoint(x: origin.x + CGFloat(point.x) * scale, y: origin.y + CGFloat(point.y) * scale))
            }
        }
        path.lineWidth = 1.1
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        PDFReportStyle.ink.setStroke()
        path.stroke()
    }

    // MARK: - Diary

    private func textHeight(_ text: String, font: UIFont) -> CGFloat {
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(bounds.height)
    }

    private func photoRows(_ block: SiteDiaryBlock) -> Int {
        let count = block.photoIDs.filter { photos[$0] != nil }.count
        return (count + PDFAppendix.photoColumns - 1) / PDFAppendix.photoColumns
    }

    private func blockHeight(_ block: SiteDiaryBlock) -> CGFloat {
        var height: CGFloat = 16
        if !block.weatherLine.isEmpty { height += 12 }
        for line in block.lines {
            height += 11 + textHeight(line.text, font: PDFAppendix.textFont) + 4
        }
        let rows = photoRows(block)
        if rows > 0 {
            height += 4 + CGFloat(rows) * PDFAppendix.photoHeight + CGFloat(rows - 1) * PDFAppendix.photoGap
        }
        return height
    }

    private func drawBlock(_ block: SiteDiaryBlock, at start: CGFloat) -> CGFloat {
        var y = start
        PDFReportStyle.draw(block.heading, in: CGRect(x: left, y: y, width: width, height: 14),
                            font: PDFAppendix.dayFont, color: PDFReportStyle.ink)
        y += 16
        if !block.weatherLine.isEmpty {
            PDFReportStyle.draw(block.weatherLine, in: CGRect(x: left, y: y, width: width, height: 11),
                                font: PDFReportStyle.smallFont, color: PDFReportStyle.secondary)
            y += 12
        }
        for line in block.lines {
            PDFReportStyle.draw(line.label.uppercased(with: table.language.locale),
                                in: CGRect(x: left, y: y, width: width, height: 10),
                                font: PDFAppendix.labelFont, color: PDFReportStyle.secondary)
            y += 11
            let height = textHeight(line.text, font: PDFAppendix.textFont)
            PDFReportStyle.drawWrapping(line.text, in: CGRect(x: left, y: y, width: width, height: height + 2),
                                        font: PDFAppendix.textFont, color: PDFReportStyle.ink)
            y += height + 4
        }

        let images = block.photoIDs.compactMap { photos[$0] }
        if !images.isEmpty {
            y += 4
            let columns = PDFAppendix.photoColumns
            let gap = PDFAppendix.photoGap
            let cellWidth = (width - CGFloat(columns - 1) * gap) / CGFloat(columns)
            for (index, image) in images.enumerated() {
                let cell = CGRect(
                    x: left + CGFloat(index % columns) * (cellWidth + gap),
                    y: y + CGFloat(index / columns) * (PDFAppendix.photoHeight + gap),
                    width: cellWidth,
                    height: PDFAppendix.photoHeight
                )
                image.draw(in: aspectFit(image.size, in: cell))
            }
            let rows = (images.count + columns - 1) / columns
            y += CGFloat(rows) * PDFAppendix.photoHeight + CGFloat(rows - 1) * gap
        }

        PDFReportStyle.line(from: CGPoint(x: left, y: y + PDFAppendix.blockGap / 2),
                            to: CGPoint(x: left + width, y: y + PDFAppendix.blockGap / 2),
                            width: 0.5, color: PDFReportStyle.rule)
        return y
    }

    /// The photo's own proportions inside its cell, against the cell's left edge.
    private func aspectFit(_ size: CGSize, in cell: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return cell }
        let scale = min(cell.width / size.width, cell.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: cell.minX, y: cell.minY + (cell.height - fitted.height) / 2, width: fitted.width, height: fitted.height)
    }
}
