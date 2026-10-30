import StoreKit
import SwiftUI
import SwiftData
import UIKit

/// One person's month, pushed from the crew list (1.2, mockup Crew): three
/// figures — their hours, the days they worked, their sick days — a line a
/// day across every site ("Trg Pravde → Jarunski" for a day split between
/// two), and at the bottom "Share Ivan's sheet" and "Sign the month".
///
/// The sheet shared is the same PDF as "One sheet per person" in the site
/// export (`CrewMemberSheetBuilder`), for one person; its page is shown at
/// the end with the Signatures switch. Opens on this month, which is what
/// someone checking their payslip asks for; the stepper reaches back.
/// Nothing leaves the phone but the file, through the share sheet.
struct CrewMemberSheetScreen: View {
    let member: CrewMember

    @Environment(\.requestReview) private var requestReview
    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The site export's switch: a crew that does not sign never does.
    @AppStorage("export.siteSignatures") private var includesSignatures = true

    /// `nil` until stepped: this month.
    @State private var chosenMonth: YearMonth?
    @State private var sheet: CrewSheetTables?
    @State private var summary: CrewMemberMonth?
    @State private var siteNames: [UUID: String] = [:]
    @State private var site: Site?
    @State private var pdfData: Data?
    @State private var pageImage: UIImage?
    @State private var fileURL: URL?
    @State private var failureMessage: String?
    @State private var showsFullPage = false
    @State private var paywallReason: ProFeature?
    @State private var signing: Site?

    var body: some View {
        Form {
            Section {
                PeriodStepper(
                    month: monthBinding,
                    latest: currentMonth,
                    title: settingsStore.dateFormatting.monthTitle(month),
                    caption: ""
                )
            }

            Section {
                tiles
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section {
                if let summary, !summary.days.isEmpty {
                    dayHeader
                    ForEach(summary.days) { day in
                        dayRow(day)
                    }
                } else if summary != nil {
                    Text("Nothing recorded this month")
                        .foregroundStyle(.hoursSecondaryText)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 60)
                }
            }

            Section {
                Toggle("Signatures", isOn: $includesSignatures)
                    .accessibilityIdentifier("crew-sheet-signatures")
                if let sheet, sheet.tables.hasContent {
                    ExportPagePreview(image: pageImage) { showsFullPage = pdfData != nil }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
            } header: {
                Text("Their sheet")
            } footer: {
                if let failureMessage {
                    Text(verbatim: failureMessage)
                } else {
                    Text("Their days on every site, with the hours and any days away: one page to check against the payslip, or to sign.")
                }
            }
        }
        .navigationTitle(Text(verbatim: member.name))
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            bottomButtons
        }
        .task { regenerate() }
        .onChange(of: regenerationKey) { _, _ in regenerate() }
        .sheet(isPresented: $showsFullPage) {
            ExportFullPageSheet(data: pdfData ?? Data())
        }
        .sheet(item: $signing) { site in
            MemberSignOffSheet(site: site, memberID: member.id, month: month)
        }
        .paywall(for: $paywallReason)
    }

    // MARK: - Parts

