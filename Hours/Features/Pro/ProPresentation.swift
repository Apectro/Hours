import SwiftUI

// Where the paywall is asked for, and what marks the door.
//
// The gate itself is a plain `subscriptions.allows(_:)` at each call site
// rather than a wrapper: the check is one line, and reading it in place beats
// following an abstraction to find out what is being sold.

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
