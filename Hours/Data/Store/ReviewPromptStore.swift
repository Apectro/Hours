import StoreKit
import SwiftUI
import UIKit

/// The app's side of `ReviewPrompt`: when it was first opened and which
/// version last asked, kept on this device only (a rating is a person's, not
/// their data's), and the details a feedback mail carries.
@MainActor
enum ReviewPromptStore {
    private static let firstUseKey = "hours.review.firstUse"
    private static let askedVersionKey = "hours.review.askedVersion"

    /// Called at launch: the first one starts the two weeks.
    static func noteLaunch(defaults: UserDefaults = .standard) {
        if defaults.object(forKey: firstUseKey) == nil {
            defaults.set(Date(), forKey: firstUseKey)
        }
    }

    /// After a sheet has really been shared: asks once this version, when it
    /// is due, a moment after the share sheet has gone so the two do not
    /// collide. Never under UI tests, where a system prompt would cover the
    /// screen the next step looks for.
    static func askIfDue(_ requestReview: RequestReviewAction, defaults: UserDefaults = .standard) {
        guard !HoursStack.isRunningUITests else { return }
        let version = shortVersion
        guard ReviewPrompt.shouldAsk(
            firstUse: defaults.object(forKey: firstUseKey) as? Date,
            now: Date(),
            lastAskedVersion: defaults.string(forKey: askedVersionKey),
            currentVersion: version,
            calendar: HoursStack.calendar
        ) else { return }
        defaults.set(version, forKey: askedVersionKey)
        Task {
            try? await Task.sleep(for: .seconds(1))
            requestReview()
        }
    }

    static var feedbackMailURL: URL? {
        ReviewPrompt.feedbackMailURL(
            subject: String(localized: "Zeitkonto feedback", comment: "Subject of the feedback mail"),
            appVersion: "\(shortVersion) (\(build))",
            system: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)",
            device: deviceModel
        )
    }

    private static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
    }

    /// "iPhone16,2" rather than "iPhone": the model, which is what tells a
    /// layout problem on a small screen from one on a large one.
    private static var deviceModel: String {
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
