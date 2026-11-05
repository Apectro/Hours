import SwiftUI
import UIKit

/// Signing full screen (1.3): the whole screen to write on, turned to
/// landscape on a phone for a longer line. Shown as a `fullScreenCover` by
/// the crew sign-off (`SignatureSheet`) and the client's signature
/// (`ExtraWorkSignSheet`), after the signer has read what they sign for.
///
/// A white page in light mode and a dark one in dark mode, a baseline with
/// "Sign here" over it, who signs and for what in small grey letters at the
/// top, Cancel on the leading side and Clear and Done on the trailing side.
/// Everything stays inside the safe area, so nothing sits under the notch.
///
/// The drawing is handed back already fitted to the 3:1 box the sheets print
/// from (`SignatureFit`), so a signature looks on paper as it always has.
///
/// Identifiers: `<prefix>-canvas`, `<prefix>-clear`, `<prefix>-sign` (Done)
/// and `<prefix>-pad-cancel`, where the prefix is the sheet's own
/// ("signature", "extra-work-signature"), so the existing tests' names still
/// find the canvas, Clear and the button that signs.
struct SignaturePad: View {
    /// "Ivan Horvat · Sign-off, Trg Pravde Zagreb".
    let caption: String
    let identifierPrefix: String
    /// Called with the fitted strokes when Done is tapped, before the pad closes.
    let onDone: ([[SignaturePoint]]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var strokes: [[SignaturePoint]] = []
    @State private var current: [SignaturePoint] = []
    @State private var padSize: CGSize = .zero
    @State private var plan: SigningOrientation.Plan?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            canvas
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear {
            if plan == nil { plan = InterfaceOrientationLock.beginSigning() }
        }
        .onDisappear {
            if let plan { InterfaceOrientationLock.endSigning(plan) }
            plan = nil
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack(alignment: .center, spacing: Metrics.medium) {
            Button {
                dismiss()
            } label: {
                Text("Cancel")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityIdentifier(identifierPrefix + "-pad-cancel")

            Text(verbatim: caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifierPrefix + "-pad-caption")

            Button {
                strokes = []
                current = []
            } label: {
                Text("Clear")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(strokes.isEmpty)
            .accessibilityIdentifier(identifierPrefix + "-clear")

            Button {
                let aspect = padSize.height > 0 ? Double(padSize.width / padSize.height) : SignatureFit.boxAspectRatio
                onDone(SignatureFit.fit(strokes, drawnIn: aspect))
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(minWidth: 64, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!CrewSignature.isSignature(strokes))
            .accessibilityIdentifier(identifierPrefix + "-sign")
        }
        .padding(.horizontal, Metrics.large)
        .padding(.vertical, Metrics.small)
    }

    // MARK: - Canvas

    private var canvas: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let height = max(size.height, 1)
            ZStack(alignment: .topLeading) {
                // The line to sign on, three quarters of the way down.
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(height: 1)
                    .padding(.horizontal, Metrics.extraLarge)
                    .offset(y: size.height * 0.75)
                    .allowsHitTesting(false)
                Text("Sign here")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.leading, Metrics.extraLarge)
                    .offset(y: size.height * 0.75 + Metrics.small)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Canvas { context, _ in
                    var path = Path()
                    for stroke in strokes + [current] {
                        guard let first = stroke.first else { continue }
                        path.move(to: CGPoint(x: CGFloat(first.x) * height, y: CGFloat(first.y) * height))
                        for point in stroke.dropFirst() {
                            path.addLine(to: CGPoint(x: CGFloat(point.x) * height, y: CGFloat(point.y) * height))
                        }
                    }
                    context.stroke(path, with: .color(.primary), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            current.append(SignatureFit.point(
                                x: Double(value.location.x), y: Double(value.location.y),
                                padWidth: Double(size.width), padHeight: Double(size.height)
                            ))
                        }
                        .onEnded { _ in
                            if !current.isEmpty { strokes.append(current) }
                            current = []
                        }
                )
            }
            .onAppear { padSize = size }
            .onChange(of: size) { _, newSize in padSize = newSize }
        }
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Signature area"))
        .accessibilityHint(String(localized: "Sign with a finger."))
        .accessibilityIdentifier(identifierPrefix + "-canvas")
        .overlay(alignment: .topLeading) {
            // For the UI tests: the pad as the app lays it out, wider than
            // tall. A test reads window frames in the device's portrait
            // coordinates, which do not follow a rotation the app asked for.
            if padSize.width > padSize.height {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier(identifierPrefix + "-pad-wide")
            }
        }
    }
}

/// The interface's orientation while the signature pad is open. The app
/// delegate asks `supported` for every window; outside signing it is what
/// the build settings allow (a phone turns to either landscape side but not
/// upside down, an iPad turns every way), so the rest of the app turns as it
/// always has.
@MainActor
enum InterfaceOrientationLock {
    /// Set while a phone signs; nil the rest of the time.
    private(set) static var lock: UIInterfaceOrientationMask?

    static var supported: UIInterfaceOrientationMask {
        if let lock { return lock }
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    /// Turns a phone to landscape and keeps it there. If the system refuses,
    /// the lock comes off again and the pad is used the way the phone is held.
    static func beginSigning() -> SigningOrientation.Plan {
        guard let scene = activeScene else { return SigningOrientation.Plan(whileSigning: nil, afterwards: nil) }
        let plan = SigningOrientation.plan(
            isPad: scene.traitCollection.userInterfaceIdiom == .pad,
            wasPortrait: scene.effectiveGeometry.interfaceOrientation.isPortrait
        )
        guard plan.whileSigning == .landscape else { return plan }
        lock = .landscape
        // Asked once the full-screen cover has finished sliding in: a turn
        // requested during the presentation can be refused. A refusal is
        // tried once more, then the lock comes off and the pad is used the
        // way the phone is held.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            MainActor.assumeIsolated { requestLandscape(retries: 1) }
        }
        return plan
    }

    private static func requestLandscape(retries: Int) {
        guard lock == .landscape, let scene = activeScene else { return }
        refresh(scene)
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    if retries > 0 {
                        requestLandscape(retries: retries - 1)
                    } else {
                        lock = nil
                        if let scene = activeScene { refresh(scene) }
                    }
                }
            }
        }
    }

    /// Takes the lock off, and turns back to portrait if that is how the
    /// phone was held before.
    static func endSigning(_ plan: SigningOrientation.Plan) {
        lock = nil
        guard let scene = activeScene else { return }
        refresh(scene)
        if plan.afterwards == .portrait {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait)) { _ in }
        }
    }

    private static var activeScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
    }

    /// Every controller on screen asks the delegate again.
    private static func refresh(_ scene: UIWindowScene) {
        for window in scene.windows {
            var controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }
}

/// Only here to answer which way the interface may turn.
@MainActor
final class HoursAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        InterfaceOrientationLock.supported
    }
}
