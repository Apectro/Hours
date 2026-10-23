import SwiftUI
import SwiftData

/// The selected day's extra work on a site (mockup 13): each job with its
/// material, who worked on it, whether it is finished and whether the boss
/// has it, and "Add extra work".
///
/// Not under the month lock — extra work is not anyone's hours (see
/// `ExtraWorkRepository`) — so only a read-only site stops it from being
/// added to or ticked done. A job opens in the editor as a sheet; the one
/// write here is the checkmark beside each job, which ticks it done or back
/// in progress at once.
struct ExtraWorkDaySection: View {
    let site: Site
    let date: CalendarDate
    let canEdit: Bool
    /// Called after a job is written or removed, so the month grid can mark
    /// the day.
    let onChange: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore

    @State private var jobs: [ExtraWorkJob] = []
    @State private var notSent = 0
    @State private var inProgress = 0
    @State private var photoCounts: [UUID: Int] = [:]
    @State private var editing: ExtraWorkEditorRequest?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            HStack(alignment: .firstTextBaseline) {
                Text("Extra work")
                    .font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: Metrics.small)
                Text(verbatim: countsLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("extra-work-counts")
            }

            if !jobs.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(jobs.enumerated()), id: \.element.id) { index, job in
                        HStack(alignment: .top, spacing: 0) {
                            ExtraWorkDoneButton(job: job, canEdit: canEdit) { toggleDone(job) }
                                .accessibilityIdentifier("extra-work-tick-\(index)")
                                .padding(.leading, Metrics.small)
                                .padding(.top, Metrics.small)
                            Button {
                                editing = ExtraWorkEditorRequest(job: job)
                            } label: {
                                ExtraWorkJobCard(
                                    job: job,
                                    photoCount: photoCounts[job.id] ?? 0,
                                    durations: settingsStore.settings.displayFormatting
                                )
                            }
                            .buttonStyle(.plain)
                            // Rows here are not a List, so there is no swipe:
                            // a long press offers the same as the checkmark.
                            .contextMenu {
                                if canEdit { ExtraWorkDoneMenuItem(job: job) { toggleDone(job) } }
                            }
                            .accessibilityIdentifier("extra-work-job-\(index)")
                        }
                        if index < jobs.count - 1 {
                            Divider().padding(.leading, Metrics.large)
                        }
                    }
                }
                .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }

            if canEdit {
                Button {
                    editing = ExtraWorkEditorRequest(job: nil)
                } label: {
                    Label("Add extra work", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .accessibilityIdentifier("extra-work-add")
            } else if jobs.isEmpty {
                Text("No extra work on this day.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear(perform: load)
        .sheet(item: $editing) { request in
            ExtraWorkEditorSheet(
                site: site,
                date: date,
                job: request.job,
                canEdit: canEdit,
                onDone: {
                    load()
                    onChange()
                }
            )
        }
    }

    /// "This day: 2 · In progress: 1 · Not sent: 5", without a plural to
    /// agree: the counts are labels, as on a tile. The last two are the
    /// whole site's, so a job left in progress on another day is not lost.
    private var countsLine: String {
        let today = jobs.count
        var parts = [String(localized: "This day: \(today)", comment: "Extra work on a site day: how many jobs on the selected day")]
        if inProgress > 0 {
            parts.append(String(localized: "In progress: \(inProgress)", comment: "Extra work on a site day: how many jobs on the site are not finished yet, whatever their day"))
        }
        if notSent > 0 {
            parts.append(String(localized: "Not sent: \(notSent)", comment: "Extra work on a site day: how many finished jobs on the site the boss has not had yet"))
        }
        return parts.joined(separator: " · ")
    }

    /// The checkmark: written at once, not under the month lock.
    private func toggleDone(_ job: ExtraWorkJob) {
        guard canEdit else { return }
        ExtraWorkRepository(context: modelContext).storeProgress(of: job.togglingDone(at: Date()))
        load()
        onChange()
    }

    /// Read outside `body`: the repository's reads collapse duplicates,
    /// which writes.
    private func load() {
        let repository = ExtraWorkRepository(context: modelContext)
        let all = repository.jobs(siteID: site.id)
        jobs = all.filter { $0.date == date }
        let counts = ExtraWorkReport.counts(all, on: date)
        notSent = counts.notSent
        inProgress = counts.inProgress
        photoCounts = repository.photoCounts(siteID: site.id)
    }
}

/// Which job the editor opens on; `nil` is a new one. Identifiable so the
/// sheet is chosen by value.
struct ExtraWorkEditorRequest: Identifiable {
    let id = UUID()
    let job: ExtraWorkJob?
}

/// One job in the day's list: what was done, whether it is finished and
/// whether the boss has it, the material as chips, and who worked on it or
/// who signed.
struct ExtraWorkJobCard: View {
    let job: ExtraWorkJob
    let photoCount: Int
    let durations: DurationFormatting

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                Text(verbatim: job.description.isEmpty ? String(localized: "Extra work") : job.description)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: Metrics.small)
                ExtraWorkChips(job: job)
            }

            // One item under another, leading-aligned: "4 × P7" over
            // "2 × P6" reads as a list, where a flow of chips side by side
            // read as one long line.
            if !job.items.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(job.items.enumerated()), id: \.offset) { _, item in
                        Text(verbatim: item.line(in: .device, decimalSeparator: ExtraWorkFormatting.decimalSeparator))
                            .font(.footnote)
                            .padding(.horizontal, Metrics.small)
                            .padding(.vertical, Metrics.tiny)
                            .background(Color.hoursCanvas, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }

            if let detail = detailLine {
                Text(verbatim: detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, Metrics.small)
        .padding(.trailing, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "1h · Marijo Mikša, Dusko Bajlović · Photos: 2" — how long the job
    /// took, then who was on it — or "Signed by Ing. Horvat".
    private var detailLine: String? {
        var parts: [String] = []
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

/// A job's chips, at most two: In progress (amber) or Finished (green, with
/// a checkmark), and Sent or Signed when there is one to show.
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
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, Metrics.small)
        .padding(.vertical, Metrics.tiny)
        .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .fixedSize()
    }

    private var color: Color {
        progress == .done ? .green : .orange
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
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, Metrics.small)
            .padding(.vertical, Metrics.tiny)
            .background(color.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        case .signed: return .secondary
        case .sent: return .accentColor
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
                .foregroundStyle(job.isDone ? Color.green : Color.secondary)
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
    var spacing: CGFloat = 8

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
