import Foundation

/// What the defects PDF says (1.4, Polish pages 22–24), in the export
/// language. The message (`DefectsDocument.text`) is not changed by any of
/// this.
///
/// Page 1 is the whole list: "<site> · Defects", the address, "as of" the
/// day and your name, four figures — open, fixed, the oldest open and the
/// floor with the most open — then a table grouped by the site's floors.
/// Fixed defects are lines in the table only. From the page after the
/// table, each open defect has half a page: its number, what and where, its
/// marked photo, who noted it and how long it has been open (long when more
/// than `longOpenDays`), who fixes it, and boxes to tick walking the site.
extension DefectsDocument {
    /// Open longer than this many days is said in the table and in red.
    static let longOpenDays = 7

    /// A defect's state as the PDF prints it.
    enum Status: Hashable, Sendable {
        case open
        /// Open longer than `longOpenDays`.
        case longOpen(days: Int)
        case fixed(CalendarDate)
    }

    /// Page 1's figures, over every defect on the site.
    struct Figures: Hashable, Sendable {
        let open: Int
        let fixed: Int
        /// The longest an open defect has waited, in days, and since when.
        let oldestOpenDays: Int?
        let oldestOpenSince: CalendarDate?
        /// The floor with the most open defects; between two with as many,
        /// the one first in the site's floor order.
        let mostOpenFloor: String?
        let mostOpenCount: Int
    }

    /// One figure as printed: a value over a small label.
    struct FigureText: Hashable, Sendable {
        enum Tone: Hashable, Sendable { case open, fixed, plain }
        let value: String
        let label: String
        let tone: Tone
    }

    /// A line of the table.
    struct TableRow: Hashable, Sendable {
        let defectID: UUID
        let number: Int
        let what: String
        /// The room; "—" when none was noted.
        let room: String
        /// "3 Nov"
        let since: String
        /// Who fixes it, "—" for nobody yet; nil while the site does not
        /// assign defects.
        let fixes: String?
        let status: Status
        let statusText: String
    }

    /// A floor's lines, under the floor's name.
    struct TableGroup: Hashable, Sendable {
        let floor: String
        let rows: [TableRow]
    }

    /// An open defect's half page.
    struct Card: Hashable, Sendable {
        let defectID: UUID
        let number: Int
        let what: String
        /// "2nd floor · Room 4"
        let place: String
        /// The floor alone, for the page's header; empty when none.
        let floor: String
        /// "Noted 3 Nov, 14:12 by Ivan"
        let noted: String
        /// "Open for 9 days"
        let openFor: String
        let isLongOpen: Bool
        /// "Fixes: Ivan"; nil while the site does not assign defects.
        let fixes: String?
    }

    // MARK: - Days

    private var dateFormatting: CalendarFormatting {
        CalendarFormatting(locale: language.locale, calendar: calendar)
    }

    /// Calendar days from the day it was noted to the list's day (or to
    /// the day it was fixed). Never less than nought.
    func daysOpen(_ defect: Defect) -> Int {
        let noted = CalendarDate(defect.notedAt, calendar: calendar)
        let end = defect.state == .fixed
            ? CalendarDate(defect.fixedAt ?? defect.updatedAt, calendar: calendar)
            : date
        return max(0, noted.days(until: end, in: calendar))
    }

    func status(of defect: Defect) -> Status {
        if defect.state == .fixed {
            return .fixed(CalendarDate(defect.fixedAt ?? defect.updatedAt, calendar: calendar))
        }
        let days = daysOpen(defect)
        return days > Self.longOpenDays ? .longOpen(days: days) : .open
    }

    /// "Open", "Open · 9 days", "Fixed 2 Nov".
    func statusText(_ status: Status) -> String {
        switch status {
        case .open:
            return language(.statusOpen)
        case let .longOpen(days):
            return "\(language(.statusOpen)) · \(language.days(days))"
        case let .fixed(day):
            return language(.statusFixed, dateFormatting.shortDate(day))
        }
    }

    // MARK: - Page 1

    /// "4 Nov 2026": the list's day.
    var formattedDate: String {
        dateFormatting.dateWithYear(date)
    }

