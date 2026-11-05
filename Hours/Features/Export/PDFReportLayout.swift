import UIKit

/// What goes on one printed page.
struct PDFPagePlan: Hashable {
    var number: Int
    /// The header block — eyebrow, headline, tiles — opens the first page
    /// only; of a split site sheet, the first page of each part.
    var showsTitle: Bool
    /// The column headings, on every page that has table rows under it.
    var showsHeadings: Bool
    var rows: Range<Int>
    /// The total row under the last day. Usually on the last page with the
    /// summary; on the page before it when the days and the total fit there
    /// and the summary does not, so a month's last day is not sent over to a
    /// page of its own just to keep the total company.
    var drawsTotal: Bool = false
    /// The summary and the lines to sign on: the last page.
    var closes: Bool
}

/// Where everything on a printed report goes, worked out before anything is
/// drawn.
///
/// Laid out first and drawn second because the footer says "page 2 of 3",
/// and the 3 is not known until the last row has found its page. The old
/// renderer drew as it went and could only ever say "page 2".
struct PDFReportLayout {
    let table: ReportTable
    /// How tall a day row is: see `fittedRowHeights`.
    let dayRowHeight: CGFloat
    /// How tall a total or a count under the days is: 18 points, or 14 on
    /// a sheet for several sites when that is what keeps its By site block
    /// on the page with them.
    let closingRowHeight: CGFloat

    init(table: ReportTable) {
        self.table = table
        let heights = Self.fittedRowHeights(
            for: table,
            titleHeight: Self.headerBlockHeight(for: table),
            headingHeight: PDFReportStyle.headingHeight + 2
        )
        self.dayRowHeight = heights.day
        self.closingRowHeight = heights.closing
    }

    /// The tightest closing rows a sheet for several sites may have.
    static let compactClosingRowHeight: CGFloat = 14

    /// 14 points, or as little as 12 when that is what keeps every day of the
    /// table and its closing rows on the first page. A month is up to 31 days
    /// and 14 points fit 30, so the 31st used to go over to a page of its own
    /// with the total; a longer range keeps the full height and simply runs on.
    ///
    /// A sheet for several sites tries to keep its By site block — three or
    /// four short lines — on that page too, first with the day rows tighter,
    /// then with its closing rows tighter as well. It went over to a second
    /// page alone, with the legend, and left the first with room to spare.
    private static func fittedRowHeights(
        for table: ReportTable,
        titleHeight: CGFloat,
        headingHeight: CGFloat
    ) -> (day: CGFloat, closing: CGFloat) {
        let standard = PDFReportStyle.closingRowHeight
        let days = table.rows.filter { $0.role == .day }.count
        guard days > 0 else { return (PDFReportStyle.rowHeight, standard) }
        let closingRows = table.rows.count - days + (table.totalRow == nil ? 0 : 1)
        let room = { (closing: CGFloat) in
            PDFReportStyle.contentBottom - PDFReportStyle.topMargin - titleHeight - headingHeight
                - CGFloat(closingRows) * closing
        }
        let heights = Array(stride(from: PDFReportStyle.rowHeight, through: 12, by: -0.5))
        if table.kind == .siteSheet && !table.bySite.isEmpty {
            let block = summaryGap + bySiteOnlyHeight(lines: table.bySite.count)
            for closing in [standard, compactClosingRowHeight] {
                if let height = heights.first(where: { CGFloat(days) * $0 <= room(closing) - block }) {
                    return (height, closing)
                }
            }
        }
        if let height = heights.first(where: { CGFloat(days) * $0 <= room(standard) }) {
            return (height, standard)
        }
        return (PDFReportStyle.rowHeight, standard)
    }

    /// The space between the last closing row and the summary under it.
    static let summaryGap: CGFloat = 10

    // MARK: - Pages

