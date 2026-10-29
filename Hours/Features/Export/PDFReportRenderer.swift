import UIKit

/// Draws a report as a paginated PDF.
///
/// A real table — ruled, aligned, with headings that repeat on every page —
/// under a header block with the figures that matter in boxes, and closed by
/// a ruled total, the summary and the lines to sign on. Where everything goes
/// is decided by `PDFReportLayout` first, so the footer can say how many
/// pages there are; this only draws what it is told.
enum PDFReportRenderer {
    static var pageSize: CGSize { PDFReportStyle.pageSize }

    /// Visible to the tests, which check that no column that must not be cut
    /// short comes out narrower than the text it draws.
    static var margin: CGFloat { PDFReportStyle.margin }

    /// - Parameter photos: the site diary's photos by id, as small JPEGs
    ///   (`DiaryPhotoProcessor.printJPEG`); only a director's sheet with its
    ///   diary included has any.
    static func data(for table: ReportTable, photos: [UUID: Data] = [:], generatedOn date: Date = Date()) -> Data {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: table.title,
            kCGPDFContextCreator as String: "Zeitkonto"
        ]
        let bounds = CGRect(origin: .zero, size: pageSize)
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)

        // A site sheet too wide for the page prints as parts, a group of
        // people each, one after another; anything else is one part, itself.
        var built: [Section] = []
        var pagesSoFar = 0
        for part in PDFReportLayout.printedParts(of: table) {
            let layout = PDFReportLayout(table: part)
            let plans = layout.pages(firstNumber: pagesSoFar + 1)
            pagesSoFar += plans.count
            built.append(Section(
                table: part,
                layout: layout,
                plans: plans,
                painter: PDFTablePainter(
                    table: part,
                    layout: layout,
                    widths: layout.columnWidths(availableWidth: PDFReportStyle.contentWidth)
                )
            ))
        }
        let sections = built
        let tablePages = pagesSoFar
        // The sign-off and the diary follow the table — every part of it —
        // on pages of their own, and count in the footer's "of".
        let appendix = PDFAppendix(table: table, photos: photos.compactMapValues { DiaryPhotoProcessor.printableImage(from: $0) })
        let extra = appendix.pages()
        let pageCount = tablePages + extra.count
        let decorations = PDFPageDecorations(
            table: table, layout: PDFReportLayout(table: table), generatedOn: date, pageCount: pageCount
        )

        return renderer.pdfData { context in
            for section in sections {
                let sectionDecorations = PDFPageDecorations(
                    table: section.table, layout: section.layout, generatedOn: date, pageCount: pageCount
                )
                for plan in section.plans {
                    context.beginPage()
                    draw(plan, table: section.table, painter: section.painter, decorations: sectionDecorations)
                }
            }
            for (index, page) in extra.enumerated() {
                context.beginPage()
                autoreleasepool { appendix.draw(page) }
                decorations.drawFooter(page: tablePages + index + 1, isLast: false)
            }
        }
    }

    /// One printed table: the whole report, or a part of a split site sheet.
    private struct Section {
        let table: ReportTable
        let layout: PDFReportLayout
        let plans: [PDFPagePlan]
        let painter: PDFTablePainter
    }

    /// The tables the PDF prints in turn, for the tests: one, unless a site
    /// sheet's crew is too big for the page.
    static func parts(of table: ReportTable) -> [ReportTable] {
        PDFReportLayout.printedParts(of: table)
    }

    /// The widths the table is drawn at, for the tests.
    static func columnWidths(for table: ReportTable, availableWidth: CGFloat) -> [CGFloat] {
        PDFReportLayout(table: table).columnWidths(availableWidth: availableWidth)
    }

    private static func draw(
        _ plan: PDFPagePlan,
        table: ReportTable,
        painter: PDFTablePainter,
        decorations: PDFPageDecorations
    ) {
        var y = PDFReportStyle.topMargin
        if plan.showsTitle {
            y = decorations.drawHeader(at: y)
        }
        if plan.showsHeadings {
            y = painter.drawHeadings(at: y)
        }
        for index in plan.rows {
            y = painter.drawRow(table.rows[index], at: y)
        }
        if plan.drawsTotal, let totalRow = table.totalRow {
            y = painter.drawRow(totalRow, at: y)
        }
        if plan.closes, !table.totals.isEmpty || !table.bySite.isEmpty {
            y = decorations.drawSummary(at: y + 10)
        }
        decorations.drawFooter(page: plan.number, isLast: plan.closes)
    }
}

