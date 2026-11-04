import SwiftUI
import SwiftData

/// Scanning material into a job (Scanning board, phone 2), full screen from
/// the editor's Scan: each code recognised adds one of its item, with a
/// short tap felt and the card at the bottom saying "Emergency light 3h ·
/// Added · now 2 pcs" with − and +. The items scanned this time are listed
/// under it; Done · 6 items closes it. A code not named yet pauses the
/// scanner and asks for a name once (`NewScannedItemSheet`).
///
/// The job's lines are the editor's draft, through the binding: nothing is
/// stored until the editor's Save, except a code that was named, which is
/// remembered at once — naming it was the point.
struct ExtraWorkScannerSheet: View {
    @Binding var items: [ExtraWorkItem]
    let onCatalogChange: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var catalog: [ExtraWorkCatalogItem] = []
    @State private var session = ScanSession()
    /// A code seen for the first time, being named. The scanner waits.
    @State private var naming: NamingCode?
    @State private var feedback = 0
    @State private var torchIsOn = false

    private struct NamingCode: Identifiable {
        let code: String
        var id: String { code }
    }

    var body: some View {
        NavigationStack {
            BarcodeScanArea(isPaused: naming != nil, onCode: scanned)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    card
                }
                .navigationTitle("Scan material")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "Close"))
                        .accessibilityIdentifier("scanner-close")
                    }
                    if BarcodeScanning.cameraIsAvailable && BarcodeScanning.hasTorch {
                        ToolbarItem(placement: .primaryAction) {
                            TorchButton(isOn: $torchIsOn)
                        }
                    }
                }
        }
        .sensoryFeedback(.success, trigger: feedback)
        .onAppear { catalog = ExtraWorkRepository(context: modelContext).catalog() }
        .onDisappear { if torchIsOn { BarcodeScanning.setTorch(false) } }
        .sheet(item: $naming) { pending in
            NewScannedItemSheet(code: pending.code) { name, unit in
                let item = ExtraWorkRepository(context: modelContext).nameCode(pending.code, name: name, unit: unit)
                catalog = ExtraWorkRepository(context: modelContext).catalog()
                onCatalogChange()
                add(item, by: 1)
            }
        }
    }

    // MARK: - The card

    /// The last item scanned with its −/+, what this session scanned, and
    /// Done. Before the first scan, a line saying what to do.
    private var card: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            if let last = lastItem {
                lastRow(last)
            } else {
                Text("Each code you scan adds one to the job.")
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !session.lines.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(session.lines.enumerated()), id: \.element.itemID) { index, line in
                        HStack(spacing: Metrics.small) {
                            Text(verbatim: line.name)
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: amount(of: line))
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.hoursSecondaryText)
                        }
                        .frame(minHeight: 40)
                        .padding(.horizontal, Metrics.medium)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("scanner-line-\(index)")
                        if index < session.lines.count - 1 {
                            Divider().padding(.leading, Metrics.medium)
                        }
                    }
                }
                .background(Color.hoursCanvas, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            Button {
                dismiss()
            } label: {
                if session.added > 0 {
                    Text(String(inflected: "Done · ^[\(session.added) item](inflect: true)"))
                } else {
                    Text("Done")
                }
            }
            .buttonStyle(.bigAction(.primary))
            .accessibilityIdentifier("scanner-done")
        }
        .padding(Metrics.large)
        .background(Color.hoursSurface)
    }

    private func lastRow(_ item: ExtraWorkCatalogItem) -> some View {
        let quantity = ExtraWorkScan.quantity(of: item, in: items)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.small))
            : AnyLayout(HStackLayout(spacing: Metrics.medium))
        return layout {
            HStack(spacing: Metrics.medium) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Color.hoursDone)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.name)
                        .font(.headline)
                    Text(String(
                        localized: "Added · now \(amount(quantity, unit: item.unit))",
                        comment: "Scanner card: an item was added to the job; the value is how many it has now, e.g. 2 pcs"
                    ))
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityIdentifier("scanner-last-amount")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Metrics.small) {
                RoundStepButton(
                    systemImage: "minus",
                    isProminent: false,
                    label: String(localized: "One fewer: \(item.name)", comment: "Extra work stepper; the value is the item's name")
                ) {
                    add(item, by: -1)
                }
                .disabled(quantity <= 0)
                .accessibilityIdentifier("scanner-minus")
                Text(verbatim: ExtraWorkFormatting.quantity(quantity))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .frame(minWidth: 32)
                    .accessibilityHidden(true)
                RoundStepButton(
                    systemImage: "plus",
                    isProminent: true,
                    label: String(localized: "One more: \(item.name)", comment: "Extra work stepper; the value is the item's name")
                ) {
                    add(item, by: 1)
                }
                .accessibilityIdentifier("scanner-plus")
            }
        }
    }

    private var lastItem: ExtraWorkCatalogItem? {
        guard let last = session.last else { return nil }
        return catalog.first { $0.id == last.itemID } ?? ExtraWorkCatalogItem(id: last.itemID, name: last.name, unit: last.unit)
    }

    private func amount(of line: ScanSession.Line) -> String {
        let item = ExtraWorkCatalogItem(id: line.itemID, name: line.name, unit: line.unit)
        return amount(ExtraWorkScan.quantity(of: item, in: items), unit: line.unit)
    }

    private func amount(_ quantity: Decimal, unit: ExtraWorkUnit) -> String {
        "\(ExtraWorkFormatting.quantity(quantity)) \(unit.name(in: .device))"
    }

    // MARK: - Scanning

    private func scanned(_ code: String) {
        guard naming == nil else { return }
        if let item = ExtraWorkCatalog.item(forCode: code, in: catalog) {
            add(item, by: 1)
        } else if let kept = ExtraWorkCatalog.code(code) {
            naming = NamingCode(code: kept)
        }
    }

    private func add(_ item: ExtraWorkCatalogItem, by step: Int) {
        items = ExtraWorkScan.adding(item, by: step, to: items)
        session.record(item, by: step)
        if step > 0 { feedback += 1 }
    }
}
