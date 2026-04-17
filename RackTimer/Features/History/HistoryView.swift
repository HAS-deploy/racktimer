import SwiftUI

struct HistoryView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var settings: SettingsStore
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            Group {
                if visible.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)
                        Text("No sets logged yet").font(.headline)
                        Text("Log a set on the Log tab and it'll show up here.")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(visible) { s in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(s.exercise).font(.headline)
                                    Spacer()
                                    Text(s.date, style: .date).font(.caption).foregroundStyle(.secondary)
                                }
                                HStack {
                                    Text("\(formatted(s.weight)) × \(s.reps)").monospacedDigit()
                                    if !s.note.isEmpty {
                                        Text("·").foregroundStyle(.secondary)
                                        Text(s.note).font(.caption).foregroundStyle(.secondary).italic()
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .onDelete { idx in
                            idx.map { visible[$0].id }.forEach(history.delete)
                        }
                        if !purchases.isPremium {
                            Section {
                                Button {
                                    showPaywall = true
                                } label: {
                                    HStack {
                                        Image(systemName: "lock.fill")
                                        Text("Unlock full history")
                                        Spacer()
                                    }
                                }
                            } footer: {
                                Text("Free tier shows the last \(PricingConfig.freeHistoryWindowDays) days.")
                            }
                        }
                    }
                }
            }
            .navigationTitle("History")
            .sheet(isPresented: $showPaywall) { PaywallView(source: "history_limit") }
        }
    }

    private var visible: [LoggedSet] {
        let days = purchases.isPremium ? nil : PricingConfig.freeHistoryWindowDays
        return history.visibleSets(maxDays: days)
    }

    private func formatted(_ v: Double) -> String {
        if v == v.rounded() { return "\(Int(v)) \(settings.unit.shortLabel)" }
        return String(format: "%.1f \(settings.unit.shortLabel)", v)
    }
}
