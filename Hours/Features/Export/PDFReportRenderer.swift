import UIKit

/// Draws a report as a paginated PDF.
///
/// A real table — ruled, aligned, with a header that repeats on every page and
/// a totals block at the end — rather than a screenshot of a list. Numeric
/// columns are right-aligned so figures line up down the page.
enum PDFReportRenderer {
    /// A4 landscape. Wide enough for ten columns without squeezing.
    static let pageSize = CGSize(width: 842, height: 595)

    /// Visible to the tests, which check that no column that must not be cut
    /// short comes out narrower than the text it draws.
    static let margin: CGFloat = 36
    private static let rowHeight: CGFloat = 20
    private static let headerHeight: CGFloat = 24
    private static let cellPadding: CGFloat = 6

    static func data(for table: ReportTable, generatedOn date: Date = Date()) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: table.title,
            kCGPDFContextCreator as String: "Hours"
        ]
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        let widths = columnWidths(for: table, availableWidth: pageSize.width - margin * 2)

        return renderer.pdfData { context in
            var pageNumber = 0
            var rowIndex = 0
            var isFirstPage = true
            var totalsDrawn = table.totals.isEmpty

            repeat {
                context.beginPage()
                pageNumber += 1
                var y = margin

                if isFirstPage {
                    y = drawTitle(table: table, at: y, generatedOn: date)
                    isFirstPage = false
                }

                // A page carrying nothing but the summary gets no column
                // header, because there is no column under it.
                if rowIndex < table.rows.count {
                    y = drawHeaderRow(table: table, widths: widths, at: y)
                }

                while rowIndex < table.rows.count, y + rowHeight <= contentBottom {
                    drawRow(table.rows[rowIndex], table: table, widths: widths, at: y, isEven: rowIndex.isMultiple(of: 2))
                    y += rowHeight
                    rowIndex += 1
                }

                // The summary takes a page of its own rather than being
                // silently dropped. drawTotals skips any line that does not
                // fit, so a report whose rows happened to end near the bottom
                // of a page exported with its totals partly or entirely
                // missing — and looked perfectly fine otherwise.
                if rowIndex >= table.rows.count,
                   !totalsDrawn,
                   y + 12 + totalsHeight(for: table) <= contentBottom {
                    y = drawTotals(table: table, at: y + 12)
                    totalsDrawn = true
                }

                drawFooter(pageNumber: pageNumber, title: table.title, language: table.language)
            } while (rowIndex < table.rows.count || !totalsDrawn) && pageNumber < maximumPages
        }
    }

    /// The lowest a row may reach before the page is full, leaving the footer
    /// its band at the bottom.
    private static var contentBottom: CGFloat { pageSize.height - margin - 24 }

    /// How tall the summary block will be, so the space can be asked for in
    /// advance rather than discovered halfway down the page.
    static func totalsHeight(for table: ReportTable) -> CGFloat {
        guard !table.totals.isEmpty else { return 0 }
        let perColumn = Int((Double(table.totals.count) / 2.0).rounded(.up))
        return 20 + CGFloat(perColumn) * 15
    }

    /// A hard stop, so a table that somehow never advances cannot spin
    /// forever. At roughly 23 rows to a page the old limit of 500 pages was
    /// about thirty years of daily entries — a working lifetime, and so not
    /// beyond reach — and reaching it dropped the remaining rows without
    /// saying so. This is set where reaching it is not possible.
    private static let maximumPages = 100_000

    // MARK: - Sections

    private static func drawTitle(table: ReportTable, at y: CGFloat, generatedOn date: Date) -> CGFloat {
        var cursor = y
        draw(
            table.title,
            in: CGRect(x: margin, y: cursor, width: pageSize.width - margin * 2, height: 26),
            font: .systemFont(ofSize: 18, weight: .semibold),
            color: .label,
            alignment: .left
        )
        cursor += 24

        // Whose hours these are, between the report's name and its dates —
        // the line a payroll department reads first, and the one a timesheet
        // is useless without.
        if !table.ownerName.isEmpty {
            draw(
                table.ownerName,
                in: CGRect(x: margin, y: cursor, width: pageSize.width - margin * 2, height: 18),
                font: .systemFont(ofSize: 12, weight: .medium),
                color: .label,
                alignment: .left
            )
            cursor += 17
        }

        let formatter = DateFormatter()
        formatter.locale = table.language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        draw(
            "\(table.subtitle)   ·   \(table.language(.generated)) \(formatter.string(from: date))",
            in: CGRect(x: margin, y: cursor, width: pageSize.width - margin * 2, height: 16),
            font: .systemFont(ofSize: 10),
            color: .secondaryLabel,
            alignment: .left
        )
        return cursor + 24
    }

    private static func drawHeaderRow(table: ReportTable, widths: [CGFloat], at y: CGFloat) -> CGFloat {
        let rect = CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: headerHeight)
        UIColor.systemGray6.setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 3).fill()

        var x = margin
        for (index, column) in table.columns.enumerated() {
            let width = widths[index]
            draw(
                column.heading(in: table.language),
                in: CGRect(x: x + cellPadding, y: y + 5, width: width - cellPadding * 2, height: headerHeight - 8),
                font: headingFont,
                color: .secondaryLabel,
                alignment: column.isNumeric ? .right : .left
            )
            x += width
        }
        return y + headerHeight + 2
    }

    private static func drawRow(
        _ row: ReportRow,
        table: ReportTable,
        widths: [CGFloat],
        at y: CGFloat,
        isEven: Bool
    ) {
        let rect = CGRect(x: margin, y: y, width: pageSize.width - margin * 2, height: rowHeight)
        if !row.isWorkingDay {
            // Non-working days are washed out so the working week stands out
            // when someone scans the page.
            UIColor.systemGray6.withAlphaComponent(0.6).setFill()
            UIBezierPath(rect: rect).fill()
        }

        var x = margin
        for (index, column) in table.columns.enumerated() where index < row.values.count {
            let width = widths[index]
            draw(
                row.values[index],
                in: CGRect(x: x + cellPadding, y: y + 4, width: width - cellPadding * 2, height: rowHeight - 6),
                font: cellFont,
                color: row.hasEntry ? .label : .secondaryLabel,
                alignment: column.isNumeric ? .right : .left
            )
            x += width
        }

        UIColor.separator.withAlphaComponent(0.4).setStroke()
        let line = UIBezierPath()
        line.move(to: CGPoint(x: margin, y: y + rowHeight))
        line.addLine(to: CGPoint(x: pageSize.width - margin, y: y + rowHeight))
        line.lineWidth = 0.4
        line.stroke()
    }

    private static func drawTotals(table: ReportTable, at y: CGFloat) -> CGFloat {
        guard !table.totals.isEmpty else { return y }
        var cursor = y

        draw(
            table.language(.summary),
            in: CGRect(x: margin, y: cursor, width: 200, height: 16),
            font: .systemFont(ofSize: 11, weight: .semibold),
            color: .label,
            alignment: .left
        )
        cursor += 20

        // Two columns of totals so a long list does not run off the page.
        let columnWidth = (pageSize.width - margin * 2) / 2
        let perColumn = Int((Double(table.totals.count) / 2.0).rounded(.up))

        for (index, total) in table.totals.enumerated() {
            let column = index / max(perColumn, 1)
            let rowOffset = index % max(perColumn, 1)
            let x = margin + CGFloat(column) * columnWidth
            let rowY = cursor + CGFloat(rowOffset) * 15
            guard rowY + 15 < pageSize.height - margin else { continue }

            draw(
                total.label,
                in: CGRect(x: x, y: rowY, width: columnWidth * 0.6, height: 14),
                font: .systemFont(ofSize: 9.5),
                color: .secondaryLabel,
                alignment: .left
            )
            draw(
                total.value,
                in: CGRect(x: x + columnWidth * 0.6, y: rowY, width: columnWidth * 0.36, height: 14),
                font: .systemFont(ofSize: 9.5, weight: total.isEmphasised ? .semibold : .regular),
                color: .label,
                alignment: .right
            )
        }

        return cursor + CGFloat(perColumn) * 15
    }

    private static func drawFooter(pageNumber: Int, title: String, language: ExportLanguage) {
        draw(
            "\(title)   ·   \(language(.page)) \(pageNumber)",
            in: CGRect(x: margin, y: pageSize.height - margin + 6, width: pageSize.width - margin * 2, height: 14),
            font: .systemFont(ofSize: 8),
            color: .tertiaryLabel,
            alignment: .center
        )
    }

    // MARK: - Layout

    /// Column widths: what each column cannot do without, and then the rest
    /// to whoever can use it.
    ///
    /// This was per-column weights normalised to the page, tuned by hand
    /// against English. Two things broke that. Longer headings — "Worked" is
    /// six letters and "Heures travaillées" is eighteen — and longer figures,
    /// where a three-figure total needs eight characters in a column drawn
    /// for six.
    ///
    /// Raising the weight of the columns that had outgrown theirs was the
    /// obvious repair and the wrong one: weights are normalised, so widening
    /// three columns quietly narrowed the other seven, and the French sheet
    /// came out with its headings intact and its dates reading "2026-08-…".
    /// Trading a clipped heading for a clipped date is not a fix.
    ///
    /// So the minimum is measured rather than weighted, in the fonts the page
    /// actually draws — a character count cannot tell "Data" from "Dzień" —
    /// and only what is left over is shared out, by the old weights, among
    /// the columns allowed to truncate. A column that must fit always fits,
    /// and the note gives up the difference.
    static func columnWidths(for table: ReportTable, availableWidth: CGFloat) -> [CGFloat] {
        guard !table.columns.isEmpty else { return [] }

        let minimum = table.columns.indices.map { index -> CGFloat in
            let column = table.columns[index]
            var needed = width(of: column.heading(in: table.language), font: headingFont)
            if !column.mayTruncate {
                for row in table.rows where index < row.values.count {
                    needed = max(needed, width(of: row.values[index], font: cellFont))
                }
            }
            return needed + cellPadding * 2
        }

        let weights = table.columns.map(weight(for:))
        let required = minimum.reduce(0, +)

        // Not enough paper even for that — a dozen columns of long words on
        // one sheet. Everything shares the squeeze, which is what the page
        // did before and the only honest answer when there is no room.
        guard required < availableWidth else {
            let total = weights.reduce(0, +)
            guard total > 0 else {
                return Array(repeating: availableWidth / CGFloat(table.columns.count), count: table.columns.count)
            }
            return weights.map { availableWidth * $0 / total }
        }

        // The remainder goes to the columns that can use it. Where none can,
        // it is spread by weight so the page still fills its width.
        let flexible = zip(table.columns, weights).map { $0.mayTruncate ? $1 : 0 }
        let share = flexible.contains(where: { $0 > 0 }) ? flexible : weights
        let total = share.reduce(0, +)
        let spare = availableWidth - required
        return zip(minimum, share).map { $0 + (total > 0 ? spare * $1 / total : 0) }
    }

    private static let headingFont = UIFont.systemFont(ofSize: 9, weight: .semibold)
    private static let cellFont = UIFont.systemFont(ofSize: 9.5)

    private static func width(of text: String, font: UIFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private static func weight(for column: ReportColumn) -> CGFloat {
        switch column {
        case .date: return 1.1
        case .weekday: return 0.6
        case .dayType: return 1.2
        case .job: return 1.1
        case .start, .end: return 0.8
        case .breakTime: return 0.7
        case .worked, .expected, .overtime, .balance, .credited: return 0.9
        case .cumulativeBalance: return 1.1
        case .holiday: return 1.4
        case .location: return 1.3
        case .tags: return 1.3
        case .note: return 2.2
        }
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        font: UIFont,
        color: UIColor,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributed = NSAttributedString(
            string: text,
            attributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
        attributed.draw(in: rect)
    }
}
