import SwiftUI

/// The running clock, as Today's first row (design v2): a small green dot
/// (orange on a break) and "Clocked in · Trg Pravde" in grey over the worked
/// time, large; when it started on the right; Discard in the ⋯ menu, well
/// away from the big buttons, and asking first. Break and Clock out are
/// the Today tab's big buttons under the list.
///
/// Only on screen while a shift is actually running — a clock you have
/// forgotten about is the one way this app can quietly record something
/// wrong.
struct ClockCard: View {
    let running: RunningShift
    let settings: AppSettings
    let formatting: CalendarFormatting
    /// The site the clock's job belongs to, when there is exactly one.
    var siteName: String? = nil
    let onDiscard: () -> Void

    @State private var isConfirmingDiscard = false

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            HStack(alignment: .center, spacing: Metrics.medium) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(running.isOnBreak ? Color.hoursAttentionFill : Color.green)
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        Text(verbatim: statusLine)
                            .font(.subheadline)
                            .foregroundStyle(.hoursSecondaryText)
                            .lineLimit(2)
                    }
                    // Ticks without a timer of its own, and stops being
                    // updated as soon as the view is off screen.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        elapsed(at: context.date)
                    }
                }
                Spacer(minLength: Metrics.small)
                Text(verbatim: sinceLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.hoursSecondaryText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
                Menu {
                    Button(role: .destructive) {
                        isConfirmingDiscard = true
                    } label: {
                        Label("Discard this shift", systemImage: "trash")
                    }
                    .accessibilityIdentifier("clock-discard")
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("More")
                .accessibilityIdentifier("clock-more")
            }

            if running.hasRunTooLong(at: Date()) {
                Label(
                    "This clock has been running for over a day. Stopping it now records a full day at most — check the times afterwards.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.footnote)
                .foregroundStyle(Color.hoursAttention)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, Metrics.tiny)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("clock-card")
        .confirmationDialog(
            "Discard the running shift?",
            isPresented: $isConfirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard", role: .destructive, action: onDiscard)
                .accessibilityIdentifier("clock-discard-confirm")
            Button("Keep running", role: .cancel) {}
        } message: {
            Text("Nothing is recorded and the clock stops.")
        }
    }

    /// "Clocked in · Trg Pravde", "On a break · Trg Pravde".
    private var statusLine: String {
        let status: String
        if running.isOnBreak {
            status = String(localized: "On a break")
        } else {
            status = running.date == CalendarDate.today(in: formatting.calendar)
                ? String(localized: "Clocked in")
                : String(localized: "Still clocked in")
        }
        guard let place = siteName ?? jobName else { return status }
        return [status, place].joined(separator: " · ")
    }

    private var jobName: String? {
        settings.tracksMultipleJobs ? settings.job(running.jobID).displayName() : nil
    }

    /// "since 07:00", and the break running or the breaks already taken.
    private var sinceLine: String {
        var parts = [String(
            localized: "since \(formatting.time(running.start, on: running.date))",
            comment: "The running clock: when it started, e.g. since 07:00"
        )]
        if let breakStart = running.breakStart {
            parts.append(String(
                localized: "break since \(formatting.time(breakStart, on: running.date))",
                comment: "The running clock, on a break: when it began, e.g. break since 12:00"
            ))
        } else if running.breakSeconds > 0 {
            parts.append(String(
                localized: "\(settings.displayFormatting.string(running.breakSeconds / 60)) break",
                comment: "The running clock: the breaks already taken, e.g. 30m break"
            ))
        }
        return parts.joined(separator: " · ")
    }

    private func elapsed(at instant: Date) -> some View {
        let seconds = running.workedSeconds(at: instant)
        return Text(verbatim: ClockCard.shortClockString(seconds))
            .font(.title2.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(.primary)
            .contentTransition(.numericText())
            .accessibilityLabel(String(
                localized: "Clocked in for \(ClockCard.spokenDuration(seconds))",
                comment: "VoiceOver, how long the running clock has been going"
            ))
            .accessibilityIdentifier("clock-elapsed")
    }

    /// `6:42`: hours and minutes, as the mockup's big figure.
    static func shortClockString(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 3600, (seconds % 3600) / 60)
    }

    /// `2:34:07` — seconds included, because a clock that does not tick does
    /// not read as running.
    static func clockString(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d:%02d", hours, minutes, remainder)
    }

    /// Read out rather than shown, so it goes through the same inflection
    /// the spoken intents use. The two literals it replaced concatenated
    /// English and had no plural at all: one minute came out "1 minutes".
    static func spokenDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 {
            return String(inflected: "^[\(minutes) minute](inflect: true)")
        }
        return String(inflected: "^[\(hours) hour](inflect: true) ^[\(minutes) minute](inflect: true)")
    }
}
