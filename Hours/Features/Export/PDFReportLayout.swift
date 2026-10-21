import UIKit

/// What goes on one printed page.
struct PDFPagePlan: Hashable {
    var number: Int
    /// The header block — eyebrow, headline, tiles — opens the first page only.
    var showsTitle: Bool
    /// The column headings, on every page that has table rows under it.
    var showsHeadings: Bool
    var rows: Range<Int>
    /// The total row and the summary, which always come together and always
    /// on the last page.
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

    // MARK: - Pages

    func pages() -> [PDFPagePlan] {
        var plans: [PDFPagePlan] = []
        var next = 0
        var closed = false

        repeat {
            let number = plans.count + 1
            var y = PDFReportStyle.topMargin
            if number == 1 { y += titleBlockHeight }

            let first = next
            let hasRows = next < table.rows.count
            if hasRows { y += headingBlockHeight }

            // At least one row per page, so a table that somehow never fits
            // still advances rather than producing pages forever.
            while next < table.rows.count {
                let height = rowHeight(table.rows[next])
                if y + height > PDFReportStyle.contentBottom && next > first { break }
                y += height
                next += 1
            }

            var closes = false
            if next >= table.rows.count {
                // The summary takes a page of its own rather than being
                // silently dropped. The renderer before the one before this
                // drew the totals wherever the last row left off and skipped
                // any line that did not fit, so a report whose rows ended near
                // the bottom of a page came out with its totals partly or
                // entirely missing — and looked perfectly fine otherwise.
                if y + closingHeight <= PDFReportStyle.contentBottom || first == next {
                    closes = true
                }
            }

            // A page that carries only the closing block still heads its
            // total row, so the figures can be read against their columns.
            let headsTotal = !hasRows && closes && table.totalRow != nil
            plans.append(PDFPagePlan(
                number: number,
                showsTitle: number == 1,
                showsHeadings: hasRows || headsTotal,
                rows: first..<next,
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

    // MARK: - Heights

    /// Eyebrow, headline and byline beside the tiles, then the rule under them.
    var titleBlockHeight: CGFloat { 70 }

    var headingBlockHeight: CGFloat { PDFReportStyle.headingHeight + 2 }

    func rowHeight(_ row: ReportRow) -> CGFloat {
        row.role == .day ? PDFReportStyle.rowHeight : PDFReportStyle.closingRowHeight
    }

    /// The total row and the summary under it, asked for in advance rather
    /// than discovered halfway down the page.
    var closingHeight: CGFloat {
        var height: CGFloat = 0
        if let totalRow = table.totalRow { height += rowHeight(totalRow) }
        if !table.totals.isEmpty { height += 10 + summaryHeight }
        return height
    }

    /// Three columns of label and figure under a small heading.
    var summaryHeight: CGFloat {
        guard !table.totals.isEmpty else { return 0 }
        return 14 + CGFloat(summaryLinesPerColumn) * 12
    }

    static let summaryColumns = 3

    var summaryLinesPerColumn: Int {
        Int((Double(table.totals.count) / Double(PDFReportLayout.summaryColumns)).rounded(.up))
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

        let padding = PDFReportStyle.cellPadding * 2
        let headings = columnHeadings()
        var everyRow = table.rows
        if let totalRow = table.totalRow { everyRow.append(totalRow) }

        var minimum = columns.indices.map { index -> CGFloat in
            let column = columns[index]
            var needed = PDFReportStyle.width(of: headings[index], font: PDFReportStyle.headingFont)
            if !column.mayTruncate {
                for row in everyRow where index < row.values.count {
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

        let weights = columns.map(PDFReportLayout.weight(for:))
        let required = minimum.reduce(0, +)

        // Not enough paper even for that — a dozen columns of long words on
        // one sheet. Everything shares the squeeze, which is the only honest
        // answer when there is no room.
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
        }
    }
}
