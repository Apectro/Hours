import StoreKit
import SwiftUI

/// The one screen that asks for money.
///
/// Written to be read rather than to pressure: what you get, what it costs, and
/// what stays free whatever you decide. No countdown, no crossed-out price, no
/// "most popular" badge on the option we would rather you took.
struct PaywallSheet: View {
    /// What the person was trying to do when they hit the wall. Naming it puts
    /// the relevant line at the top rather than making them find it.
    var reason: ProFeature? = nil

    @Environment(SubscriptionStore.self) private var subscriptions
    @Environment(\.dismiss) private var dismiss

    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.extraLarge) {
                    header
                    features
                    products
                    freeForever
                    smallprint
                }
                .padding(Metrics.large)
            }
            .background(Color.hoursCanvas)
            .navigationTitle("Hours Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { Task { await restore() } }
                        .disabled(isWorking)
                }
            }
            .task { await subscriptions.loadProducts() }
            .onChange(of: subscriptions.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .alert(
                "Hours",
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(message ?? "") }
            )
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text(reason?.title ?? "Everything Hours can do")
                .font(.title2.bold())
            Text(reason?.explanation ?? "One purchase opens the parts of the app that turn a record of your hours into something you can hand to someone else.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var features: some View {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            ForEach(ProFeature.allCases) { feature in
                HStack(alignment: .top, spacing: Metrics.medium) {
                    Image(systemName: feature.symbolName)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title).font(.subheadline.weight(.semibold))
                        Text(feature.explanation)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                // The line that brought them here is worth pointing at.
                .padding(feature == reason ? Metrics.small : 0)
                .background {
                    if feature == reason {
                        RoundedRectangle(cornerRadius: Metrics.smallCornerRadius)
                            .fill(Color.accentColor.opacity(0.10))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var products: some View {
        if subscriptions.isLoadingProducts {
            HStack { Spacer(); ProgressView(); Spacer() }
                .padding(.vertical, Metrics.large)
        } else if let failure = subscriptions.loadFailure {
            Text(failure)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: Metrics.medium) {
                ForEach(subscriptions.products, id: \.id) { product in
                    Button {
                        Task { await buy(product) }
                    } label: {
                        ProductRow(product: product)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                }
            }
        }
    }

    private var freeForever: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("Free, whatever you decide")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(ProFeature.alwaysFree, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: Metrics.small) {
                    Image(systemName: "checkmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Color.hoursPositive)
                        .accessibilityHidden(true)
                    Text(line).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .fill(Color.hoursSurface)
        }
    }

    private var smallprint: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text("There is no account to make. A purchase belongs to your Apple ID, so it is already on your other devices — you should not need Restore, and it is there in case you do.")
            Text("A subscription renews until you cancel it, in Settings › your name › Subscriptions. Buying Hours outright is a single payment and never renews.")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Actions

    private func buy(_ product: Product) async {
        isWorking = true
        defer { isWorking = false }

        switch await subscriptions.purchase(product) {
        case .bought:
            dismiss()
        case .pending:
            message = "That purchase is waiting for approval. Hours will open up on its own once it goes through."
        case .cancelled:
            break
        case let .failed(reason):
            message = reason
        }
    }

    private func restore() async {
        isWorking = true
        defer { isWorking = false }

        if await subscriptions.restore() {
            dismiss()
        } else {
            message = "Nothing to restore on this Apple ID. If you bought Hours with a different one, sign in with that one and try again."
        }
    }
}

/// One purchase option.
private struct ProductRow: View {
    let product: Product

    private var isLifetime: Bool { product.id == SubscriptionStore.ProductID.lifetime }

    /// "£2.99 / month" — built from the product's own period so it is right in
    /// every storefront rather than only in ours.
    private var priceLine: String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice) / \(period.unit.localizedDescription.lowercased())"
    }

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.medium) {
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName).font(.headline)
                if !product.description.isEmpty {
                    Text(product.description)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Text(priceLine)
                .font(.hoursFigure(.subheadline))
                .foregroundStyle(isLifetime ? Color.primary : Color.accentColor)
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .fill(Color.hoursSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .strokeBorder(Color.accentColor.opacity(isLifetime ? 0 : 0.35), lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
}

private extension Product.SubscriptionPeriod.Unit {
    var localizedDescription: String {
        switch self {
        case .day: return String(localized: "Day")
        case .week: return String(localized: "Week")
        case .month: return String(localized: "Month")
        case .year: return String(localized: "Year")
        @unknown default: return String(localized: "Period")
        }
    }
}

#Preview {
    PaywallSheet(reason: .fileExport)
        .environment(SubscriptionStore.ephemeral())
}
