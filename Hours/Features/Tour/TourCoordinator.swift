import SwiftUI

/// Where the guided tour is, and where on screen the things it points at
/// are.
///
/// One instance, owned by `RootView` and handed down through the
/// environment. The stops themselves are the engine's (`GuidedTour`); this
/// holds the running one and the frames the marked views report.
///
/// The frames travel through this object rather than as anchor preferences:
/// the targets live inside the `TabView`'s tabs, inside navigation stacks and
/// lists, and a preference set in there does not reliably reach a view
/// outside the `TabView`. A frame in the window's coordinates does, from
/// anywhere, and the overlay converts it into its own.
@Observable
final class TourCoordinator {
    /// Nil while no tour is running.
    private(set) var tour: GuidedTour?
    /// Each marked view's frame in the window (`.global`), while it is on
    /// screen.
    private(set) var frames: [TourTarget: CGRect] = [:]

    /// Starts the tour from the beginning, or again from the beginning if
    /// it is already running.
    func start(leadsCrew: Bool) {
        tour = GuidedTour(leadsCrew: leadsCrew)
    }

    /// The next stop, or the end after the last.
    func next() {
        guard var running = tour else { return }
        if running.advance() {
            tour = running
        } else {
            tour = nil
        }
    }

    /// Skip and Done.
    func end() {
        tour = nil
    }

    /// Nil when the view has gone. Only real changes are written, so a
    /// target that redraws without moving does not redraw the overlay.
    func report(_ target: TourTarget, frame: CGRect?) {
        guard frames[target] != frame else { return }
        frames[target] = frame
    }

    // MARK: - Launch argument

    /// Starts the tour at launch, for the UI tests that walk through it.
    /// Never set otherwise: the tour is never shown on its own, only from the
    /// welcome's "Show me around" and Settings › Show the tour again.
    static let launchArgument = "-hours-tour"

    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

extension View {
    /// Marks this view as something the tour can point at. Nil marks
    /// nothing, for a modifier applied to one row of several.
    func tourTarget(_ target: TourTarget?) -> some View {
        modifier(TourTargetModifier(target: target))
    }
}

private struct TourTargetModifier: ViewModifier {
    let target: TourTarget?

    /// Optional, so a view used where no tour exists — a preview, a sheet in
    /// another window — simply marks nothing.
    @Environment(TourCoordinator.self) private var coordinator: TourCoordinator?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let target, let coordinator {
            content.background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    Color.clear
                        .onAppear { coordinator.report(target, frame: frame) }
                        .onChange(of: frame) { _, newFrame in coordinator.report(target, frame: newFrame) }
                        .onDisappear { coordinator.report(target, frame: nil) }
                }
                .accessibilityHidden(true)
            }
        } else {
            content
        }
    }
}
