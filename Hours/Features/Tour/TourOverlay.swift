import SwiftUI

/// The guided tour, drawn over the whole app: the screen dimmed, a rounded
/// cut-out around the control a stop is about, and a card above or below it
/// saying what it is.
///
/// It waits, up to a moment, for the stop's target to report where it is —
/// the tour may just have switched tabs — and a target that never appears
/// (switched off in Settings, scrolled away) shows the card in the middle
/// with nothing lit, so the tour can never get stuck. Taps outside the card
/// do nothing, so nothing is skipped by accident.
struct TourOverlay: View {
    let coordinator: TourCoordinator

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The stop whose card is showing. Behind `coordinator.tour` while it
    /// waits for the next stop's target.
    @State private var shownStop: TourStop?
    @State private var cardHeight: CGFloat = 0
    @AccessibilityFocusState private var cardHasFocus: Bool

    var body: some View {
        if let tour = coordinator.tour {
            ZStack {
                dimming
                cardLayer(tour)
            }
            .task(id: tour.stop) { await settle(on: tour.stop) }
            .onDisappear { shownStop = nil }
        }
    }

    // MARK: - The dimmed screen

    /// Edge to edge, under the status bar and the tab bar too. It takes
    /// every tap and does nothing with it, and VoiceOver never sees it.
    private var dimming: some View {
        GeometryReader { proxy in
            let hole = spotlight(in: proxy.frame(in: .global))
            SpotlightShape(
                hole: hole ?? CGRect(x: proxy.size.width / 2, y: proxy.size.height / 2, width: 0, height: 0),
                cornerRadius: Metrics.cornerRadius
            )
            .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
            .animation(movement, value: hole)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture {}
        .accessibilityHidden(true)
    }

    // MARK: - The card

    /// Inside the safe area, so the card never slides under the status bar,
    /// the home indicator or the tab bar's edge.
    private func cardLayer(_ tour: GuidedTour) -> some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let hole = spotlight(in: proxy.frame(in: .global))
            let width = min(bounds.width - 2 * Metrics.large, 440)
            TourCard(
                tour: tour,
                title: title(for: tour.stop),
                message: message(for: tour),
                onNext: coordinator.next,
                onEnd: coordinator.end,
                focus: $cardHasFocus
            )
            .frame(width: max(width, 0))
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
            .offset(x: (bounds.width - width) / 2, y: cardTop(in: bounds, avoiding: hole))
            // Hidden, untappable and silent while the next stop settles, so
            // a second tap cannot skip a stop nobody has seen.
            .opacity(shownStop == tour.stop ? 1 : 0)
            .allowsHitTesting(shownStop == tour.stop)
            .accessibilityHidden(shownStop != tour.stop)
            .animation(movement, value: shownStop)
            .animation(movement, value: hole)
        }
    }

    /// Below the lit control when it fits there (or there is more room
    /// there), otherwise above it; in the middle when nothing is lit.
    private func cardTop(in bounds: CGRect, avoiding hole: CGRect?) -> CGFloat {
        let gap = Metrics.medium
        guard let hole else { return max((bounds.height - cardHeight) / 2, 0) }
        let roomBelow = bounds.maxY - hole.maxY - gap
        let roomAbove = hole.minY - bounds.minY - gap
        let top: CGFloat
        if roomBelow >= cardHeight || roomBelow >= roomAbove {
            top = hole.maxY + gap
        } else {
            top = hole.minY - gap - cardHeight
        }
        return min(max(top, 0), max(bounds.height - cardHeight, 0))
    }

    /// The shown stop's target, in the coordinates of the view whose
    /// window frame is `container`, a little larger than the control; nil
    /// when there is none or it is not on screen.
    private func spotlight(in container: CGRect) -> CGRect? {
        guard let stop = shownStop, let target = stop.target, let frame = coordinator.frames[target] else { return nil }
        let local = frame.offsetBy(dx: -container.minX, dy: -container.minY).insetBy(dx: -6, dy: -6)
        let visible = CGRect(origin: .zero, size: container.size)
        guard local.intersects(visible), local.width > 0, local.height > 0 else { return nil }
        return local
    }

    private var movement: Animation? {
        reduceMotion ? nil : .snappy(duration: 0.35)
    }

    // MARK: - Moving between stops

    /// Waits up to about a second for the stop's target to be on screen —
    /// a tab switch and its first layout take a moment — then shows the
    /// card, and moves VoiceOver to it.
    private func settle(on stop: TourStop) async {
        // Off first, so turning it on below moves VoiceOver even when the
        // card's title already had it.
        cardHasFocus = false
        if let target = stop.target {
            for _ in 0..<12 {
                if let frame = coordinator.frames[target], frame.width > 0, frame.height > 0 { break }
                try? await Task.sleep(for: .milliseconds(100))
                if Task.isCancelled { return }
            }
            // One more beat, so a list that has just scrolled is where it
            // stops rather than where it was passing through.
            try? await Task.sleep(for: .milliseconds(150))
            if Task.isCancelled { return }
        }
        shownStop = stop
        try? await Task.sleep(for: .milliseconds(50))
        if Task.isCancelled { return }
        cardHasFocus = true
    }

    // MARK: - Words

    private var settings: AppSettings { settingsStore.settings }

    private func title(for stop: TourStop) -> String {
        switch stop {
        case .welcome: return String(localized: "Zeitkonto in a minute")
        case .today: return String(localized: "Today")
        case .summary: return String(localized: "Your month")
        case .sites: return String(localized: "Your sites")
        case .insights: return String(localized: "Insights")
        case .export: return String(localized: "Your sheets")
        }
    }

    private func message(for tour: GuidedTour) -> String {
        switch tour.stop {
        case .welcome:
            return String(localized: "Write your hours each day, and Zeitkonto keeps your balance and makes the sheets for your boss.")
        case .today:
            return String(localized: "Your own hours live on Today. Write today in one tap, or tap a day to change it.")
        case .summary:
            if settings.showsEarnings {
                return String(localized: "Worked is what you did this month. Earned is what those hours have paid so far.")
            }
            if settings.features.showsBalance {
                return String(localized: "Worked is what you did this month. Balance is how far ahead (+) or behind (−) your normal hours you are.")
            }
            return String(localized: "Worked is what you did this month, with your average day beside it.")
        case .sites:
            if tour.leadsCrew {
                return String(localized: "Each site keeps its crew and its usual day. Open one to write the crew's day in one tap.")
            }
            return String(localized: "Sites are there if you ever lead a crew.")
        case .insights:
            return String(localized: "Your week, month or year in figures. Pick the period here.")
        case .export:
            return String(
                localized: "A site's Sheet sends the month as PDF or Excel. Here you choose how sheets look. Report language: \(reportLanguageName).",
                comment: "Last stop of the guided tour; the value is a language's name, such as Croatian"
            )
        }
    }

    /// The report language in the phone's language: "Croatian" on an
    /// English phone, "Kroatisch" on a German one.
    private var reportLanguageName: String {
        let language = settings.export.language.resolved
        guard let code = language.locale.language.languageCode?.identifier,
              let name = Locale.current.localizedString(forLanguageCode: code)
        else { return language.title }
        return name.capitalizedFirstLetter
    }
}

