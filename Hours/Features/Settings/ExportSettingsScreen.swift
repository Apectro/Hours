import SwiftUI

/// How exported files are shaped, including which columns appear and in what
/// order.
struct ExportSettingsScreen: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        List {
            Section {
                TextField("Name and surname", text: settingsStore.binding(\.export.ownerName))
                    .textContentType(.name)
                    .autocorrectionDisabled()
            } header: {
                Text("Name on the timesheet")
            } footer: {
                Text("Printed under the title of every timesheet, and used to name the file. Leave it empty and nothing is printed. It stays on this device like everything else.")
            }

            Section("Formatting") {
                Picker("Dates", selection: settingsStore.binding(\.export.dateStyle)) {
                    ForEach(ExportDateStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Times", selection: settingsStore.binding(\.export.timeStyle)) {
                    ForEach(ExportTimeStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Picker("Durations", selection: settingsStore.binding(\.export.durationStyle)) {
                    ForEach(DurationStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
            }

            Section {
                Picker("Field separator", selection: settingsStore.binding(\.export.fieldSeparator)) {
                    ForEach(CSVSeparator.allCases) { separator in
                        Text(separator.title).tag(separator)
                    }
                }
                Picker("Decimal separator", selection: settingsStore.binding(\.export.decimalSeparator)) {
                    ForEach(DecimalSeparator.allCases) { separator in
                        Text(separator.title).tag(separator)
                    }
                }
                Toggle("Byte-order mark", isOn: settingsStore.binding(\.export.includeByteOrderMark))
            } header: {
                Text("CSV")
            } footer: {
                Text("Excel on Windows needs the byte-order mark to read accented characters correctly. Numbers, Google Sheets and LibreOffice are happy either way.")
            }

            Section {
                Toggle("Include days with no entry", isOn: settingsStore.binding(\.export.includeEmptyDays))
                Toggle("Include a summary", isOn: settingsStore.binding(\.export.includeSummaryRows))
                Picker("Default range", selection: settingsStore.binding(\.export.defaultRange)) {
                    ForEach(ExportRangeKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
            } header: {
                Text("Contents")
            } footer: {
                Text("Including empty days keeps every date in the range on its own row, which is what most timesheets expect.")
            }

            columnSections
        }
        .navigationTitle("Export options")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    // MARK: - Columns

    @ViewBuilder
    private var columnSections: some View {
        Section {
            ForEach(selectedColumns) { column in
                Text(column.title)
            }
            .onMove(perform: moveColumns)
            .onDelete(perform: removeColumns)
        } header: {
            Text("Columns")
        } footer: {
            Text("Drag to reorder. Columns for fields you have switched off are never offered.")
        }

        if !availableColumns.isEmpty {
            Section("Add a column") {
                ForEach(availableColumns) { column in
                    Button {
                        addColumn(column)
                    } label: {
                        Label(column.title, systemImage: "plus.circle")
                    }
                }
            }
        }
    }

    private var selectedColumns: [ReportColumn] {
        settingsStore.settings.effectiveExportColumns
    }

    private var availableColumns: [ReportColumn] {
        let selected = Set(selectedColumns)
        return settingsStore.settings.features.availableColumns().filter { !selected.contains($0) }
    }

    private func moveColumns(from offsets: IndexSet, to destination: Int) {
        var columns = selectedColumns
        columns.move(fromOffsets: offsets, toOffset: destination)
        settingsStore.update { $0.export.columns = columns }
    }

    private func removeColumns(at offsets: IndexSet) {
        var columns = selectedColumns
        columns.remove(atOffsets: offsets)
        // An empty column list would produce an empty file, so the date stays.
        settingsStore.update { $0.export.columns = columns.isEmpty ? [.date] : columns }
    }

    private func addColumn(_ column: ReportColumn) {
        var columns = selectedColumns
        columns.append(column)
        settingsStore.update { $0.export.columns = columns }
    }
}
