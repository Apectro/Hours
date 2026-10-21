import SwiftUI
import UIKit

/// The report, on screen, laid out as it will be in the file.
///
/// Scrolls horizontally rather than shrinking to fit: a preview that is too
/// small to read is not a preview.
struct ExportPreviewTable: View {
    let table: ReportTable
    var rowLimit: Int = 12

    /// Read so the widths are measured again when the text size changes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let widths = ExportPreviewWidths.measure(table)
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                if table.validGroups.isEmpty {
                    flatHeadings(widths)
                } else {
                    groupHeadings(widths)
                    subHeadings(widths)
                }
                ForEach(Array(dayRows.prefix(rowLimit))) { row in
                    ExportPreviewRow(table: table, row: row, widths: widths, isSummary: false)
                    Divider()
                }
                // The director's sheet ends with its own month total and days
                // worked. They are the point of the sheet, so they are shown
                // even when the days above them are cut short.
                ForEach(Array(summaryRows)) { row in
                    ExportPreviewRow(table: table, row: row, widths: widths, isSummary: true)
                    Divider()
                }
                if !table.totals.isEmpty {
                    totalsBlock
                }
            }
            .padding(.horizontal, Metrics.large)
        }
        .accessibilityLabel(String(
            localized: "Export preview, \(table.rows.count) rows",
            comment: "VoiceOver, the table showing what the file will contain"
        ))
    }

    // MARK: - Headings

    private func flatHeadings(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            // By index: a column is not a unique identity on the director's
            // sheet, which repeats its columns once per person.
            ForEach(table.columns.indices, id: \.self) { index in
                headingText(table.heading(at: index))
                    .frame(width: widths[index], alignment: table.columns[index].isNumeric ? .trailing : .leading)
                    .accessibilityIdentifier("export-preview-heading")
            }
        }
        .padding(.vertical, Metrics.small)
        .overlay(alignment: .bottom) { hairline }
    }

    /// A person's name across both of their columns.
    private func groupHeadings(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(table.groupRanges.enumerated()), id: \.offset) { item in
                headingText(table.validGroups[item.offset].title)
                    .frame(width: ExportPreviewWidths.span(item.element, in: widths), alignment: .leading)
                    .accessibilityIdentifier("export-preview-heading")
            }
        }
        .padding(.top, Metrics.small)
    }

    /// What each column of a pair holds, under the name.
    private func subHeadings(_ widths: [CGFloat]) -> some View {
        let titles = table.columnHeadings()
        let grouped = Set(table.groupRanges.filter { $0.count > 1 }.flatMap { Array($0) })
        return HStack(spacing: 0) {
            ForEach(table.columns.indices, id: \.self) { index in
                Text(grouped.contains(index) ? titles[index] : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: widths[index], alignment: table.columns[index].isNumeric ? .trailing : .leading)
                    .accessibilityIdentifier("export-preview-subheading")
            }
        }
        .padding(.bottom, Metrics.tiny)
        .overlay(alignment: .bottom) { hairline }
    }

    private func headingText(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var hairline: some View {
        Rectangle().fill(Color.hoursHairline).frame(height: 1)
    }

    // MARK: - Summary

    private var totalsBlock: some View {
        VStack(alignment: .leading, spacing: Metrics.tiny) {
            Text(table.language(.summary))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.top, Metrics.small)
            ForEach(table.totals) { total in
                HStack {
                    Text(total.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: Metrics.large)
                    Text(total.value)
                        .font(.caption.weight(total.isEmphasised ? .semibold : .regular))
                        .monospacedDigit()
                }
                .frame(minWidth: 260, alignment: .leading)
                .fixedSize()
            }
        }
        .padding(.bottom, Metrics.small)
    }

    // MARK: - Rows

    /// The days, without the summary rows a builder wrote at the end.
    private var dayRows: ArraySlice<ReportRow> {
        table.rows.dropLast(summaryCount)
    }

    private var summaryRows: ArraySlice<ReportRow> {
        table.rows.suffix(summaryCount)
    }

    private var summaryCount: Int {
        min(max(table.trailingSummaryRows, 0), table.rows.count)
    }
}

