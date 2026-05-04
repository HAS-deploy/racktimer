//  PortfolioAnalytics.swift
//  App Factory — shared Swift drop-in (canonical 2026-04-26 schema lock).
//
//  One file per iOS app, copied verbatim. Do NOT diverge per app — when the
//  spec changes, update this file in ~/Developer/app-factory/swift/ and
//  re-copy to each app's Core/Analytics/ folder.
//
//  Spec: ~/Developer/portfolio-spec/ANALYTICS.md
//
//  Install:
//    1. SwiftPM dependency: https://github.com/PostHog/posthog-ios (product "PostHog").
//    2. Info.plist:
//         PostHogKey    = "phc_xxx"      // leave empty in dev for no-op
//         PostHogHost   = "https://us.i.posthog.com"
//    3. App launch (e.g. inside @main App init):
//         PortfolioAnalytics.shared.start(appName: "expiryvault")
//    4. On entitlement change (purchase landed, subscription expired, etc.):
//         PortfolioAnalytics.shared.setEntitlement(isPremium: true,
//                                                  segment: .premium)
//    5. Anywhere:
//         PortfolioAnalytics.shared.track(PortfolioEvent.paywallViewed,
//             ["trigger_source": "settings"])
//
//  Privacy posture:
//    - Autocapture OFF — every event explicit.
//    - Session recording OFF — apps process documents/PHI.
//    - respectsDoNotTrack = true.
//    - User-controllable opt-out — once optOut() is called, every subsequent
//      track() is a no-op even after relaunch (UserDefaults flag).

import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif
#if canImport(UIKit)
import UIKit
#endif
import CryptoKit
#if canImport(StoreKit)
import StoreKit
#endif

#if canImport(PostHog)
import PostHog
#endif

// MARK: - Top-level

final class PortfolioAnalytics: @unchecked Sendable {
    static let shared = PortfolioAnalytics()

    // Configuration
    private var started = false
    private var appName: String = "unknown"

    // Mutable runtime traits — kept in memory + UserDefaults so we can attach
    // them to every event without re-reading per call.
    private var isPremium: Bool = false
    private var userSegment: UserSegment = .anonymous
    private var locale: String = Locale.current.identifier
    private var firstLaunchAt: Date = Date()

    // Opt-out (persisted)
    private static let kOptedOut = "portfolio.analytics.opted_out"
    private static let kFirstLaunch = "portfolio.analytics.first_launch_at"
    private static let kIdentified = "portfolio.analytics.identified"

    private init() {}

    // MARK: Lifecycle

    func start(appName: String) {
        guard !started else { return }
        self.appName = appName

        // First-launch tracking
        let defaults = UserDefaults.standard
        if let stored = defaults.object(forKey: Self.kFirstLaunch) as? Date {
            firstLaunchAt = stored
        } else {
            firstLaunchAt = Date()
            defaults.set(firstLaunchAt, forKey: Self.kFirstLaunch)
        }
        let isFirstLaunchEver = defaults.object(forKey: Self.kFirstLaunch) == nil
            || abs(firstLaunchAt.timeIntervalSinceNow) < 5

        // Honor opt-out before SDK init
        guard !isOptedOut else {
            started = true // mark started so subsequent calls are short-circuited
            return
        }

        #if canImport(PostHog)
        let key = (Bundle.main.object(forInfoDictionaryKey: "PostHogKey") as? String) ?? ""
        let host = (Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String)
            ?? "https://us.i.posthog.com"
        guard !key.isEmpty else {
            started = true
            return
        }
        let config = PostHogConfig(apiKey: key, host: host)
        config.captureApplicationLifecycleEvents = false  // we emit our own
        config.captureScreenViews = false                  // explicit screen.viewed
        config.sessionReplay = false
        config.personProfiles = .never
        PostHogSDK.shared.setup(config)
        // Tag every event (incl. PostHog auto-lifecycle) with app name.
        PostHogSDK.shared.register(["app": appName])
        #endif

        started = true

        // Lifecycle events
        if isFirstLaunchEver {
            track(PortfolioEvent.install, [:])
        }
        track(PortfolioEvent.appForegrounded, [:])
    }

    // MARK: Identity

    /// Associate subsequent events with a stable user id. Call once after
    /// authenticate / first purchase. Before this, events are anonymous-by-device.
    func identify(userId: String, traits: [String: Any] = [:]) {
        guard started, !isOptedOut else { return }
        #if canImport(PostHog)
        PostHogSDK.shared.identify(userId, userProperties: traits)
        #endif
        UserDefaults.standard.set(true, forKey: Self.kIdentified)
    }

