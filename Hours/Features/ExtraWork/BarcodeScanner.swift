import SwiftUI
import AVFoundation
import Vision
import VisionKit

/// Reading a barcode (1.3): VisionKit's `DataScannerViewController`, on the
/// device only — nothing is sent anywhere and nothing is looked up online.
/// Where it cannot run (the simulator, a phone without the Neural Engine,
/// camera access refused, the UI tests) the same place offers a field to
/// type the code into, so every flow still works.
enum BarcodeScanning {
    /// The codes on material boxes: EAN-13 and EAN-8 (UPC-A reads as
    /// EAN-13), UPC-E, Code 128, Code 39, QR and DataMatrix.
    static let symbologies: [VNBarcodeSymbology] = [.ean13, .ean8, .upce, .code128, .code39, .qr, .dataMatrix]

    /// Whether the camera scanner can run now. Never in the UI tests, which
    /// type the code instead. Read by views, on the main thread.
    static var cameraIsAvailable: Bool {
        guard !HoursStack.isRunningUITests else { return false }
        return MainActor.assumeIsolated {
            DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        }
    }

    /// Asks for the camera once, if it has never been asked: the scanner
    /// reads as unavailable until then.
    static func requestCameraIfNeeded() async {
        guard !HoursStack.isRunningUITests,
              AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined else { return }
        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    /// Switches the torch on or off, where the camera has one.
    static func setTorch(_ isOn: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = isOn ? .on : .off
            device.unlockForConfiguration()
        } catch {
            // No torch this time; scanning goes on without it.
        }
    }

    static var hasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }
}

/// The camera, scanning barcodes and handing each one recognised to
/// `onCode`. Paused, it stops looking (a sheet is over it).
///
/// Reading text too (`readsText`), it also keeps the lines of text it saw in
/// the last two seconds and hands them over with each code, the box's name
/// among them (`BoxTextSuggestions`); text never adds anything by itself.
/// Seeing several things at once, it hands over only the barcode nearest
/// the middle, so a box with two codes still counts once.
struct BarcodeCameraView: UIViewControllerRepresentable {
    var isPaused: Bool
    var readsText = false
    let onCode: (String, [RecognisedLine]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        var types: Set<DataScannerViewController.RecognizedDataType> = [.barcode(symbologies: BarcodeScanning.symbologies)]
        if readsText { types.insert(.text()) }
        let controller = DataScannerViewController(
            recognizedDataTypes: types,
            qualityLevel: .balanced,
            recognizesMultipleItems: readsText,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if isPaused {
            if controller.isScanning { controller.stopScanning() }
        } else if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String, [RecognisedLine]) -> Void
        /// The lines of text seen lately, by the scanner's id for each.
        private var recentText: [UUID: SeenText] = [:]

        private struct SeenText {
            let transcript: String
            let bounds: RecognizedItem.Bounds
            let seen: Date
        }

        init(onCode: @escaping (String, [RecognisedLine]) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            note(addedItems)
            let middle = CGPoint(x: dataScanner.view.bounds.midX, y: dataScanner.view.bounds.midY)
            let nearest = allItems
                .compactMap { item -> (id: UUID, distance: Double)? in
                    guard case let .barcode(barcode) = item else { return nil }
                    return (item.id, TextScanning.distance(TextScanning.centre(of: barcode.bounds), middle))
                }
                .min { $0.distance < $1.distance }
                .map { $0.id }
            for item in addedItems {
                guard case let .barcode(barcode) = item, let value = barcode.payloadStringValue else { continue }
                if let nearest, nearest != item.id { continue }
                onCode(value, lines(near: barcode.bounds))
            }
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didUpdate updatedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            note(updatedItems)
        }

        /// Keeps the text items seen, and forgets those not seen lately.
        private func note(_ items: [RecognizedItem]) {
            let now = Date()
            for item in items {
                if case let .text(text) = item {
                    recentText[item.id] = SeenText(transcript: text.transcript, bounds: text.bounds, seen: now)
                }
            }
            recentText = recentText.filter { now.timeIntervalSince($0.value.seen) <= TextScanning.recentWindow }
        }

        private func lines(near codeBounds: RecognizedItem.Bounds) -> [RecognisedLine] {
            let now = Date()
            let codeCentre = TextScanning.centre(of: codeBounds)
            return recentText.values
                .filter { now.timeIntervalSince($0.seen) <= TextScanning.recentWindow }
                .flatMap { seen in
                    // One item can hold more than one line; each is offered.
                    seen.transcript.split(whereSeparator: \.isNewline).map { part in
                        RecognisedLine(
                            text: String(part),
                            area: TextScanning.area(of: seen.bounds),
                            distanceToCode: TextScanning.distance(TextScanning.centre(of: seen.bounds), codeCentre)
                        )
                    }
                }
        }
    }
}

