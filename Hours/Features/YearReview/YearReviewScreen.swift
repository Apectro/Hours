import SwiftUI
import SwiftData

/// Which year's review is open. A value for `fullScreenCover(item:)`.
struct ReviewedYear: Identifiable, Hashable {
    let year: Int
    var id: Int { year }
}

/// "Your 2026": a year's figures as a plain list, full screen (design v2:
/// the year's hours large on the background, then a row per figure).
///
/// Every figure is `YearReview`'s; this only fetches and draws. Nothing about
/// anybody else's hours is in it, and money only when you have a rate.
struct YearReviewScreen: View {
    let year: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settingsStore
    @Query private var siteEntries: [SiteEntry]

    var body: some View {
        // The year's whole weeks: earnings need them.
        PeriodDataProvider(range: settingsStore.engine.earningsRange(covering: yearRange)) { data in
            YearReviewPages(
                review: review(data),
                settings: settingsStore.settings,
                formatting: settingsStore.dateFormatting,
                close: { dismiss() }
            )
        }
        // No identifier here: on a container it is handed down to every
        // element inside and replaces theirs, so the pages name themselves.
    }

    private var calendar: Calendar { settingsStore.workCalendar }
    private var yearRange: CalendarDateRange { CalendarDateRange.year(year, in: calendar) }

    private func review(_ data: PeriodData) -> YearReview {
        YearReview.make(
            year: year,
            engine: PeriodEngine(settings: settingsStore.settings, calendar: calendar, firstRecorded: data.firstRecorded),
            records: data.records,
            holidays: data.holidays,
            today: CalendarDate.today(in: calendar),
            // Archived sites too: they are part of the year that was.
            siteNames: Dictionary(siteEntries.map { ($0.site.id, $0.site.name) }, uniquingKeysWith: { first, _ in first })
        )
    }
}

/// The year's figures, with Close and Share in the toolbar.
private struct YearReviewPages: View {
    let review: YearReview
    let settings: AppSettings
    let formatting: CalendarFormatting
    let close: () -> Void

    @State private var sharedImage: Image?

    var body: some View {
        NavigationStack {
            Group {
                if review.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle(titleText)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) {
                        Label("Close", systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("year-review-close")
                }
                ToolbarItem(placement: .primaryAction) {
                    if let sharedImage, !review.isEmpty {
                        ShareLink(
                            item: sharedImage,
                            preview: SharePreview(titleText, image: sharedImage)
                        ) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityIdentifier("year-review-share")
                    }
                }
            }
        }
        .onAppear { renderShareImage() }
        .onChange(of: review) { _, _ in renderShareImage() }
    }

