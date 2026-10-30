import SwiftUI

/// This sheet (Export board, phone 3): the name on the sheet, its language
/// and file name; the switches the sheet has; Columns and the CSV file.
///
/// Everything but the name is for this export only: the screen edits a copy
/// of `ExportPreferences` the export screen holds, and Settings › Sheets
/// keeps the defaults. The name is yours and is kept, as it always was.
struct ExportThisSheetScreen: View {
    let mode: ExportMode
    /// This export's copy of the preferences.
    @Binding var preferences: ExportPreferences
    /// The file's name without its extension, and what it would be called
    /// untouched. Nil when there is no one name: a file per person.
    var fileName: Binding<String>?
    let suggestedFileName: String

    /// A crew sheet's switches.
    @Binding var perPerson: Bool
    /// Only for a month with a diary, and one sheet rather than one each.
    let offersDiary: Bool
    @Binding var includesDiary: Bool
    @Binding var includesSignatures: Bool
    /// The crew sheet's own site and month, for collecting signatures.
    let signOffSite: Site?
    let month: YearMonth
    let onSigned: () -> Void
    /// The CSV file, written and opened like PDF and Excel.
    let onCSV: () -> Void

    @Environment(SettingsStore.self) private var settingsStore
    @State private var asksForName = false
    @State private var typedName = ""

