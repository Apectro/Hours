import SwiftUI

/// "Show public holidays for your country?" — once, at the top of the
/// calendar, for someone with no holidays at all. Put away for good by
/// "Not now" or by adding a country's holidays; nothing is added without
/// picking one.
struct PublicHolidayOfferCard: View {
    let onChoose: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: Metrics.medium) {
                Label {
                    Text("Show public holidays for your country?")
                        .font(.headline)
                } icon: {
                    Image(systemName: "flag")
                        .foregroundStyle(.purple)
                }
                Text("Pick your country and they show in the calendar as paid days off. On one you worked, tap I worked.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Metrics.small) {
                    Button(action: onChoose) {
                        Text("Choose country")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("public-holiday-offer-choose")
                    Button(action: onDismiss) {
                        Text("Not now")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("public-holiday-offer-dismiss")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("public-holiday-offer")
    }
}
