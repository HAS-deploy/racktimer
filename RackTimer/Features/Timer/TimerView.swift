import SwiftUI

struct TimerView: View {
    @EnvironmentObject private var timer: RestTimerEngine
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.analytics) private var analytics

    @State private var showPlates = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Text(timer.remaining.minutesSeconds)
                    .font(.system(size: 120, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(timer.state == .finished ? Color.red : Color.primary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Rest timer remaining \(Int(timer.remaining)) seconds")

                stateLabel

                Spacer()

                presetsRow

                controlsRow

                Button("Plate calculator") { showPlates = true }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .padding(.top, 8)

                Spacer()
            }
            .padding()
            .navigationTitle("Rest Timer")
            .onChange(of: timer.state) { new in
                if new == .finished { finished() }
            }
            .sheet(isPresented: $showPlates) {
                NavigationStack { PlateCalculatorView() }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(source: "timer_advanced_presets")
            }
        }
    }

    // MARK: Subviews

    private var stateLabel: some View {
        Group {
            switch timer.state {
            case .idle: Text("Pick a preset to start").foregroundStyle(.secondary)
            case .running: Text("Resting").foregroundStyle(.secondary)
            case .paused: Text("Paused").foregroundStyle(.orange)
            case .finished: Text("Done").foregroundStyle(.red).bold()
            }
        }
        .font(.headline)
    }

    private var presetsRow: some View {
        HStack(spacing: 10) {
            ForEach(settings.timerPresets, id: \.self) { secs in
                Button {
                    analytics.track(.timerStarted, properties: ["duration": "\(secs)"])
                    PortfolioAnalytics.shared.track("timer.started", [
                        "duration_sec": secs,
                        "preset": "\(secs)s",
                    ])
                    timer.start(seconds: Double(secs))
                } label: {
                    VStack {
                        Text("\(secs / 60):\(String(format: "%02d", secs % 60))")
                            .font(.title3.weight(.bold))
                        Text("sec").font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(isAdvancedPreset(secs) ? .orange : .accentColor)
            }
            if !purchases.isPremium {
                Button {
                    analytics.track(.paywallViewed, properties: ["from": "timer_preset_plus"])
                    showPaywall = true
                } label: {
                    Image(systemName: "plus").frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Add preset (premium)")
            }
        }
    }

    /// Rough gate: presets > 180 s treated as advanced (premium visual cue).
    private func isAdvancedPreset(_ secs: Int) -> Bool { secs > 180 }

    private var controlsRow: some View {
        HStack(spacing: 12) {
            if timer.isRunning {
                Button("Pause") { timer.pause() }
                    .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
            } else if timer.isPaused {
                Button("Resume") { timer.resume() }
                    .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            } else {
                Button("Restart") {
                    analytics.track(.timerStarted, properties: ["duration": "\(Int(timer.lastDuration))"])
                    PortfolioAnalytics.shared.track("timer.started", [
                        "duration_sec": Int(timer.lastDuration),
                        "preset": "restart",
                    ])
                    timer.restart()
                }
                .buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
            }

            Button("Stop") { timer.stop() }
                .buttonStyle(.bordered).controlSize(.large).frame(maxWidth: .infinity)
                .disabled(timer.state == .idle)
        }
    }

    private func finished() {
        analytics.track(.timerCompleted, properties: ["duration": "\(Int(timer.lastDuration))"])
        PortfolioAnalytics.shared.track("timer.completed", [
            "duration_sec": Int(timer.lastDuration),
        ])
        if settings.hapticsEnabled {
            let g = UINotificationFeedbackGenerator()
            g.notificationOccurred(.success)
        }
        if settings.autoRestart {
            timer.restart()
        }
    }
}

#Preview {
    TimerView()
        .environmentObject(SettingsStore())
        .environmentObject(RestTimerEngine())
        .environmentObject(PurchaseManager())
}
