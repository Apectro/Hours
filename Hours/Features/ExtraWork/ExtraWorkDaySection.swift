import SwiftUI
import SwiftData

/// The selected day's extra work on a site (mockup 13): each job with its
/// material, who worked on it and its status, and "Add extra work".
///
/// Not under the month lock — extra work is not anyone's hours (see
/// `ExtraWorkRepository`) — so only a read-only site stops it from being
/// added to. A job opens in the editor as a sheet; nothing here writes.
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
                        .accessibilityIdentifier("extra-work-job-\(index)")
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

    /// "2 today · 5 not sent", without a plural to agree: the two counts
    /// are labels, as on a tile.
    private var countsLine: String {
        let today = jobs.count
        let onDay = String(localized: "This day: \(today)", comment: "Extra work on a site day: how many jobs on the selected day")
        let open = String(localized: "Not sent: \(notSent)", comment: "Extra work on a site day: how many jobs on the site are not yet sent to the boss")
        return notSent > 0 ? "\(onDay) · \(open)" : onDay
    }

    /// Read outside `body`: the repository's reads collapse duplicates,
    /// which writes.
    private func load() {
        let repository = ExtraWorkRepository(context: modelContext)
        let all = repository.jobs(siteID: site.id)
        jobs = all.filter { $0.date == date }
        notSent = ExtraWorkReport.counts(all, on: date).notSent
        photoCounts = repository.photoCounts(siteID: site.id)
    }
}

/// Which job the editor opens on; `nil` is a new one. Identifiable so the
/// sheet is chosen by value.
struct ExtraWorkEditorRequest: Identifiable {
    let id = UUID()
    let job: ExtraWorkJob?
}

/// One job in the day's list: what was done, its status, the material as
/// chips, and who worked on it or who signed.
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
                ExtraWorkChipView(chip: job.chip)
            }

            if !job.items.isEmpty {
                ExtraWorkFlow(spacing: 6) {
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
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// "Ivan, Marko · 6h · 2 photos", or "Signed by Ing. Horvat".
    private var detailLine: String? {
        var parts: [String] = []
        if job.hasHours {
            parts.append(job.hours.filter { $0.minutes > 0 }.map(\.name).joined(separator: ", "))
            parts.append(durations.string(job.totalMinutes))
        }
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

/// Open / Signed / Sent / Invoiced, coloured as in mockup 13.
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
            .accessibilityIdentifier("extra-work-chip-\(chip.rawValue)")
    }

    private var title: LocalizedStringKey {
        switch chip {
        case .open: return "Open"
        case .signed: return "Signed"
        case .sent: return "Sent"
        case .invoiced: return "Invoiced"
        }
    }

    private var color: Color {
        switch chip {
        case .open: return .orange
        case .signed: return .green
        case .sent: return .accentColor
        case .invoiced: return .secondary
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
