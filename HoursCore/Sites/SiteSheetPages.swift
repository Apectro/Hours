import Foundation

/// A big crew's sheet split into parts for the printed page.
///
/// Every person is two columns that may never be cut short — "07:00–16:00"
/// and their hours — so an A4 page runs out of width at some crew size. The
/// PDF then prints the month once per group of people, each part a complete
/// table of its own: the date and the day, that group's people, the notes,
/// and that group's closing rows. How many fit is measured by the app, in the
/// fonts the page draws; how the sheet is cut is decided here.
///
/// Only the PDF is split. A workbook has the width a page does not, and a
/// CSV is one table by nature.
extension SiteSheetBuilder {
    /// How many people the sheet has, or `nil` for a table that is not a
    /// site sheet in the shape `makeTable` writes: the leading columns, a
    /// group of two per person, and the notes.
    static func peopleCount(in table: ReportTable) -> Int? {
        guard table.kind == .siteSheet else { return nil }
        let groups = table.validGroups
        let people = groups.count - leadingColumns - 1
        guard people >= 0,
              table.columns.count == leadingColumns + people * 2 + 1,
              groups.prefix(leadingColumns).allSatisfy({ $0.span == 1 }),
              groups.dropFirst(leadingColumns).dropLast().allSatisfy({ $0.span == 2 }),
              groups.last?.span == 1
        else { return nil }
        return people
    }

    /// Consecutive groups of at most `perPage` people, as even as they can
    /// be: seven at five a page is four and three, not five and two, so the
    /// last page does not look like an afterthought. The larger groups come
    /// first.
    static func groupSizes(people: Int, perPage: Int) -> [Int] {
        guard people > 0 else { return [] }
        let perPage = max(1, perPage)
        let count = (people + perPage - 1) / perPage
        let base = people / count
        let larger = people % count
        return (0..<count).map { $0 < larger ? base + 1 : base }
    }

    /// The sheet as the parts the PDF prints, each with `peoplePerPage`
    /// people at most. A sheet everyone fits on — and any other table —
    /// comes back as it is, alone, so it prints exactly as before.
    static func split(_ table: ReportTable, peoplePerPage: Int) -> [ReportTable] {
        guard let people = peopleCount(in: table), people > max(1, peoplePerPage) else { return [table] }
        var parts: [ReportTable] = []
        var first = 0
        for size in groupSizes(people: people, perPage: peoplePerPage) {
            parts.append(part(of: table, people: first..<(first + size), of: people))
            first += size
        }
        return parts
    }

    /// One part: the leading columns, `people`'s groups and the notes, every
    /// mark moved along with its person.
    private static func part(of table: ReportTable, people: Range<Int>, of total: Int) -> ReportTable {
        let lead = leadingColumns
        let noteColumn = table.columns.count - 1
        let noteGroup = table.validGroups.count - 1

        let columns = Array(0..<lead)
            + people.flatMap { [lead + $0 * 2, lead + $0 * 2 + 1] }
            + [noteColumn]
        let groups = Array(0..<lead) + people.map { lead + $0 } + [noteGroup]
        let newColumn = Dictionary(uniqueKeysWithValues: columns.enumerated().map { ($1, $0) })
        let newGroup = Dictionary(uniqueKeysWithValues: groups.enumerated().map { ($1, $0) })

        func pick<T>(_ cells: [T]) -> [T] {
            // `numbers` is empty on a sheet without quantities, and stays so.
            columns.compactMap { $0 < cells.count ? cells[$0] : nil }
        }
        func narrow(_ row: ReportRow) -> ReportRow {
            var row = row
            row.values = pick(row.values)
            row.minutes = pick(row.minutes)
            row.numbers = pick(row.numbers)
            row.flagged = Set(row.flagged.compactMap { newColumn[$0] })
            row.mergedGroups = Set(row.mergedGroups.compactMap { newGroup[$0] })
            return row
        }

        var part = table
        part.columns = columns.map { table.columns[$0] }
        if let overrides = table.headingOverrides, overrides.count == table.columns.count {
            part.headingOverrides = columns.map { overrides[$0] }
        }
        part.columnGroups = groups.map { table.validGroups[$0] }

        // The days, then the closing rows. Month total and days worked are
        // always there; a row of sick or leave days only where somebody in
        // this part had one, as the whole sheet has it only where anybody did.
        let summaryStart = table.rows.count - min(table.trailingSummaryRows, table.rows.count)
        var rows: [ReportRow] = []
        var summaries = 0
        for (index, original) in table.rows.enumerated() {
            let row = narrow(original)
            if index >= summaryStart {
                let isOptional = index - summaryStart >= 2
                let personCells = row.values.dropFirst(lead).dropLast()
                if isOptional && personCells.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    continue
                }
                summaries += 1
            }
            rows.append(row)
        }
        part.rows = rows
        part.trailingSummaryRows = summaries
        part.totalRow = table.totalRow.map(narrow)

        part.partLabel = table.language.peopleOnPage((people.lowerBound + 1)...people.upperBound, of: total)
        // The sign-off and the diary follow the whole sheet once, after the
        // last part, rather than after each.
        part.signOff = []
        part.diary = nil
        return part
    }
}
