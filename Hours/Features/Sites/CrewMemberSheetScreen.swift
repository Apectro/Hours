import StoreKit
import SwiftUI
import SwiftData
import UIKit

/// One person's month, pushed from the crew list (design v2, mockup More
/// phone 4): the month as the inline title with ‹ ›, their name large, three
/// figures — hours, days, sick — a row a day across every site ("then
/// Jarunski from 12:40" in blue for a day split between two), and at the
/// bottom "Share Ivan's sheet" and "Sign the month".
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
        List {
            Section {
                VStack(alignment: .leading, spacing: Metrics.medium) {
                    Text(verbatim: member.name)
                        .font(.largeTitle.bold())
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    figures
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large + 4, bottom: Metrics.small, trailing: Metrics.large))
            }

            Section {
                if let summary, !summary.days.isEmpty {
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
        .listStyle(.insetGrouped)
        .navigationTitle(Text(verbatim: settingsStore.dateFormatting.monthTitle(month)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    chosenMonth = month.adding(months: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(String(localized: "Previous month"))
                .accessibilityIdentifier("crew-sheet-month-previous")
                Button {
                    chosenMonth = month.adding(months: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(month >= currentMonth)
                .accessibilityLabel(String(localized: "Next month"))
                .accessibilityIdentifier("crew-sheet-month-next")
            }
        }
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

    /// Hours, days and sick days, big, with a word under each.
    private var figures: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.small))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Metrics.extraLarge))
        return layout {
            figure(settings.displayFormatting.string(summary?.totalMinutes ?? 0), word: String(localized: "Hours"))
            figure(String(summary?.daysWorked ?? 0), word: String(localized: "Days"))
            figure(String(summary?.sickDays ?? 0), word: String(localized: "Sick"))
        }
    }

    private func figure(_ value: String, word: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: value)
                .font(.title2.bold())
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: word)
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Thu 29 · Trg Pravde · 8h 30m", a split day with "then Jarunski from
    /// 12:40" in blue under the site, a day away with its reason in the
    /// day type's colour.
    private func dayRow(_ day: CrewMemberMonth.Day) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.medium) {
            Text(verbatim: shortDay(day.date))
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
                .frame(minWidth: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if let reason = day.reason {
                    Text(verbatim: reasonText(reason))
                        .foregroundStyle(reasonColor(reason))
                } else {
                    Text(verbatim: day.siteIDs.first.flatMap { siteNames[$0] } ?? "—")
                    ForEach(Array(day.siteIDs.dropFirst().enumerated()), id: \.offset) { offset, siteID in
                        Text(verbatim: thenText(siteID: siteID, start: day.starts.indices.contains(offset + 1) ? day.starts[offset + 1] : nil, on: day.date))
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: day.reason == nil ? settings.displayFormatting.string(day.minutes) : "—")
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
        }
        .accessibilityElement(children: .combine)
    }

    /// "Thu 29".
    private func shortDay(_ date: CalendarDate) -> String {
        "\(settingsStore.dateFormatting.weekdayAbbreviation(date)) \(date.day)"
    }

    /// "then Jarunski from 12:40", or "then Jarunski" without a time.
    private func thenText(siteID: UUID, start: TimeOfDay?, on date: CalendarDate) -> String {
        let name = siteNames[siteID] ?? "—"
        guard let start else {
            return String(localized: "then \(name)", comment: "A person's month: the second site of a split day; the value is its name")
        }
        let time = settingsStore.dateFormatting.time(start, on: date)
        return String(localized: "then \(name) from \(time)", comment: "A person's month: the second site of a split day; the values are its name and the time they started there")
    }

    private func reasonColor(_ reason: AbsenceReason) -> Color {
        switch reason {
        case let .dayType(id): return settings.dayTypeCatalog.definition(for: id).tint.color
        case .otherSite: return .secondary
        }
    }

    private func reasonText(_ reason: AbsenceReason) -> String {
        switch reason {
        case let .dayType(id):
            return settings.dayTypeCatalog.definition(for: id).displayName()
        case let .otherSite(siteID):
            return siteID.flatMap { siteNames[$0] } ?? String(localized: "On another site")
        }
    }

    /// Share and Sign, side by side; one above the other at the largest
    /// text sizes.
    private var bottomButtons: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.small))
        return layout {
            Button(action: share) {
                Text(String(
                    localized: "Share \(member.name)'s sheet",
                    comment: "A crew member's month: share their own sheet; the value is their name"
                ))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .buttonStyle(.bigAction(.primary))
            .disabled(!canShare)
            .accessibilityIdentifier("crew-sheet-share")

            Button {
                signing = site
            } label: {
                Text("Sign the month")
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
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
