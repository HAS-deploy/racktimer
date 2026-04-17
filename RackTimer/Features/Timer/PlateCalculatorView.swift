import SwiftUI

struct PlateCalculatorView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var purchases: PurchaseManager
    @Environment(\.analytics) private var analytics
    @Environment(\.dismiss) private var dismiss

    @State private var targetText: String = ""
    @State private var barText: String = ""

    var body: some View {
        Form {
            Section {
                Picker("Unit", selection: $settings.unit) {
                    ForEach(WeightUnit.allCases) { u in
                        Text(u.shortLabel.uppercased()).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Target")
                    Spacer()
                    TextField("135", text: $targetText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
                HStack {
                    Text("Bar")
                    Spacer()
                    TextField("\(Int(settings.defaultBar))", text: $barText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                }
            } header: { Text("Target") } footer: {
                Text("All values in \(settings.unit.shortLabel).")
            }

            if let r = result {
                Section("Per side") {
                    if r.perSide.isEmpty {
                        Text("Just the bar").foregroundStyle(.secondary)
                    } else {
                        ForEach(grouped(r.perSide), id: \.weight) { row in
                            HStack {
                                Text(formatted(row.weight))
                                Spacer()
                                Text("× \(row.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Totals") {
                    row("Loaded", formatted(r.loadedTotal))
                    if r.underBy > 0.01 {
                        row("Short of target", "-\(formatted(r.underBy))")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .navigationTitle("Plates")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear {
            if barText.isEmpty { barText = String(Int(settings.defaultBar)) }
            analytics.track(.plateCalculatorUsed)
        }
    }

    // MARK: Derived

    private var result: PlateCalculator.Result? {
        guard let target = Double(targetText.replacingOccurrences(of: ",", with: ".")),
              target > 0 else { return nil }
        let bar = Double(barText.replacingOccurrences(of: ",", with: ".")) ?? settings.defaultBar
        let plates = settings.activePlates(premium: purchases.isPremium)
        return PlateCalculator.calculate(target: target, bar: bar, plates: plates)
    }

    private func formatted(_ v: Double) -> String {
        if v == v.rounded() { return "\(Int(v)) \(settings.unit.shortLabel)" }
        return String(format: "%.2f \(settings.unit.shortLabel)", v)
    }

    private func grouped(_ plates: [Double]) -> [(weight: Double, count: Int)] {
        var counts: [Double: Int] = [:]
        for p in plates { counts[p, default: 0] += 1 }
        return counts.keys.sorted(by: >).map { (weight: $0, count: counts[$0]!) }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack { Text(label); Spacer(); Text(value).foregroundStyle(.primary).monospacedDigit() }
    }
}
