import Foundation
import SwiftData

/// One person's own sheet, built for the file and for the screen, and what
/// its file is called.
struct CrewSheetTables: Identifiable {
    var person: CrewSheetPerson
    var tables: ExportTables
    /// "Ana Horvat – August 2026", before the file writer cleans it.
    var fileName: String

    var id: String { person.id }
}

extension ExportTableMaker {
    /// A sheet for everyone on `site`'s sheet for the month, in its order,
    /// each with their days on every site (`CrewMemberSheetBuilder`).
    ///
    /// With more sites on the director's sheet (1.2), everyone on any of
    /// them — you first, then each site's people in the order chosen — and
    /// each sheet holds only those sites' days.
    func crewSheets(site: Site, month: YearMonth, includeSignatures: Bool, sites chosen: [Site] = []) -> [CrewSheetTables] {
        var input = crewSheetInput(month: month)
        var siteIDs = [site.id]
        for other in chosen where !siteIDs.contains(other.id) { siteIDs.append(other.id) }
        if siteIDs.count > 1 {
            let kept = Set(siteIDs)
            input.results = input.results.filter { kept.contains($0.day.siteID) }
        }
        var seen = Set<String>()
        var people: [CrewSheetPerson] = []
        for id in siteIDs {
            let onSite = CrewMemberSheetBuilder.people(
                on: id,
                crew: input.crew,
                results: input.results,
                range: input.range,
                ownerName: settings.export.ownerName
            )
            for person in onSite where seen.insert(person.id).inserted {
                if person.isYou { people.insert(person, at: 0) } else { people.append(person) }
            }
        }
        return people.map { crewSheet(for: $0, input: input, includeSignatures: includeSignatures) }
    }

    /// One crew member's sheet for the month, across every site they are on.
    func crewSheet(for member: CrewMember, month: YearMonth, includeSignatures: Bool) -> CrewSheetTables {
        let input = crewSheetInput(month: month)
        let person = CrewSheetPerson.matching(member, in: input.crew)
        return crewSheet(for: person, input: input, includeSignatures: includeSignatures)
    }

    private struct CrewSheetInput {
        var range: CalendarDateRange
        var sites: [Site]
        var crew: [CrewMember]
        var results: [SiteDayResult]
    }

    /// Every site, archived too, every crew with its hidden members, and
    /// every site day of the month: a person's sheet covers all their sites,
    /// and someone hidden or on an archived site worked the days they worked.
    private func crewSheetInput(month: YearMonth) -> CrewSheetInput {
        let repository = SiteRepository(context: context)
        let range = month.range(in: calendar)
        let sites = repository.sites(includeArchived: true)
        let crew = sites.flatMap { repository.crew(for: $0.id, includeHidden: true) }
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = repository.siteDays(siteID: nil, in: range).map { calculator.compute($0) }
        return CrewSheetInput(range: range, sites: sites, crew: crew, results: results)
    }

    private func crewSheet(for person: CrewSheetPerson, input: CrewSheetInput, includeSignatures: Bool) -> CrewSheetTables {
        func build(_ placeholder: String) -> ReportTable {
            CrewMemberSheetBuilder(settings: settings, calendar: calendar, emptyPlaceholder: placeholder)
                .makeTable(
                    person: person,
                    sites: input.sites,
                    results: input.results,
                    range: input.range,
                    includesSignatures: includeSignatures
                )
        }
        let file = build("")
        let naming = ExportNaming(settings: settings, calendar: calendar)
        return CrewSheetTables(
            person: person,
            tables: ExportTables(file: file, preview: build("—")),
            fileName: naming.crewSheetFileName(file.ownerName, range: input.range)
        )
    }
}

/// Writes one file per person, for one share.
enum CrewSheetFiles {
    /// - Parameter firstPDF: the first sheet's PDF, already drawn for the
    ///   preview, so the page on screen is the page shared.
    static func write(
        _ sheets: [CrewSheetTables],
        format: ExportFormat,
        preferences: ExportPreferences,
        firstPDF: Data? = nil
    ) throws -> [URL] {
        var used = Set<String>()
        var urls: [URL] = []
        for (index, sheet) in sheets.enumerated() where sheet.tables.hasContent {
            // Two names a file cannot tell apart once cleaned get a number,
            // so neither overwrites the other.
            let clean = ExportFileFactory.sanitise(sheet.fileName)
            var name = clean
            var number = 2
            while !used.insert(name.lowercased()).inserted {
                name = "\(clean) \(number)"
                number += 1
            }
            if format == .pdf {
                let data = index == 0 ? (firstPDF ?? PDFReportRenderer.data(for: sheet.tables.file)) : PDFReportRenderer.data(for: sheet.tables.file)
                urls.append(try ExportFileFactory.write(data: data, format: .pdf, baseName: name))
            } else {
                urls.append(try ExportFileFactory.write(
                    table: sheet.tables.file,
                    format: format,
                    preferences: preferences,
                    baseName: name
                ))
            }
        }
        return urls
    }
}