    /// The year's hours first, on the background, then a row per figure.
    private var list: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Metrics.tiny) {
                    Text(introTitle)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                    Text(duration.string(review.workedMinutes))
                        .font(.largeTitle.bold())
                        .monospacedDigit()
                    Text(introCaption)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .listRowInsets(EdgeInsets(top: 0, leading: Metrics.large + Metrics.tiny, bottom: Metrics.small, trailing: Metrics.large))
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(cards, id: \.self) { card in
                    row(content(for: card))
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
    }

    private func row(_ content: YearReviewCardContent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text(content.title)
                Spacer(minLength: Metrics.small)
                Text(content.figure)
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if !content.detail.isEmpty {
                Text(content.detail)
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .combine)
    }

    private var duration: DurationFormatting { settings.displayFormatting }

    private var titleText: String {
        String(localized: "Your \(String(review.year))", comment: "Year in review title; the value is a year")
    }

    private var introTitle: String {
        String(localized: "In \(String(review.year)) you worked", comment: "Year in review, first card, over the year's hours; the value is a year")
    }

    /// "on 4 sites, with 212 days on site and 41h of overtime." — the parts
    /// there is something to say about.
    private var introCaption: String {
        guard review.sitesWorked > 0 else {
            if settings.features.showsBalance && review.overtimeMinutes > 0 {
                return String(
                    localized: "with \(duration.string(review.overtimeMinutes)) of overtime.",
                    comment: "Year in review, first card, under the hours; the value is a duration"
                )
            }
            return String(localized: "Swipe for your year in numbers.", comment: "Year in review, first card")
        }
        let sites = String(inflected: "^[\(review.sitesWorked) site](inflect: true)")
        let days = String(inflected: "^[\(review.daysOnSites) day](inflect: true)")
        if settings.features.showsBalance && review.overtimeMinutes > 0 {
            return String(
                localized: "on \(sites), with \(days) on site and \(duration.string(review.overtimeMinutes)) of overtime.",
                comment: "Year in review, first card; a number of sites, a number of days, and a duration"
            )
        }
        return String(
            localized: "on \(sites), with \(days) on site.",
            comment: "Year in review, first card; a number of sites and a number of days"
        )
    }

    /// The engine's cards, less the ones a setting has switched off here.
    private var cards: [YearReview.Card] {
        review.cards.filter { card in
            switch card {
            case .balance: return settings.features.showsBalance
            case .earnings: return settings.earningsAreSetUp
            default: return true
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(titleText, systemImage: "calendar.badge.clock")
        } description: {
            Text(String(
                localized: "Nothing recorded in \(String(review.year)) yet. Your review fills in as the days do.",
                comment: "Year in review with no data; the value is a year"
            ))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("year-review-empty")
    }

    // MARK: - What each card says

    func content(for card: YearReview.Card) -> YearReviewCardContent {
        switch card {
        case .hours:
            return YearReviewCardContent(
                title: String(localized: "Hours worked"),
                figure: duration.string(review.workedMinutes),
                detail: String(inflected: "^[\(review.daysWorked) day](inflect: true) worked"),
                systemImage: "clock"
            )
        case .sites:
            let top = review.topSite.map { top in
                String(
                    localized: "Most often at \(top.name): \(String(inflected: "^[\(top.days) day](inflect: true)"))",
                    comment: "Year in review; a site's name, then a number of days"
                )
            }
            return YearReviewCardContent(
                title: String(localized: "Days on sites"),
                figure: String(review.daysOnSites),
                detail: top ?? "",
                systemImage: "building.2"
            )
        case .busiestMonth:
            let month = review.busiestMonth
            return YearReviewCardContent(
                title: String(localized: "Busiest month"),
                figure: month.map { formatting.monthName($0.month) } ?? "",
                detail: month.map { String(localized: "\(duration.string($0.workedMinutes)) worked", comment: "A duration worked in a month") } ?? "",
                systemImage: "chart.bar.fill"
            )
        case .longestDay:
            let day = review.longestDay
            return YearReviewCardContent(
                title: String(localized: "Longest day"),
                figure: day.map { duration.string($0.workedMinutes) } ?? "",
                detail: day.map { formatting.fullDate($0.date) } ?? "",
                systemImage: "sun.max.fill"
            )
        case .balance:
            return YearReviewCardContent(
                title: String(localized: "The year's balance"),
                figure: duration.signedString(review.balanceMinutes),
                detail: String(localized: "This year's days only, not the running balance."),
                systemImage: "plusminus"
            )
        case .vacation:
            return YearReviewCardContent(
                title: String(localized: "Vacation days taken"),
                figure: review.vacationDays.localized,
                detail: "",
                systemImage: "beach.umbrella.fill"
            )
        case .earnings:
            return YearReviewCardContent(
                title: String(localized: "Earned"),
                figure: settings.money.string(review.earningsCents ?? 0, showsCents: false),
                detail: String(localized: "Before tax, from your own hours."),
                systemImage: "banknote"
            )
        case .badWeather:
            let type = settings.dayTypeCatalog.definition(for: YearReview.badWeatherTypeID)
            return YearReviewCardContent(
                title: type.displayName(),
                figure: String(review.badWeatherDays ?? 0),
                detail: "",
                systemImage: type.symbolName
            )
        }
    }

    // MARK: - Sharing

    /// The summary as a picture, for the share sheet. Drawn once per review
    /// rather than when Share is tapped, so the button opens straight away.
    @MainActor
    private func renderShareImage() {
        guard !review.isEmpty else { sharedImage = nil; return }
        let summary = YearReviewShareImage(
            title: titleText,
            rows: cards.map { content(for: $0) }
        )
        let renderer = ImageRenderer(content: summary)
        renderer.scale = 3
        sharedImage = renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// What one card shows.
struct YearReviewCardContent: Hashable {
    var title: String
    var figure: String
    var detail: String
    var systemImage: String
}

/// The picture that is shared: the year's figures as a plain list on
/// white. Fixed size and type, so it looks the same whatever text size the
/// phone is set to.
private struct YearReviewShareImage: View {
    let title: String
    let rows: [YearReviewCardContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(.black)
                .padding(.bottom, 4)
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(row.title)
                        .font(.system(size: 17))
                        .foregroundStyle(.black)
                    Spacer(minLength: 12)
                    Text(row.figure)
                        .font(.system(size: 17, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                Divider()
            }
            Text(verbatim: AppIdentity.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.gray)
                .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 390, alignment: .leading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}

/// The late-December row on Insights: an offer, not a notification.
/// Opening it or putting it away puts it away for the year. Without
/// `dismiss` it is only the row that opens the review.
struct YearReviewInvitation: View {
    let year: Int
    let open: () -> Void
    /// Nil where the row is part of the screen rather than a seasonal offer
    /// that can be put away.
    var dismiss: (() -> Void)?
    var identifier = "insights-year-review-invitation"

    var body: some View {
        HStack(spacing: Metrics.small) {
            Button(action: open) {
                HStack(spacing: Metrics.medium) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Your \(String(year))", comment: "Opens the year in review; the value is a year"))
                            .foregroundStyle(.primary)
                        Text("Your year in numbers")
                            .font(.subheadline)
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier(identifier)

            if let dismiss {
                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(String(localized: "Not now"))
                .accessibilityIdentifier("insights-year-review-dismiss")
            }
        }
        // Two buttons in one row: without this a tap anywhere in the row
        // presses both.
        .buttonStyle(.borderless)
    }
}
