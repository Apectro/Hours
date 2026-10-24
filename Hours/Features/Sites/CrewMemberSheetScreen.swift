import StoreKit
import SwiftUI
import SwiftData
import UIKit

/// One crew member's own sheet, from the crew list: their days on every site
/// for a month, as the page they are handed, and the button that shares it.
///
/// The same PDF as "One sheet per person" in the site export
/// (`CrewMemberSheetBuilder`), for one person. Opens on this month, which is
/// what someone checking their payslip asks for; the stepper reaches back.
/// Nothing leaves the phone but the file, through the share sheet.
struct CrewMemberSheetScreen: View {
    let member: CrewMember

    @Environment(\.dismiss) private var dismiss
    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions

    /// The site export's switch: a crew that does not sign never does.
    @AppStorage("export.siteSignatures") private var includesSignatures = true

    /// `nil` until stepped: this month.
    @State private var chosenMonth: YearMonth?
    @State private var sheet: CrewSheetTables?
    @State private var pdfData: Data?
    @State private var pageImage: UIImage?
    @State private var fileURL: URL?
    @State private var failureMessage: String?
    @State private var showsFullPage = false
    @State private var paywallReason: ProFeature?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    PeriodStepper(
                        month: monthBinding,
                        latest: currentMonth,
                        title: settingsStore.dateFormatting.monthTitle(month),
                        caption: caption
                    )
                    Toggle("Signatures", isOn: $includesSignatures)
                        .accessibilityIdentifier("crew-sheet-signatures")
                } footer: {
                    Text("Their days on every site, with the hours and any days away: one page to check against the payslip, or to sign.")
                }
                Section("Preview") {
                    if let sheet, sheet.tables.hasContent {
                        ExportPagePreview(image: pageImage) { showsFullPage = pdfData != nil }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    } else if sheet != nil {
                        ContentUnavailableView(
                            "Nothing recorded this month",
                            systemImage: "tray",
                            description: Text("Choose another month to see its days.")
                        )
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                    }
                }
            }
            .navigationTitle(Text(verbatim: member.name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("crew-sheet-done")
                }
            }
            .safeAreaInset(edge: .bottom) {
                ExportShareBar(
                    format: .pdf,
                    state: shareState,
                    onLocked: { paywallReason = .fileExport },
                    onNeedsName: {},
                    onShare: { url in
                        ShareSheetPresenter.present(url) { outcome in
                            if outcome == .completed { ReviewPromptStore.askIfDue(requestReview) }
                        }
                    }
                )
            }
            .task { regenerate() }
            .onChange(of: regenerationKey) { _, _ in regenerate() }
            .sheet(isPresented: $showsFullPage) {
                ExportFullPageSheet(data: pdfData ?? Data())
            }
            .paywall(for: $paywallReason)
        }
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var currentMonth: YearMonth { CalendarDate.today(in: calendar).yearMonth }
    private var month: YearMonth { chosenMonth ?? currentMonth }

    private var monthBinding: Binding<YearMonth> {
        Binding(get: { month }, set: { chosenMonth = $0 })
    }

    /// "12 days", read off the sheet: a row is a day there or away.
    private var caption: String {
        guard let sheet, sheet.tables.hasContent else { return "" }
        let days = sheet.tables.file.rows.filter { $0.role == .day }.count
        return String(inflected: "^[\(days) day](inflect: true)")
    }

    private var shareState: ExportShareState {
        guard let sheet else { return .preparing }
        guard sheet.tables.hasContent else { return .empty }
        if !subscriptions.allows(.fileExport) { return .locked }
        if let fileURL { return .ready(fileURL) }
        if let failureMessage { return .failed(failureMessage) }
        return .preparing
    }

    private var regenerationKey: String {
        "\(month.year)-\(month.month)-\(settings.export.hashValue)-\(includesSignatures)-\(subscriptions.allows(.fileExport))"
    }

    // MARK: - Generation

    private func regenerate() {
        let maker = ExportTableMaker(context: modelContext, settings: settings, calendar: calendar)
        let built = maker.crewSheet(for: member, month: month, includeSignatures: includesSignatures)
        sheet = built
        guard built.tables.hasContent else {
            pdfData = nil
            pageImage = nil
            fileURL = nil
            failureMessage = nil
            return
        }
        // Drawn for the preview whether or not it can be shared; the same
        // bytes become the file.
        let data = PDFReportRenderer.data(for: built.tables.file)
        pdfData = data
        pageImage = ExportPagePreview.thumbnail(of: data)
        guard subscriptions.allows(.fileExport) else {
            fileURL = nil
            failureMessage = nil
            return
        }
        do {
            fileURL = try CrewSheetFiles.write([built], format: .pdf, preferences: settings.export, firstPDF: data).first
            failureMessage = nil
        } catch {
            fileURL = nil
            failureMessage = String(
                localized: "The file could not be prepared. \(error.localizedDescription)",
                comment: "Export failed; the value is the system's own description"
            )
        }
    }
}
