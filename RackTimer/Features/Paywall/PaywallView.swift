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

            Spacer()

            VStack(spacing: 12) {
                monthlyButton
                lifetimeButton
                Button("Restore purchases") {
                    analytics.track(.restorePurchasesTapped)
                    Task {
                        await purchases.restore()
                        if purchases.isPremium { dismiss() }
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)

            VStack(alignment: .leading, spacing: 8) {
                Text("RackTimer Premium (Monthly) — \(purchases.monthlyDisplayPrice) per month, auto-renewing subscription. Payment is charged to your Apple ID at confirmation of purchase and renews each month unless canceled at least 24 hours before the end of the current period. Manage or cancel in your Apple ID Account Settings.")
                Text("RackTimer Lifetime — \(purchases.lifetimeDisplayPrice) one-time non-consumable purchase. No recurring charges.")
                Text("Restore purchases at any time from this screen.")
                HStack(spacing: 12) {
                    Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    Text("·")
                    Link("Privacy Policy", destination: URL(string: "https://has-deploy.github.io/racktimer/privacy-policy.html")!)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .padding(.vertical)
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
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly").font(.headline)
                    Text("Cancel anytime").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(purchases.monthlyDisplayPrice)/mo").font(.headline.monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12).padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.secondarySystemBackground)))
            )
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchaseState == .purchasing)
    }

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
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Lifetime").font(.headline).foregroundStyle(.white)
                    Text("Best value · pay once").font(.caption).foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Text(purchases.lifetimeDisplayPrice).font(.headline.monospacedDigit()).foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14).padding(.horizontal, 14)
            .background(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(purchases.purchaseState == .purchasing)
    }
}
