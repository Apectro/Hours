import UIKit

/// Everything on a printed page that is not the table: the header block with
/// its tiles, the summary under the total, and the footer with the page count
/// and the lines to sign on.
struct PDFPageDecorations {
    let table: ReportTable
    let layout: PDFReportLayout
    let generatedOn: Date
    let pageCount: Int

    private static let tileWidth: CGFloat = 88
    private static let tileHeight: CGFloat = 40
    private static let tileGap: CGFloat = 6

    // MARK: - Header block

    /// Eyebrow, headline and byline on the left, the tiles on the right, and
    /// a heavy rule under both.
    func drawHeader(at y: CGFloat) -> CGFloat {
        let margin = PDFReportStyle.margin
        let tiles = table.tiles
        let widths = tiles.map(PDFPageDecorations.width(of:))
        let tilesWidth = tiles.isEmpty
            ? 0
            : widths.reduce(0, +) + CGFloat(tiles.count - 1) * PDFPageDecorations.tileGap
        let textWidth = PDFReportStyle.contentWidth - tilesWidth - (tiles.isEmpty ? 0 : 16)

        PDFReportStyle.draw(
            table.eyebrow.uppercased(with: table.language.locale),
            in: CGRect(x: margin, y: y, width: textWidth, height: 11),
            font: PDFReportStyle.eyebrowFont,
            color: PDFReportStyle.accent,
            kern: 0.8
        )
        PDFReportStyle.draw(
            table.headline,
            in: CGRect(x: margin, y: y + 12, width: textWidth, height: 30),
            font: PDFReportStyle.titleFont,
            color: PDFReportStyle.ink
        )
        PDFReportStyle.draw(
            table.byline,
            in: CGRect(x: margin, y: y + 43, width: textWidth, height: 13),
            font: PDFReportStyle.bylineFont,
            color: PDFReportStyle.secondary
        )

        var x = margin + PDFReportStyle.contentWidth - tilesWidth
        for (tile, width) in zip(tiles, widths) {
            drawTile(tile, in: CGRect(x: x, y: y, width: width, height: PDFPageDecorations.tileHeight))
            x += width + PDFPageDecorations.tileGap
        }

        let ruleY = y + 60
        PDFReportStyle.line(
            from: CGPoint(x: margin, y: ruleY),
            to: CGPoint(x: margin + PDFReportStyle.contentWidth, y: ruleY),
            width: 2,
            color: PDFReportStyle.ink
        )
        // A part of a sheet split across pages says whose hours it holds.
        if !table.partLabel.isEmpty {
            PDFReportStyle.draw(
                table.partLabel,
                in: CGRect(x: margin, y: ruleY + 5, width: PDFReportStyle.contentWidth, height: 11),
                font: PDFReportStyle.cellBoldFont,
                color: PDFReportStyle.secondary
            )
        }
        return y + layout.titleBlockHeight
    }

    /// As wide as its figure or its label needs, and never narrower than the
    /// others' 88 points: "489h 30m" of crew hours was cut to "489h…".
    private static func width(of tile: ReportTile) -> CGFloat {
        func measured(_ text: String, _ font: UIFont) -> CGFloat {
            ceil((text as NSString).size(withAttributes: [.font: font]).width)
        }
        let content = max(measured(tile.value, PDFReportStyle.tileValueFont), measured(tile.label, PDFReportStyle.tileLabelFont))
        return max(tileWidth, content + 18)
    }

    private func drawTile(_ tile: ReportTile, in rect: CGRect) {
        (tile.isNegative ? PDFReportStyle.negativeTile : PDFReportStyle.tile).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        let inner = rect.insetBy(dx: 8, dy: 0)
        PDFReportStyle.draw(
            tile.label,
            in: CGRect(x: inner.minX, y: rect.minY + 5, width: inner.width, height: 10),
            font: PDFReportStyle.tileLabelFont,
            color: PDFReportStyle.secondary
        )
        PDFReportStyle.draw(
            tile.value,
            in: CGRect(x: inner.minX, y: rect.minY + 16, width: inner.width, height: 21),
            font: PDFReportStyle.tileValueFont,
            color: tile.isNegative ? PDFReportStyle.negative : PDFReportStyle.ink
        )
    }

