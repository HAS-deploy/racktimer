import Foundation
import StoreKit

/// StoreKit 2 wrapper. Multi-product: monthly auto-renewable subscription +
/// lifetime non-consumable. Either one grants `isPremium = true`.
///
/// Install-time trial: fresh installs get full Premium for
/// `PricingConfig.annualTrialDays` (14 days) before any free-tier caps kick
/// in. State lives in UserDefaults under `firstLaunchAtKey` so it survives
/// app launches but resets on uninstall — matching the StoreKit-side
/// intro-offer eligibility model and the canonical RoadBinder pattern.
@MainActor
final class PurchaseManager: ObservableObject {

    @Published private(set) var lifetimeProduct: Product?
    @Published private(set) var monthlyProduct: Product?
    @Published private(set) var yearlyProduct: Product?
    @Published private(set) var isPremium: Bool = false
    /// True while the install-time trial window is active and the user has
    /// not yet purchased. Independent of `isPremium`.
    @Published private(set) var installTrialActive: Bool = false
    @Published private(set) var purchaseState: PurchaseState = .idle

    enum PurchaseState: Equatable {
        case idle
        case purchasing
        case cancelled            // user dismissed the StoreKit sheet
        case pending              // Ask-to-Buy / parental approval / SCA pending
        case unknownState         // StoreKit returned an @unknown default case
        case failed(String)       // real StoreKit error (network, verification, etc.)
        case restoring
    }

    /// UserDefaults key for the first-launch timestamp. Set exactly once,
    /// the first time `PurchaseManager` initializes after a fresh install.
    static let firstLaunchAtKey = "racktimer.firstLaunchAt"

    /// Single entitlement source of truth — `true` if the user is paid or
    /// still inside the install-time trial. Views should consult this for
    /// free-cap gating; only restore/purchase UI should read `isPremium`.
    var isEntitled: Bool { isPremium || installTrialActive }

    private let defaults: UserDefaults
    private let now: () -> Date
    private var updatesTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        stampFirstLaunchIfNeeded()
        recomputeInstallTrial()
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

    var yearlyDisplayPrice: String {
        yearlyProduct?.displayPrice ?? PricingConfig.fallbackAnnualDisplayPrice
    }

    // MARK: Public API

    func load() async {
        do {
            let products = try await Product.products(for: PricingConfig.allProductIDs)
            self.lifetimeProduct = products.first { $0.id == PricingConfig.lifetimeProductID }
            self.monthlyProduct  = products.first { $0.id == PricingConfig.monthlyProductID }
            self.yearlyProduct   = products.first { $0.id == PricingConfig.annualProductID }
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

    func purchaseYearly() async {
        guard let product = yearlyProduct else {
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
                    recomputeInstallTrial()
                    purchaseState = .idle
                case .unverified(let tx, let err):
                    await tx.finish()
                    await refreshEntitlements()
                    purchaseState = .failed("Apple couldn't verify the purchase: \(err.localizedDescription)")
                }
            case .userCancelled:
                purchaseState = .cancelled
            case .pending:
                purchaseState = .pending
            @unknown default:
                purchaseState = .unknownState
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
                recomputeInstallTrial()
                return
            }
        }
        isPremium = false
        recomputeInstallTrial()
    }

    // MARK: Install-time trial

    /// Stamps the first-launch timestamp the first time the app ever runs
    /// on this install. Subsequent launches read the existing value.
    private func stampFirstLaunchIfNeeded() {
        if defaults.object(forKey: Self.firstLaunchAtKey) == nil {
            defaults.set(now(), forKey: Self.firstLaunchAtKey)
        }
    }

    /// Days elapsed since first launch on this install. Floor-rounded to
    /// whole days so a fresh install reports 0 and the trial flips off
    /// strictly after 14 full days have passed.
    private func daysSinceFirstLaunch() -> Int {
        guard let start = defaults.object(forKey: Self.firstLaunchAtKey) as? Date else { return 0 }
        return Calendar.current.dateComponents([.day], from: start, to: now()).day ?? 0
    }

    /// True iff the install-time trial window is still open AND no paid
    /// entitlement is active. Paying users don't need the trial flag.
    private func recomputeInstallTrial() {
        installTrialActive = !isPremium && daysSinceFirstLaunch() < PricingConfig.annualTrialDays
    }

    /// Test/debug hook — call after mutating UserDefaults or the clock in a
    /// test to refresh the published flag.
    func refreshInstallTrialForTesting() {
        recomputeInstallTrial()
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
    func debugTogglePremium() {
        isPremium.toggle()
        recomputeInstallTrial()
    }
#endif
}
