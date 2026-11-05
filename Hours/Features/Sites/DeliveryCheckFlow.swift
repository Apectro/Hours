import SwiftUI
import SwiftData
import PhotosUI

/// Check a delivery (Delivery board, phones 10–12), full screen from
/// Missing › Ordered: scan the boxes and the list of what is expected fills
/// up; then what came, what is short and what was not on the list, with a
/// photo of the delivery note if wanted; then, saved, the message for the
/// warehouse. Nothing is stored until "Save the delivery", except a code
/// named on the way, which is remembered at once — naming it was the point.
struct DeliveryCheckFlow: View {
    let site: Site
    let onSaved: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Step: Hashable {
        case scan, result, saved
    }

    @State private var step: Step = .scan
    @State private var check = DeliveryCheck(expected: [])
    @State private var catalog: [ExtraWorkCatalogItem] = []
    @State private var naming: String?
    @State private var feedback = 0
    @State private var torchIsOn = false
    @State private var photo: CapturedPhoto?
    @State private var showsCamera = false
    @State private var picked: PhotosPickerItem?
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .scan: scanStep
                case .result: resultStep
                case .saved: savedStep
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
        .sensoryFeedback(.success, trigger: feedback)
        .onAppear(perform: load)
        .onDisappear { if torchIsOn { BarcodeScanning.setTorch(false) } }
        .sheet(item: Binding(get: { naming.map(NamingCode.init) }, set: { naming = $0?.code })) { pending in
            NewScannedItemSheet(code: pending.code) { name, unit in
                let item = ExtraWorkRepository(context: modelContext).nameCode(pending.code, name: name, unit: unit)
                catalog = ExtraWorkRepository(context: modelContext).catalog()
                check.addingExtra(item)
                feedback += 1
            }
        }
    }

    private struct NamingCode: Identifiable {
        let code: String
        var id: String { code }
    }

    // MARK: - Scanning (phone 10)

    private var scanStep: some View {
        BarcodeScanArea(isPaused: naming != nil, onCode: scanned)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                card
            }
            .navigationTitle("Delivery")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Close"))
                    .accessibilityIdentifier("delivery-close")
                }
                if BarcodeScanning.cameraIsAvailable && BarcodeScanning.hasTorch {
                    ToolbarItem(placement: .primaryAction) {
                        TorchButton(isOn: $torchIsOn)
                    }
                }
            }
    }

    /// The last scanned, "2 of 3 here", what is expected with its progress
    /// and what came without being ordered, and Done.
    private var card: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 2) {
                if let last = lastLine {
                    Text(verbatim: last)
                        .font(.headline)
                        .accessibilityIdentifier("delivery-last")
                } else {
                    Text("Scan each box. The list fills up as you go.")
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
                Text(String(
                    localized: "\(check.hereCount) of \(check.expected.count) here",
                    comment: "Delivery check: how many of the ordered items came so far"
                ))
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
                .monospacedDigit()
                .accessibilityIdentifier("delivery-here")
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(check.expected.enumerated()), id: \.element.id) { index, item in
                        expectedRow(item, index: index)
                        Divider().padding(.leading, Metrics.medium)
                    }
                    ForEach(Array(check.extras.enumerated()), id: \.offset) { index, line in
                        extraRow(line, index: index)
                        Divider().padding(.leading, Metrics.medium)
                    }
                }
                .background(Color.hoursCanvas, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            }
            .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 200 : 260)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                step = .result
            } label: {
                Text("Done")
            }
            .buttonStyle(.bigAction(.primary))
            .disabled(!check.hasAnything)
            .accessibilityIdentifier("delivery-done")
        }
        .padding(Metrics.large)
        .background(Color.hoursSurface)
    }

    private func expectedRow(_ item: MissingItem, index: Int) -> some View {
        let came = check.cameAmount(of: item.id)
        let measured = DeliveryCheck.isMeasured(item.unit)
        return HStack(spacing: Metrics.small) {
            progressSymbol(check.progress(of: item))
            Text(verbatim: item.name)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
            if measured && came > 0 {
                stepper(
                    amount: amount(came, unit: item.unit),
                    name: item.name,
                    identifier: "delivery-line-\(index)",
                    minus: { check.step(item.id, by: -1) },
                    plus: { check.step(item.id, by: 1) }
                )
            } else {
                Text(String(
                    localized: "\(quantity(came)) of \(amount(item.quantity, unit: item.unit))",
                    comment: "Delivery check: how much of an ordered item came; e.g. 2 of 6 pcs"
                ))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.hoursSecondaryText)
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Metrics.medium)
        .accessibilityElement(children: .contain)
    }

    private func extraRow(_ line: DeliveryLine, index: Int) -> some View {
        HStack(spacing: Metrics.small) {
            Image(systemName: "plus.circle")
                .foregroundStyle(Color.hoursAttention)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: line.name)
                    .font(.subheadline)
                Text("Not on the list")
                    .font(.caption)
                    .foregroundStyle(.hoursSecondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            stepper(
                amount: amount(line.came, unit: line.unit),
                name: line.name,
                identifier: "delivery-extra-\(index)",
                minus: { check.stepExtra(index, by: -1) },
                plus: { check.stepExtra(index, by: 1) }
            )
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Metrics.medium)
        .accessibilityElement(children: .contain)
    }

    private func stepper(amount: String, name: String, identifier: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        HStack(spacing: Metrics.tiny) {
            RoundStepButton(
                systemImage: "minus",
                isProminent: false,
                label: String(localized: "One fewer: \(name)", comment: "Extra work stepper; the value is the item's name"),
                action: minus
            )
            .accessibilityIdentifier(identifier + "-minus")
            Text(verbatim: amount)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(minWidth: 52)
                .accessibilityIdentifier(identifier + "-amount")
            RoundStepButton(
                systemImage: "plus",
                isProminent: false,
                label: String(localized: "One more: \(name)", comment: "Extra work stepper; the value is the item's name"),
                action: plus
            )
            .accessibilityIdentifier(identifier + "-plus")
        }
    }

    private func progressSymbol(_ progress: DeliveryProgress) -> some View {
        Group {
            switch progress {
            case .full:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.hoursDone)
            case .partly:
                Image(systemName: "circle.lefthalf.filled").foregroundStyle(Color.hoursAttention)
            case .notYet:
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
        }
        .accessibilityHidden(true)
    }

    /// "Junction box IP65 · 6 of 6 ✓", the line the last scan was about.
    private var lastLine: String? {
        switch check.focus {
        case let .expected(id):
            guard let item = check.expected.first(where: { $0.id == id }) else { return nil }
            let came = check.cameAmount(of: id)
            let done = check.progress(of: item) == .full ? " ✓" : ""
            let progress = String(
                localized: "\(quantity(came)) of \(amount(item.quantity, unit: item.unit))",
                comment: "Delivery check: how much of an ordered item came; e.g. 2 of 6 pcs"
            )
            return "\(item.name) · \(progress)\(done)"
        case let .extra(index):
            guard check.extras.indices.contains(index) else { return nil }
            let line = check.extras[index]
            return "\(line.name) · \(amount(line.came, unit: line.unit))"
        case .none:
            return nil
        }
    }

    private func scanned(_ code: String) {
        guard naming == nil else { return }
        switch check.scan(code, catalog: catalog) {
        case .counted, .measured, .extra:
            feedback += 1
        case let .unknown(kept):
            naming = kept
        case .ignored:
            break
        }
    }

    // MARK: - The result (phone 11)

    private var lines: [DeliveryLine] { check.lines }

    private var resultStep: some View {
        List {
            DeliveryLinesSections(lines: lines)
            Section {
                photoRow
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("screen-delivery-result")
        .navigationTitle(Text(String(
            localized: "Delivery, \(settingsStore.dateFormatting.shortDate(today))",
            comment: "Delivery check result: the title; the value is today's date"
        )))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    step = .scan
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(String(localized: "Back to scanning"))
                .accessibilityIdentifier("delivery-back")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: save) {
                Text("Save the delivery")
            }
            .buttonStyle(.bigAction(.primary))
            .accessibilityIdentifier("delivery-save")
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.small)
            .background(Color.hoursCanvas)
        }
        .fullScreenCover(isPresented: $showsCamera) {
            PhotoCaptureCamera(
                onPicked: { image in
                    showsCamera = false
                    photo = CapturedPhoto.from(image)
                },
                onCancel: { showsCamera = false }
            )
            .ignoresSafeArea()
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            Task { photo = await CapturedPhoto.from(item) }
        }
    }

    @ViewBuilder
    private var photoRow: some View {
        if let photo {
            HStack(spacing: Metrics.medium) {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
                    .accessibilityHidden(true)
                Text("Photo of the delivery note")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(role: .destructive) {
                    self.photo = nil
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(String(localized: "Remove photo"))
                .accessibilityIdentifier("delivery-photo-remove")
            }
        } else if PhotoCaptureCamera.isAvailable {
            Menu {
                Button {
                    showsCamera = true
                } label: {
                    Label(String(localized: "Take photo"), systemImage: "camera")
                }
                PhotosPicker(selection: $picked, matching: .images) {
                    Label(String(localized: "From photos"), systemImage: "photo.on.rectangle")
                }
            } label: {
                Label(String(localized: "Photo of the delivery note"), systemImage: "doc.text.viewfinder")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("delivery-photo")
        } else {
            PhotosPicker(selection: $picked, matching: .images) {
                Label(String(localized: "Photo of the delivery note"), systemImage: "doc.text.viewfinder")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("delivery-photo")
        }
    }

    private func save() {
        DeliveryRepository(context: modelContext).record(lines: lines, photo: photo?.jpegData, siteID: site.id)
        onSaved()
        step = .saved
    }

    // MARK: - Saved (phone 12)

    private var savedStep: some View {
        List {
            Section {
                VStack(spacing: Metrics.small) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.hoursDone)
                        .accessibilityHidden(true)
                    Text("Delivery saved")
                        .font(.title3.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }
            Section {
                LabeledContent("Arrived") {
                    Text(verbatim: "\(lines.filter { $0.kind != .extra && $0.came > 0 }.count)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("delivery-saved-arrived")
                LabeledContent("Still on order") {
                    Text(verbatim: "\(lines.filter { $0.kind == .short }.count)")
                        .monospacedDigit()
                }
                .accessibilityIdentifier("delivery-saved-short")
            }
            Section {
                Text(verbatim: message.text)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .accessibilityLabel(Text(verbatim: message.text))
                    .accessibilityIdentifier("delivery-message")
            } header: {
                Text("Message")
            } footer: {
                Text("The delivery and its photo stay under Missing › Arrived, so later you can show what came and when.")
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("screen-delivery-saved")
        .navigationTitle("Delivery saved")
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .bottom) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: Metrics.small))
                : AnyLayout(HStackLayout(spacing: Metrics.small))
            layout {
                Button {
                    ShareSheetPresenter.present(text: message.text) { _ in }
                } label: {
                    Text("Send as message")
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("delivery-send")
                Button {
                    dismiss()
                } label: {
                    Text("Done")
                }
                .buttonStyle(.bigAction(.secondary))
                .accessibilityIdentifier("delivery-finish")
            }
            .padding(.horizontal, Metrics.large)
            .padding(.vertical, Metrics.small)
            .background(Color.hoursCanvas)
        }
    }

    private var message: DeliveryMessage {
        let settings = settingsStore.settings
        return DeliveryMessage(
            siteName: site.name,
            date: today,
            lines: lines,
            ownerName: settings.export.ownerName,
            language: settings.export.language,
            decimalSeparator: settings.export.decimalSeparator.character,
            calendar: settingsStore.workCalendar
        )
    }

    // MARK: - Helpers

    private var today: CalendarDate {
        CalendarDate.today(in: settingsStore.workCalendar)
    }

    private func quantity(_ value: Decimal) -> String {
        ExtraWorkFormatting.quantity(value)
    }

    private func amount(_ value: Decimal, unit: ExtraWorkUnit) -> String {
        "\(ExtraWorkFormatting.quantity(value)) \(unit.name(in: .device))"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        check = DeliveryCheck(expected: MissingRepository(context: modelContext).items(siteID: site.id))
        catalog = ExtraWorkRepository(context: modelContext).catalog()
    }
}

/// Arrived, Short · stays ordered, and Not on the list: a checked
/// delivery's lines, as the result screen and a saved delivery show them.
struct DeliveryLinesSections: View {
    let lines: [DeliveryLine]

    var body: some View {
        let arrived = lines.filter { $0.kind == .arrived }
        let short = lines.filter { $0.kind == .short }
        let extra = lines.filter { $0.kind == .extra }
        if !arrived.isEmpty {
            Section("Arrived") {
                ForEach(Array(arrived.enumerated()), id: \.offset) { index, line in
                    row(line.name, detail: nil, value: amount(line.came, line.unit), symbol: "checkmark.circle.fill", colour: .hoursDone)
                        .accessibilityIdentifier("delivery-arrived-\(index)")
                }
            }
        }
        if !short.isEmpty {
            Section("Short · stays ordered") {
                ForEach(Array(short.enumerated()), id: \.offset) { index, line in
                    row(
                        line.name,
                        detail: line.came > 0
                            ? String(
                                localized: "\(ExtraWorkFormatting.quantity(line.came)) of \(amount(line.ordered, line.unit)) came",
                                comment: "A delivery's short item: how much of the order came; e.g. 30 of 50 m came"
                            )
                            : String(localized: "Nothing came"),
                        value: amount(line.remainder, line.unit),
                        symbol: line.came > 0 ? "circle.lefthalf.filled" : "circle",
                        colour: .hoursAttention
                    )
                    .accessibilityIdentifier("delivery-short-\(index)")
                }
            }
        }
        if !extra.isEmpty {
            Section("Not on the list") {
                ForEach(Array(extra.enumerated()), id: \.offset) { index, line in
                    row(line.name, detail: String(localized: "came anyway"), value: amount(line.came, line.unit), symbol: "plus.circle", colour: .hoursAttention)
                        .accessibilityIdentifier("delivery-extra-row-\(index)")
                }
            }
        }
    }

    private func row(_ name: String, detail: String?, value: String, symbol: String, colour: Color) -> some View {
        HStack(spacing: Metrics.medium) {
            Image(systemName: symbol)
                .foregroundStyle(colour)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: name)
                if let detail {
                    Text(verbatim: detail)
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: value)
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }

    private func amount(_ value: Decimal, _ unit: ExtraWorkUnit) -> String {
        "\(ExtraWorkFormatting.quantity(value)) \(unit.name(in: .device))"
    }
}

/// A saved delivery, read-only (from Missing › Arrived): what came, what
/// was short and what was not on the list, and the delivery note's photo
/// in the photo viewer.
struct DeliveryDetailSheet: View {
    let deliveryID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss

    @State private var delivery: Delivery?
    @State private var viewingPhoto = false

    var body: some View {
        NavigationStack {
            List {
                if let delivery {
                    DeliveryLinesSections(lines: delivery.lines)
                    if let data = delivery.photoData {
                        Section {
                            Button {
                                viewingPhoto = true
                            } label: {
                                HStack(spacing: Metrics.medium) {
                                    if let image = DiaryPhotoProcessor.thumbnail(from: data, maxPixel: 160) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 52, height: 52)
                                            .clipShape(RoundedRectangle(cornerRadius: Metrics.smallCornerRadius, style: .continuous))
                                            .accessibilityHidden(true)
                                    }
                                    Text("Photo of the delivery note")
                                        .foregroundStyle(.primary)
                                }
                            }
                            .accessibilityIdentifier("delivery-detail-photo")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .accessibilityIdentifier("screen-delivery-detail")
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("delivery-detail-done")
                }
            }
            .sheet(isPresented: $viewingPhoto) {
                if let data = delivery?.photoData {
                    PhotoViewerSheet(
                        data: data,
                        spokenName: String(localized: "Photo of the delivery note"),
                        onRemove: nil,
                        caption: title
                    )
                }
            }
        }
        .onAppear {
            delivery = DeliveryRepository(context: modelContext).delivery(id: deliveryID)
        }
    }

    private var title: String {
        guard let delivery else { return "" }
        let day = CalendarDate(delivery.receivedAt, calendar: settingsStore.workCalendar)
        return DeliveryWords.title(day, formatting: settingsStore.dateFormatting)
    }
}

enum DeliveryWords {
    /// "4 Nov delivery".
    static func title(_ day: CalendarDate, formatting: CalendarFormatting) -> String {
        String(localized: "\(formatting.shortDate(day)) delivery", comment: "A saved delivery under Missing › Arrived; the value is its date, e.g. 4 Nov")
    }
}