    /// Promote anonymous → identified using a hashed IDFV (per-app vendor id).
    /// Call once on the first successful purchase of the install.
    func identifyAfterPurchase(productId: String, revenueUsd: Double, isFirstPurchase: Bool = true) {
        let idfv = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let hash = Insecure.MD5.hash(data: Data(idfv.utf8))
            .map { String(format: "%02x", $0) }.joined()
        let userId = "anon_\(hash.prefix(12))"
        let traits: [String: Any] = [
            "first_app": appName,
            "first_purchase_sku": productId,
            "first_purchase_revenue_usd": revenueUsd,
            "first_purchase_at": ISO8601DateFormatter().string(from: Date()),
            "is_first_purchase": isFirstPurchase,
        ]
        identify(userId: userId, traits: traits)
    }

    /// Clear the stored identity (sign-out / account-delete).
    func reset() {
        guard started else { return }
        #if canImport(PostHog)
        PostHogSDK.shared.reset()
        #endif
        UserDefaults.standard.set(false, forKey: Self.kIdentified)
    }

    // MARK: Entitlement (mutable runtime traits)

    enum UserSegment: String {
        case anonymous, free, trial, premium, lifetime
    }

    /// Update the entitlement-driven base props that go on every event.
    /// Call from the EntitlementStore / PurchaseManager whenever segment changes.
    func setEntitlement(isPremium: Bool, segment: UserSegment) {
        self.isPremium = isPremium
        self.userSegment = segment
        // Persist as person properties so cohorts work after the app closes
        guard started, !isOptedOut else { return }
        #if canImport(PostHog)
        PostHogSDK.shared.register(["user_segment": segment.rawValue,
                                    "is_premium": isPremium])
        #endif
    }

    // MARK: Opt-out

    var isOptedOut: Bool {
        UserDefaults.standard.bool(forKey: Self.kOptedOut)
    }

    func optOut() {
        UserDefaults.standard.set(true, forKey: Self.kOptedOut)
        #if canImport(PostHog)
        if started { PostHogSDK.shared.optOut() }
        #endif
        track(PortfolioEvent.analyticsOptedOut, [:])
    }

    func optIn() {
        UserDefaults.standard.set(false, forKey: Self.kOptedOut)
        #if canImport(PostHog)
        if started { PostHogSDK.shared.optIn() }
        #endif
        track(PortfolioEvent.analyticsOptedIn, [:])
    }

    // MARK: Track

