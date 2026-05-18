import Foundation

/// Single source of truth for pricing, product IDs, display copy, and the
/// 3.1.2(a) disclosure block. The paywall, `Configuration.storekit`, and
/// the ASC-side products must all agree with these constants.
///
/// Trial-determination model (portfolio-wide pattern, 2026-05-18):
///   - Every fresh install gets the highest Premium tier free for 7 days
///     via the install-time trial in `PurchaseManager` — no card, no
///     paywall, no subscription tap required.
///   - On the 8th day the user drops back to the free tier and the paywall
///     starts gating Premium-only surfaces normally.
///   - Purchasing any sub/IAP consumes the install-trial immediately
///     (`installTrialConsumedKey` → true) so paid users never get a
///     double-trial. The ASC-side subscription intro offer has been
///     stripped portfolio-wide; install-time is the canonical pattern.
enum PricingConfig {
    // Product IDs (legacy names kept for source-compat with existing call
    // sites; mirror `ProductIDs` enum for the canonical lookup).
    static let lifetimeProductID = ProductIDs.lifetime
    static let monthlyProductID  = ProductIDs.monthly
    static let annualProductID   = ProductIDs.yearly
    static let subscriptionGroupID = "racktimer_premium"

    // Display-only fallbacks used when StoreKit `Product.displayPrice` is
    // unavailable (sandbox flake / cold launch). Real prices come from
    // runtime `Product.displayPrice`.
    static let fallbackLifetimeDisplayPrice = "$14.99"
    static let fallbackMonthlyDisplayPrice  = "$2.99"
    static let fallbackAnnualDisplayPrice   = "$19.99"

    static let monthlyDisplayPrice = "$2.99"
    static let annualDisplayPrice  = "$19.99"

    static let allProductIDs: [String] = ProductIDs.all

    static let paywallTitle = "Unlock RackTimer"
    static let paywallSubtitle = "Pick yearly, monthly, or one-time lifetime unlock."

    static let paywallBenefits: [String] = [
        "Unlimited workout templates",
        "Unlimited exercise history",
        "Previous-set recall across every exercise",
        "Advanced timer presets",
        "Custom plate inventory",
    ]

    /// Install-time trial length (portfolio policy 2026-05-18).
    /// Read by `PurchaseManager.recomputeInstallTrial()` and rendered by the
    /// paywall banner. Name kept for source-compat with prior call sites —
    /// "annual" no longer implies an ASC-side introductory offer.
    static let annualTrialDays: Int = 7
    static let annualTrialDescription: String = "Auto-renews yearly · cancel anytime"

    /// 3.1.2(a) disclosures rendered verbatim by the paywall.
    static let disclosurePaymentCharged =
        "Payment will be charged to your Apple ID account at confirmation of purchase."
    static let disclosureAutoRenew =
        "Subscription automatically renews unless canceled at least 24 hours before the end of the current period."
    static let disclosureRenewalCharge =
        "Your account will be charged for renewal within 24 hours prior to the end of the current period."
    static let disclosureManage =
        "Subscriptions may be managed and auto-renewal may be turned off by going to the user's Account Settings after purchase."
    static let disclosureFreeTrial =
        "If you start a free trial, any unused portion is forfeited if you purchase a subscription before the trial ends."

    /// URLs rendered as tappable links in the paywall, Settings, and ASC
    /// metadata. Single source of truth so Settings ↔ paywall ↔ App Privacy
    /// reviewer never see drift between two parallel-maintained policies.
    static let privacyPolicyURL = "https://has-deploy.github.io/racktimer/privacy-policy.html"
    static let supportURL       = "https://has-deploy.github.io/racktimer/support.html"
    static let appleStdEULAURL  = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"

    // Free-tier caps
    static let freeTemplateSlots = 3
    static let freeHistoryWindowDays = 14
}