/// Draws the table itself: headings and rows.
struct PDFTablePainter {
    let table: ReportTable
    let layout: PDFReportLayout
    let widths: [CGFloat]

    /// Where each column starts.
    private var origins: [CGFloat] {
        var x = PDFReportStyle.margin
        return widths.map { width in
            defer { x += width }
            return x
        }
    }

    private var tableRight: CGFloat { PDFReportStyle.margin + PDFReportStyle.contentWidth }

    // MARK: - Headings

    func drawHeadings(at y: CGFloat) -> CGFloat {
        let height = PDFReportStyle.headingHeight
        let headings = layout.columnHeadings()
        let xs = origins
        let padding = PDFReportStyle.cellPadding

        for (index, column) in table.columns.enumerated() where index < widths.count {
            draw(
                headings[index],
                in: CGRect(x: xs[index] + padding, y: y, width: widths[index] - padding * 2, height: height),
                font: PDFReportStyle.headingFont,
                color: PDFReportStyle.secondary,
                alignment: column.isNumeric ? .right : .left
            )
        }
        // A person's name heads both of their columns.
        for (group, range) in zip(table.validGroups, table.groupRanges) where range.count > 1 {
            let frame = span(range)
            draw(
                layout.printedHeading(group.title),
                in: CGRect(x: frame.minX + padding, y: y, width: frame.width - padding * 2, height: height),
                font: PDFReportStyle.headingFont,
                color: PDFReportStyle.secondary,
                alignment: .left
            )
        }
        drawGroupSeparators(from: y, to: y + height)

        PDFReportStyle.line(
            from: CGPoint(x: PDFReportStyle.margin, y: y + height),
            to: CGPoint(x: tableRight, y: y + height),
            width: 0.8,
            color: PDFReportStyle.ink
        )
        return y + layout.headingBlockHeight
    }

    // MARK: - Rows

    func drawRow(_ row: ReportRow, at y: CGFloat) -> CGFloat {
        let height = layout.rowHeight(row)
        let full = CGRect(x: PDFReportStyle.margin, y: y, width: PDFReportStyle.contentWidth, height: height)

        if let wash = wash(for: row) {
            wash.setFill()
            UIBezierPath(rect: full).fill()
        }
        if row.role == .total {
            PDFReportStyle.line(
                from: CGPoint(x: full.minX, y: y),
                to: CGPoint(x: full.maxX, y: y),
                width: 1.2,
                color: PDFReportStyle.ink
            )
        }

        var covered = drawMergedGroups(of: row, at: y, height: height)
        let xs = origins
        let padding = PDFReportStyle.cellPadding
        // A closing label across the empty date, day and site cells.
        let label = layout.labelSpan(of: row)
        covered.formUnion(label.dropFirst())
        for (index, column) in table.columns.enumerated() where index < row.values.count && index < widths.count {
            guard !covered.contains(index) else { continue }
            let width = index == 0 ? label.reduce(CGFloat(0), { $0 + widths[$1] }) : widths[index]
            draw(
                row.values[index],
                in: CGRect(x: xs[index] + padding, y: y, width: width - padding * 2, height: height),
                font: row.splitDay == .subtotal
                    ? PDFReportStyle.cellBoldFont
                    : PDFReportLayout.font(for: column, role: row.role),
                color: color(of: row, column: column, index: index),
                alignment: column.isNumeric ? .right : .left
            )
        }

        drawGroupSeparators(from: y, to: y + height)
        // A day split across sites is one group: ruled under its Total row only.
        if row.role == .day && row.splitDay != .site {
            PDFReportStyle.line(
                from: CGPoint(x: full.minX, y: full.maxY),
                to: CGPoint(x: full.maxX, y: full.maxY),
                width: 0.5,
                color: PDFReportStyle.rule
            )
        }
        return y + height
    }