/// Where the scanning happens: the camera when it can run, otherwise a
/// field to type the code into. A code from the camera goes through the
/// one-box-counts-once filter (`ScanRepeatFilter`); a typed code is meant
/// and always counts.
struct BarcodeScanArea: View {
    var isPaused = false
    /// "Point at the barcode on the box".
    var hint: String = String(localized: "Point at the barcode on the box")
    let onCode: (String) -> Void
    /// Set where a new code is named: the camera reads the box's text too,
    /// and the lines seen around each code are handed here just before the
    /// code itself (the UI tests' typed code brings `TextScanning.testBoxText`).
    var onBoxText: (([RecognisedLine]) -> Void)? = nil

    @State private var cameraIsAvailable = BarcodeScanning.cameraIsAvailable
    @State private var filter = ScanRepeatFilter()
    @State private var typed = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if cameraIsAvailable {
                ZStack(alignment: .bottom) {
                    BarcodeCameraView(isPaused: isPaused, readsText: onBoxText != nil) { code, lines in
                        guard filter.accepts(code, at: Date()) else { return }
                        onBoxText?(lines)
                        onCode(code)
                    }
                    .ignoresSafeArea()
                    .accessibilityLabel(String(localized: "Camera"))
                    .accessibilityHint(hint)
                    // What the UI tests wait for. On a leaf, not on a
                    // container, whose identifier would replace the ones of
                    // the controls inside it.
                    .accessibilityIdentifier("screen-scanner")
                    Text(verbatim: hint)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Metrics.medium)
                        .padding(.vertical, Metrics.tiny + 2)
                        .background(Color.black.opacity(0.55), in: Capsule())
                        .padding(.bottom, Metrics.large)
                        .accessibilityHidden(true)
                }
            } else {
                typedEntry
            }
        }
        .task {
            await BarcodeScanning.requestCameraIfNeeded()
            cameraIsAvailable = BarcodeScanning.cameraIsAvailable
        }
    }

    /// The fallback: "Type the code" and Add.
    private var typedEntry: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("Type the code")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.hoursSecondaryText)
                // What the UI tests wait for where there is no camera.
                .accessibilityIdentifier("screen-scanner")
            HStack(spacing: Metrics.small) {
                Image(systemName: "barcode")
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityHidden(true)
                TextField(String(localized: "Code under the barcode"), text: $typed)
                    .keyboardType(.asciiCapable)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .monospacedDigit()
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                    .accessibilityLabel(String(localized: "Type the code"))
                    .accessibilityIdentifier("scanner-code-field")
                Button("Add", action: submit)
                    .fontWeight(.semibold)
                    .disabled(ExtraWorkCatalog.code(typed) == nil || isPaused)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("scanner-code-add")
            }
            .padding(.horizontal, Metrics.large)
            .frame(minHeight: 50)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            Text("The camera isn't available here, so type the numbers under the barcode.")
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.hoursCanvas)
    }

    private func submit() {
        guard !isPaused, let code = ExtraWorkCatalog.code(typed) else { return }
        typed = ""
        onBoxText?(TextScanning.testBoxText)
        onCode(code)
    }
}