    /// - Parameter firstNumber: the number this table's first page has in
    ///   the document: 1, unless it is a later part of a split site sheet.
    func pages(firstNumber: Int = 1) -> [PDFPagePlan] {
        var plans: [PDFPagePlan] = []
        var next = 0
        var closed = false
        var totalDrawn = false

        repeat {
            let number = firstNumber + plans.count
            let isFirst = plans.isEmpty
            var y = PDFReportStyle.topMargin
            // A later page says what it belongs to, smaller.
            y += isFirst ? titleBlockHeight : runningHeaderHeight

            let first = next
            let hasRows = next < table.rows.count
            if hasRows { y += headingBlockHeight }

            // At least one row per page, so a table that somehow never fits
            // still advances rather than producing pages forever.
            var tops: [CGFloat] = []
            while next < table.rows.count {
                let height = rowHeight(table.rows[next])
                if y + height > PDFReportStyle.contentBottom && next > first {
                    // A day on more than one site is not broken across pages,
                    // nor are the closing rows, which go over with the last
                    // few days rather than leave "Month total" behind.
                    var start = splitGroupStart(of: next)
                    let closingStart = table.rows.count - min(table.trailingSummaryRows, table.rows.count)
                    if table.trailingSummaryRows > 0, next >= closingStart {
                        start = splitGroupStart(of: closingStart - Self.daysCarriedWithTheClosingRows)
                    }
                    if start > first && start < next {
                        y = tops[start - first]
                        next = start
                    }
                    break
                }
                tops.append(y)
                y += height
                next += 1
            }

            // A sheet whose closing rows reached this page but whose By site
            // block does not fit under them takes the closing rows, and the
            // last few days with them, over to the next page, rather than
            // sending the block there alone.
            if next >= table.rows.count, next > first, table.trailingSummaryRows > 0,
               summaryBlockHeight > 0, y + summaryBlockHeight > PDFReportStyle.contentBottom {
                let closingStart = table.rows.count - min(table.trailingSummaryRows, table.rows.count)
                let carried = splitGroupStart(of: closingStart - Self.daysCarriedWithTheClosingRows)
                // Only from a page that keeps days of its own.
                if closingStart - Self.daysCarriedWithTheClosingRows > first, carried > first, carried < next {
                    y = tops[carried - first]
                    next = carried
                }
            }

            var closes = false
            var drawsTotal = false
            if next >= table.rows.count {
                // The summary takes a page of its own rather than being
                // silently dropped. The renderer before the one before this
                // drew the totals wherever the last row left off and skipped
                // any line that did not fit, so a report whose rows ended near
                // the bottom of a page came out with its totals partly or
                // entirely missing — and looked perfectly fine otherwise.
                let remaining = totalDrawn ? summaryBlockHeight : closingHeight
                if y + remaining <= PDFReportStyle.contentBottom || first == next {
                    closes = true
                    drawsTotal = !totalDrawn && table.totalRow != nil
                } else if !totalDrawn, let totalRow = table.totalRow, next > first,
                          y + rowHeight(totalRow) <= PDFReportStyle.contentBottom {
                    // The total stays under the days it adds up; the summary
                    // goes on.
                    drawsTotal = true
                }
                if drawsTotal { totalDrawn = true }
            }

            // A page that carries only the closing block still heads its
            // total row, so the figures can be read against their columns.
            let headsTotal = !hasRows && drawsTotal
            plans.append(PDFPagePlan(
                number: number,
                showsTitle: isFirst,
                showsHeadings: hasRows || headsTotal,
                rows: first..<next,
                drawsTotal: drawsTotal,
                closes: closes
            ))
            closed = closes
        } while !closed && plans.count < PDFReportLayout.maximumPages

        return plans
    }

    /// A hard stop, so a table that somehow never advances cannot spin
    /// forever. At roughly 28 rows to a page this is a working lifetime of
    /// daily entries many times over; it is set where reaching it is not
    /// possible, because reaching the old limit dropped rows without a word.
    static let maximumPages = 100_000

    /// How many day rows go over with the closing rows when those must leave
    /// the page: about a working week, so the totals stand under days.
    static let daysCarriedWithTheClosingRows = 5

    /// The first row of the day `index` belongs to, when it is a row of a
    /// day on more than one site; `index` itself otherwise.
    func splitGroupStart(of index: Int) -> Int {
        guard index >= 0, index < table.rows.count, table.rows[index].splitDay != nil else { return index }
        var start = index
        // The first site row carries the date; the others and the Total
        // under them have none.
        while start > 0, table.rows[start].splitDay != nil,
              table.rows[start].values.first?.isEmpty ?? true,
              table.rows[start - 1].splitDay != nil {
            start -= 1
        }
        return start
    }

    // MARK: - Heights

    /// The title, the kind and the period, the address and the day it was
    /// made beside the two figures, then the rule under them; on a part of a
    /// split sheet, the "People 1–5 of 9" line too. The address shares the
    /// grey line, so it adds no height of its own.
    var titleBlockHeight: CGFloat { Self.headerBlockHeight(for: table) }

