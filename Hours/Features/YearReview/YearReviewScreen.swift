import SwiftUI
import SwiftData

/// Which year's review is open. A value for `fullScreenCover(item:)`.
struct ReviewedYear: Identifiable, Hashable {
    let year: Int
    var id: Int { year }
}

/// The app icon's navy and amber, which the widgets are drawn in too. The
/// review is always on navy, in light and dark alike, so it reads as the
/// same object in both.
enum YearReviewPalette {
    static let navy = Color(red: 0x12 / 255, green: 0x1a / 255, blue: 0x45 / 255)
    static let navyLight = Color(red: 0x1f / 255, green: 0x2d / 255, blue: 0x6b / 255)
    static let amber = Color(red: 0xff / 255, green: 0xb0 / 255, blue: 0x2e / 255)
    static let amberDeep = Color(red: 0xf0 / 255, green: 0x8a / 255, blue: 0x1e / 255)
    /// Secondary text on navy.
    static let mist = Color(red: 0x9f / 255, green: 0xb0 / 255, blue: 0xe8 / 255)

    static var background: LinearGradient {
        LinearGradient(colors: [navyLight, navy], startPoint: .top, endPoint: .bottom)
    }
}

/// "Your 2026": a year's figures, a card at a time, full screen.
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

/// The swipeable cards, with the close and share buttons over them.
private struct YearReviewPages: View {
    let review: YearReview
    let settings: AppSettings
    let formatting: CalendarFormatting
    let close: () -> Void

    @State private var sharedImage: Image?

    var body: some View {
        ZStack(alignment: .top) {
            YearReviewPalette.background.ignoresSafeArea()

            if review.isEmpty {
                emptyState
            } else {
                TabView {
                    YearReviewCardView(title: titleText, figure: String(review.year), caption: introCaption, isIntro: true)
                    ForEach(cards, id: \.self) { card in
                        YearReviewCardView(content: content(for: card))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .interactive))
            }

            toolbar
        }
        // Always on navy, so always dark — for this screen only. Not
        // `preferredColorScheme`, which can reach past a presentation to the
        // window behind it.
        .environment(\.colorScheme, .dark)
        .onAppear { renderShareImage() }
        .onChange(of: review) { _, _ in renderShareImage() }
    }

    private var duration: DurationFormatting { settings.displayFormatting }

    private var titleText: String {
        String(localized: "Your \(String(review.year))", comment: "Year in review title; the value is a year")
    }

    private var introCaption: String {
        String(localized: "Swipe for your year in numbers.", comment: "Year in review, first card")
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

    private var toolbar: some View {
        HStack {
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .accessibilityLabel(String(localized: "Close"))
            .accessibilityIdentifier("year-review-close")

            Spacer()

            if let sharedImage, !review.isEmpty {
                ShareLink(
                    item: sharedImage,
                    preview: SharePreview(titleText, image: sharedImage)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.headline)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.12), in: Circle())
                }
                .accessibilityLabel(String(localized: "Share"))
                .accessibilityIdentifier("year-review-share")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Metrics.large)
        .padding(.top, Metrics.small)
    }

    private var emptyState: some View {
        VStack(spacing: Metrics.medium) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundStyle(YearReviewPalette.amber)
                .accessibilityHidden(true)
            Text(titleText)
                .font(.largeTitle.bold())
            Text(String(
                localized: "Nothing recorded in \(String(review.year)) yet. Your review fills in as the days do.",
                comment: "Year in review with no data; the value is a year"
            ))
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(YearReviewPalette.mist)
        }
        .foregroundStyle(.white)
        .padding(Metrics.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

/// One full-screen card.
private struct YearReviewCardView: View {
    var title: String
    var figure: String
    var caption: String
    var systemImage: String = "sparkles"
    var isIntro = false

    /// The figure is the card. It grows with the text size, and shrinks to
    /// fit a long month name rather than wrapping it.
    @ScaledMetric(relativeTo: .largeTitle) private var figureSize: CGFloat = 64

    init(title: String, figure: String, caption: String, isIntro: Bool) {
        self.title = title
        self.figure = figure
        self.caption = caption
        self.isIntro = isIntro
    }

    init(content: YearReviewCardContent) {
        self.title = content.title
        self.figure = content.figure
        self.caption = content.detail
        self.systemImage = content.systemImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            Spacer()
            if !isIntro {
                Image(systemName: systemImage)
                    .font(.title)
                    .foregroundStyle(YearReviewPalette.amber)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(isIntro ? .title.bold() : .title3.weight(.semibold))
                .foregroundStyle(isIntro ? YearReviewPalette.amber : YearReviewPalette.mist)
            Text(figure)
                .font(.system(size: isIntro ? figureSize * 1.35 : figureSize, weight: .bold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.4)
                .lineLimit(2)
                .foregroundStyle(.white)
            if !caption.isEmpty {
                Text(caption)
                    .font(.title3)
                    .foregroundStyle(YearReviewPalette.mist)
            }
            Spacer()
            Spacer()
        }
        .padding(.horizontal, Metrics.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The picture that is shared: the year's figures on one navy card. Fixed
/// size and type, so it looks the same whatever text size the phone is set
/// to.
private struct YearReviewShareImage: View {
    let title: String
    let rows: [YearReviewCardContent]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(YearReviewPalette.amber)
                Spacer()
                Image(systemName: "sparkles")
                    .font(.system(size: 26))
                    .foregroundStyle(YearReviewPalette.amber)
            }
            ForEach(rows, id: \.self) { row in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: row.systemImage)
                        .font(.system(size: 17))
                        .foregroundStyle(YearReviewPalette.amber)
                        .frame(width: 24)
                    Text(row.title)
                        .font(.system(size: 17))
                        .foregroundStyle(YearReviewPalette.mist)
                    Spacer(minLength: 12)
                    Text(row.figure)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
            }
            Text(verbatim: AppIdentity.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(YearReviewPalette.mist)
                .padding(.top, 6)
        }
        .padding(28)
        .frame(width: 390, alignment: .leading)
        .background(YearReviewPalette.background)
        .environment(\.colorScheme, .dark)
    }
}

/// The late-December card on Insights: an offer, not a notification. Opening
/// it or putting it away puts it away for the year.
struct YearReviewInvitation: View {
    let year: Int
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: Metrics.medium) {
            Button(action: open) {
                HStack(spacing: Metrics.medium) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(YearReviewPalette.amber)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "Your \(String(year))", comment: "Opens the year in review; the value is a year"))
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Your year in numbers, a card at a time.")
                            .font(.subheadline)
                            .foregroundStyle(YearReviewPalette.mist)
                    }
                    Spacer(minLength: 0)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("insights-year-review-invitation")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(YearReviewPalette.mist)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(String(localized: "Not now"))
            .accessibilityIdentifier("insights-year-review-dismiss")
        }
        .padding(.leading, Metrics.large)
        .padding(.vertical, Metrics.small)
        .background(YearReviewPalette.background, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}