    // MARK: - Summary

    /// Every figure the summary holds, in three columns of label and value.
    ///
    /// The tiles repeat four of them, and they are kept here as well: this
    /// block is where the figures have always been, and a test reads it back
    /// out of the finished page to be sure the summary was never dropped.
    func drawSummary(at y: CGFloat) -> CGFloat {
        let margin = PDFReportStyle.margin
        PDFReportStyle.draw(
            table.language(.summary),
            in: CGRect(x: margin, y: y, width: 200, height: 12),
            font: PDFReportStyle.cellBoldFont,
            color: PDFReportStyle.ink
        )

        let columnWidth = min(240, PDFReportStyle.contentWidth / CGFloat(PDFReportLayout.summaryColumns))
        let perColumn = max(layout.summaryLinesPerColumn, 1)
        for (index, total) in table.totals.enumerated() {
            let x = margin + CGFloat(index / perColumn) * columnWidth
            let rowY = y + 14 + CGFloat(index % perColumn) * 12
            PDFReportStyle.draw(
                total.label,
                in: CGRect(x: x, y: rowY, width: columnWidth * 0.62, height: 12),
                font: PDFReportStyle.smallFont,
                color: PDFReportStyle.secondary
            )
            PDFReportStyle.draw(
                total.value,
                in: CGRect(x: x + columnWidth * 0.62, y: rowY, width: columnWidth * 0.3, height: 12),
                font: total.isEmphasised ? PDFReportStyle.cellBoldFont : PDFReportStyle.cellFont,
                color: PDFReportStyle.ink,
                alignment: .right
            )
        }
        return y + layout.summaryHeight
    }

    // MARK: - Footer

    /// "Zeitkonto · generated … · page 2 of 3" on every page; on the last,
    /// the legend and the lines to sign on beside it.
    func drawFooter(page: Int, isLast: Bool) {
        let margin = PDFReportStyle.margin
        let bandTop = PDFReportStyle.contentBottom
        let bottom = PDFReportStyle.pageSize.height - PDFReportStyle.bottomMargin

        let footer = footerText(page: page)
        let footerWidth = PDFReportStyle.width(of: footer, font: PDFReportStyle.footerFont) + 2
        PDFReportStyle.draw(
            footer,
            in: CGRect(x: margin + PDFReportStyle.contentWidth - footerWidth, y: bottom - 10, width: footerWidth, height: 10),
            font: PDFReportStyle.footerFont,
            color: PDFReportStyle.faint,
            alignment: .right
        )
        guard isLast else { return }

        let area = PDFReportStyle.contentWidth - footerWidth - 24
        let signatures = table.signatures
        let count = CGFloat(signatures.count)
        var x = margin
        let signatureWidth: CGFloat
        let gap: CGFloat
        if table.legend.isEmpty {
            gap = 36
            signatureWidth = count > 0 ? (area - (count - 1) * gap) / count : 0
        } else {
            gap = 24
            signatureWidth = min(200, area * 0.35)
            let legendWidth = max(120, area - count * (signatureWidth + gap))
            PDFReportStyle.drawWrapping(
                table.legend,
                in: CGRect(x: margin, y: bandTop + 4, width: legendWidth, height: bottom - bandTop - 4),
                font: PDFReportStyle.smallFont,
                color: PDFReportStyle.secondary
            )
            x = margin + legendWidth + gap
        }

        for label in signatures {
            let lineY = bottom - 12
            PDFReportStyle.line(
                from: CGPoint(x: x, y: lineY),
                to: CGPoint(x: x + signatureWidth, y: lineY),
                width: 0.6,
                color: PDFReportStyle.signatureRule
            )
            PDFReportStyle.draw(
                label,
                in: CGRect(x: x, y: lineY + 1, width: signatureWidth, height: 11),
                font: PDFReportStyle.smallFont,
                color: PDFReportStyle.secondary
            )
            x += signatureWidth + gap
        }
    }

    private func footerText(page: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = table.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let generated = table.language(.generated) + " " + formatter.string(from: generatedOn)
        return ["Zeitkonto", generated, table.language.pageOf(page, pageCount)].joined(separator: " · ")
    }
}
