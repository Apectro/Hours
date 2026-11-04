import SwiftUI
import VisionKit

/// Reading the name off a box (1.3), on the device only, as the barcode
/// scanner does: VisionKit reads the text, nothing is sent anywhere. Where
/// the camera cannot run (the simulator, camera access refused, the UI
/// tests) the same place offers a field to type into.
enum TextScanning {
    /// How long a line of text the camera saw counts as "near the moment"
    /// a new code is read.
    static let recentWindow: TimeInterval = 2

    /// The UI tests' stand-in for the text on a box: the lines given after
    /// `-hours-box-text`, separated by "|", the first the most prominent.
    /// Handed over with every code typed into the scanner's fallback field.
    static var testBoxText: [RecognisedLine] {
        guard HoursStack.isRunningUITests else { return [] }
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-hours-box-text"), arguments.indices.contains(index + 1) else { return [] }
        let texts = arguments[index + 1].split(separator: "|").map(String.init)
        return texts.enumerated().map { offset, text in
            RecognisedLine(text: text, area: Double(texts.count - offset), distanceToCode: Double(offset))
        }
    }

    /// The size of a recognised item in the picture, in square points.
    static func area(of bounds: RecognizedItem.Bounds) -> Double {
        let points = [bounds.topLeft, bounds.topRight, bounds.bottomRight, bounds.bottomLeft]
        var twice: Double = 0
        for index in points.indices {
            let a = points[index]
            let b = points[(index + 1) % points.count]
            twice += Double(a.x * b.y - b.x * a.y)
        }
        return abs(twice) / 2
    }

    /// The middle of a recognised item in the picture.
    static func centre(of bounds: RecognizedItem.Bounds) -> CGPoint {
        CGPoint(
            x: (bounds.topLeft.x + bounds.topRight.x + bounds.bottomRight.x + bounds.bottomLeft.x) / 4,
            y: (bounds.topLeft.y + bounds.topRight.y + bounds.bottomRight.y + bounds.bottomLeft.y) / 4
        )
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }
}

/// The camera in text mode: the lines it reads are highlighted, and a tap on
/// one hands its text to `onTap`.
struct TextCameraView: UIViewControllerRepresentable {
    let onTap: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onTap = onTap
        if !controller.isScanning {
            try? controller.startScanning()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onTap: (String) -> Void

        init(onTap: @escaping (String) -> Void) {
            self.onTap = onTap
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            if case let .text(text) = item {
                onTap(text.transcript)
            }
        }
    }
}

