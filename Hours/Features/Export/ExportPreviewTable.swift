import SwiftUI

/// The report, on screen, laid out exactly as it will be in the file.
///
/// Scrolls horizontally rather than shrinking to fit: a preview that is too
/// small to read is not a preview.
struct ExportPreviewTable: View {
    let table: ReportTable
    var rowLimit: Int = 12

    private static let columnWidths: [ReportColumn: CGFloat] = [
        .date: 92, .weekday: 46, .dayType: 96, .job: 96, .start: 60, .end: 68,
        .breakTime: 60, .worked: 70, .credited: 84, .expected: 74,
        .overtime: 74, .balance: 74, .cumulativeBalance: 96,
        .holiday: 120, .location: 110, .tags: 110, .note: 160
    ]

    var body: some View {
        let widths = columnWidths
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow(widths)
                ForEach(Array(dayRows.prefix(rowLimit))) { row in
                    dataRow(row, widths: widths)
                    Divider()
                }
                // The director's sheet ends with its own month total and days
                // worked. They are the point of the sheet, so they are shown
                // even when the days above them are cut short.
                ForEach(Array(summaryRows)) { row in
                    dataRow(row, widths: widths, isSummary: true)
                    Divider()
                }
                if !table.totals.isEmpty {
                    totalsRow
                }
            }
            .padding(.horizontal, Metrics.large)
        }
        .accessibilityLabel(String(
            localized: "Export preview, \(table.rows.count) rows",
            comment: "VoiceOver, the table showing what the file will contain"
        ))
    }

    private func headerRow(_ widths: [CGFloat]) -> some View {
        HStack(spacing: 0) {
            // By index: the director's sheet repeats `.worked` once per person,
            // so a column is not a unique identity here.
            ForEach(table.columns.indices, id: \.self) { index in
                let column = table.columns[index]
                Text(table.heading(at: index))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: widths[index], alignment: column.isNumeric ? .trailing : .leading)
                    .accessibilityIdentifier("export-preview-heading")
            }
        }
        .padding(.vertical, Metrics.small)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hoursHairline).frame(height: 1)
        }
    }

    private func dataRow(_ row: ReportRow, widths: [CGFloat], isSummary: Bool = false) -> some View {
        HStack(spacing: 0) {
            ForEach(table.columns.indices, id: \.self) { index in
                let column = table.columns[index]
                Text(index < row.values.count ? row.values[index] : "")
                    .font(isSummary ? .caption.weight(.semibold) : .caption)
                    .monospacedDigit()
                    .foregroundStyle(row.hasEntry ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: widths[index], alignment: column.isNumeric ? .trailing : .leading)
                    .accessibilityIdentifier(isSummary ? "export-preview-summary" : "")
            }
        }
        .padding(.vertical, 5)
        .background(row.isWorkingDay ? Color.clear : Color.hoursSubdued.opacity(0.08))
    }

    private var totalsRow: some View {
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
                .frame(width: 260, alignment: .leading)
            }
        }
        .padding(.bottom, Metrics.small)
    }

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

    /// One width per column, by position.
    ///
    /// A timesheet's columns are kinds of figure and get the fixed widths
    /// above. The director's sheet's are people, each holding "07:00–16:00 ·
    /// 8:30" under a name of any length, so those are sized to what they hold:
    /// 70 points cut every cell in half.
    private var columnWidths: [CGFloat] {
        table.columns.indices.map { (index: Int) -> CGFloat in
            let column = table.columns[index]
            guard table.headingOverrides != nil, column == .worked else {
                return ExportPreviewTable.columnWidths[column] ?? 80
            }
            let longest = table.rows.reduce(table.heading(at: index).count) { widest, row in
                index < row.values.count ? max(widest, row.values[index].count) : widest
            }
            // About seven points a character at caption size, plus a gap
            // before the next column.
            return min(max(CGFloat(longest) * 7 + 12, 70), 240)
        }
    }
}
