import SwiftUI

/// The report, on screen, laid out exactly as it will be in the file.
///
/// Scrolls horizontally rather than shrinking to fit: a preview that is too
/// small to read is not a preview.
struct ExportPreviewTable: View {
    let table: ReportTable
    var rowLimit: Int = 12

    private static let columnWidths: [ReportColumn: CGFloat] = [
        .date: 92, .weekday: 46, .dayType: 96, .start: 60, .end: 68,
        .breakTime: 60, .worked: 70, .credited: 84, .expected: 74,
        .overtime: 74, .balance: 74, .cumulativeBalance: 96,
        .holiday: 120, .location: 110, .tags: 110, .note: 160
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                ForEach(Array(table.rows.prefix(rowLimit))) { row in
                    dataRow(row)
                    Divider()
                }
                if !table.totals.isEmpty {
                    totalsRow
                }
            }
            .padding(.horizontal, Metrics.large)
        }
        .accessibilityLabel("Export preview, \(table.rows.count) rows")
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(table.columns) { column in
                Text(column.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: width(for: column), alignment: column.isNumeric ? .trailing : .leading)
            }
        }
        .padding(.vertical, Metrics.small)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.hoursHairline).frame(height: 1)
        }
    }

    private func dataRow(_ row: ReportRow) -> some View {
        HStack(spacing: 0) {
            ForEach(table.columns.indices, id: \.self) { index in
                let column = table.columns[index]
                Text(index < row.values.count ? row.values[index] : "")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(row.hasEntry ? .primary : .secondary)
                    .lineLimit(1)
                    .frame(width: width(for: column), alignment: column.isNumeric ? .trailing : .leading)
            }
        }
        .padding(.vertical, 5)
        .background(row.isWorkingDay ? Color.clear : Color.hoursSubdued.opacity(0.08))
    }

    private var totalsRow: some View {
        VStack(alignment: .leading, spacing: Metrics.tiny) {
            Text("Summary")
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

    private func width(for column: ReportColumn) -> CGFloat {
        ExportPreviewTable.columnWidths[column] ?? 80
    }
}
