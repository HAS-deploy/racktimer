import Foundation
import StoreKit

/// StoreKit 2 wrapper. Single non-consumable product — `com.racktimer.app.lifetime`.
@MainActor
final class PurchaseManager: ObservableObject {

    @Published private(set) var product: Product?
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

    /// Live price from the App Store, falling back to the local constant while loading.
    var lifetimeDisplayPrice: String {
        product?.displayPrice ?? PricingConfig.fallbackLifetimeDisplayPrice
    }

    // MARK: Public API

    func load() async {
        do {
            let products = try await Product.products(for: [PricingConfig.lifetimeProductID])
            self.product = products.first
            await refreshEntitlements()
        } catch {
            // Offline / sandbox hiccups — keep previous state.
        }
    }

    func purchase() async {
        guard let product else {
            purchaseState = .failed("Product not available")
            return
        }
        purchaseState = .purchasing
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    await tx.finish()
                    isPremium = true
                }
                purchaseState = .idle
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
               tx.productID == PricingConfig.lifetimeProductID,
               tx.revocationDate == nil {
                isPremium = true
                return
            }
        }
        isPremium = false
    }

    private func listenForTransactions() async {
        for await update in Transaction.updates {
            if case .verified(let tx) = update {
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