    /// Single transport. Auto-attaches the standard base props.
    /// Per-app callers add their own custom props as the second arg.
    func track(_ event: String, _ props: [String: Any] = [:]) {
        guard started, !isOptedOut else { return }
        #if canImport(PostHog)
        var enriched = props
        enriched["app"] = appName
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            enriched["app_version"] = v
        }
        if let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            enriched["build"] = b
        }
        enriched["locale"] = locale
        enriched["user_segment"] = userSegment.rawValue
        enriched["is_premium"] = isPremium
        enriched["days_since_install"] = max(0, Int(Date().timeIntervalSince(firstLaunchAt) / 86400))
        PostHogSDK.shared.capture(event, properties: enriched)
        #endif
    }

    // MARK: Helpers — common typed call sites

    /// Track a paywall view with structured trigger metadata.
    func trackPaywallViewed(triggerSource: PaywallTriggerSource,
                            triggerFeature: String? = nil,
                            productsCount: Int? = nil) {
        var p: [String: Any] = ["trigger_source": triggerSource.rawValue]
        if let f = triggerFeature { p["trigger_feature"] = f }
        if let c = productsCount { p["products_count"] = c }
        track(PortfolioEvent.paywallViewed, p)
    }

    /// Track a successful in-app purchase. Pass the StoreKit `Product` and
    /// `Transaction` for full context. Auto-decides if first purchase via
    /// UserDefaults flag.
    #if canImport(StoreKit)
    func trackPurchaseSuccess(product: Product,
                              transaction: StoreKit.Transaction,
                              secondsToPurchase: Double? = nil) {
        let priceUsd = NSDecimalNumber(decimal: product.price).doubleValue
        let isFirst = !UserDefaults.standard.bool(forKey: "portfolio.analytics.first_purchase_done")
        var p: [String: Any] = [
            "product_id": product.id,
            "revenue_usd": priceUsd,
            "currency": product.priceFormatStyle.currencyCode ?? "USD",
            "transaction_id": String(transaction.id),
            "is_first_purchase": isFirst,
        ]
        if let s = secondsToPurchase { p["seconds_to_purchase"] = s }
        track(PortfolioEvent.paywallPurchaseSuccess, p)
        if isFirst {
            UserDefaults.standard.set(true, forKey: "portfolio.analytics.first_purchase_done")
            identifyAfterPurchase(productId: product.id, revenueUsd: priceUsd, isFirstPurchase: true)
        }
    }

    /// Track a subscription purchase with type-specific props.
    func trackSubscriptionPurchase(product: Product,
                                   transaction: StoreKit.Transaction,
                                   isPromotionalOffer: Bool = false) {
        let priceUsd = NSDecimalNumber(decimal: product.price).doubleValue
        let period = product.subscription?.subscriptionPeriod
        var p: [String: Any] = [
            "product_id": product.id,
            "revenue_usd": priceUsd,
            "currency": product.priceFormatStyle.currencyCode ?? "USD",
            "transaction_id": String(transaction.id),
            "original_transaction_id": String(transaction.originalID),
            "is_promotional_offer": isPromotionalOffer,
        ]
        if let period {
            p["period"] = "\(period.value)\(period.unit)"
        }
        track(PortfolioEvent.subscriptionPurchased, p)
    }
    #endif

    /// Map a StoreKit purchase failure into a structured `reason` and emit.
    /// Call from the catch block / non-success switch case.
    func trackPaywallFailure(productId: String,
                             reason: PurchaseFailureReason,
                             errorCode: String? = nil,
                             attemptNumber: Int? = nil) {
        var p: [String: Any] = [
            "product_id": productId,
            "reason": reason.rawValue,
        ]
        if let c = errorCode { p["error_code"] = c }
        if let n = attemptNumber { p["attempt_number"] = n }
        track(PortfolioEvent.paywallPurchaseFailed, p)
    }

    /// Map an unknown error to a typed reason. Use when catching a generic
    /// Swift error from `product.purchase()`.
    func trackPaywallFailure(productId: String,
                             error: Error,
                             attemptNumber: Int? = nil) {
        let reason = PurchaseFailureReason(error: error)
        let code = String(describing: error).prefix(200)
        trackPaywallFailure(productId: productId,
                            reason: reason,
                            errorCode: String(code),
                            attemptNumber: attemptNumber)
    }

    /// Track a user-surfaced error / warning (not a crash).
    func trackError(code: String,
                    messageId: String? = nil,
                    screen: String? = nil,
                    severity: ErrorSeverity = .error,
                    feature: String? = nil) {
        var p: [String: Any] = ["code": code, "severity": severity.rawValue]
        if let m = messageId { p["message_id"] = m }
        if let s = screen { p["screen"] = s }
        if let f = feature { p["feature"] = f }
        track(PortfolioEvent.errorSurfaced, p)
    }

    /// Track a permission OS-prompt outcome.
    func trackPermission(_ permission: Permission,
                         state: PermissionState,
                         triggerFeature: String? = nil) {
        var p: [String: Any] = ["permission": permission.rawValue]
        if let f = triggerFeature { p["trigger_feature"] = f }
        let event: String
        switch state {
        case .requested: event = PortfolioEvent.permissionRequested
        case .granted: event = PortfolioEvent.permissionGranted
        case .denied: event = PortfolioEvent.permissionDenied
        case .deferred: event = PortfolioEvent.permissionDeferred
        }
        track(event, p)
    }
}

// MARK: - Enums

enum PaywallTriggerSource: String {
    case settings, onboarding, featureGate = "feature_gate", limitHit = "limit_hit"
    case deepLink = "deep_link", push, restoreFailed = "restore_failed"
}

enum PurchaseFailureReason: String {
    case userCanceled = "user_canceled"
    case pending
    case noPaymentMethod = "no_payment_method"
    case notInStorefront = "not_in_storefront"
    case networkError = "network_error"
    case verificationFailed = "verification_failed"
    case unverifiedReceipt = "unverified_receipt"
    case unknown