    var body: some View {
        Form {
            Section {
                if mode != .onePerson {
                    ExportNameRow(name: ownerName) {
                        typedName = ownerName
                        asksForName = true
                    }
                }
                Picker("Language", selection: $preferences.language) {
                    ForEach(ExportLanguage.allCases) { language in
                        Text(language.title).tag(language)
                    }
                }
                .accessibilityIdentifier("export-language")
                if let fileName {
                    HStack {
                        Text("File name")
                        Spacer(minLength: Metrics.small)
                        TextField(suggestedFileName, text: fileName)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.hoursSecondaryText)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .accessibilityLabel(Text("File name"))
                            .accessibilityIdentifier("export-file-name")
                    }
                    .frame(minHeight: 44)
                }
            }

            switchesSection

            Section {
                NavigationLink {
                    ExportColumnsScreen(columns: $preferences.columns)
                } label: {
                    LabeledContent {
                        Text(verbatim: columnSummary)
                            .lineLimit(1)
                    } label: {
                        Text("Columns")
                    }
                }
                .accessibilityIdentifier("export-columns")
                Button(action: onCSV) {
                    HStack {
                        Text("CSV file")
                            .foregroundStyle(.primary)
                        Spacer(minLength: Metrics.small)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("export-format-csv")
            } footer: {
                Text("Only for this export. Your defaults are in Settings › Sheets.")
            }

            Section {
                NavigationLink {
                    ExportSettingsScreen()
                } label: {
                    Label("Sheets", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("export-defaults")
            }
        }
        .navigationTitle("This sheet")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("screen-export-this-sheet")
        .alert("Your name on the sheet", isPresented: $asksForName) {
            TextField("Name and surname", text: $typedName)
                .textInputAutocapitalization(.words)
            Button("Save") {
                let name = typedName.trimmingCharacters(in: .whitespacesAndNewlines)
                settingsStore.update { $0.export.ownerName = name }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if mode == .crewSheet {
                Text("Printed above your column instead of “You”, and kept in Settings › Sheets.")
            } else {
                Text("Printed on every sheet you export, and kept in Settings › Sheets.")
            }
        }
    }

    // MARK: - Switches

    /// Only the switches this kind of sheet has.
    @ViewBuilder
    private var switchesSection: some View {
        switch mode {
        case .crewSheet:
            Section {
                Toggle("One sheet per person", isOn: $perPerson)
                    .accessibilityIdentifier("export-per-person")
                if offersDiary && !perPerson {
                    Toggle("Include the site diary", isOn: $includesDiary)
                        .accessibilityIdentifier("export-include-diary")
                }
                Toggle("Crew sign-off", isOn: $includesSignatures)
                    .accessibilityIdentifier("export-include-signatures")
                if let site = signOffSite {
                    // Who has signed this month, and signing now: shown
                    // even with the sign-off off, greyed, saying why.
                    NavigationLink {
                        SiteSignOffScreen(site: site, month: month, onChange: onSigned)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label("Signatures", systemImage: "signature")
                            if !includesSignatures {
                                Text("Turned off for this sheet")
                                    .font(.caption)
                                    .foregroundStyle(.hoursSecondaryText)
                            }
                        }
                    }
                    .disabled(!includesSignatures)
                    .accessibilityIdentifier("export-sign-off")
                }
            } footer: {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    if perPerson {
                        Text("A file for each person, with their days on the sites on this sheet. They all go in one share.")
                    } else if offersDiary && includesDiary {
                        Text("The diary follows the hours: on pages of its own in the PDF, on a second sheet in Excel. A CSV holds the hours only.")
                    }
                    if !includesSignatures {
                        Text("No line to sign on and no sign-off page. Signatures already given are kept.")
                    }
                }
            }
        case .onePerson:
            Section {
                Toggle("Crew sign-off", isOn: $includesSignatures)
                    .accessibilityIdentifier("export-include-signatures")
            }
        case .myHours:
            Section {
                Toggle("Include days with no entry", isOn: $preferences.includeEmptyDays)
                    .accessibilityIdentifier("export-include-empty-days")
                Toggle("Include a summary", isOn: $preferences.includeSummaryRows)
                    .accessibilityIdentifier("export-include-summary")
                // Only once there is a rate: without one there is nothing to add.
                if settingsStore.settings.earningsAreSetUp {
                    Toggle("Earnings", isOn: $preferences.includeEarnings)
                        .accessibilityIdentifier("export-include-earnings")
                }
            }
        }
    }

    // MARK: - Derived

    private var ownerName: String {
        settingsStore.settings.export.ownerName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Date, Start, End…": the first few columns in this export's language.
    private var columnSummary: String {
        var settings = settingsStore.settings
        settings.export = preferences
        let titles = settings.effectiveExportColumns.map { $0.heading(in: preferences.language) }
        let shown = titles.prefix(3).joined(separator: ", ")
        return titles.count > 3 ? "\(shown)…" : shown
    }
}

/// Columns, for this export: which, and in what order. The same editing as
/// Settings › Sheets, on this export's copy.
struct ExportColumnsScreen: View {
    @Binding var columns: [ReportColumn]

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        List {
            Section {
                ForEach(selected) { column in
                    Text(verbatim: column.heading(in: .device))
                }
                .onMove { offsets, destination in
                    var next = selected
                    next.move(fromOffsets: offsets, toOffset: destination)
                    columns = next
                }
                .onDelete { offsets in
                    var next = selected
                    next.remove(atOffsets: offsets)
                    // An empty column list would produce an empty file, so the
                    // date stays.
                    columns = next.isEmpty ? [.date] : next
                }
            } footer: {
                Text("Drag to reorder. Columns for fields you have switched off are never offered.")
            }

            if !available.isEmpty {
                Section("Add a column") {
                    ForEach(available) { column in
                        Button {
                            columns = selected + [column]
                        } label: {
                            Label {
                                Text(verbatim: column.heading(in: .device))
                            } icon: {
                                Image(systemName: "plus.circle")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Columns")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }

    /// The columns as the file will have them: chosen, and allowed by the
    /// fields switched on.
    private var selected: [ReportColumn] {
        var settings = settingsStore.settings
        settings.export.columns = columns
        return settings.effectiveExportColumns
    }

    private var available: [ReportColumn] {
        let chosen = Set(selected)
        return settingsStore.settings.features.availableColumns().filter { !chosen.contains($0) }
    }
}
