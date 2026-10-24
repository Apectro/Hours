import UIKit

/// The system share sheet, with word of how it ended.
///
/// `ShareLink` does not say whether anything was shared, and the extra-work
/// report must know: its jobs are marked sent only once the file has gone
/// somewhere (`ExtraWorkSending`). `UIActivityViewController` reports that
/// through its completion handler — completed, cancelled, or an error — so
/// it is presented from the front-most view controller and the answer handed
/// back as an `ExtraWorkShareOutcome`.
@MainActor
enum ShareSheetPresenter {
    static func present(_ url: URL, completion: @escaping (ExtraWorkShareOutcome) -> Void) {
        present([url], completion: completion)
    }

    /// Several files in one share: a crew's sheets, one per person.
    static func present(_ urls: [URL], completion: @escaping (ExtraWorkShareOutcome) -> Void) {
        guard let presenter = frontMostController(), !urls.isEmpty else {
            completion(.failed)
            return
        }
        let controller = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            if error != nil {
                completion(.failed)
            } else {
                completion(completed ? .completed : .cancelled)
            }
        }
        // An iPad shows it as a popover, which needs somewhere to point; the
        // app is iPhone-only, but a popover without an anchor is a crash.
        if let popover = controller.popoverPresentationController {
            popover.sourceView = presenter.view
            popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.maxY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        presenter.present(controller, animated: true)
    }

    /// The controller on top of whatever is showing — a sheet over a sheet
    /// included — in the active window.
    private static func frontMostController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)
            ?? scenes.flatMap(\.windows).first(where: \.isKeyWindow)
        var controller = window?.rootViewController
        while let presented = controller?.presentedViewController, !presented.isBeingDismissed {
            controller = presented
        }
        return controller
    }
}