/// "Scan text": the camera reading text, each line tapped added to the tray
/// at the bottom (joined with a space); Use fills the field, Clear empties
/// the tray, ✕ leaves the field as it was.
struct TextScanSheet: View {
    let onUse: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tray = ""
    @State private var typed = ""
    @State private var cameraIsAvailable = BarcodeScanning.cameraIsAvailable
    @State private var torchIsOn = false
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if cameraIsAvailable {
                    camera
                } else {
                    typedEntry
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                trayCard
            }
            .navigationTitle("Scan text")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(String(localized: "Cancel"))
                    .accessibilityIdentifier("text-scan-close")
                }
                if cameraIsAvailable && BarcodeScanning.hasTorch {
                    ToolbarItem(placement: .primaryAction) {
                        TorchButton(isOn: $torchIsOn)
                    }
                }
            }
        }
        .task {
            await BarcodeScanning.requestCameraIfNeeded()
            cameraIsAvailable = BarcodeScanning.cameraIsAvailable
        }
        .onDisappear { if torchIsOn { BarcodeScanning.setTorch(false) } }
    }

    private var camera: some View {
        ZStack(alignment: .bottom) {
            TextCameraView { line in
                tray = BoxTextSuggestions.appending(line, to: tray)
            }
            .ignoresSafeArea()
            .accessibilityLabel(String(localized: "Camera"))
            .accessibilityHint(String(localized: "Tap the words on the box"))
            // What the UI tests wait for; on a leaf, as the barcode
            // scanner's is.
            .accessibilityIdentifier("screen-text-scan")
            Text("Tap the words on the box")
                .font(.subheadline)
                .foregroundStyle(.white)
                .padding(.horizontal, Metrics.medium)
                .padding(.vertical, Metrics.tiny + 2)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(.bottom, Metrics.large)
                .accessibilityHidden(true)
        }
    }

    /// The fallback: "Type the text" and Add, which adds to the tray as a
    /// tapped line would.
    private var typedEntry: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("Type the text")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.hoursSecondaryText)
                // What the UI tests wait for where there is no camera.
                .accessibilityIdentifier("screen-text-scan")
            HStack(spacing: Metrics.small) {
                Image(systemName: "text.viewfinder")
                    .foregroundStyle(.hoursSecondaryText)
                    .accessibilityHidden(true)
                TextField(String(localized: "What the box says"), text: $typed)
                    .submitLabel(.done)
                    .focused($fieldFocused)
                    .onSubmit(addTyped)
                    .accessibilityLabel(String(localized: "Type the text"))
                    .accessibilityIdentifier("text-scan-field")
                Button("Add", action: addTyped)
                    .fontWeight(.semibold)
                    .disabled(BoxTextSuggestions.cleaned(typed).isEmpty)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("text-scan-add")
            }
            .padding(.horizontal, Metrics.large)
            .frame(minHeight: 50)
            .background(Color.hoursSurface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            Text("The camera isn't available here, so type what the box says.")
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.hoursCanvas)
    }

    /// What was tapped so far, with Clear and Use.
    private var trayCard: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            Group {
                if tray.isEmpty {
                    Text("Tap a line of text to add it here.")
                        .font(.subheadline)
                        .foregroundStyle(.hoursSecondaryText)
                } else {
                    Text(verbatim: tray)
                        .font(.headline)
                        .lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("text-scan-tray")
            HStack(spacing: Metrics.small) {
                Button {
                    tray = ""
                } label: {
                    Text("Clear")
                }
                .buttonStyle(.bigAction(.secondary))
                .disabled(tray.isEmpty)
                .accessibilityIdentifier("text-scan-clear")
                Button {
                    onUse(tray)
                    dismiss()
                } label: {
                    Text("Use")
                }
                .buttonStyle(.bigAction(.primary))
                .disabled(tray.isEmpty)
                .accessibilityIdentifier("text-scan-use")
            }
        }
        .padding(Metrics.large)
        .background(Color.hoursSurface)
    }

    private func addTyped() {
        let added = BoxTextSuggestions.cleaned(typed)
        guard !added.isEmpty else { return }
        tray = BoxTextSuggestions.appending(added, to: tray)
        typed = ""
    }
}

/// The small "Scan text" button beside a name field: opens `TextScanSheet`
/// and hands what was chosen to `onText`.
struct ScanTextButton: View {
    /// "new-item-scan-text", "missing-add-scan-text", …
    let identifier: String
    let onText: (String) -> Void

    @State private var isScanning = false

    var body: some View {
        Button {
            isScanning = true
        } label: {
            Image(systemName: "text.viewfinder")
                .font(.body)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        // Its own tap target inside a Form row, not the whole row's.
        .buttonStyle(.borderless)
        .accessibilityLabel(String(localized: "Scan text"))
        .accessibilityIdentifier(identifier)
        .sheet(isPresented: $isScanning) {
            TextScanSheet(onUse: onText)
        }
    }
}

/// "From the box": the names read off the box while its new code was
/// scanned, as chips; a tap fills the name, which stays editable.
struct BoxSuggestionChips: View {
    let suggestions: [String]
    let onPick: (String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("From the box")
                .font(.footnote)
                .foregroundStyle(.hoursSecondaryText)
                .accessibilityAddTraits(.isHeader)
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Metrics.small) {
                    chips
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.small) {
                        chips
                    }
                }
            }
        }
        .padding(.vertical, Metrics.tiny)
    }

    private var chips: some View {
        ForEach(Array(suggestions.enumerated()), id: \.offset) { index, suggestion in
            Button {
                onPick(suggestion)
            } label: {
                Text(verbatim: suggestion)
                    .lineLimit(1)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityHint(String(localized: "Fills in the name"))
            .accessibilityIdentifier("new-item-suggestion-\(index)")
        }
    }
}
