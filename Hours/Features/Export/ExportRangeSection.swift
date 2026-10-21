import SwiftUI

/// Which days of your own go into the timesheet: a day, week, month or year
/// around the one the screen was opened on, or a custom range.
struct ExportRangeSection: View {
    @Binding var rangeKind: ExportRangeKind
    @Binding var customStart: Date
    @Binding var customEnd: Date
    /// The resolved range in words, for every kind but custom.
    let description: String
    /// "31 days · 22 with hours recorded".
    let footer: String

    var body: some View {
        Section {
            Picker("Range", selection: $rangeKind) {
                ForEach(ExportRangeKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            if rangeKind == .custom {
                DatePicker("From", selection: $customStart, displayedComponents: .date)
                DatePicker("To", selection: $customEnd, displayedComponents: .date)
            } else {
                LabeledContent(rangeKind.title) {
                    Text(verbatim: description)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Range")
        } footer: {
            Text(verbatim: footer)
        }
    }
}