    static func headerBlockHeight(for table: ReportTable) -> CGFloat {
        table.partLabel.isEmpty ? 70 : 84
    }

    var headingBlockHeight: CGFloat { PDFReportStyle.headingHeight + 2 }

    /// A page after the first: the eyebrow, the title on one smaller line,
    /// a rule (`PDFPageDecorations.drawRunningHeader`).
    var runningHeaderHeight: CGFloat { 36 }

    func rowHeight(_ row: ReportRow) -> CGFloat {
        row.role == .day ? dayRowHeight : closingRowHeight
    }

    /// The total row and the summary under it, asked for in advance rather
    /// than discovered halfway down the page.
    var closingHeight: CGFloat {
        var height: CGFloat = 0
        if let totalRow = table.totalRow { height += rowHeight(totalRow) }
        return height + summaryBlockHeight
    }

    /// The summary with the gap above it, without the total row.
    var summaryBlockHeight: CGFloat {
        table.totals.isEmpty && table.bySite.isEmpty ? 0 : Self.summaryGap + summaryHeight
    }

    /// Three columns of label and figure under a small heading; two beside
    /// the "By site" block when the period has more than one site. A sheet
    /// for several sites' month has the By site block alone.
    var summaryHeight: CGFloat {
        guard !table.totals.isEmpty else {
            return table.bySite.isEmpty ? 0 : Self.bySiteOnlyHeight(lines: table.bySite.count)
        }
        let lines = table.bySite.isEmpty ? summaryLinesPerColumn : max(summaryLinesPerColumn, table.bySite.count)
        return 14 + CGFloat(lines) * 12
    }

    /// The By site block on its own: a heading and a line per site.
    private static func bySiteOnlyHeight(lines: Int) -> CGFloat {
        14 + CGFloat(lines) * 12
    }

    static let summaryColumns = 3

    /// How many columns the summary's own figures take.
    var summaryFigureColumns: Int {
        table.bySite.isEmpty ? PDFReportLayout.summaryColumns : PDFReportLayout.summaryColumns - 1
    }

    var summaryLinesPerColumn: Int {
        Int((Double(table.totals.count) / Double(summaryFigureColumns)).rounded(.up))
    }

    // MARK: - Columns

    /// The font a cell is drawn in. Hours and every closing row are bold.
    static func font(for column: ReportColumn, role: ReportRowRole) -> UIFont {
        role != .day || column == .worked ? PDFReportStyle.cellBoldFont : PDFReportStyle.cellFont
    }

    /// A heading as the page prints it: in capitals, in the export language.
    func printedHeading(_ text: String) -> String {
        text.uppercased(with: table.language.locale)
    }

    /// The headings drawn over each column. A column inside a group of
    /// several has none of its own: the group's title spans it.
    func columnHeadings() -> [String] {
        let titles = table.columnHeadings()
        var headings = titles.map(printedHeading)
        for range in table.groupRanges where range.count > 1 {
            for index in range { headings[index] = "" }
        }
        return headings
    }

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
    /// and the note gives up the difference. A group's title must fit across
    /// its columns too, so a person's name is never cut above their hours.
    func columnWidths(availableWidth: CGFloat) -> [CGFloat] {
        let columns = table.columns
        guard !columns.isEmpty else { return [] }

        let minimum = minimumWidths()
        let weights = columns.map(PDFReportLayout.weight(for:))
        let required = minimum.reduce(0, +)

        // Not enough paper even for that — a dozen columns of long words on
        // one sheet. Everything shares the squeeze, which is the only honest
        // answer when there is no room. A site sheet never gets here: it is
        // split across pages first (`printedParts`).
        guard required < availableWidth else {
            let total = weights.reduce(0, +)
            guard total > 0 else {
                return Array(repeating: availableWidth / CGFloat(columns.count), count: columns.count)
            }
            return weights.map { availableWidth * $0 / total }
        }

        // The remainder goes to the columns that can use it. Where none can,
        // it is spread by weight so the page still fills its width.
        let flexible = zip(columns, weights).map { $0.mayTruncate ? $1 : 0 }
        let share = flexible.contains(where: { $0 > 0 }) ? flexible : weights
        let total = share.reduce(0, +)
        let spare = availableWidth - required
        return zip(minimum, share).map { $0 + (total > 0 ? spare * $1 / total : 0) }
    }

    /// Whether every column gets at least what it cannot do without.
    func fits(availableWidth: CGFloat) -> Bool {
        minimumWidths().reduce(0, +) < availableWidth
    }

