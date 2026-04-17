import SwiftUI

struct LogView: View {
    @EnvironmentObject private var history: HistoryStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var purchases: PurchaseManager
    @EnvironmentObject private var timer: RestTimerEngine
    @Environment(\.analytics) private var analytics

    @State private var exercise: String = ""
    @State private var weight: String = ""
    @State private var reps: String = ""
    @State private var note: String = ""
    @State private var showPaywall = false
    @FocusState private var focus: Field?

    enum Field: Hashable { case exercise, weight, reps, note }

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    TextField("Exercise name", text: $exercise)
                        .textInputAutocapitalization(.words)
                        .focused($focus, equals: .exercise)
                    if let last = recall {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Last time").font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text("\(formatted(last.weight)) × \(last.reps)")
                                    .font(.body.weight(.semibold)).monospacedDigit()
                                Spacer()
                                Text(last.date, style: .date).font(.caption).foregroundStyle(.secondary)
                            }
                            if !last.note.isEmpty {
                                Text(last.note).font(.caption2).foregroundStyle(.secondary).italic()
                            }
                            if !purchases.isPremium {
                                Text("Free tier shows the most recent \(PricingConfig.freeHistoryWindowDays) days.")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Set") {
                    HStack {
                        TextField("Weight", text: $weight)
                            .keyboardType(.decimalPad).focused($focus, equals: .weight)
                        Text(settings.unit.shortLabel).foregroundStyle(.secondary)
                    }
                    TextField("Reps", text: $reps)
                        .keyboardType(.numberPad).focused($focus, equals: .reps)
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3).focused($focus, equals: .note)
                }

                Section {
                    Button(action: save) {
                        Label("Save set", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!canSave)
                }
            }
            .navigationTitle("Log")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focus = nil }
                }
            }
            .sheet(isPresented: $showPaywall) { PaywallView(source: "log_recall") }
        }
    }

    // MARK: Derived

    private var canSave: Bool {
        let w = Double(weight.replacingOccurrences(of: ",", with: "."))
        let r = Int(reps)
        return !exercise.trimmingCharacters(in: .whitespaces).isEmpty && (w ?? 0) > 0 && (r ?? 0) > 0
    }

    private var recall: LoggedSet? {
        guard !exercise.isEmpty else { return nil }
        let max = purchases.isPremium ? nil : PricingConfig.freeHistoryWindowDays
        let scope = history.visibleSets(maxDays: max)
        return scope.first { $0.exercise.lowercased() == exercise.lowercased() }
    }

    // MARK: Actions

    private func save() {
        let w = Double(weight.replacingOccurrences(of: ",", with: ".")) ?? 0
        let r = Int(reps) ?? 0
        let set = LoggedSet(exercise: exercise.trimmingCharacters(in: .whitespaces),
                            weight: w, reps: r, note: note.trimmingCharacters(in: .whitespaces))
        history.add(set)
        analytics.track(.setLogged, properties: ["has_note": "\(!set.note.isEmpty)"])
        // Reset the set fields but keep the exercise name for the next set.
        weight = ""; reps = ""; note = ""
        focus = .weight
        if settings.hapticsEnabled {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        // Convenience — auto-start the default rest timer on save.
        let default_ = settings.timerPresets.first ?? 90
        timer.start(seconds: Double(default_))
    }

    private func formatted(_ v: Double) -> String {
        if v == v.rounded() { return "\(Int(v)) \(settings.unit.shortLabel)" }
        return String(format: "%.1f \(settings.unit.shortLabel)", v)
    }
}
