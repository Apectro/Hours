import UIKit

/// Everything on a printed page that is not the table: the header block,
/// the summary under the total, and the footer with the page count and the
/// lines to sign on.
struct PDFPageDecorations {
    let table: ReportTable
    let layout: PDFReportLayout
    let generatedOn: Date
    let pageCount: Int

    // MARK: - Header block

    /// The eyebrow as it fits beside the figures. "Timesheet · Site A · Site B"
    /// that is too long loses "Timesheet" first, so the sites — the part that
    /// says something — are what is left whole; only then is it cut short.
    static func fittedEyebrow(_ text: String, width: CGFloat) -> String {
        func fits(_ candidate: String) -> Bool {
            let attributes: [NSAttributedString.Key: Any] = [.font: PDFReportStyle.eyebrowFont, .kern: 0.8]
            return (candidate as NSString).size(withAttributes: attributes).width <= width
        }
        guard !fits(text), let range = text.range(of: " · ") else { return text }
        return String(text[range.upperBound...])
    }

    /// "SITE HOURS · OCTOBER 2026" in small orange capitals, the site or the
    /// person as the title under it, the address and the day it was made in
    /// grey, and up to two figures as plain right-aligned text, over a thin
    /// rule (no tiles). The words come from `ReportTable.pageHeader`.
    func drawHeader(at y: CGFloat) -> CGFloat {
        let margin = PDFReportStyle.margin
        let header = table.pageHeader(
            madeOn: CalendarDate(generatedOn, calendar: .current),
            calendar: .current
        )
        let figuresWidth = PDFPageDecorations.figuresWidth(header.figures)
        let textWidth = PDFReportStyle.contentWidth - figuresWidth - (header.figures.isEmpty ? 0 : 24)

        PDFReportStyle.draw(
            Self.fittedEyebrow(header.kindLine.uppercased(with: table.language.locale), width: textWidth),
            in: CGRect(x: margin, y: y, width: textWidth, height: 11),
            font: PDFReportStyle.eyebrowFont,
            color: PDFReportStyle.accent,
            kern: 0.8
        )
        PDFReportStyle.draw(
            header.title,
            in: CGRect(x: margin, y: y + 12, width: textWidth, height: 30),
            font: PDFReportStyle.titleFont,
            color: PDFReportStyle.ink
        )
        PDFReportStyle.draw(
            header.detailLine,
            in: CGRect(x: margin, y: y + 45, width: textWidth, height: 12),
            font: PDFReportStyle.headerDetailFont,
            color: PDFReportStyle.secondary
        )

        // The figures, bottom-aligned with the grey line under the title.
        let figuresX = margin + PDFReportStyle.contentWidth - figuresWidth
        let firstFigureY = y + 45 - CGFloat(max(header.figures.count - 1, 0)) * 14
        for (index, figure) in header.figures.enumerated() {
            drawFigure(figure, in: CGRect(x: figuresX, y: firstFigureY + CGFloat(index) * 14, width: figuresWidth, height: 13))
        }

        let ruleY = y + 60
        PDFReportStyle.line(
            from: CGPoint(x: margin, y: ruleY),
            to: CGPoint(x: margin + PDFReportStyle.contentWidth, y: ruleY),
            width: 1,
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

    /// The gap between a figure's label and its value.
    private static let figureGap: CGFloat = 6

    /// As wide as the widest "Crew hours  489h 30m", so the values line up
    /// on the right.
    private static func figuresWidth(_ figures: [ReportTile]) -> CGFloat {
        figures.map { figure in
            ceil(PDFReportStyle.width(of: figure.label, font: PDFReportStyle.figureLabelFont)
                + figureGap
                + PDFReportStyle.width(of: figure.value, font: PDFReportStyle.figureValueFont))
        }.max() ?? 0
    }

    /// "Crew hours" in grey, then "489h 30m" in bold, right-aligned. Plain
    /// ink even below zero: the table's late and early are the one colour.
    private func drawFigure(_ figure: ReportTile, in rect: CGRect) {
        let valueWidth = ceil(PDFReportStyle.width(of: figure.value, font: PDFReportStyle.figureValueFont)) + 1
        PDFReportStyle.draw(
            figure.value,
            in: CGRect(x: rect.maxX - valueWidth, y: rect.minY, width: valueWidth, height: rect.height),
            font: PDFReportStyle.figureValueFont,
            color: PDFReportStyle.ink,
            alignment: .right
        )
        let labelWidth = max(0, rect.width - valueWidth - PDFPageDecorations.figureGap)
        PDFReportStyle.draw(
            figure.label,
            in: CGRect(x: rect.minX, y: rect.minY, width: labelWidth, height: rect.height),
            font: PDFReportStyle.figureLabelFont,
            color: PDFReportStyle.secondary,
            alignment: .right
        )
    }

    // MARK: - Summary

    /// Every figure the summary holds, in three columns of label and value.
    ///
    /// The header repeats two of them, and they are kept here as well: this
    /// block is where the figures have always been, and a test reads it back
    /// out of the finished page to be sure the summary was never dropped.
    func drawSummary(at y: CGFloat) -> CGFloat {
        let margin = PDFReportStyle.margin
        // A sheet for several sites' month has no summary of its own: its
        // By site block stands where the summary would, in the same style.
        guard !table.totals.isEmpty else {
            let columnWidth = min(240, PDFReportStyle.contentWidth / CGFloat(PDFReportLayout.summaryColumns))
            drawBySite(at: y, x: margin, width: columnWidth * 1.5)
            return y + layout.summaryHeight
        }
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
        drawBySite(at: y, x: margin + CGFloat(layout.summaryFigureColumns) * columnWidth + 16)
        return y + layout.summaryHeight
    }

    /// Hours per site beside the summary (1.2): the name, its address in
    /// grey after it, the hours on the right. Only for a period on more than
    /// one site.
    private func drawBySite(at y: CGFloat, x: CGFloat, width fixedWidth: CGFloat? = nil) {
        guard !table.bySite.isEmpty else { return }
        let width = fixedWidth ?? (PDFReportStyle.margin + PDFReportStyle.contentWidth - x)
        PDFReportStyle.draw(
            table.language(.bySite),
            in: CGRect(x: x, y: y, width: width, height: 12),
            font: PDFReportStyle.cellBoldFont,
            color: PDFReportStyle.ink
        )
        let valueWidth: CGFloat = 60
        for (index, site) in table.bySite.enumerated() {
            let rowY = y + 14 + CGFloat(index) * 12
            // The total line adds up the sites above it, ruled off from them.
            if site.isTotal {
                PDFReportStyle.line(
                    from: CGPoint(x: x, y: rowY),
                    to: CGPoint(x: x + width, y: rowY),
                    width: 0.6,
                    color: PDFReportStyle.ink
                )
            }
            let label = NSMutableAttributedString(
                string: site.name,
                attributes: [
                    .font: site.isTotal ? PDFReportStyle.cellBoldFont : PDFReportStyle.smallFont,
                    .foregroundColor: PDFReportStyle.ink
                ]
            )
            if !site.address.isEmpty {
                label.append(NSAttributedString(
                    string: " · \(site.address)",
                    attributes: [.font: PDFReportStyle.smallFont, .foregroundColor: PDFReportStyle.secondary]
                ))
            }
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            label.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: label.length))
            let lineHeight = PDFReportStyle.smallFont.lineHeight
            label.draw(in: CGRect(x: x, y: rowY + (12 - lineHeight) / 2, width: width - valueWidth - 6, height: lineHeight))
            PDFReportStyle.draw(
                site.value,
                in: CGRect(x: x + width - valueWidth, y: rowY, width: valueWidth, height: 12),
                font: PDFReportStyle.cellBoldFont,
                color: PDFReportStyle.ink,
                alignment: .right
            )
        }
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
