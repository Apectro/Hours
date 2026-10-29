import AppIntents
import SwiftUI
import WidgetKit

/// The widgets' look (1.2): the system's own widget background, system label
/// colours, and one accent — the app icon's blue. Quiet on purpose: no
/// gradients, no chips, no capital-letter labels on the Home Screen, so a
/// widget sits beside Apple's own and does not shout.
///
/// The colours live in the extension's asset catalogue, each with its light
/// and dark value. They are named through `Color("…")` rather than the
/// generated symbols, so nothing here depends on that build setting.
enum WidgetTheme {
    /// Brand blue: #4C8FDB on dark, #356FB4 on white.
    static let accent = Color("WidgetBlue")
    /// The system widget background: #1C1C1E dark, white light.
    static let background = Color("WidgetBackground")
    /// Empty bars, rings and discs: #3A3A3C / #E5E5EA.
    static let track = Color("WidgetTrack")
    /// The capsule buttons' fill: #2C2C2E / #E9E9EB.
    static let fill = Color("WidgetFill")
    /// Hairlines between list rows.
    static let rule = Color("WidgetRule")
    /// The Stop button: system red.
    static let stop = Color.red
}

extension Font {
    /// The big figure: SF Rounded, semibold, tabular digits. 38pt on the Home
    /// Screen, as the design draws it.
    static func widgetFigure(size: CGFloat = 38, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    /// Header titles: 13pt semibold.
    static let widgetHeader = Font.system(size: 13, weight: .semibold)
    /// The lines under a figure: 12.5pt.
    static let widgetLine = Font.system(size: 12.5).monospacedDigit()
    /// Lock Screen label, above the figure.
    static let lockLabel = Font.system(size: 11, weight: .semibold)
    /// Lock Screen figure.
    static func lockFigure(size: CGFloat = 27) -> Font {
        .system(size: size, weight: .semibold, design: .rounded).monospacedDigit()
    }
    /// Lock Screen line under the figure.
    static let lockLine = Font.system(size: 12.5).monospacedDigit()
}

extension View {
    /// A Home Screen widget on the system's widget background; a Lock Screen
    /// accessory on the wallpaper. Both declare a container background, as
    /// iOS 17 made mandatory; in the tinted and clear styles the system takes
    /// the background away itself.
    @ViewBuilder
    func widgetSurface(onHomeScreen: Bool) -> some View {
        if onHomeScreen {
            containerBackground(WidgetTheme.background, for: .widget)
        } else {
            containerBackground(.clear, for: .widget)
        }
    }
}

extension WidgetFamily {
    var isHomeScreen: Bool {
        switch self {
        case .systemSmall, .systemMedium, .systemLarge, .systemExtraLarge: return true
        default: return false
        }
    }
}

extension WidgetRenderingMode {
    /// False in the tinted and clear Home Screen styles and on the Lock
    /// Screen, where every colour becomes one tint.
    var isFullColor: Bool { self == .fullColor }
}

// MARK: - Marks

/// The app icon's mark in one colour: the clock's rim and the part of the
/// day already worked, from twelve to five, which is how the icon shades it.
struct ClockMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let rim = side * 0.11
        let outer = side / 2 - rim / 2
        let wedge = outer - rim * 1.6

        var path = Path(ellipseIn: CGRect(
            x: centre.x - outer, y: centre.y - outer, width: outer * 2, height: outer * 2
        )).strokedPath(StrokeStyle(lineWidth: rim))
        // Twelve o'clock is -90° in SwiftUI's downward y; five is 60° on.
        path.move(to: centre)
        path.addArc(center: centre, radius: wedge, startAngle: .degrees(-90), endAngle: .degrees(60), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The clock's rim alone: the mark on a day off, with nothing worked.
struct ClockRim: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let rim = side * 0.11
        let outer = side / 2 - rim / 2
        return Path(ellipseIn: CGRect(
            x: rect.midX - outer, y: rect.midY - outer, width: outer * 2, height: outer * 2
        )).strokedPath(StrokeStyle(lineWidth: rim))
    }
}

/// A wedge from twelve o'clock, as much of the circle as `fraction` says:
/// the day filled like the app icon, on the circular Lock Screen widget.
struct DayWedge: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let share = min(max(fraction, 0), 1)
        var path = Path()
        guard share > 0 else { return path }
        if share >= 1 { return Path(ellipseIn: rect.insetBy(dx: rect.width / 2 - radius, dy: rect.height / 2 - radius)) }
        path.move(to: centre)
        path.addArc(
            center: centre, radius: radius,
            startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * share), clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// The small symbol and title every Home Screen widget starts with.
struct WidgetHeader<Symbol: View>: View {
    let title: String
    @ViewBuilder let symbol: () -> Symbol

    var body: some View {
        HStack(spacing: 5) {
            symbol()
                .foregroundStyle(WidgetTheme.accent)
                .frame(width: 13, height: 13)
                .widgetAccentable()
                .accessibilityHidden(true)
            Text(verbatim: title)
                .font(.widgetHeader)
                .lineLimit(1)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

extension WidgetHeader where Symbol == AnyView {
    /// A header with an SF Symbol.
    init(title: String, systemImage: String) {
        self.title = title
        self.symbol = {
            AnyView(Image(systemName: systemImage).resizable().scaledToFit().font(.system(size: 13, weight: .semibold)))
        }
    }
}

/// The big number.
struct BigFigure: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.widgetFigure())
            .lineLimit(1)
            .minimumScaleFactor(0.45)
            .widgetAccentable()
    }
}

/// A line in the secondary label colour.
struct SecondaryLine: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.widgetLine)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }
}

