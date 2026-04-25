import Foundation
import StoreKit

/// StoreKit 2 wrapper. Multi-product: monthly auto-renewable subscription +
/// lifetime non-consumable. Either one grants `isPremium = true`.
@MainActor
final class PurchaseManager: ObservableObject {

    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var isPremium: Bool = false
    @Published private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case failed(String)
        case restoring
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            await self?.listenForTransactions()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    /// Live prices from the App Store, falling back to local constants while loading.
    var lifetimeDisplayPrice: String {
        lifetimeProduct?.displayPrice ?? PricingConfig.fallbackLifetimeDisplayPrice
    }

    var monthlyDisplayPrice: String {
        monthlyProduct?.displayPrice ?? PricingConfig.fallbackMonthlyDisplayPrice
    }

    // MARK: Public API

    func load() async {
        do {
            let products = try await Product.products(for: PricingConfig.allProductIDs)
            self.lifetimeProduct = products.first { $0.id == PricingConfig.lifetimeProductID }
            self.monthlyProduct  = products.first { $0.id == PricingConfig.monthlyProductID }
            await refreshEntitlements()
        } catch {
            // Offline / sandbox hiccups — keep previous state.
        }
    }

    func purchaseLifetime() async {
        guard let product = lifetimeProduct else {
            purchaseState = .failed("Product not available")
            return
        }
        await purchase(product)
    }

    func purchaseMonthly() async {
        guard let product = monthlyProduct else {
            purchaseState = .failed("Product not available")
            return
        }
        await purchase(product)
    }

    private func purchase(_ product: Product) async {
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let tx):
                    await tx.finish()
                    isPremium = true
                    purchaseState = .idle
                case .unverified(let tx, let err):
                    await tx.finish()
                    await refreshEntitlements()
                    purchaseState = .failed("Apple couldn't verify the purchase: \(err.localizedDescription)")
                }
            case .userCancelled:
                purchaseState = .idle
            case .pending:
                purchaseState = .idle
            @unknown default:
                purchaseState = .idle
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .restoring
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseState = .failed(error.localizedDescription)
            return
        }
        purchaseState = .idle
    }

    // MARK: Entitlements

    func refreshEntitlements() async {
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let tx) = entitlement,
               PricingConfig.allProductIDs.contains(tx.productID),
               tx.revocationDate == nil {
                isPremium = true
                return
            }
        }
        isPremium = false
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            switch update {
            case .verified(let tx):
                await tx.finish()
                await refreshEntitlements()
            case .unverified(let tx, _):
                await tx.finish()
                await refreshEntitlements()
            }
        }
    }

#if DEBUG
    /// Debug-only override — never shipped in Release.
    func debugTogglePremium() { isPremium.toggle() }
#endif
}
