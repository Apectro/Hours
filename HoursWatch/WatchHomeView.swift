import SwiftUI
import WatchKit

/// "6:42 of 8:00", the month beneath it, and Clock in or Clock out.
struct WatchHomeView: View {
    @Environment(WatchConnection.self) private var connection

    var body: some View {
        NavigationStack {
            // Redrawn every minute — also in always-on — so today's total
            // moves with the running clock in the app's own duration style.
            TimelineView(.everyMinute) { context in
                content(WatchFace(
                    snapshot: connection.context?.snapshot,
                    pending: connection.pending,
                    at: context.date,
                    calendar: .current
                ))
            }
            // The name is never translated (see `AppIdentity`).
            .navigationTitle(Text(verbatim: "Zeitkonto"))
        }
    }

    private func content(_ face: WatchFace) -> some View {
        ScrollView {
            VStack(spacing: 6) {
                if face.hasData || face.isWaitingForPhone {
                    TodayFigure(face: face)
                    if face.hasData {
                        SecondaryLine(secondary: face.secondary)
                    }
                } else {
                    Text("Open Zeitkonto on your iPhone once to see your hours here.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("watch.waiting")
                }

                ClockButton(face: face) { connection.tap(face.action == .clockIn ? .clockIn : .clockOut) }
                    .padding(.top, 4)

                if let since = face.runningSince {
                    RunningLine(since: since, place: face.place)
                }

                // A tap the phone has not heard yet: it is recorded there, by
                // the phone's own clock, once the two are in reach again.
                if face.isWaitingForPhone && !connection.isReachable {
                    Label("Records on your iPhone when it is in reach.", systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("watch.pending")
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Today's total, large, with what it is measured against under it.
private struct TodayFigure: View {
    let face: WatchFace

    var body: some View {
        VStack(spacing: 0) {
            Text("TODAY")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(WatchPalette.amber)
            Text(face.workedText)
                .font(.system(size: 40, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Group {
                if let expected = face.expectedText {
                    Text("of \(expected)")
                } else {
                    Text("Not a working day")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.today")
    }
}

/// The month, as the app's main figure has it.
private struct SecondaryLine: View {
    let secondary: WatchFace.Secondary

    var body: some View {
        Group {
            switch secondary {
            case let .balance(text, isBehind):
                // "Balance", as the phone names the same figure.
                Text(String(localized: "Balance \(text)", comment: "Watch, the month's balance"))
                    .foregroundStyle(isBehind ? WatchPalette.stop : WatchPalette.positive)
            case let .earnings(text):
                Text(String(localized: "\(text) month", comment: "Watch, what the month has earned"))
                    .foregroundStyle(WatchPalette.amber)
            case let .monthWorked(text):
                Text(String(localized: "Month \(text)", comment: "Watch, the month's hours"))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.medium))
        .monospacedDigit()
        .accessibilityIdentifier("watch.month")
    }
}

/// The one thing to do: start the clock, or stop it.
private struct ClockButton: View {
    let face: WatchFace
    let action: () -> Void

    var body: some View {
        Button {
            WKInterfaceDevice.current().play(face.action == .clockIn ? .start : .stop)
            action()
        } label: {
            Label(
                face.action == .clockIn ? "Clock in" : "Clock out",
                systemImage: face.action == .clockIn ? "play.fill" : "stop.fill"
            )
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(face.action == .clockIn ? WatchPalette.amber : WatchPalette.stop)
        .foregroundStyle(face.action == .clockIn ? Color.black : Color.white)
        .accessibilityIdentifier("watch.clockButton")
    }
}

/// Where the clock is running and for how long, counting by the second.
private struct RunningLine: View {
    let since: Date
    let place: String?

    var body: some View {
        VStack(spacing: 2) {
            if let place {
                Text(place)
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 4) {
                Circle()
                    .fill(WatchPalette.running)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(String(
                    localized: "since \(since.formatted(date: .omitted, time: .shortened))",
                    comment: "Watch, the time the running clock was started"
                ))
                Text(since, style: .timer)
                    .monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("watch.running")
    }
}
