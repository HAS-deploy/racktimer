import SwiftUI
import StoreKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.analytics) private var analytics

    @State private var showPaywall = false
    @State private var status: String?
    @State private var notificationsAuthorized: Bool = true

    /// Bind the Settings analytics toggle directly to `PortfolioAnalytics`
    /// opt-out state so flipping the switch immediately stops capture even
    /// before the SDK is consulted (UserDefaults flag short-circuits track()).
    @AppStorage("portfolio.analytics.opted_out") private var optedOut: Bool = false
    private var analyticsEnabled: Binding<Bool> {
        Binding(
            get: { !optedOut },
            set: { newValue in
                if newValue {
                    PortfolioAnalytics.shared.optIn()
                } else {
                    PortfolioAnalytics.shared.optOut()
                }
            }
        )
    }

    /// Upsell subtitle on the Settings premium row. Falls back to a generic
    /// "Premium subscription" line when the lifetime IAP isn't provisioned
    /// (H1) so we don't advertise a price the user can't actually purchase.
    private var upsellSubtitle: String {
        if purchases.lifetimeProduct != nil {
            return "One-time \(purchases.lifetimeDisplayPrice). No subscription."
        }
        return "Yearly or monthly. Cancel anytime."
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if purchases.isPremium {
                        Label("Premium unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.accentColor)
                        // Pattern B — let subscribers manage / cancel from
                        // inside the app per 3.1.2 guidance.
                        Button("Manage subscription") {
                            Task {
                                let scenes = UIApplication.shared.connectedScenes
                                let active = scenes.first(where: { $0.activationState == .foregroundActive })
                                    as? UIWindowScene
                                let fallback = scenes.first as? UIWindowScene
                                if let scene = active ?? fallback {
                                    try? await AppStore.showManageSubscriptions(in: scene)
                                }
                            }
                        }
                    } else if purchases.installTrialActive {
                        Label("Free trial active", systemImage: "sparkles")
                            .foregroundStyle(Color.accentColor)
                        Button {
                            analytics.track(.paywallViewed, properties: ["from": "settings"])
                            showPaywall = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Keep Premium after trial").font(.headline)
                                    Text(upsellSubtitle)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Button {
                            analytics.track(.paywallViewed, properties: ["from": "settings"])
                            showPaywall = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Unlock everything").font(.headline)
                                    Text(upsellSubtitle)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                        }
                    }
                    // Restore is always visible — Apple's "reinstall then
                    // restore" review flow requires the button be reachable
                    // even after premium is active on the current device.
                    Button("Restore purchases") {
                        analytics.track(.restorePurchasesTapped)
                        Task {
                            await purchases.restore()
                            status = purchases.isPremium ? "Purchase restored." : "No previous purchases found."
                        }
                    }
                } header: { Text("RackTimer Premium") }

                Section("Units") {
                    Picker("Unit", selection: $settings.unit) {
                        ForEach(WeightUnit.allCases) { u in Text(u == .pounds ? "Pounds (lb)" : "Kilograms (kg)").tag(u) }
                    }
                    Stepper("Default bar: \(Int(settings.defaultBar)) \(settings.unit.shortLabel)",
                            value: $settings.defaultBar,
                            in: 10...100, step: settings.unit == .pounds ? 5 : 2.5)
                }

                Section {
                    ForEach(Array(settings.timerPresets.enumerated()), id: \.offset) { idx, secs in
                        Stepper("Preset \(idx + 1): \(secs)s", value: Binding(
                            get: { settings.timerPresets[idx] },
                            set: { settings.timerPresets[idx] = $0 }
                        ), in: 10...600, step: 10)
                    }
                    // S1 — premium-only Add/Remove preset affordance.
                    // Description's "Advanced timer presets" bullet promised
                    // beyond the fixed four; pre-fix premium users saw the
                    // exact same four steppers as free + the `+` button was
                    // merely suppressed. Now `isEntitled` users can append
                    // up to 8 total presets and delete any beyond the first.
                    if purchases.isEntitled {
                        if settings.timerPresets.count < 8 {
                            Button {
                                let suggested = (settings.timerPresets.last ?? 90) + 30
                                let clamped = max(10, min(600, suggested))
                                settings.timerPresets.append(clamped)
                                PortfolioAnalytics.shared.track(PortfolioEvent.presetSaved, [
                                    "preset_count": settings.timerPresets.count,
                                    "source": "settings_add",
                                ])
                            } label: {
                                Label("Add preset", systemImage: "plus.circle.fill")
                            }
                        }
                        if settings.timerPresets.count > 1 {
                            Button(role: .destructive) {
                                settings.timerPresets.removeLast()
                            } label: {
                                Label("Remove last preset", systemImage: "minus.circle")
                            }
                        }
                    }
                    Toggle("Auto-restart", isOn: $settings.autoRestart)
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                    // P1 — surface the previously-dead `soundEnabled`
                    // preference. SettingsStore already persists it; the
                    // BackgroundTimerNotifier now reads it at schedule time.
                    Toggle("Notification sound", isOn: $settings.soundEnabled)
                    Toggle("Background timer alerts", isOn: $settings.backgroundAlertsEnabled)
                    // P2 — if the user denied the notification permission,
                    // the Background-alerts toggle silently does nothing.
                    // Surface a recovery row that deep-links into iOS
                    // Settings → Notifications for this app.
                    if settings.backgroundAlertsEnabled && !notificationsAuthorized {
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Notifications are off")
                                        .font(.subheadline.weight(.semibold))
                                    Text("Enable in iOS Settings to receive rest-complete alerts.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "bell.slash.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: { Text("Timer") }

                Section("Privacy") {
                    // S2 — analytics opt-out toggle. Pre-fix the App Store
                    // description promised "anonymous, opt-out product
                    // analytics only" with no reachable control. The toggle
                    // writes the `portfolio.analytics.opted_out` UserDefault
                    // which PortfolioAnalytics.track() short-circuits on.
                    Toggle("Share anonymous usage analytics", isOn: analyticsEnabled)
                    Text("Helps us see which features are useful. No name, email, or set data ever leaves the device.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.marketingVersion)
                    // S4 — collapse to the single PricingConfig URLs so the
                    // paywall footer and Settings link the same documents.
                    Link("Privacy policy", destination: URL(string: PricingConfig.privacyPolicyURL)!)
                    Link("Support", destination: URL(string: PricingConfig.supportURL)!)
                }

                Section {
                    // P3 — wrap each cross-app link in a Button that fires
                    // settings.cross_app_link_tapped before opening the URL
                    // so we can measure cross-portfolio funnel attribution.
                    crossAppRow(name: "WalkCue",
                                targetApp: "walkcue",
                                appStoreID: "id6762468976",
                                blurb: "Step-by-step audio cues for your walks.")
                    crossAppRow(name: "HydroLite",
                                targetApp: "hydrolite",
                                appStoreID: "id6762470335",
                                blurb: "Simple, friendly hydration tracking.")
                    crossAppRow(name: "SleepWindow",
                                targetApp: "sleepwindow",
                                appStoreID: "id6762465676",
                                blurb: "Personalized bed/wake windows.")
                } header: { Text("More from us") } footer: {
                    Text("Other useful apps from the same team. Tap to open in the App Store.")
                }

                if let s = status {
                    Section { Text(s).foregroundStyle(.secondary) }
                }

                #if DEBUG
                Section("Developer") {
                    Button(purchases.isPremium ? "Disable premium (debug)" : "Enable premium (debug)") {
                        purchases.debugTogglePremium()
                    }
                }
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showPaywall) { PaywallView(source: "settings") }
            .task {
                await refreshNotificationAuthorization()
            }
            .onReceive(NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification)) { _ in
                Task { await refreshNotificationAuthorization() }
            }
        }
    }

    @ViewBuilder
    private func crossAppRow(name: String,
                             targetApp: String,
                             appStoreID: String,
                             blurb: String) -> some View {
        Button {
            PortfolioAnalytics.shared.track(
                PortfolioEvent.settingsCrossAppLinkTapped,
                ["target_app": targetApp]
            )
            if let url = URL(string: "https://apps.apple.com/app/\(appStoreID)") {
                UIApplication.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body).foregroundStyle(.primary)
                Text(blurb).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Re-read the OS notification authorization status. Called on appear
    /// and on `didBecomeActive` so toggling Settings → Notifications and
    /// returning updates the in-app banner.
    private func refreshNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                notificationsAuthorized = true
            case .denied, .notDetermined:
                notificationsAuthorized = false
            @unknown default:
                notificationsAuthorized = false
            }
        }
    }
}

private extension Bundle {
    var marketingVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