    /// Best-effort mapping from a generic Swift error to a reason. Falls back
    /// to .unknown — the raw error string is also captured separately on the
    /// event so we can refine this mapping over time.
    init(error: Error) {
        #if canImport(StoreKit)
        if let skErr = error as? StoreKitError {
            switch skErr {
            case .userCancelled: self = .userCanceled; return
            case .networkError: self = .networkError; return
            case .notAvailableInStorefront: self = .notInStorefront; return
            case .notEntitled: self = .verificationFailed; return
            case .systemError: self = .unknown; return
            case .unknown: self = .unknown; return
            @unknown default: self = .unknown; return
            }
        }
        if let purchaseErr = error as? Product.PurchaseError {
            switch purchaseErr {
            case .productUnavailable: self = .notInStorefront; return
            case .invalidQuantity, .invalidOfferIdentifier, .invalidOfferPrice, .invalidOfferSignature:
                self = .verificationFailed; return
            case .missingOfferParameters, .ineligibleForOffer:
                self = .verificationFailed; return
            @unknown default: self = .unknown; return
            }
        }
        #endif
        // URLError surfaces network issues
        if let urlErr = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(urlErr.code) {
            self = .networkError; return
        }
        self = .unknown
    }
}

enum ErrorSeverity: String { case info, warn, error }

enum Permission: String {
    case notifications, camera, photos, location, contacts, faceid, motion
}

enum PermissionState { case requested, granted, denied, deferred }

// MARK: - Event-name constants
//
// Keep in lockstep with ~/Developer/portfolio-spec/ANALYTICS.md.

enum PortfolioEvent {
    // 1. Lifecycle
    static let install                 = "install"
    static let appForegrounded         = "app.foregrounded"
    static let appBackgrounded         = "app.backgrounded"
    static let updateInstalled         = "update.installed"
    static let sessionColdStart        = "session.cold_start"
    static let sessionWarmStart        = "session.warm_start"

    // 2. Onboarding
    static let onboardingViewed        = "onboarding.viewed"
    static let onboardingAdvanced      = "onboarding.advanced"
    static let onboardingSkipped       = "onboarding.skipped"
    static let onboardingCompleted     = "onboarding.completed"
    static let onboardingAbandoned     = "onboarding.abandoned"

    // 3. Permissions
    static let permissionRequested     = "permission.requested"
    static let permissionGranted       = "permission.granted"
    static let permissionDenied        = "permission.denied"
    static let permissionDeferred      = "permission.deferred"

    // 4. Navigation
    static let screenViewed            = "screen.viewed"
    static let screenDismissed         = "screen.dismissed"
    static let navTabChanged           = "nav.tab_changed"
    static let searchQueried           = "search.queried"
    static let listScrolled            = "list.scrolled"
    static let detailViewed            = "detail.viewed"

    // 5. Monetization — IAP
    static let paywallViewed           = "paywall.viewed"
    static let paywallProductSelected  = "paywall.product_selected"
    static let paywallPurchaseClick    = "paywall.purchase_clicked"
    static let paywallPurchaseSuccess  = "paywall.purchase_success"
    static let paywallPurchaseFailed   = "paywall.purchase_failed"
    static let paywallDismissed        = "paywall.dismissed"
    static let restoreTapped           = "restore.tapped"
    static let restoreCompleted        = "restore.completed"
    static let restoreFailed           = "restore.failed"

    // 6. Subscriptions (most fire server-side from Apple S2S notifications)
    static let subIntroOfferEligibleSeen = "subscription.intro_offer_eligible_seen"
    static let subIntroOfferRedeemed     = "subscription.intro_offer_redeemed"
    static let subTrialStarted           = "subscription.trial.started"
    static let subscriptionPurchased     = "subscription.purchased"
    static let subscriptionRenewed       = "subscription.renewed"
    static let subscriptionUpgraded      = "subscription.upgraded"
    static let subscriptionDowngraded    = "subscription.downgraded"
    static let subscriptionCrossgraded   = "subscription.crossgraded"
    static let subscriptionCanceled      = "subscription.canceled"
    static let subscriptionReactivated   = "subscription.reactivated"
    static let subscriptionExpired       = "subscription.expired"
    static let subscriptionBillingRetry  = "subscription.billing_retry"
    static let subscriptionGracePeriod   = "subscription.grace_period"
    static let subscriptionRefunded      = "subscription.refunded"
    static let subPriceIncreaseSeen      = "subscription.price_increase_seen"
    static let subPriceIncreaseConsent   = "subscription.price_increase_consent"

    // 8. Friction / errors
    static let errorSurfaced           = "error.surfaced"
    static let errorNetwork            = "error.network"
    static let errorPermissionBlocked  = "error.permission_blocked"
    static let rageTap                 = "rage_tap"
    static let crashHandled            = "crash.handled"
    static let featureUnavailable      = "feature.unavailable"
    static let featureBlockedByPaywall = "feature.blocked_by_paywall"