/// A sheet that reads one code and hands it back: the Missing list's
/// arrivals and its add sheet, Settings › Materials' "scan to find" and a
/// second barcode on an item.
struct BarcodeScanSheet: View {
    let title: String
    var hint: String = String(localized: "Point at the barcode on the box")
    let onCode: (String) -> Void
    /// The text seen around the code, handed over just before it; set where
    /// a new code is then named (see `BarcodeScanArea.onBoxText`).
    var onBoxText: (([RecognisedLine]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var torchIsOn = false
    /// One code is handed back; the camera may see more before it closes.
    @State private var handled = false

    var body: some View {
        NavigationStack {
            BarcodeScanArea(isPaused: handled, hint: hint, onCode: { code in
                guard !handled else { return }
                handled = true
                onCode(code)
                dismiss()
            }, onBoxText: boxTextUntilHandled)
            .navigationTitle(Text(verbatim: title))
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
            .onDisappear { if torchIsOn { BarcodeScanning.setTorch(false) } }
        }
    }

    /// `onBoxText`, quiet once the code is handed back.
    private var boxTextUntilHandled: (([RecognisedLine]) -> Void)? {
        guard let onBoxText else { return nil }
        return { lines in
            guard !handled else { return }
            onBoxText(lines)
        }
    }
}

/// The torch, on and off.
struct TorchButton: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
            BarcodeScanning.setTorch(isOn)
        } label: {
            Image(systemName: isOn ? "flashlight.on.fill" : "flashlight.off.fill")
        }
        .accessibilityLabel(String(localized: "Torch"))
        .accessibilityValue(isOn ? String(localized: "On") : String(localized: "Off"))
        .accessibilityIdentifier("scanner-torch")
    }
}

/// A code seen for the first time, named once (Scanning board, phone 3):
/// the code, a name, what it is counted in, and one button. Kept on the
/// phone (and in the user's own iCloud when that is on); nothing is looked
/// up online.
struct NewScannedItemSheet: View {
    let code: String
    /// "Save and add 1" in the extra-work scanner.
    var saveTitle: String = String(localized: "Save and add 1")
    var initialName: String = ""
    /// Names read off the box as its code was scanned ("From the box").
    var suggestions: [String] = []
    let onSave: (String, ExtraWorkUnit) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var unitCode: String = ExtraWorkUnit.pieces.code
    @FocusState private var nameFocused: Bool

    init(
        code: String,
        saveTitle: String = String(localized: "Save and add 1"),
        initialName: String = "",
        suggestions: [String] = [],
        onSave: @escaping (String, ExtraWorkUnit) -> Void
    ) {
        self.code = code
        self.saveTitle = saveTitle
        self.initialName = initialName
        self.suggestions = suggestions
        self.onSave = onSave
        _name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(verbatim: code)
                            .monospacedDigit()
                            .textSelection(.enabled)
                    } icon: {
                        Image(systemName: "barcode")
                            .foregroundStyle(.hoursSecondaryText)
                    }
                    .accessibilityIdentifier("new-item-code")
                } header: {
                    Text("Code")
                }

                Section("Name") {
                    HStack(spacing: Metrics.small) {
                        TextField(String(localized: "Name, e.g. Junction box"), text: $name)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .accessibilityLabel(String(localized: "Name"))
                            .accessibilityIdentifier("new-item-name")
                        ScanTextButton(identifier: "new-item-scan-text") { text in
                            name = text
                        }
                    }
                    if !suggestions.isEmpty {
                        BoxSuggestionChips(suggestions: suggestions) { suggestion in
                            name = suggestion
                        }
                    }
                }

                Section {
                    Picker(selection: $unitCode) {
                        ForEach(ExtraWorkScan.units, id: \.code) { unit in
                            Text(verbatim: unit.name(in: .device)).tag(unit.code)
                        }
                    } label: {
                        Text("Counted in")
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("new-item-unit")
                } header: {
                    Text("Counted in")
                } footer: {
                    if HoursStack.isSyncing {
                        Text("Kept on this phone and in your own iCloud. Nothing is looked up online.")
                    } else {
                        Text("Kept on this phone. Nothing is looked up online.")
                    }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Text("This code isn't in your list yet. Name it once and it fills itself in next time.")
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Metrics.large + 4)
                    .padding(.top, Metrics.small)
                    .background(Color.hoursCanvas)
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text(verbatim: saveTitle)
                }
                .buttonStyle(.bigAction(.primary))
                .accessibilityIdentifier("new-item-save")
                .disabled(!canSave)
                .padding(.horizontal, Metrics.large)
                .padding(.vertical, Metrics.small)
                .background(Color.hoursCanvas)
            }
            .navigationTitle("New item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("new-item-cancel")
                }
            }
            .onAppear { nameFocused = name.isEmpty }
        }
        .presentationDetents([.large])
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        guard canSave else { return }
        onSave(name.trimmingCharacters(in: .whitespacesAndNewlines), ExtraWorkUnit(code: unitCode))
        dismiss()
    }
}
