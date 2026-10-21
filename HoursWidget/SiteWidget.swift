import SwiftUI
import WidgetKit

/// Today on the site you are working on: written or not, who was there last
/// time, and a button to write today the same way.
///
/// Both buttons are links that open the app (see `AppLink`). The site's days
/// live in the app's own store, which a widget cannot safely write, so the
/// widget asks and the app does it, under the same month lock and the same
/// rules as the button on the site screen.
struct SiteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursSite", provider: HoursProvider()) { entry in
            SiteWidgetView(entry: entry)
                .widgetCard(.paper, onHomeScreen: true)
        }
        .configurationDisplayName("Site")
        .description("Today on your site, and who was there last time.")
        .supportedFamilies([.systemMedium])
    }
}

struct SiteWidgetView: View {
    let entry: HoursEntry

    var body: some View {
        if !entry.hasData {
            HStack {
                Spacer(minLength: 0)
                EmptyStateView(state: entry.state, compact: false)
                Spacer(minLength: 0)
            }
        } else if let site = entry.snapshot.site {
            SiteCard(entry: entry, site: site)
        } else {
            NoSiteView()
        }
    }
}

/// Board 11, bottom.
struct SiteCard: View {
    let entry: HoursEntry
    let site: WidgetSite
    private let calendar = Calendar.current

    private var isWritten: Bool { entry.snapshot.isSiteTodayWritten(at: entry.date, calendar: calendar) }
    private var today: CalendarDate { CalendarDate(entry.date, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                HardHatBadge(size: 26)
                Text(site.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.navy)
                    .lineLimit(1)
                Spacer(minLength: 4)
                WidgetChip(
                    text: isWritten ? String(localized: "Written") : String(localized: "Not written yet"),
                    foreground: isWritten ? WidgetPalette.writtenText : WidgetPalette.pendingText,
                    background: isWritten ? WidgetPalette.running.opacity(0.16) : WidgetPalette.pendingBackground
                )
            }
            Spacer(minLength: 6)
            CrewLine(site: site, summary: lastDaySummary)
            Spacer(minLength: 6)
            buttons
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            // Hidden once today is written: there is nothing left to copy
            // into, and the app would only open the site anyway.
            if !isWritten, let lastDay = site.lastDay {
                Link(destination: AppLink.siteSameAsLastDay(site.id).url) {
                    SiteButton(title: sameAsTitle(lastDay), isPrimary: true)
                }
            }
            Link(destination: AppLink.site(site.id).url) {
                SiteButton(title: String(localized: "Open site"), isPrimary: false)
            }
        }
    }

    /// "Same as yesterday" when it was yesterday, which is nearly always;
    /// the site screen's own words otherwise.
    private func sameAsTitle(_ lastDay: CalendarDate) -> String {
        lastDay == today.adding(days: -1, in: calendar)
            ? String(localized: "Same as yesterday")
            : String(localized: "Same as last day")
    }

    /// "Yesterday · 4 people · 07:00–16:00".
    private var lastDaySummary: String {
        guard let lastDay = site.lastDay else { return String(localized: "Nothing written yet") }
        var parts = [dayName(lastDay)]
        if site.lastDayPeople > 0 {
            parts.append(String(inflected: "^[\(site.lastDayPeople) person](inflect: true)"))
        }
        if let start = site.lastStart, let end = site.lastEnd {
            let formatting = CalendarFormatting(locale: .current, calendar: calendar)
            parts.append(formatting.time(start, on: lastDay) + "–" + formatting.time(end, on: lastDay))
        }
        return parts.joined(separator: " · ")
    }

    private func dayName(_ date: CalendarDate) -> String {
        let days = date.days(until: today, in: calendar)
        let formatting = CalendarFormatting(locale: .current, calendar: calendar)
        switch days {
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Yesterday")
        case 2...6: return formatting.weekdayName(for: date.weekday(in: calendar))
        default: return formatting.shortDate(date)
        }
    }
}

/// Up to four faces, overlapping, then the line about the day.
struct CrewLine: View {
    let site: WidgetSite
    let summary: String

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: -12) {
                if site.includesYou {
                    Face(content: Image(systemName: "person.fill"), color: WidgetPalette.navy)
                }
                ForEach(Array(site.initials.enumerated()), id: \.offset) { index, initials in
                    Face(
                        content: Text(verbatim: initials),
                        color: WidgetPalette.faces[index % WidgetPalette.faces.count]
                    )
                }
            }
            .accessibilityHidden(true)
            if site.morePeople > 0 {
                Text(verbatim: "+\(site.morePeople)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.navy)
            }
            Text(summary)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(WidgetPalette.paperText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

/// One round face on the site card: you as a figure, everyone else as
/// their initials.
struct Face<Content: View>: View {
    let content: Content
    let color: Color
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(renderingMode.isFullColor ? Color.white : Color.primary)
            .frame(width: 30, height: 30)
            .background(Circle().fill(renderingMode.isFullColor ? color : Color.primary.opacity(0.2)))
            .overlay(Circle().stroke(WidgetPalette.paper, lineWidth: renderingMode.isFullColor ? 2 : 0))
    }
}

struct SiteButton: View {
    let title: String
    let isPrimary: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        Text(title)
            .font(.system(size: 14, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isPrimary && renderingMode.isFullColor ? Color.white : WidgetPalette.navy)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .widgetAccentable(isPrimary)
    }

    private var background: Color {
        guard renderingMode.isFullColor else { return Color.primary.opacity(isPrimary ? 0.25 : 0.12) }
        return isPrimary ? WidgetPalette.navy : WidgetPalette.paperButton
    }
}

/// No active site: say so kindly, and open the Sites tab where one is added.
struct NoSiteView: View {
    var body: some View {
        HStack(spacing: 14) {
            HardHatBadge(size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text("No sites yet")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.navy)
                Text("Add the site you work on, and today's crew is one tap away here.")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(WidgetPalette.paperText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .widgetURL(AppLink.sites.url)
    }
}