    /// "Ilica 207C · as of Wednesday 4 Nov 2026 · Marijo Mikša".
    var byline: String {
        let asOf = language(.asOf, dateFormatting.weekdayDateWithYear(date))
        return [address.trimmingCharacters(in: .whitespacesAndNewlines), asOf, ownerName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var figures: Figures {
        let open = defects.filter { $0.state == .open }
        let oldest = open.max { daysOpen($0) < daysOpen($1) }
        let groups = DefectList.groupedByFloor(DefectList.items(.open, in: defects), floors: floors)
            .filter { !$0.floor.isEmpty }
        // `max` would keep the last of equals; the first in floor order wins.
        var most: DefectList.FloorGroup?
        for group in groups where group.defects.count > (most?.defects.count ?? 0) {
            most = group
        }
        return Figures(
            open: open.count,
            fixed: DefectList.count(.fixed, in: defects),
            oldestOpenDays: oldest.map(daysOpen),
            oldestOpenSince: oldest.map { CalendarDate($0.notedAt, calendar: calendar) },
            mostOpenFloor: most?.floor,
            mostOpenCount: most?.defects.count ?? 0
        )
    }

    /// The four figures as printed; the last two only when something is open.
    var figureTexts: [FigureText] {
        let figures = self.figures
        var texts = [
            FigureText(value: String(figures.open), label: language(.figureOpen), tone: .open),
            FigureText(value: String(figures.fixed), label: language(.figureFixed), tone: .fixed),
        ]
        if let days = figures.oldestOpenDays, let since = figures.oldestOpenSince {
            texts.append(FigureText(
                value: language.days(days),
                label: language(.oldestOpen, dateFormatting.shortDate(since)),
                tone: .plain
            ))
        }
        if let floor = figures.mostOpenFloor {
            texts.append(FigureText(value: floor, label: language(.mostOpen, count: figures.mostOpenCount), tone: .plain))
        }
        return texts
    }

    /// The table's headings; Fixes only while the site assigns defects.
    var columns: [String] {
        var columns = [language(.columnNumber), language(.columnWhat), language(.columnWhere), language(.columnSince)]
        if showsAssignee { columns.append(language(.columnFixes)) }
        columns.append(language(.columnStatus))
        return columns
    }

    /// The listed defects by floor, numbered as `rows` and the message are.
    var table: [TableGroup] {
        let numbers = Dictionary(uniqueKeysWithValues: listed.enumerated().map { ($1.id, $0 + 1) })
        return DefectList.groupedByFloor(listed, floors: floors).map { group in
            TableGroup(
                floor: group.floor.isEmpty ? language(.noFloor) : group.floor,
                rows: group.defects.map { defect in
                    let status = status(of: defect)
                    return TableRow(
                        defectID: defect.id,
                        number: numbers[defect.id] ?? 0,
                        what: defect.what,
                        room: defect.room.isEmpty ? "—" : defect.room,
                        since: dateFormatting.shortDate(CalendarDate(defect.notedAt, calendar: calendar)),
                        fixes: showsAssignee ? (defect.assignee == .nobody ? "—" : fixer(of: defect)) : nil,
                        status: status,
                        statusText: statusText(status)
                    )
                }
            )
        }
    }

    /// The line under the table: where the half pages start.
    func tableNote(firstCardPage: Int) -> String {
        String(format: language(.halfPageNote), firstCardPage)
    }

    // MARK: - The half pages

    /// Each open defect listed, in the table's order.
    var cards: [Card] {
        table.flatMap(\.rows).compactMap { row -> Card? in
            guard let defect = listed.first(where: { $0.id == row.defectID }), defect.state == .open else { return nil }
            let days = daysOpen(defect)
            return Card(
                defectID: defect.id,
                number: row.number,
                what: defect.what,
                place: defect.whereLine,
                floor: defect.floor,
                noted: notedLine(defect),
                openFor: days == 0 ? language(.openSinceToday) : language(.openFor, language.days(days)),
                isLongOpen: days > Self.longOpenDays,
                fixes: showsAssignee ? language(.fixes, fixer(of: defect)) : nil
            )
        }
    }

    /// The boxes ticked on paper: Fixed, Date, Initials.
    var walkRound: [String] {
        [language(.boxFixed), language(.boxDate), language(.boxInitials)]
    }

    /// "Noted 3 Nov, 14:12 by Ivan"; noted by you, your name on the sheets,
    /// or no name at all.
    private func notedLine(_ defect: Defect) -> String {
        let day = CalendarDate(defect.notedAt, calendar: calendar)
        let parts = calendar.dateComponents([.hour, .minute], from: defect.notedAt)
        let time = dateFormatting.time(TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0), on: day)
        let moment = "\(dateFormatting.shortDate(day)), \(time)"
        let by = defect.notedBy.trimmingCharacters(in: .whitespacesAndNewlines)
        let who = by.isEmpty ? ownerName.trimmingCharacters(in: .whitespacesAndNewlines) : by
        guard !who.isEmpty else { return language(.notedOn, moment) }
        return String(format: language(.notedBy), moment, who)
    }

    // MARK: - Every page

    /// "Trg Pravde Zagreb · Defects · as of 4 Nov 2026"
    var footer: String {
        "\(title) · \(language(.asOf, formattedDate))"
    }

    /// "Page 2 of 4"
    func pageText(_ page: Int, of count: Int) -> String {
        let text = language.pageOf(page, count)
        guard let first = text.first else { return text }
        return String(first).uppercased(with: language.locale) + text.dropFirst()
    }
}
