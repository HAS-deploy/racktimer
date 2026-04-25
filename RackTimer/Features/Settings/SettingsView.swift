import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.analytics) private var analytics

    @State private var showPaywall = false
    @State private var status: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if purchases.isPremium {
                        Label("Premium unlocked", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Button {
                            analytics.track(.paywallViewed, properties: ["from": "settings"])
                            showPaywall = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Unlock everything").font(.headline)
                                    Text("One-time \(purchases.lifetimeDisplayPrice). No subscription.")
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

                Section("Timer") {
                    ForEach(Array(settings.timerPresets.enumerated()), id: \.offset) { idx, secs in
                        Stepper("Preset \(idx + 1): \(secs)s", value: Binding(
                            get: { settings.timerPresets[idx] },
                            set: { settings.timerPresets[idx] = $0 }
                        ), in: 10...600, step: 10)
                    }
                    Toggle("Auto-restart", isOn: $settings.autoRestart)
                    Toggle("Haptics", isOn: $settings.hapticsEnabled)
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.marketingVersion)
                    Link("Privacy policy", destination: URL(string: "https://has-deploy.github.io/racktimer/privacy.html")!)
                    Link("Support", destination: URL(string: "https://has-deploy.github.io/racktimer/support.html")!)
                }

                Section {
                    Link(destination: URL(string: "https://apps.apple.com/app/id6762468976")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("WalkCue").font(.body).foregroundStyle(.primary)
                            Text("Step-by-step audio cues for your walks.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://apps.apple.com/app/id6762470335")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("HydroLite").font(.body).foregroundStyle(.primary)
                            Text("Simple, friendly hydration tracking.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Link(destination: URL(string: "https://apps.apple.com/app/id6762465676")!) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SleepWindow").font(.body).foregroundStyle(.primary)
                            Text("Personalized bed/wake windows.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
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
        }
    }
}

private extension Bundle {
    var marketingVersion: String {
        (infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0.0"
    }
}
