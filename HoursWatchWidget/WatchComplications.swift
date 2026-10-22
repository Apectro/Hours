import SwiftUI
import WidgetKit

/// The watch face complications: today's hours and whether the clock runs.
///
/// Fed by what the watch app last heard from the phone, kept in the watch's
/// own App Group (`WatchStore`), and worked out by the same `WatchFace` as
/// the app's screen, so the two never disagree.
@main
struct WatchComplications: WidgetBundle {
    var body: some Widget {
        TodayComplication()
    }
}

struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ZeitkontoWatchToday", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Today")
        .description("What you have worked today, and whether the clock is running.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct ComplicationEntry: TimelineEntry {
    let date: Date
    let face: WatchFace
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), face: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        let now = Date()
        completion(ComplicationEntry(date: now, face: context.isPreview ? Self.sample : Self.face(at: now)))
    }

    /// One entry until midnight when the clock is stopped — the watch app
    /// reloads the timeline whenever the phone sends anything — and one every
    /// ten minutes for two hours while it runs, as the phone's widgets do.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let now = Date()
        let context = WatchStore.readContext()
        let pending = WatchCommand.stillWaiting(WatchStore.readPending(), handled: context?.handledCommandIDs ?? [], now: now)
        let first = WatchFace(snapshot: context?.snapshot, pending: pending, at: now, calendar: .current)

        guard first.isRunning else {
            let midnight = Calendar.current.nextDate(
                after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime
            ) ?? now.addingTimeInterval(3600)
            completion(Timeline(entries: [ComplicationEntry(date: now, face: first)], policy: .after(midnight)))
            return
        }
        let entries = stride(from: 0, through: 110, by: 10).map { minutes -> ComplicationEntry in
            let date = now.addingTimeInterval(TimeInterval(minutes * 60))
            return ComplicationEntry(
                date: date,
                face: WatchFace(snapshot: context?.snapshot, pending: pending, at: date, calendar: .current)
            )
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func face(at date: Date) -> WatchFace {
        let context = WatchStore.readContext()
        let pending = WatchCommand.stillWaiting(WatchStore.readPending(), handled: context?.handledCommandIDs ?? [], now: date)
        return WatchFace(snapshot: context?.snapshot, pending: pending, at: date, calendar: .current)
    }

    /// Plausible figures for the face gallery.
    private static var sample: WatchFace {
        let now = Date()
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = now
        snapshot.todayWorkedMinutes = 402
        snapshot.todayExpectedMinutes = 480
        snapshot.monthBalanceMinutes = 90
        snapshot.durationStyle = .clock
        return WatchFace(snapshot: snapshot, pending: [], at: now, calendar: .current)
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    private var face: WatchFace { entry.face }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryCorner: corner
        default: inline
        }
    }

    private var circular: some View {
        Gauge(value: min(face.fraction ?? 0, 1)) {
            Image(systemName: face.isRunning ? "play.fill" : "clock")
        } currentValueLabel: {
            Text(face.workedText)
                .minimumScaleFactor(0.5)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if face.isRunning {
                    Circle().fill(WatchPalette.running).frame(width: 6, height: 6)
                    Text(face.place ?? String(localized: "Clocked in"))
                        .lineLimit(1)
                } else {
                    Text("TODAY")
                }
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(WatchPalette.amber)
            .widgetAccentable()

            Text(face.workedText)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .monospacedDigit()
            Group {
                if let expected = face.expectedText {
                    Text("of \(expected)")
                } else {
                    Text("Not a working day")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var corner: some View {
        Text(face.workedText)
            .monospacedDigit()
            .widgetCurvesContent()
            .widgetLabel {
                if let fraction = face.fraction {
                    Gauge(value: min(fraction, 1)) {
                        Text("TODAY")
                    }
                } else {
                    Text("TODAY")
                }
            }
    }

    @ViewBuilder
    private var inline: some View {
        if face.isRunning {
            Label(face.workedText, systemImage: "play.fill")
        } else {
            Label(face.workedText, systemImage: "clock")
        }
    }
}
