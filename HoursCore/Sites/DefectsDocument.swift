import Foundation

/// A site's defects as they are sent (Camera board, phone 21), in the export
/// language: the PDF's header and numbered rows, and the same lines as a
/// message without the photos.
///
///     Trg Pravde Zagreb · Defects
///     Ilica 207C · 4 Nov 2026 · 4 open
///
///     1. Socket loose
///     2nd floor · Room 4 · Fixes: Ivan · since 3 Nov
///
/// The fixer is only there while the site assigns defects to people.
struct DefectsDocument: Sendable {
    let siteName: String
    let address: String
    let date: CalendarDate
    /// Every defect on the site; `onlyOpen` chooses.
    let defects: [Defect]
    let floors: [String]
    let onlyOpen: Bool
    let showsAssignee: Bool
    let ownerName: String
    let language: ExportLanguage
    let calendar: Calendar

    struct Row: Hashable, Sendable {
        let defectID: UUID
        let number: Int
        /// "1. Socket loose"
        let title: String
        /// "2nd floor · Room 4"
        let whereLine: String
        /// "Fixes: Ivan · since 3 Nov", "fixed 4 Nov".
        let detail: String
        let isFixed: Bool
    }

    private var formatting: CalendarFormatting {
        CalendarFormatting(locale: language.locale, calendar: calendar)
    }

    private var owner: String {
        ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The defects printed, in their numbered order.
    var listed: [Defect] {
        DefectList.listed(defects, state: onlyOpen ? .open : nil, floors: floors)
    }

    var openCount: Int {
        DefectList.count(.open, in: defects)
    }

    /// "Trg Pravde Zagreb · Defects"
    var title: String {
        "\(siteName) · \(language(.defects))"
    }

    /// "Ilica 207C · 4 Nov 2026 · 4 open"
    var subtitle: String {
        [address.trimmingCharacters(in: .whitespacesAndNewlines), formatting.dateWithYear(date), language(.openCount, count: openCount)]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    var rows: [Row] {
        listed.enumerated().map { index, defect in
            Row(
                defectID: defect.id,
                number: index + 1,
                title: "\(index + 1). \(defect.what)",
                whereLine: defect.whereLine,
                detail: detail(of: defect),
                isFixed: defect.state == .fixed
            )
        }
    }

    /// The message: the title, the subtitle, a line or two per defect, your
    /// name.
    var text: String {
        var lines = [title, subtitle]
        for row in rows {
            lines.append("")
            lines.append(row.title)
            let rest = [row.whereLine, row.detail].filter { !$0.isEmpty }.joined(separator: " · ")
            if !rest.isEmpty { lines.append(rest) }
        }
        if !owner.isEmpty {
            lines.append("")
            lines.append(owner)
        }
        return lines.joined(separator: "\n")
    }

    var fileName: String {
        "\(siteName) - \(language(.defects)) \(date)"
    }

    /// Who fixes it, as the PDF says it.
    func fixer(of defect: Defect) -> String {
        switch defect.assignee {
        case .nobody: return language(.nobodyYet)
        case .you: return owner.isEmpty ? language(.me) : owner
        case let .person(name): return name
        }
    }

    private func detail(of defect: Defect) -> String {
        if defect.state == .fixed {
            let day = CalendarDate(defect.fixedAt ?? defect.updatedAt, calendar: calendar)
            return language(.fixedOn, formatting.shortDate(day))
        }
        let since = language(.since, formatting.shortDate(CalendarDate(defect.notedAt, calendar: calendar)))
        guard showsAssignee else { return since }
        return "\(language(.fixes, fixer(of: defect))) · \(since)"
    }
}

/// A site's open defects on its sheet's sign-off pages (1.3, off unless the
/// sign-off sheet's switch is on): a photo with its marks, what, where.
struct ReportDefect: Hashable, Sendable {
    let number: Int
    let what: String
    let whereLine: String
    /// "since 3 Nov"
    let since: String
    /// The marked photo, by id, when there is one; the PDF is handed the
    /// bytes beside the diary's.
    let photoID: UUID?
    let marks: [DefectMark]
}

extension DefectsDocument {
    /// The open defects as the site's sheet prints them.
    func signOffRows(firstPhotos: [UUID: DefectPhoto]) -> [ReportDefect] {
        DefectList.listed(defects, state: .open, floors: floors).enumerated().map { index, defect in
            let photo = firstPhotos[defect.id]
            return ReportDefect(
                number: index + 1,
                what: defect.what,
                whereLine: defect.whereLine,
                since: language(.since, formatting.shortDate(CalendarDate(defect.notedAt, calendar: calendar))),
                photoID: photo?.id,
                marks: photo?.marks ?? []
            )
        }
    }
}
