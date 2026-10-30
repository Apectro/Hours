import SwiftUI
import SwiftData

/// The selected day's extra work on a site, as a section of the day's list
/// (design v2): a row per job with its checkmark, what was done and its
/// material, time and photos, then "Add extra work". The header has "Send to
/// boss" when finished jobs wait for the report; the footer says what is in
/// progress, or what happens to finished jobs.
///
/// Not under the month lock — extra work is not anyone's hours (see
/// `ExtraWorkRepository`) — so only a read-only site stops it from being
/// added to or ticked done. Draws and reports only: the site day reads the
/// jobs (`ExtraWorkDayModel.load`), presents the editor and writes the
/// checkmark, so the editor's sheet hangs off the day screen and not off a
/// row a List may not have drawn.
struct ExtraWorkDaySection: View {
    let model: ExtraWorkDayModel
    let canEdit: Bool
    /// Opens the editor on a job, or on a new one for nil.
    let onEdit: (ExtraWorkJob?) -> Void
    /// The checkmark: finished, or back in progress.
    let onToggleDone: (ExtraWorkJob) -> Void
    /// Opens the Extra-work report, which the site screen presents. With it,
    /// finished jobs the boss has not had become "Send to boss (3)" in the
    /// header rather than a count in the footer.
    var onOpenReport: (() -> Void)? = nil

    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Section {
            ForEach(Array(model.jobs.enumerated()), id: \.element.id) { index, job in
                HStack(alignment: .top, spacing: 0) {
                    ExtraWorkDoneButton(job: job, canEdit: canEdit) { onToggleDone(job) }
                        .accessibilityIdentifier("extra-work-tick-\(index)")
                        .padding(.leading, -Metrics.small)
                    Button {
                        onEdit(job)
                    } label: {
                        ExtraWorkJobCard(
                            job: job,
                            photoCount: model.photoCounts[job.id] ?? 0,
                            durations: settingsStore.settings.displayFormatting
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("extra-work-job-\(index)")
                }
                .contextMenu {
                    if canEdit { ExtraWorkDoneMenuItem(job: job) { onToggleDone(job) } }
                }
            }

            if canEdit {
                Button {
                    onEdit(nil)
                } label: {
                    Label("Add extra work", systemImage: "plus")
                }
                .accessibilityIdentifier("extra-work-add")
            } else if model.jobs.isEmpty {
                Text("No extra work on this day.")
                    .foregroundStyle(.hoursSecondaryText)
            }
        } header: {
            HStack(alignment: .center, spacing: Metrics.small) {
                Text("Extra work")
                    // The listing's screenshot scrolls this to the top.
                    .accessibilityIdentifier("extra-work-heading")
                Spacer(minLength: Metrics.small)
                if model.notSent > 0, let onOpenReport {
                    Button(action: onOpenReport) {
                        Text(String(
                            localized: "Send to boss (\(model.notSent))",
                            comment: "Extra work on a site day: opens the Extra-work report; the value is how many finished jobs the boss has not had yet"
                        ))
                        .font(.subheadline.weight(.semibold))
                        .frame(minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("extra-work-send-report")
                }
            }
            .textCase(nil)
        } footer: {
            if let counts = countsLine {
                Text(verbatim: counts)
                    .accessibilityIdentifier("extra-work-counts")
            } else {
                Text("Finished jobs go in the extra-work report for your boss.")
            }
        }
    }

    /// The site's jobs in progress, whatever their day, and where the header
    /// has no button for it, "Not sent: 5" — labels rather than sentences,
    /// so no plural to agree. Nil when there is neither.
    private var countsLine: String? {
        var parts: [String] = []
        if model.inProgress > 0 {
            parts.append(String(localized: "In progress: \(model.inProgress)", comment: "Extra work on a site day: how many jobs on the site are not finished yet, whatever their day"))
        }
        if model.notSent > 0, onOpenReport == nil {
            parts.append(String(localized: "Not sent: \(model.notSent)", comment: "Extra work on a site day: how many finished jobs on the site the boss has not had yet"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// What a site day's extra-work section shows: the day's jobs, and the
/// site's counts of jobs in progress and not sent.
struct ExtraWorkDayModel {
    var jobs: [ExtraWorkJob] = []
    var notSent = 0
    var inProgress = 0
    var photoCounts: [UUID: Int] = [:]

    /// Read outside `body`: the repository's reads collapse duplicates,
    /// which writes.
    @MainActor
    static func load(siteID: UUID, date: CalendarDate, context: ModelContext) -> ExtraWorkDayModel {
        let repository = ExtraWorkRepository(context: context)
        let all = repository.jobs(siteID: siteID)
        let counts = ExtraWorkReport.counts(all, on: date)
        return ExtraWorkDayModel(
            jobs: all.filter { $0.date == date },
            notSent: counts.notSent,
            inProgress: counts.inProgress,
            photoCounts: repository.photoCounts(siteID: siteID)
        )
    }

    /// The checkmark: written at once, not under the month lock.
    @MainActor
    static func toggleDone(_ job: ExtraWorkJob, context: ModelContext, settingsStore: SettingsStore) {
        ExtraWorkRepository(context: context).storeProgress(of: job.togglingDone(at: Date()))
        // Finished, or back in progress: the weekly note's count changes.
        Task { await ExtraWorkReminderRefresher.refresh(context: context, settingsStore: settingsStore) }
    }
}

/// Which job the editor opens on; `nil` is a new one. Identifiable so the
/// sheet is chosen by value.
struct ExtraWorkEditorRequest: Identifiable {
    let id = UUID()
    let job: ExtraWorkJob?
}

/// One job's card: what was done with its Finished or In progress tag, and
/// under it one line of the material, the time and the photos ("6 × LED
/// fitting · 20 m Cable · 2h 30m · Photos: 2").
struct ExtraWorkJobCard: View {
    let job: ExtraWorkJob
    let photoCount: Int
    let durations: DurationFormatting

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.tiny + 2) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text(verbatim: job.description.isEmpty ? String(localized: "Extra work") : job.description)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Metrics.small)
                ExtraWorkChips(job: job)
            }
            if let detail = detailLine {
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.leading, Metrics.tiny)
        .padding(.vertical, Metrics.small)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// The material, then how long and who, the photos, and who signed.
    private var detailLine: String? {
        var parts = job.items.map { $0.line(in: .device, decimalSeparator: ExtraWorkFormatting.decimalSeparator) }
        let time = job.timeLine(durations)
        if !time.isEmpty { parts.append(time) }
        if photoCount > 0 {
            parts.append(String(localized: "Photos: \(photoCount)", comment: "Extra work job: how many photos it has"))
        }
        if let signature = job.clientSignature, !job.hasHours {
            let name = signature.signerName.trimmingCharacters(in: .whitespacesAndNewlines)
            parts.append(name.isEmpty
                ? String(localized: "Signed by the client")
                : String(localized: "Signed by \(name)", comment: "Extra work job: who signed it for the client; the value is their name"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// A job's state in a word or two, coloured, with no box (design v2): In
/// progress (orange) or Finished (green, with a checkmark), and Sent or
/// Signed when there is one to show.
struct ExtraWorkChips: View {
    let job: ExtraWorkJob

    var body: some View {
        HStack(spacing: Metrics.tiny) {
            ExtraWorkProgressChip(progress: job.progress)
            if let chip = job.chip {
                ExtraWorkChipView(chip: chip)
            }
        }
    }
}

/// In progress / Finished: whether the work itself is done.
struct ExtraWorkProgressChip: View {
    let progress: ExtraWorkProgress

    var body: some View {
        Group {
            switch progress {
            case .inProgress:
                Text("In progress")
            case .done:
                Label("Finished", systemImage: "checkmark")
                    .labelStyle(ExtraWorkChipLabelStyle())
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(color)
        .fixedSize()
    }

    private var color: Color {
        progress == .done ? .hoursDone : .hoursAttention
    }
}

/// A small icon before the word, tighter than a list label.
private struct ExtraWorkChipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}

/// Sent / Signed: whether the boss has it, or the client signed it.
struct ExtraWorkChipView: View {
    let chip: ExtraWorkChip

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .fixedSize()
    }

    private var title: LocalizedStringKey {
        switch chip {
        case .signed: return "Signed"
        case .sent: return "Sent"
        }
    }

    private var color: Color {
        switch chip {
        // Green: sent is done (the colour rule); signed is a note.
        case .signed: return .secondary
        case .sent: return .hoursDone
        }
    }
}

/// The checkmark beside a job: ticks it finished, or back in progress. 44
/// points, selected when the job is done, so VoiceOver and the UI tests read
/// its state without reading its words.
struct ExtraWorkDoneButton: View {
    let job: ExtraWorkJob
    let canEdit: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: job.isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(job.isDone ? Color.hoursPositive : Color.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canEdit)
        .accessibilityLabel(job.isDone
            ? String(localized: "Finished: \(title)", comment: "Extra work: VoiceOver, the checkmark of a finished job; the value is what was done")
            : String(localized: "In progress: \(title)", comment: "Extra work: VoiceOver, the checkmark of a job not finished yet; the value is what was done"))
        .accessibilityHint(job.isDone
            ? String(localized: "Marks it in progress again.")
            : String(localized: "Marks the work as finished."))
        .accessibilityAddTraits(job.isDone ? .isSelected : [])
    }

    private var title: String {
        job.description.isEmpty ? String(localized: "Extra work") : job.description
    }
}

/// The same as the checkmark, in a job's long-press menu.
struct ExtraWorkDoneMenuItem: View {
    let job: ExtraWorkJob
    let action: () -> Void

    var body: some View {
        if job.isDone {
            Button(action: action) {
                Label("Mark as in progress", systemImage: "circle")
            }
        } else {
            Button(action: action) {
                Label("Mark as finished", systemImage: "checkmark.circle")
            }
        }
    }
}

/// How the app writes a quantity on screen: the phone's decimal mark.
enum ExtraWorkFormatting {
    static var decimalSeparator: String { Locale.current.decimalSeparator ?? "." }

    static func quantity(_ value: Decimal) -> String {
        ExtraWorkQuantity.string(value, decimalSeparator: decimalSeparator)
    }
}

/// Chips that wrap onto as many lines as they need.
struct ExtraWorkFlow: Layout {
    var spacing: CGFloat = Metrics.small

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if x > 0 && x + size.width > maxWidth {
                y += lineHeight + spacing
                x = 0
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX {
                y += lineHeight + spacing
                x = bounds.minX
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