/// The card: what this is, where you are, and the way on. A plain
/// rounded rectangle of the system's material (design v2), no shadow.
private struct TourCard: View {
    let tour: GuidedTour
    let title: String
    let message: String
    let onNext: () -> Void
    let onEnd: () -> Void
    var focus: AccessibilityFocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            // The identifier is on the title, not on the card: the card
            // holds the buttons, and an identifier on a container that wraps
            // buttons takes theirs away.
            Text(title)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(focus)
                .accessibilityIdentifier("tour-card")

            Text(message)
                .foregroundStyle(.hoursSecondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Metrics.medium) {
                Text(String(
                    localized: "\(tour.number) of \(tour.count)",
                    comment: "Guided tour progress, such as 2 of 6"
                ))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
                Spacer(minLength: 0)
                if !tour.isLast {
                    Button(action: onEnd) {
                        Text("Skip")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityHint(Text("Ends the tour"))
                    .accessibilityIdentifier("tour-skip")
                }
                if tour.isLast {
                    Button(action: onEnd) {
                        Text("Done")
                            .font(.headline)
                            .frame(minWidth: 64, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("tour-done")
                } else {
                    Button(action: onNext) {
                        Text("Next")
                            .font(.headline)
                            .frame(minWidth: 64, minHeight: 32)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityIdentifier("tour-next")
                }
            }
            .padding(.top, Metrics.tiny)
        }
        .padding(Metrics.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

/// The whole rectangle with a rounded hole in it, filled even-odd. The hole
/// is animatable, so it glides from one control to the next.
private struct SpotlightShape: Shape {
    var hole: CGRect
    var cornerRadius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.minX, hole.minY), AnimatablePair(hole.width, hole.height)) }
        set {
            hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second)
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if hole.width > 0, hole.height > 0 {
            let radius = min(cornerRadius, hole.width / 2, hole.height / 2)
            path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        }
        return path
    }
}