    private var tiles: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.small))
        return layout {
            tile(
                settingsStore.dateFormatting.monthName(month),
                value: settings.displayFormatting.string(summary?.totalMinutes ?? 0)
            )
            tile(String(localized: "Days"), value: String(summary?.daysWorked ?? 0))
            tile(
                String(localized: "Sick"),
                value: String(summary?.sickDays ?? 0),
                colour: (summary?.sickDays ?? 0) > 0 ? .hoursAttention : .primary
            )
        }
    }

    private func tile(_ title: String, value: String, colour: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.hoursSecondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(verbatim: value)
                .font(.hoursFigure(.title2, weight: .heavy))
                .foregroundStyle(colour)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, Metrics.medium + 2)
        .padding(.vertical, Metrics.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var dayHeader: some View {
        HStack(spacing: Metrics.small) {
            Text("Date").frame(minWidth: 56, alignment: .leading)
            Text("Site").frame(maxWidth: .infinity, alignment: .leading)
            Text("Hours")
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(.hoursSecondaryText)
        .accessibilityHidden(true)
    }

    private func dayRow(_ day: CrewMemberMonth.Day) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
            Text(verbatim: settingsStore.dateFormatting.shortDate(day.date))
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .leading)
            Group {
                if let reason = day.reason {
                    Text(verbatim: reasonText(reason))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.hoursAttention)
                } else {
                    Text(verbatim: day.siteIDs.map { siteNames[$0] ?? "—" }.joined(separator: " → "))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: day.reason == nil ? settings.displayFormatting.string(day.minutes) : "")
                .font(.hoursFigure(.body, weight: .regular))
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private func reasonText(_ reason: AbsenceReason) -> String {
        switch reason {
        case let .dayType(id):
            return settings.dayTypeCatalog.definition(for: id).displayName()
        case let .otherSite(siteID):
            return siteID.flatMap { siteNames[$0] } ?? String(localized: "On another site")
        }
    }

    private var bottomButtons: some View {
        VStack(spacing: Metrics.small) {
            Button(action: share) {
                Text(String(
                    localized: "Share \(member.name)'s sheet",
                    comment: "A crew member's month: share their own sheet; the value is their name"
                ))
            }
            .buttonStyle(.bigAction(.primary))
            .disabled(!canShare)
            .accessibilityIdentifier("crew-sheet-share")

            Button {
                signing = site
            } label: {
                Text("Sign the month")
            }
            .buttonStyle(.bigAction(.secondary))
            .disabled(site == nil)
            .accessibilityIdentifier("crew-sheet-sign")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(Color.hoursCanvas)
    }

    // MARK: - Derived

    private var settings: AppSettings { settingsStore.settings }
    private var calendar: Calendar { settingsStore.workCalendar }
    private var currentMonth: YearMonth { CalendarDate.today(in: calendar).yearMonth }
    private var month: YearMonth { chosenMonth ?? currentMonth }

    private var monthBinding: Binding<YearMonth> {
        Binding(get: { month }, set: { chosenMonth = $0 })
    }

    private var shareState: ExportShareState {
        guard let sheet else { return .preparing }
        guard sheet.tables.hasContent else { return .empty }
        if !subscriptions.allows(.fileExport) { return .locked }
        if let fileURL { return .ready(fileURL) }
        if let failureMessage { return .failed(failureMessage) }
        return .preparing
    }

    private var canShare: Bool {
        switch shareState {
        case .ready, .locked: return true
        default: return false
        }
    }

    private func share() {
        switch shareState {
        case let .ready(url):
            ShareSheetPresenter.present(url) { outcome in
                if outcome == .completed { ReviewPromptStore.askIfDue(requestReview) }
            }
        case .locked:
            paywallReason = .fileExport
        default:
            break
        }
    }

    private var regenerationKey: String {
        "\(month.year)-\(month.month)-\(settings.export.hashValue)-\(includesSignatures)-\(subscriptions.allows(.fileExport))"
    }

    // MARK: - Generation

    private func regenerate() {
        // The month on screen: every site, archived too, and every crew with
        // its hidden members, as the sheet reads them.
        let repository = SiteRepository(context: modelContext)
        let sites = repository.sites(includeArchived: true)
        let crew = sites.flatMap { repository.crew(for: $0.id, includeHidden: true) }
        let range = month.range(in: calendar)
        let calculator = SiteDayCalculator(settings: settings, calendar: calendar)
        let results = repository.siteDays(siteID: nil, in: range).map { calculator.compute($0) }
        siteNames = Dictionary(sites.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        site = sites.first { $0.id == member.siteID }
        summary = CrewMemberMonth.make(
            person: CrewSheetPerson.matching(member, in: crew),
            sites: sites,
            results: results,
            range: range
        )

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
