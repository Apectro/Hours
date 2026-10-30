import SwiftUI

/// "Show public holidays for your country?" — once, on the Today tab, for
/// someone with no holidays at all. Put away for good by "Not now" or by
/// adding a country's holidays; nothing is added without picking one.
///
/// A section of the Today tab's list (design v2): the question, Choose
/// country and Not now as rows, and one footer sentence.
struct PublicHolidayOfferCard: View {
    let onChoose: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Section {
            Label {
                Text("Show public holidays for your country?")
                    .font(.headline)
            } icon: {
                Image(systemName: "flag")
                    .foregroundStyle(.purple)
            }
            // The question is the offer: the tests look for it by this.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("public-holiday-offer")

            Button("Choose country", action: onChoose)
                .accessibilityIdentifier("public-holiday-offer-choose")
            Button("Not now", action: onDismiss)
                .foregroundStyle(.hoursSecondaryText)
                .accessibilityIdentifier("public-holiday-offer-dismiss")
        } footer: {
            Text("Pick your country and they show in the calendar as paid days off. On one you worked, tap I worked.")
        }
    }
}
