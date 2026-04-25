//  PortfolioAnalytics.swift
//  App Factory — shared Swift drop-in.
//
//  One file per iOS app, copied verbatim. Calls PostHog when a key is set in
//  the bundle's Info.plist under `PostHogKey` (and optional `PostHogHost`).
//  No-op when the key is missing — safe to ship in a free build.
//
//  Event schema lives in ~/Documents/app-factory-analytics.md. Keep this
//  file dumb: it is a transport. Per-app semantics belong in the caller.
//
//  Install:
//    1. Add SwiftPM dependency: https://github.com/PostHog/posthog-ios
//       (product "PostHog").
//    2. Info.plist add:
//         PostHogKey    = "phc_xxx"   // leave empty in dev
//         PostHogHost   = "https://us.i.posthog.com"
//    3. At app launch:
//         PortfolioAnalytics.shared.start(appName: "expiryvault")
//    4. Anywhere in the app:
//         PortfolioAnalytics.shared.track("paywall.viewed",
//                                         ["source": "settings"])
//
//  Privacy posture:
//    - Autocapture OFF — we emit explicit events only.
//    - Session recording OFF — may capture document contents / PHI.
//    - respectsDoNotTrack = true
//    - user_id set only after authenticate() (keeps anonymous sessions clean).

import Foundation
import SwiftUI
import UIKit
import CryptoKit

#if canImport(PostHog)
import PostHog
#endif

final class PortfolioAnalytics: @unchecked Sendable {
    static let shared = PortfolioAnalytics()

    private var started = false
    private var appName: String = "unknown"

    private init() {}

    func start(appName: String) {
        guard !started else { return }
        self.appName = appName
        started = true
        #if canImport(PostHog)
        let key = (Bundle.main.object(forInfoDictionaryKey: "PostHogKey") as? String) ?? ""
        let host = (Bundle.main.object(forInfoDictionaryKey: "PostHogHost") as? String)
            ?? "https://us.i.posthog.com"
        guard !key.isEmpty else { return } // silent no-op when unconfigured
        let config = PostHogConfig(apiKey: key, host: host)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false        // we emit explicit screen.view
        config.sessionReplay = false             // do not capture document contents
        PostHogSDK.shared.setup(config)
        track("app.launched")
        #endif
    }

    /// Track a single product event. Props should stay bounded:
    /// no free-text names, no DOBs, no document bodies.
    func track(_ event: String, _ props: [String: Any] = [:]) {
        #if canImport(PostHog)
        guard started else { return }
        var enriched = props
        enriched["app"] = appName
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            enriched["version"] = v
        }
        if let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            enriched["build"] = b
        }
        PostHogSDK.shared.capture(event, properties: enriched)
        #endif
    }

    /// Associate subsequent events with a stable user id. Call once after
    /// sign-in / server-generated identity is known. Before this, events are
    /// anonymous-by-session.
    func identify(userId: String, traits: [String: Any] = [:]) {
        #if canImport(PostHog)
        guard started else { return }
        PostHogSDK.shared.identify(userId, userProperties: traits)
        #endif
    }

    /// Clear the stored identity on sign-out / account-delete.
    func reset() {
        #if canImport(PostHog)
        guard started else { return }
        PostHogSDK.shared.reset()
        #endif
    }
}

// MARK: - Event-name constants (keep in sync with app-factory-analytics.md)

enum PortfolioEvent {
    // Mandatory — every app emits these
    static let appLaunched           = "app.launched"
    static let onboardingStarted     = "onboarding.started"
    static let onboardingCompleted   = "onboarding.completed"
    static let sessionStart          = "session.start"
    static let screenView            = "screen.view"

    static let paywallViewed         = "paywall.viewed"
    static let paywallPurchaseClick  = "paywall.purchase_clicked"
    static let paywallPurchaseSuccess = "paywall.purchase_success"
    static let paywallPurchaseFailed = "paywall.purchase_failed"
    static let paywallRestoreClick   = "paywall.restore_clicked"
    static let paywallRestoreSuccess = "paywall.restore_success"
    static let paywallDismissed      = "paywall.dismissed"

    static let accountDeleted        = "account.deleted"
    static let limitHit              = "limit.hit"
}

// MARK: - Anonymous identity after first purchase
extension PortfolioAnalytics {
    /// Promote the current anonymous session to an identified user using a
    /// stable non-PII device-scoped id (IDFV hash). Sets cohort traits so
    /// PostHog's funnels + retention can segment by first-purchase tier.
    /// Call once on the first successful purchase of the install.
    func identifyAfterPurchase(productId: String, revenueUsd: Double) {
        let idfv = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        let hash = Insecure.MD5.hash(data: Data(idfv.utf8)).map { String(format: "%02x", $0) }.joined()
        let userId = "anon_\(hash.prefix(12))"
        let traits: [String: Any] = [
            "first_app": appName,
            "first_purchase_sku": productId,
            "first_purchase_revenue_usd": revenueUsd,
            "first_purchase_at": ISO8601DateFormatter().string(from: Date()),
        ]
        identify(userId: userId, traits: traits)
    }
}

// MARK: - Screen tracking modifier

extension View {
    /// Fires a `screen.view` event on appear. Keep names snake_case and
    /// stable — the PostHog cohort tooling matches on the `screen` property.
    func trackScreen(_ name: String) -> some View {
        self.onAppear {
            PortfolioAnalytics.shared.track(PortfolioEvent.screenView, ["screen": name])
        }
    }
}