    /// Someone not there that day: one faint dash across their group, or why
    /// they were away ("Sick leave") a step darker. Returns the columns it
    /// covered, so they are not drawn again.
    private func drawMergedGroups(of row: ReportRow, at y: CGFloat, height: CGFloat) -> Set<Int> {
        let ranges = table.groupRanges
        var covered = Set<Int>()
        for group in row.mergedGroups.sorted() where group < ranges.count {
            let range = ranges[group]
            let value = range.lowerBound < row.values.count ? row.values[range.lowerBound] : ""
            let isReason = !value.isEmpty && value != "—"
            draw(
                isReason ? value : "—",
                in: CGRect(x: span(range).minX, y: y, width: span(range).width, height: height),
                font: PDFReportStyle.cellFont,
                color: isReason ? PDFReportStyle.secondary : PDFReportStyle.faint,
                alignment: .center
            )
            covered.formUnion(range)
        }
        return covered
    }

    private func wash(for row: ReportRow) -> UIColor? {
        guard row.role == .day else { return nil }
        if row.splitDay != nil { return PDFReportStyle.splitDayWash }
        if row.isAbsence { return PDFReportStyle.absenceWash }
        if !row.isWorkingDay { return PDFReportStyle.restWash }
        return nil
    }

    /// The colour of one cell, from what it means rather than where it is.
    private func color(of row: ReportRow, column: ReportColumn, index: Int) -> UIColor {
        if row.flagged.contains(index) { return PDFReportStyle.accent }
        if row.role == .count { return PDFReportStyle.secondary }
        // A weekend is there to be counted, not read.
        if row.role == .day && !row.isWorkingDay && !row.isAbsence { return PDFReportStyle.faint }

        // Plus and minus figures carry their sign in colour as well.
        switch column {
        case .overtime, .balance, .cumulativeBalance:
            let minutes = index < row.minutes.count ? row.minutes[index] : nil
            if let minutes, minutes > 0 { return PDFReportStyle.positive }
            if let minutes, minutes < 0 { return PDFReportStyle.negative }
        default:
            break
        }

        if column == .times { return PDFReportStyle.secondary }
        if column == .note && table.kind == .siteSheet { return PDFReportStyle.secondary }
        if row.role == .day && !row.hasEntry { return PDFReportStyle.secondary }
        return PDFReportStyle.ink
    }

    // MARK: - Helpers

    private func span(_ range: Range<Int>) -> CGRect {
        let xs = origins
        guard let first = range.first, first < xs.count else { return .zero }
        let width = range.reduce(CGFloat(0)) { $0 + ($1 < widths.count ? widths[$1] : 0) }
        return CGRect(x: xs[first], y: 0, width: width, height: 0)
    }

    /// A rule before every column group but the first, which starts at the
    /// margin: before each person's pair and before a group of one too, so
    /// a site sheet's Date and Day are ruled apart like everyone else.
    private func drawGroupSeparators(from top: CGFloat, to bottom: CGFloat) {
        for range in table.groupRanges where (range.first ?? 0) > 0 {
            separator(at: span(range).minX, from: top, to: bottom)
        }
    }

    private func separator(at x: CGFloat, from top: CGFloat, to bottom: CGFloat) {
        PDFReportStyle.line(
            from: CGPoint(x: x, y: top),
            to: CGPoint(x: x, y: bottom),
            width: 0.5,
            color: PDFReportStyle.rule
        )
    }

    private func draw(_ text: String, in rect: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment) {
        PDFReportStyle.draw(text, in: rect, font: font, color: color, alignment: alignment)
    }
}
