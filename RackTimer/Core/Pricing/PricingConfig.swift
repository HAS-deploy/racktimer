import Foundation

/// Single source of truth for pricing. Update values here, not scattered.
/// Product IDs must match App Store Connect and Configuration.storekit.
enum PricingConfig {
    static let lifetimeProductID  = "com.racktimer.app.lifetime"
    static let monthlyProductID   = "com.racktimer.app.monthly"
    static let subscriptionGroupID = "racktimer_premium"

    static let fallbackLifetimeDisplayPrice = "$14.99"
    static let fallbackMonthlyDisplayPrice  = "$2.99"

    static let allProductIDs: [String] = [monthlyProductID, lifetimeProductID]

    static let paywallTitle = "Unlock RackTimer"
    static let paywallSubtitle = "Choose monthly or one-time lifetime unlock."

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