    /// What each column cannot do without: its heading, and every value of
    /// a column that must not be cut short, measured in the fonts the page
    /// draws, with a group's title fitting across its columns.
    func minimumWidths() -> [CGFloat] {
        let columns = table.columns
        guard !columns.isEmpty else { return [] }

        let padding = PDFReportStyle.cellPadding * 2
        let headings = columnHeadings()
        var everyRow = table.rows
        if let totalRow = table.totalRow { everyRow.append(totalRow) }

        // On a site sheet the site is what the row is about, so it is never
        // cut to "Trg Pravde Za…".
        let measured = { (column: ReportColumn) in
            !column.mayTruncate || (column == .site && self.table.kind == .siteSheet)
        }
        var minimum = columns.indices.map { index -> CGFloat in
            let column = columns[index]
            var needed = PDFReportStyle.width(of: headings[index], font: PDFReportStyle.headingFont)
            if measured(column) {
                for row in everyRow where index < row.values.count {
                    // A closing label runs on over the empty cells beside it.
                    if index == 0 && labelSpan(of: row).count > 1 { continue }
                    // A dash spanning an absent person's group draws across
                    // the whole group, not in this column.
                    let font = PDFReportLayout.font(for: column, role: row.role)
                    needed = max(needed, PDFReportStyle.width(of: row.values[index], font: font))
                }
            }
            return needed + padding
        }

        for (group, range) in zip(table.validGroups, table.groupRanges) where range.count > 1 {
            let title = PDFReportStyle.width(of: printedHeading(group.title), font: PDFReportStyle.headingFont)
            let have = range.reduce(CGFloat(0)) { $0 + minimum[$1] }
            if have < title + padding, let last = range.last {
                minimum[last] += title + padding - have
            }
        }
        for row in everyRow {
            let range = labelSpan(of: row)
            guard range.count > 1, let first = row.values.first, let last = range.last else { continue }
            let label = PDFReportStyle.width(of: first, font: PDFReportLayout.font(for: columns[0], role: row.role))
            let have = range.reduce(CGFloat(0)) { $0 + minimum[$1] }
            if have < label + padding {
                minimum[last] += label + padding - have
            }
        }
        return minimum
    }

    /// The columns a site sheet's closing label — "Month total", a site's
    /// name — is drawn across: the date's, and the empty day and site cells
    /// beside it. Measured against the date column alone, "Month total"
    /// made the dates twice as wide as they are. Any other row: the first
    /// column alone.
    func labelSpan(of row: ReportRow) -> Range<Int> {
        let columns = table.columns
        guard table.kind == .siteSheet, row.role != .day, !columns.isEmpty else { return 0..<1 }
        var end = 1
        while end < columns.count, end < row.values.count,
              [ReportColumn.weekday, .site].contains(columns[end]), row.values[end].isEmpty {
            end += 1
        }
        return 0..<end
    }

    // MARK: - Parts

    /// The tables the PDF prints one after another: the table itself, or a
    /// site sheet too wide for the page split into groups of people
    /// (`SiteSheetBuilder.split`).
    ///
    /// Every person is two columns that may not be cut short, so the page
    /// holds five or six before the times would be squeezed. The most people
    /// a part can hold is measured, not guessed: the largest group size at
    /// which every part fits, in the fonts the page draws, with that part's
    /// own names and times. A sheet everyone fits on comes back alone and
    /// unchanged, and so prints exactly as it did before sheets were split.
    static func printedParts(
        of table: ReportTable,
        availableWidth: CGFloat = PDFReportStyle.contentWidth
    ) -> [ReportTable] {
        guard let people = SiteSheetBuilder.peopleCount(in: table), people > 1,
              !PDFReportLayout(table: table).fits(availableWidth: availableWidth)
        else { return [table] }
        for perPage in stride(from: people - 1, through: 2, by: -1) {
            let parts = SiteSheetBuilder.split(table, peoplePerPage: perPage)
            if parts.allSatisfy({ PDFReportLayout(table: $0).fits(availableWidth: availableWidth) }) {
                return parts
            }
        }
        // One person to a page is as far as splitting goes; a name too long
        // even for that is squeezed like any other column that has no room.
        return SiteSheetBuilder.split(table, peoplePerPage: 1)
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
        case .times: return 1.0
        case .earnings: return 0.9
        case .allowance: return 0.9
        case .kilometres: return 0.6
        case .travel: return 0.8
        case .site: return 1.4
        }
    }
}