    // 9. Settings
    static let settingsToggled              = "settings.toggled"
    static let settingsNotificationsChanged = "settings.notifications_changed"
    static let settingsQuietHoursChanged    = "settings.quiet_hours_changed"
    static let settingsThemeChanged         = "settings.theme_changed"
    static let settingsUnitsChanged         = "settings.units_changed"
    static let settingsExportTapped         = "settings.export_tapped"
    static let settingsDeleteDataTapped     = "settings.delete_data_tapped"
    static let settingsSupportTapped        = "settings.support_tapped"
    static let settingsPrivacyTapped        = "settings.privacy_tapped"
    static let settingsTermsTapped          = "settings.terms_tapped"
    static let settingsReviewTapped         = "settings.review_tapped"
    static let settingsCrossAppLinkTapped   = "settings.cross_app_link_tapped"
    static let analyticsOptedOut           = "analytics.opted_out"
    static let analyticsOptedIn            = "analytics.opted_in"

    // 10. Re-engagement
    static let notificationReceived    = "notification.received"
    static let notificationTapped      = "notification.tapped"
    static let deepLinkOpened          = "deep_link.opened"
    static let shareExtensionInvoked   = "share_extension.invoked"
    static let widgetTapped            = "widget.tapped"

    // 11. Feature flags
    static let experimentExposed       = "experiment.exposed"

    // Legacy aliases (kept for back-compat — emit both during migration)
    static let appLaunched             = "app.launched"
    static let onboardingStarted       = "onboarding.started"
    static let sessionStart            = "session.start"
    static let screenView              = "screen.view"
    static let paywallRestoreClick     = "paywall.restore_clicked"
    static let paywallRestoreSuccess   = "paywall.restore_success"
    static let restorePurchasesTapped  = "restore.tapped"  // alias
    static let accountDeleted          = "account.deleted"
    static let limitHit                = "limit.hit"
    static let goalChanged             = "goal.changed"
    static let reminderEnabled         = "reminder.enabled"
    static let presetSaved             = "preset.saved"
}

// MARK: - Feature flags (PostHog)

extension PortfolioAnalytics {
    /// Read a PostHog feature flag value. Returns the variant string if a
    /// multivariate flag, "true"/"false" for boolean, or nil if not set.
    /// Side-effect: emits `experiment.exposed` so PostHog knows the flag was
    /// actually consulted (drives accurate experiment reporting).
    func featureFlag(_ key: String) -> String? {
        guard started, !isOptedOut else { return nil }
        #if canImport(PostHog)
        let value = PostHogSDK.shared.getFeatureFlag(key)
        let variant: String?
        if let s = value as? String { variant = s }
        else if let b = value as? Bool { variant = b ? "true" : "false" }
        else { variant = nil }
        if let v = variant {
            track(PortfolioEvent.experimentExposed, ["flag_key": key, "variant": v])
        }
        return variant
        #else
        return nil
        #endif
    }
}

// MARK: - SwiftUI helpers

#if canImport(SwiftUI)
extension View {
    /// Fires `screen.viewed` on appear, `screen.dismissed` on disappear with
    /// dwell time. Use canonical snake_case screen names — the cohort tooling
    /// matches on the `screen` property.
    func trackScreen(_ name: String, fromScreen: String? = nil) -> some View {
        modifier(ScreenTrackingModifier(name: name, fromScreen: fromScreen))
    }
}

private struct ScreenTrackingModifier: ViewModifier {
    let name: String
    let fromScreen: String?
    @State private var appeared: Date?

    func body(content: Content) -> some View {
        content
            .onAppear {
                appeared = Date()
                var p: [String: Any] = ["screen": name]
                if let f = fromScreen { p["from_screen"] = f }
                PortfolioAnalytics.shared.track(PortfolioEvent.screenViewed, p)
            }
            .onDisappear {
                guard let appeared else { return }
                let secs = Date().timeIntervalSince(appeared)
                PortfolioAnalytics.shared.track(PortfolioEvent.screenDismissed,
                    ["screen": name, "seconds_on_screen": Int(secs)])
            }
    }
}
#endif

// Note: each app keeps its own `AnalyticsService` env (e.g. WalkCue's
// AnalyticsService.swift, HouseholdOS's AnalyticsEnvironment.swift). Those
// only debug-log; PostHog data flows exclusively through
// PortfolioAnalytics.shared.track(...). New spec wiring must use the static
// constants in PortfolioEvent above, never the per-app AnalyticsEvent enum.