/// The capsule under the Today widget: Clock out in red, Clock in in the
/// accent. The app's own words rather than a bare "Start", whose
/// translations already mean a start time.
/// A real button, run by the clock's own App Intents in the app's process.
struct ClockButton: View {
    let isRunning: Bool

    var body: some View {
        Group {
            if isRunning {
                Button(intent: StopClockIntent()) {
                    label(String(localized: "Clock out"), symbol: "stop.fill", tint: WidgetTheme.stop)
                }
                .accessibilityIdentifier("widget-stop")
            } else {
                Button(intent: ToggleClockIntent(value: true)) {
                    label(String(localized: "Clock in"), symbol: "play.fill", tint: WidgetTheme.accent)
                }
                .accessibilityIdentifier("widget-start")
            }
        }
        .buttonStyle(.plain)
    }

    private func label(_ title: String, symbol: String, tint: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
            Text(verbatim: title)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(tint)
        .frame(maxWidth: .infinity)
        .frame(height: 30)
        .background(WidgetTheme.fill, in: Capsule())
        .contentShape(Capsule())
        .widgetAccentable()
    }
}

extension ToggleClockIntent {
    /// The intent set to the state it should end in: `true` clocks in.
    init(value: Bool) {
        self.init()
        self.value = value
    }
}

/// What every widget shows when there is nothing to show.
///
/// Different nothings need different words: one is waiting for the app to be
/// opened, one cannot ever work until a capability is turned on, and one is
/// simply not part of what was bought.
struct EmptyStateView: View {
    var state: HoursEntry.State
    var compact: Bool = false

    private var symbol: String {
        switch state {
        case .unavailable: return "exclamationmark.triangle"
        case .locked: return "lock.fill"
        default: return "clock.badge.questionmark"
        }
    }

    // Built as `String`, so unlike a `Text("literal")` these do not localise
    // themselves — they have to ask.
    private var message: String {
        switch state {
        case .unavailable:
            return compact
                ? String(localized: "Set up")
                : String(localized: "Turn on App Groups to use the widget")
        case .waiting:
            return compact
                ? String(localized: "Open Zeitkonto")
                : String(localized: "Open Zeitkonto once to fill this in")
        case .locked:
            return compact
                ? String(localized: "Zeitkonto Pro")
                : String(localized: "Widgets are part of Zeitkonto Pro")
        case .data, .sample:
            return ""
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            if compact {
                Image(systemName: symbol)
                    .font(.title3)
            } else {
                ClockMark()
                    .fill(WidgetTheme.accent)
                    .frame(width: 26, height: 26)
                    .widgetAccentable()
            }
            Text(message)
                .font(.caption2)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A quiet sentence in place of figures: "Set your hourly rate", "Overtime
/// is switched off". The widget is placed and working; there is simply
/// nothing of this kind to show yet.
struct QuietNote: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.widgetLine)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .lineLimit(3)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension HoursEntry {
    /// Real figures or the gallery's sample: the two states with something to
    /// draw.
    var hasData: Bool { state == .data || state == .sample }
}

extension WidgetSnapshot {
    /// What the running clock is for: its site when that is certain, its job
    /// when there is more than one, otherwise nothing.
    var clockPlace: String? { clockSiteName ?? clockJobName }
}

/// Text the widgets share, in one place.
enum WidgetText {
    /// "16:30" or "4:30 PM", as the phone tells the time.
    static func time(_ time: TimeOfDay, on date: Date, calendar: Calendar = .current) -> String {
        CalendarFormatting(locale: .current, calendar: calendar).time(time, on: CalendarDate(date, calendar: calendar))
    }

    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "106 h": a month's hours, whole.
    static func wholeHours(_ minutes: Int) -> String {
        String(localized: "\(minutes / 60) h", comment: "Widget, a number of whole hours, e.g. 106 h")
    }

    /// "October", in the phone's language.
    static func monthName(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide))
    }

    /// "OCT".
    static func monthAbbreviation(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated)).uppercased()
    }

    /// "Week 43".
    static func week(_ number: Int?) -> String {
        guard let number else { return String(localized: "Week", comment: "Widget header, the week widget") }
        return String(localized: "Week \(number)", comment: "Widget header, the week's number in the year")
    }

    /// "≈ 1½ days off".
    static func daysOff(_ days: HalfDays) -> String {
        if days == HalfDays(halves: 2) {
            return String(localized: "≈ 1 day off", comment: "Widget, the balance read as one day off")
        }
        if days == HalfDays(halves: 1) {
            return String(localized: "≈ ½ day off", comment: "Widget, the balance read as half a day off")
        }
        return String(localized: "≈ \(days.withHalfSign) days off", comment: "Widget, the balance read as days off, e.g. 1½")
    }

    /// "22–24 Dec", or "30 Dec – 2 Jan" across a month.
    static func range(_ start: CalendarDate, _ end: CalendarDate, calendar: Calendar = .current) -> String {
        let from = start.date(in: calendar)
        let to = end.date(in: calendar)
        if start == end { return from.formatted(.dateTime.day().month(.abbreviated)) }
        if start.month == end.month, start.year == end.year {
            return from.formatted(.dateTime.day()) + "–" + to.formatted(.dateTime.day().month(.abbreviated))
        }
        return from.formatted(.dateTime.day().month(.abbreviated)) + " – " + to.formatted(.dateTime.day().month(.abbreviated))
    }

    /// The letter for a weekday, as the phone writes it.
    static func weekdayLetter(_ date: CalendarDate, calendar: Calendar = .current) -> String {
        CalendarFormatting(locale: .current, calendar: calendar).veryShortWeekdaySymbol(for: date.weekday(in: calendar))
    }
}
