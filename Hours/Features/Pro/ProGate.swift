import SwiftUI

/// One way to ask "may they?", so five screens cannot answer it five ways.
///
/// The gate is always at the moment of doing the thing, never at the door of
/// the screen. Someone who has not paid can still open Export, choose a range,
/// pick their columns and see the preview — they are stopped at the point a
/// file would be written. Hiding the screen would leave them guessing what they
/// were being sold.
@MainActor
struct ProGate {
    let subscriptions: SubscriptionStore

    /// Runs `action` if the feature is open, and otherwise asks for the
    /// paywall by writing the reason into `request`.
    func callAsFunction(
        _ feature: ProFeature,
        request: Binding<ProFeature?>,
        action: () -> Void
    ) {
        guard subscriptions.allows(feature) else {
            request.wrappedValue = feature
            return
        }
        action()
    }
}

extension View {
    /// Presents the paywall whenever a gate writes a reason into the binding.
    func paywall(for request: Binding<ProFeature?>) -> some View {
        sheet(item: request) { feature in
            PaywallSheet(reason: feature)
        }
    }

    /// The lock that appears beside something a gate will stop.
    ///
    /// Shown rather than disabling the control: a greyed-out button says "not
    /// for you" and nothing else, where a lock says there is a door.
    @ViewBuilder
    func proLock(_ shows: Bool) -> some View {
        if shows {
            HStack(spacing: Metrics.small) {
                self
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Hours Pro")
            }
        } else {
            self
        }
    }
}

/// A short line naming what Pro would add here, for the foot of a section
/// whose control is locked.
struct ProFootnote: View {
    let feature: ProFeature
    var isPro: Bool

    var body: some View {
        if isPro {
            EmptyView()
        } else {
            Text("\(feature.explanation) Included in Hours Pro.")
        }
    }
}
