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
    /// The plan Continue buys; the yearly one until another is tapped.
    @State private var selectedID: String?

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
            // The one thing to do here, always in reach.
            .safeAreaInset(edge: .bottom) {
                if let product = selectedProduct {
                    Button {
                        Task { await buy(product) }
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(.bigAction(.primary, isMain: true))
                    .disabled(isWorking)
                    .accessibilityIdentifier("paywall-continue")
                    .padding(.horizontal, Metrics.large)
                    .padding(.vertical, Metrics.small)
                    .background(.bar)
                }
            }
            .background(Color.hoursCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not now") { dismiss() }
                        .accessibilityIdentifier("paywall-not-now")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Restore") { Task { await restore() } }
                        .disabled(isWorking)
                        .accessibilityIdentifier("paywall-restore")
                }
            }
            .task { await subscriptions.loadProducts() }
            .onChange(of: subscriptions.isPro) { _, isPro in
                if isPro { dismiss() }
            }
            .alert(
                Text(verbatim: AppIdentity.name),
                isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } }),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(message ?? "") }
            )
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: Metrics.small) {
            Text(verbatim: AppIdentity.proName)
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            if let reason {
                Text(reason.title)
                    .font(.headline)
                Text(reason.explanation)
                    .font(.subheadline)
                    .foregroundStyle(.hoursSecondaryText)
            }
            Text("Your own hours stay free, whatever you decide.")
                .font(.subheadline)
                .foregroundStyle(.hoursSecondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var features: some View {
        SurfaceCard {
        VStack(alignment: .leading, spacing: Metrics.medium) {
            // Sync is only sold in a build that can sync (`SyncPreference`);
            // offering a feature the build lacks is grounds for rejection.
            ForEach(ProFeature.allCases.filter { $0 != .iCloudSync || SyncPreference.isAvailable }) { feature in
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
                ForEach(orderedProducts, id: \.id) { product in
                    Button {
                        selectedID = product.id
                    } label: {
                        ProductRow(product: product, isSelected: product.id == selectedProduct?.id)
                    }
                    .buttonStyle(.plain)
                    .disabled(isWorking)
                    .accessibilityAddTraits(product.id == selectedProduct?.id ? .isSelected : [])
                    .accessibilityIdentifier("paywall-plan-\(product.id)")
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
            Text("A subscription renews until you cancel it, in Settings › your name › Subscriptions. Buying Zeitkonto outright is a single payment and never renews.")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Yearly, monthly, then buying it outright.
    private var orderedProducts: [Product] {
        let order = [SubscriptionStore.ProductID.yearly, SubscriptionStore.ProductID.monthly, SubscriptionStore.ProductID.lifetime]
        return subscriptions.products.sorted {
            (order.firstIndex(of: $0.id) ?? order.count) < (order.firstIndex(of: $1.id) ?? order.count)
        }
    }

    private var selectedProduct: Product? {
        let products = orderedProducts
        return products.first { $0.id == selectedID } ?? products.first
    }

    // MARK: - Actions

    private func buy(_ product: Product) async {
        isWorking = true
        defer { isWorking = false }

        switch await subscriptions.purchase(product) {
        case .bought:
            dismiss()
        case .pending:
            message = "That purchase is waiting for approval. Zeitkonto will open up on its own once it goes through."
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
            message = "Nothing to restore on this Apple ID. If you bought Zeitkonto with a different one, sign in with that one and try again."
        }
    }
}

/// One plan, as a card: its name, the real price, and "Best value" on
/// the yearly one. Tapping picks it; Continue buys it.
private struct ProductRow: View {
    let product: Product
    let isSelected: Bool

    private var isYearly: Bool { product.id == SubscriptionStore.ProductID.yearly }

    /// "£2.99 / month" — built from the product's own period so it is right in
    /// every storefront rather than only in ours.
    private var priceLine: String {
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        return "\(product.displayPrice) / \(period.unit.localizedDescription.lowercased())"
    }

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.medium) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Metrics.small) {
                    Text(product.displayName).font(.headline)
                    if isYearly {
                        Text("Best value")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.hoursPositive)
                            .padding(.horizontal, Metrics.small)
                            .padding(.vertical, 2)
                            .background(Color.hoursPositive.opacity(0.12), in: Capsule())
                    }
                }
                Text(priceLine)
                    .font(.hoursFigure(.subheadline))
                    .foregroundStyle(.hoursSecondaryText)
                if !product.description.isEmpty {
                    Text(product.description)
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.large)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .fill(Color.hoursSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.cornerRadius)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
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
