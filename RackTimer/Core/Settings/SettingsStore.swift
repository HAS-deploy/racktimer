import Foundation
import Combine

/// Persists user preferences in UserDefaults. Kept small; anything list-shaped
/// belongs in its own file-backed store.
@MainActor
final class SettingsStore: ObservableObject {

    private enum Keys {
        static let unit = "settings.unit"
        static let defaultBar = "settings.defaultBar"
        static let timerPresets = "settings.timerPresets"
        static let haptics = "settings.haptics"
        static let sound = "settings.sound"
        static let autoRestart = "settings.autoRestart"
        static let customPlatesLb = "settings.customPlatesLb"
        static let customPlatesKg = "settings.customPlatesKg"
    }

    @Published var unit: WeightUnit {
        didSet { defaults.set(unit.rawValue, forKey: Keys.unit) }
    }
    @Published var defaultBar: Double {
        didSet { defaults.set(defaultBar, forKey: Keys.defaultBar) }
    }
    @Published var timerPresets: [Int] {
        didSet { defaults.set(timerPresets, forKey: Keys.timerPresets) }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    @Published var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Keys.sound) }
    }
    @Published var autoRestart: Bool {
        didSet { defaults.set(autoRestart, forKey: Keys.autoRestart) }
    }
    /// Custom plate inventory (premium-only UI). Falls back to defaults when empty.
    @Published var customPlatesLb: [Double] {
        didSet { defaults.set(customPlatesLb, forKey: Keys.customPlatesLb) }
    }
    @Published var customPlatesKg: [Double] {
        didSet { defaults.set(customPlatesKg, forKey: Keys.customPlatesKg) }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let rawUnit = defaults.string(forKey: Keys.unit) ?? WeightUnit.pounds.rawValue
        let u = WeightUnit(rawValue: rawUnit) ?? .pounds
        self.unit = u
        self.defaultBar = defaults.object(forKey: Keys.defaultBar) as? Double
            ?? (PlateInventory.defaultBarWeight[u] ?? 45)
        self.timerPresets = (defaults.object(forKey: Keys.timerPresets) as? [Int]) ?? [60, 90, 120, 180]
        self.hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        self.soundEnabled = defaults.object(forKey: Keys.sound) as? Bool ?? true
        self.autoRestart = defaults.bool(forKey: Keys.autoRestart)
        self.customPlatesLb = (defaults.object(forKey: Keys.customPlatesLb) as? [Double]) ?? []
        self.customPlatesKg = (defaults.object(forKey: Keys.customPlatesKg) as? [Double]) ?? []
    }

    /// Returns the plate inventory to use for the current unit. Premium users
    /// with a custom roster override the defaults; everyone else sees the
    /// built-in set.
    func activePlates(premium: Bool) -> [Double] {
        if premium {
            let custom = unit == .pounds ? customPlatesLb : customPlatesKg
            if !custom.isEmpty { return custom }
        }
        return PlateInventory.defaults(for: unit)
    }
}
