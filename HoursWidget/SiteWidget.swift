import SwiftUI
import WidgetKit

/// Today on the site you are working on: who is there, and why the others
/// are not. Before today is written, the last day and a button to write
/// today the same way.
///
/// The buttons are links that open the app (see `AppLink`). The site's days
/// live in the app's own store, which a widget cannot safely write, so the
/// widget asks and the app does it, under the same month lock and the same
/// rules as the button on the site screen.
struct SiteWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "HoursSite", provider: HoursProvider()) { entry in
            SiteWidgetView(entry: entry)
                .widgetSurface(onHomeScreen: true)
        }
        .configurationDisplayName("Site")
        .description("Today's crew on your site: who is there, and why the others are not.")
        .supportedFamilies([.systemMedium])
    }
}

struct SiteWidgetView: View {
    let entry: HoursEntry

    var body: some View {
        if !entry.hasData {
            VStack(alignment: .leading, spacing: 0) {
                WidgetHeader(title: String(localized: "Site"), systemImage: "person.2.fill")
                Spacer(minLength: 0)
                EmptyStateView(state: entry.state).frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            }
        } else if let site = entry.snapshot.site {
            SiteCard(entry: entry, site: site)
                .widgetURL(AppLink.site(site.id).url)
        } else {
            NoSiteView()
        }
    }
}

/// The site's name, "4 of 5 · since 07:00", and the crew.
struct SiteCard: View {
    let entry: HoursEntry
    let site: WidgetSite
    private let calendar = Calendar.current

    private var isWritten: Bool { entry.snapshot.isSiteTodayWritten(at: entry.date, calendar: calendar) }
    private var today: CalendarDate { CalendarDate(entry.date, calendar: calendar) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                WidgetHeader(title: site.name, systemImage: "person.2.fill")
                Spacer(minLength: 4)
                Text(verbatim: status)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .layoutPriority(1)
            }
            if isWritten {
                CrewList(rows: site.crew)
                    .padding(.top, 9)
                Spacer(minLength: 0)
            } else {
                SecondaryLine(text: lastDaySummary).padding(.top, 11)
                Spacer(minLength: 6)
                buttons
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "4 of 5 · since 07:00" once today is written, "Not written yet" before.
    private var status: String {
        guard isWritten else { return String(localized: "Not written yet") }
        var parts = [String(
            localized: "\(site.presentCount) of \(site.crew.count)",
            comment: "Site widget, people present of everyone on the crew list, e.g. 4 of 5"
        )]
        if let start = site.lastStart {
            parts.append(String(
                localized: "since \(WidgetText.time(start, on: entry.date))",
                comment: "Widget, the time the running clock was started"
            ))
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var buttons: some View {
        HStack(spacing: 8) {
            if let lastDay = site.lastDay {
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

/// Up to four lines: a name and ✓, or the reason they are away. More than
/// four, and the last line says how many more.
struct CrewList: View {
    let rows: [WidgetCrewRow]

    var body: some View {
        let fitting = WidgetCrewRow.fitting(rows, lines: 4)
        VStack(spacing: 0) {
            ForEach(Array(fitting.rows.enumerated()), id: \.offset) { _, row in
                line {
                    Text(verbatim: row.name).lineLimit(1)
                    Spacer(minLength: 8)
                    if row.isPresent {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WidgetTheme.accent)
                            .widgetAccentable()
                            .accessibilityLabel(Text("Present", comment: "VoiceOver, someone ticked present on the site"))
                    } else {
                        Text(verbatim: row.reason ?? "–")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            if fitting.more > 0 {
                line {
                    Text(verbatim: String(localized: "+\(fitting.more) more", comment: "Site widget, people not listed, e.g. +2 more"))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func line<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Rectangle().fill(WidgetTheme.rule).frame(height: 0.75)
            HStack(spacing: 0) { content() }
                .font(.system(size: 12).monospacedDigit())
                .frame(height: 24)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A capsule like the Today widget's, for the site's links.
struct SiteButton: View {
    let title: String
    let isPrimary: Bool

    var body: some View {
        Text(verbatim: title)
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(isPrimary ? WidgetTheme.accent : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(WidgetTheme.fill, in: Capsule())
            .widgetAccentable(isPrimary)
    }
}

/// No active site: say so quietly, and open the Sites tab where one is added.
struct NoSiteView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(title: String(localized: "No sites yet"), systemImage: "person.2.fill")
            Text(verbatim: String(localized: "Add the site you work on, and today's crew is one tap away here."))
                .font(.widgetLine)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .padding(.top, 8)
            Spacer(minLength: 6)
            SiteButton(title: String(localized: "Add a site"), isPrimary: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(AppLink.sites.url)
    }
}
