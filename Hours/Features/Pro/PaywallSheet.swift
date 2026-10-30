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
            List {
                if let reason {
                    Section {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reason.title)
                                .font(.headline)
                            Text(reason.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.hoursSecondaryText)
                        }
                        .padding(.vertical, Metrics.tiny)
                    }
                }
                features
                products
                freeForever
            }
            .listStyle(.insetGrouped)
            // The one thing to do here, always in reach.
            .safeAreaInset(edge: .bottom) {
                if let product = selectedProduct {
                    Button {
                        Task { await buy(product) }
                    } label: {
                        Text("Continue")
                    }
                    .buttonStyle(.bigAction(.primary))
                    .disabled(isWorking)
                    .accessibilityIdentifier("paywall-continue")
                    .padding(.horizontal, Metrics.large)
                    .padding(.vertical, Metrics.small)
                    .background(Color.hoursCanvas)
                }
            }
            .navigationTitle(Text(verbatim: AppIdentity.proName))
            .navigationBarTitleDisplayMode(.large)
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

    /// What Pro adds, a row each with its symbol.
    private var features: some View {
        Section {
            // Sync is only sold in a build that can sync (`SyncPreference`);
            // offering a feature the build lacks is grounds for rejection.
            ForEach(ProFeature.allCases.filter { $0 != .iCloudSync || SyncPreference.isAvailable }) { feature in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title)
                        Text(feature.explanation)
                            .font(.subheadline)
                            .foregroundStyle(.hoursSecondaryText)
                    }
                } icon: {
                    Image(systemName: feature.symbolName)
                        .foregroundStyle(Color.accentColor)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        } footer: {
            Text("Your own hours stay free, whatever you decide.")
        }
    }

    /// The plans as rows; the chosen one has a checkmark.
    @ViewBuilder
    private var products: some View {
        Section {
            if subscriptions.isLoadingProducts {
                ProgressView()
                    .frame(maxWidth: .infinity)
            } else if let failure = subscriptions.loadFailure {
                Text(failure)
                    .font(.footnote)
                    .foregroundStyle(.hoursSecondaryText)
            } else {
                ForEach(orderedProducts, id: \.id) { product in
                    Button {
                        selectedID = product.id
                    } label: {
                        ProductRow(product: product, isSelected: product.id == selectedProduct?.id)
                    }
                    .disabled(isWorking)
                    .accessibilityAddTraits(product.id == selectedProduct?.id ? .isSelected : [])
                    .accessibilityIdentifier("paywall-plan-\(product.id)")
                }
            }
        }
    }

    private var freeForever: some View {
        Section {
            ForEach(ProFeature.alwaysFree, id: \.self) { line in
                Text(line)
            }
        } header: {
            Text("Free, whatever you decide")
        } footer: {
            VStack(alignment: .leading, spacing: Metrics.small) {
                Text("There is no account to make. A purchase belongs to your Apple ID, so it is already on your other devices — you should not need Restore, and it is there in case you do.")
                Text("A subscription renews until you cancel it, in Settings › your name › Subscriptions. Buying Zeitkonto outright is a single payment and never renews.")
            }
        }
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

/// One plan, as a row: its name, the real price in grey, "Best value" on
/// the yearly one, and a checkmark when it is the one Continue buys.
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
            VStack(alignment: .leading, spacing: 2) {
                Text(product.displayName)
                    .foregroundStyle(.primary)
                HStack(spacing: Metrics.small) {
                    Text(priceLine)
                        .monospacedDigit()
                        .foregroundStyle(.hoursSecondaryText)
                    if isYearly {
                        Text("Best value")
                            .foregroundStyle(Color.hoursPositive)
                    }
                }
                .font(.subheadline)
                if !product.description.isEmpty {
                    Text(product.description)
                        .font(.footnote)
                        .foregroundStyle(.hoursSecondaryText)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark")
                .fontWeight(.semibold)
                .foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
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
