import SwiftUI

/// The running clock.
///
/// Only on screen while a shift is actually running, where it sits above
/// everything else — a clock you have forgotten about is the one way this app
/// can quietly record something wrong.
struct ClockCard: View {
    let running: RunningShift
    let settings: AppSettings
    let formatting: CalendarFormatting
    let onClockOut: () -> Void
    let onDiscard: () -> Void

    @State private var isConfirmingDiscard = false

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                header

                // Ticks once a second without a timer of its own, and stops
                // being updated as soon as the view is off screen.
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    elapsed(at: context.date)
                }

                if running.hasRunTooLong(at: Date()) {
                    Label(
                        "This clock has been running for over a day. Stopping it now records a full day at most — check the times afterwards.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.footnote)
                    .foregroundStyle(Color.hoursNegative)
                }

                HStack(spacing: Metrics.small) {
                    Button(action: onClockOut) {
                        Label("Clock out", systemImage: "stop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isConfirmingDiscard = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Discard this shift")
                }
            }
        }
        .confirmationDialog(
            "Discard the running shift?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive, action: onDiscard)
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("Nothing is recorded and the clock stops.")
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.medium) {
            Image(systemName: "record.circle")
                .foregroundStyle(Color.hoursPositive)
                .font(.title3)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.headline)
                Text("Started \(formatting.time(running.start, on: running.date))\(jobSuffix)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    private var title: String {
        running.date == CalendarDate.today(in: Calendar.current)
            ? String(localized: "Clocked in")
            : String(localized: "Still clocked in")
    }

    private var jobSuffix: String {
        guard settings.tracksMultipleJobs else { return "" }
        return " · \(settings.job(running.jobID).name)"
    }

    private func elapsed(at instant: Date) -> some View {
        let seconds = running.elapsedSeconds(at: instant)
        return VStack(alignment: .leading, spacing: 2) {
            Text(ClockCard.clockString(seconds))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text("elapsed")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clocked in for \(ClockCard.spokenDuration(seconds))")
    }

    /// `2:34:07` — seconds included, because a clock that does not tick does
    /// not read as running.
    static func clockString(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }

    static func spokenDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 { return "\(minutes) minutes" }
        return "\(hours) hours \(minutes) minutes"
    }
}
