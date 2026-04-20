import SwiftUI

struct PaywallView: View {
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss

    /// Which feature surface triggered this paywall — goes into analytics.
    let source: String

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
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

            VStack(spacing: 10) {
                Button {
                    analytics.track(.purchaseStarted, properties: ["source": source])
                    PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseClick, [
                        "source": source,
                    ])
                    Task {
                        let before = purchases.isPremium
                        await purchases.purchase()
                        if purchases.isPremium && !before {
                            analytics.track(.purchaseCompleted, properties: ["source": source])
                            PortfolioAnalytics.shared.track(PortfolioEvent.paywallPurchaseSuccess, [
                                "is_sub": false,
                                "source": source,
                            ])
                            dismiss()
                        }
                    }
                } label: {
                    Text("Unlock for \(purchases.lifetimeDisplayPrice)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

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

            Text("One-time purchase. No subscriptions or recurring charges.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
    }
}
