import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss

    /// Which feature surface triggered this paywall — goes into analytics.
    let source: String

    @State private var purchaseAttempted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 8)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)
                Text(PricingConfig.paywallTitle)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text(PricingConfig.paywallSubtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(PricingConfig.paywallBenefits, id: \.self) { b in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor)
                            Text(b)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                VStack(spacing: 12) {
                    yearlyCard
                    monthlyButton
                    lifetimeButton
                    Button("Restore purchases") {
                        analytics.track(.restorePurchasesTapped)
                        PortfolioAnalytics.shared.track(PortfolioEvent.paywallRestoreClick)
                        Task {
                            await purchases.restore()
                            if purchases.isPremium { dismiss() }
                        }
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.horizontal)

                legalFooter
            }
            .padding(.vertical)
        }
        .onAppear {
            analytics.track(.paywallViewed, properties: ["source": source])
            PortfolioAnalytics.shared.track(PortfolioEvent.paywallViewed, [
                "source": source,
            ])
        }
        .onDisappear {
            if !purchaseAttempted {
                PortfolioAnalytics.shared.track(PortfolioEvent.paywallDismissed, [
                    "source": source,
                ])
            }
        }
        .trackScreen("paywall")
    }

    // MARK: - Yearly (with 14-day trial)

    private var yearlyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                purchaseAttempted = true
                analytics.track(.purchaseStarted, properties: ["source": source, "product": "yearly"])
                PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseClick, [
                    "source": source,
                    "product_id": PricingConfig.annualProductID,
                ])
                Task {
                    let before = purchases.isPremium
                    await purchases.purchaseYearly()
                    if purchases.isPremium && !before {
                        analytics.track(.purchaseCompleted, properties: ["source": source, "product": "yearly"])
                        let product = purchases.yearlyProduct
                        let price = NSDecimalNumber(decimal: product?.price ?? 0).doubleValue
                        let productId = product?.id ?? PricingConfig.annualProductID
                        PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseSuccess, [
                            "is_sub": true,
                            "source": source,
                            "product_id": productId,
                            "revenue_usd": price,
                            "currency": product?.priceFormatStyle.currencyCode ?? "USD",
                        ])
                        if !UserDefaults.standard.bool(forKey: "posthog.identified") {
                            PortfolioAnalytics.shared.identifyAfterPurchase(productId: productId, revenueUsd: price)
                            UserDefaults.standard.set(true, forKey: "posthog.identified")
                        }
                        dismiss()
                    } else {
                        let reason: String
                        switch purchases.purchaseState {
                        case .cancelled:    reason = "user_cancelled"
                        case .pending:      reason = "pending_approval"
                        case .unknownState: reason = "storekit_unknown_case"
                        case .failed(let m):reason = m
                        default:            reason = "unknown"
                        }
                        PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseFailed, [
                            "is_sub": true,
                            "source": source,
                            "product_id": PricingConfig.annualProductID,
                            "reason": reason,
                        ])
                    }
                }
            } label: {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text("Yearly").font(.headline).foregroundStyle(.white)
                            Text("Best Value")
                                .font(.caption.bold())
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Color.white.opacity(0.22))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }
                        Text(PricingConfig.annualTrialDescription)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                    Text("\(purchases.yearlyDisplayPrice)/yr")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16).padding(.horizontal, 16)
                .background(Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(purchases.purchaseState == .purchasing)

            // 3.1.2(a) forfeiture sentence — rendered inline under the
            // trial offer so the reviewer sees it next to the buy button.
            // Paired with the same line in the bottom disclosure block.
            Text(PricingConfig.disclosureFreeTrial)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
    }

    // MARK: - Monthly

    private var monthlyButton: some View {
        Button {
            purchaseAttempted = true
            analytics.track(.purchaseStarted, properties: ["source": source, "product": "monthly"])
            PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseClick, [
                "source": source,
                "product_id": PricingConfig.monthlyProductID,
            ])
            Task {
                let before = purchases.isPremium
                await purchases.purchaseMonthly()
                if purchases.isPremium && !before {
                    analytics.track(.purchaseCompleted, properties: ["source": source, "product": "monthly"])
                    let product = purchases.monthlyProduct
                    let price = NSDecimalNumber(decimal: product?.price ?? 0).doubleValue
                    let productId = product?.id ?? PricingConfig.monthlyProductID
                    PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseSuccess, [
                        "is_sub": true,
                        "source": source,
                        "product_id": productId,
                        "revenue_usd": price,
                        "currency": product?.priceFormatStyle.currencyCode ?? "USD",
                    ])
                    if !UserDefaults.standard.bool(forKey: "posthog.identified") {
                        PortfolioAnalytics.shared.identifyAfterPurchase(productId: productId, revenueUsd: price)
                        UserDefaults.standard.set(true, forKey: "posthog.identified")
                    }
                    dismiss()
                } else {
                    let reason: String
                    switch purchases.purchaseState {
                    case .cancelled:    reason = "user_cancelled"
                    case .pending:      reason = "pending_approval"
                    case .unknownState: reason = "storekit_unknown_case"
                    case .failed(let m):reason = m
                    default:            reason = "unknown"
                    }
                    PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseFailed, [
                        "is_sub": true,
                        "source": source,
                        "product_id": PricingConfig.monthlyProductID,
                        "reason": reason,
                    ])
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly").font(.headline)
                    Text("Flexible — cancel anytime").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(purchases.monthlyDisplayPrice)/mo").font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
            )
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchaseState == .purchasing)
    }

    // MARK: - Lifetime

    private var lifetimeButton: some View {
        Button {
            purchaseAttempted = true
            analytics.track(.purchaseStarted, properties: ["source": source, "product": "lifetime"])
            PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseClick, [
                "source": source,
                "product_id": PricingConfig.lifetimeProductID,
            ])
            Task {
                let before = purchases.isPremium
                await purchases.purchaseLifetime()
                if purchases.isPremium && !before {
                    analytics.track(.purchaseCompleted, properties: ["source": source, "product": "lifetime"])
                    let product = purchases.lifetimeProduct
                    let price = NSDecimalNumber(decimal: product?.price ?? 0).doubleValue
                    let productId = product?.id ?? PricingConfig.lifetimeProductID
                    PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseSuccess, [
                        "is_sub": false,
                        "source": source,
                        "product_id": productId,
                        "revenue_usd": price,
                        "currency": product?.priceFormatStyle.currencyCode ?? "USD",
                    ])
                    if !UserDefaults.standard.bool(forKey: "posthog.identified") {
                        PortfolioAnalytics.shared.identifyAfterPurchase(productId: productId, revenueUsd: price)
                        UserDefaults.standard.set(true, forKey: "posthog.identified")
                    }
                    dismiss()
                } else {
                    let reason: String
                    switch purchases.purchaseState {
                    case .cancelled:    reason = "user_cancelled"
                    case .pending:      reason = "pending_approval"
                    case .unknownState: reason = "storekit_unknown_case"
                    case .failed(let m):reason = m
                    default:            reason = "unknown"
                    }
                    PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseFailed, [
                        "is_sub": false,
                        "source": source,
                        "product_id": PricingConfig.lifetimeProductID,
                        "reason": reason,
                    ])
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifetime").font(.headline)
                    Text("One-time unlock · keep forever").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(purchases.lifetimeDisplayPrice).font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemBackground)))
            )
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchaseState == .purchasing)
    }

    // MARK: - Legal footer (3.1.2(a) disclosure block, verbatim from PricingConfig)

    private var legalFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Auto-renewing subscriptions (RackTimer Premium Monthly, RackTimer Premium Yearly)")
                .font(.footnote).fontWeight(.semibold)
            // 3.1.2(a) disclosure block — rendered VERBATIM from
            // PricingConfig so paywall copy + ASC metadata stay in lockstep.
            // The free-trial forfeiture sentence appears here AND inline
            // under the yearly card per the canonical pattern.
            VStack(alignment: .leading, spacing: 4) {
                Text("• " + PricingConfig.disclosurePaymentCharged)
                Text("• " + PricingConfig.disclosureAutoRenew)
                Text("• " + PricingConfig.disclosureRenewalCharge)
                Text("• " + PricingConfig.disclosureManage)
                Text("• " + PricingConfig.disclosureFreeTrial)
                Text("• RackTimer Lifetime is a one-time non-consumable purchase with no recurring charges.")
            }
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Link("Terms of Use (EULA)", destination: URL(string: PricingConfig.appleStdEULAURL)!)
                Text("·")
                Link("Privacy Policy", destination: URL(string: PricingConfig.privacyPolicyURL)!)
            }
            .font(.caption2)
        }
        .padding(.horizontal)
        .padding(.bottom)
    }
}