/// One row of the preview.
private struct ExportPreviewRow: View {
    let table: ReportTable
    let row: ReportRow
    let widths: [CGFloat]
    let isSummary: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments, id: \.columns.lowerBound) { segment in
                cell(segment)
            }
        }
        .padding(.vertical, 5)
        .background(rowBackground)
    }

    /// A cell, or a whole group drawn as one: the dash for someone who was
    /// not there that day.
    private struct Segment {
        var columns: Range<Int>
        var isMerged: Bool
    }

    private var segments: [Segment] {
        let ranges = table.groupRanges
        var merged: [Int: Range<Int>] = [:]
        for group in row.mergedGroups where group < ranges.count {
            merged[ranges[group].lowerBound] = ranges[group]
        }
        var result: [Segment] = []
        var index = 0
        while index < table.columns.count {
            if let range = merged[index] {
                result.append(Segment(columns: range, isMerged: true))
                index = range.upperBound
            } else {
                result.append(Segment(columns: index..<(index + 1), isMerged: false))
                index += 1
            }
        }
        return result
    }

    @ViewBuilder
    private func cell(_ segment: Segment) -> some View {
        let index = segment.columns.lowerBound
        let value = index < row.values.count ? row.values[index] : ""
        let width = ExportPreviewWidths.span(segment.columns, in: widths)
        if segment.isMerged {
            Text(value.isEmpty ? "—" : value)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: width, alignment: .center)
        } else {
            let column = table.columns[index]
            Text(value)
                .font(font(for: column))
                .monospacedDigit()
                .foregroundStyle(color(index: index, column: column))
                .lineLimit(1)
                .frame(width: width, alignment: column.isNumeric ? .trailing : .leading)
                .accessibilityIdentifier(isSummary ? "export-preview-summary" : "")
        }
    }

    private func font(for column: ReportColumn) -> Font {
        isSummary || column == .worked ? .caption.weight(.semibold) : .caption
    }

    /// Someone who came late or left early is in the same amber as on the
    /// printed page; their times are quieter than their hours, as there.
    private func color(index: Int, column: ReportColumn) -> Color {
        if row.flagged.contains(index) { return ExportPreviewWidths.accent }
        if column == .times || row.role == .count || !row.hasEntry { return .secondary }
        return .primary
    }

    private var rowBackground: Color {
        if row.isAbsence { return ExportPreviewWidths.accent.opacity(0.08) }
        return row.isWorkingDay ? Color.clear : Color.hoursSubdued.opacity(0.08)
    }
}

/// Column widths for the preview, measured from what each column holds.
///
/// They were fixed per kind of column once, and the director's sheet put
/// "07:00–16:00 · 8:30" into a column drawn seventy points wide. Measured,
/// in the font the preview draws at its current size, a column is as wide as
/// its widest value and no wider — except free text, which is capped so one
/// long note does not push the rest of the table off the screen.
enum ExportPreviewWidths {
    static let accent = Color(red: 0.878, green: 0.482, blue: 0.071)

    static func measure(_ table: ReportTable) -> [CGFloat] {
        let base = UIFont.preferredFont(forTextStyle: .caption1)
        let bold = UIFont.systemFont(ofSize: base.pointSize, weight: .semibold)
        let grouped = Set(table.groupRanges.filter { $0.count > 1 }.flatMap { Array($0) })
        let headings = table.columnHeadings()
        let flat = table.headerTitles()

        var widths = table.columns.indices.map { index -> CGFloat in
            let column = table.columns[index]
            let heading = grouped.contains(index) ? headings[index] : flat[index]
            var widest = textWidth(heading, font: bold)
            for row in table.rows where index < row.values.count {
                let font = row.role != .day || column == .worked ? bold : base
                widest = max(widest, textWidth(row.values[index], font: font))
            }
            let cap: CGFloat = column.mayTruncate ? 220 : 360
            return min(widest, cap) + Metrics.large
        }

        // A name must fit across the pair of columns it heads.
        for (group, range) in zip(table.validGroups, table.groupRanges) where range.count > 1 {
            let needed = textWidth(group.title, font: bold) + Metrics.large
            let have = span(range, in: widths)
            if have < needed, let last = range.last {
                widths[last] += needed - have
            }
        }
        return widths
    }

    static func span(_ range: Range<Int>, in widths: [CGFloat]) -> CGFloat {
        range.reduce(CGFloat(0)) { $0 + ($1 < widths.count ? widths[$1] : 0) }
    }

    private static func textWidth(_ text: String, font: UIFont) -> CGFloat {
        // Tabular digits run a little wider than the proportional ones
        // measured here, hence the rounding up and the padding beside it.
        ceil((text as NSString).size(withAttributes: [.font: font]).width) + 2
    }
}
