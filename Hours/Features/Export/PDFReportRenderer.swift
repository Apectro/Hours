import UIKit

/// Draws a report as a paginated PDF.
///
/// A real table — ruled, aligned, with a header that repeats on every page and
/// a totals block at the end — rather than a screenshot of a list. Numeric
/// columns are right-aligned so figures line up down the page.
enum PDFReportRenderer {
    /// A4 landscape. Wide enough for ten columns without squeezing.
    static let pageSize = CGSize(width: 842, height: 595)

    private static let margin: CGFloat = 36
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
                font: .systemFont(ofSize: 9, weight: .semibold),
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
                font: .systemFont(ofSize: 9.5),
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

    /// Column widths from per-column weights, normalised to the page.
    static func columnWidths(for table: ReportTable, availableWidth: CGFloat) -> [CGFloat] {
        let weights = table.columns.indices.map { weight(forColumnAt: $0, in: table) }
        let total = weights.reduce(0, +)
        guard total > 0 else {
            let equal = availableWidth / CGFloat(max(table.columns.count, 1))
            return Array(repeating: equal, count: table.columns.count)
        }
        return weights.map { availableWidth * $0 / total }
    }

    /// The tuned weight below, raised when the column's contents will not fit
    /// in it.
    ///
    /// The weights were chosen against "9h 45m", six characters, and held
    /// only while nothing was longer — a three-figure total or a negative
    /// running balance is eight, and a column tuned for six clips it. A
    /// truncated note is untidy; a truncated duration is a wrong number, so
    /// duration columns take whatever room their widest value needs and the
    /// note gives it up.
    ///
    /// It was a translated unit that exposed this — "9 Std 45 Min" in a
    /// column built for "9h 45m" — and the units are no longer translated,
    /// but the measurement stays: the constant was wrong before any language
    /// touched it.
    private static func weight(forColumnAt index: Int, in table: ReportTable) -> CGFloat {
        let column = table.columns[index]
        let base = weight(for: column)
        guard column.isDuration else { return base }

        let widest = table.rows.reduce(0) { widest, row in
            max(widest, index < row.values.count ? row.values[index].count : 0)
        }
        let englishReference = 6
        guard widest > englishReference else { return base }
        return base * CGFloat(widest) / CGFloat(englishReference)
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
