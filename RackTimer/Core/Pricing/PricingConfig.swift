import Foundation

/// Single source of truth for pricing. Change the price in App Store Connect
/// and update `fallbackLifetimeDisplayPrice` here to keep the cached label
/// consistent before StoreKit hydrates.
enum PricingConfig {
    static let lifetimeProductID = "com.racktimer.app.lifetime"
    static let fallbackLifetimeDisplayPrice = "$9.99"

    static let paywallTitle = "Unlock RackTimer"
    static let paywallSubtitle = "One-time purchase. No subscriptions."

    static let paywallBenefits: [String] = [
        "Unlimited workout templates",
        "Unlimited exercise history",
        "Previous-set recall across every exercise",
        "Advanced timer presets",
        "Custom plate inventory",
    ]

    // Free-tier caps
    static let freeTemplateSlots = 3
    static let freeHistoryWindowDays = 14
}
