import Foundation

/// Asking for a rating, and the two ways to reach the developer from
/// Settings.
///
/// The system decides whether its rating prompt actually appears and caps it
/// at three a year; this decides whether to ask at all. Only right after a
/// sheet has really gone to someone (a good moment, never mid-entry), never
/// in the first two weeks, and once a version. Nothing filters who is asked:
/// a "do you like it?" gate in front of the prompt is against the App Store
/// rules.
enum ReviewPrompt {
    static let minimumDaysOfUse = 14

    /// The App Store's write-a-review page for Zeitkonto.
    static let writeReviewURL = URL(string: "https://apps.apple.com/app/id6825054128?action=write-review")!

    static let feedbackAddress = "marijomiksa@pm.me"

    static func shouldAsk(
        firstUse: Date?,
        now: Date,
        lastAskedVersion: String?,
        currentVersion: String,
        calendar: Calendar
    ) -> Bool {
        guard let firstUse, lastAskedVersion != currentVersion else { return false }
        let used = calendar.dateComponents([.day], from: firstUse, to: now).day ?? 0
        return used >= minimumDaysOfUse
    }

    /// A mail to the developer with what helps to answer it: the app's
    /// version, the system and the model. Nothing of the person's hours.
    static func feedbackMailURL(subject: String, appVersion: String, system: String, device: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = feedbackAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: "\n\n—\nZeitkonto \(appVersion) · \(system) · \(device)"),
        ]
        return components.url
    }
}
