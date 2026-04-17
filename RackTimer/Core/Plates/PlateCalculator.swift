import Foundation

enum WeightUnit: String, Codable, CaseIterable, Identifiable {
    case pounds, kilograms
    var id: String { rawValue }
    var shortLabel: String { self == .pounds ? "lb" : "kg" }
}

/// Pure, stateless plate-math. Given a target total bar weight, a barbell
/// weight, and an inventory of plates-per-side, greedily determine the plate
/// combination required on *one* side (mirrored on the other).
enum PlateCalculator {

    struct Result: Equatable {
        let perSide: [Double]        // plate weights used on one side, descending
        let loadedTotal: Double      // bar + (2 × sum(perSide))
        let underBy: Double          // target − loadedTotal (≥ 0)
    }

    /// - Parameters:
    ///   - target: desired total weight on the bar (bar + plates).
    ///   - bar:    barbell weight (e.g. 45 lb / 20 kg). If `target < bar`, caller should handle.
    ///   - plates: available plate denominations per side (unordered); dupes mean multiples of that size.
    /// - Returns: greedy best-fit per-side combination (never over target).
    static func calculate(target: Double, bar: Double, plates: [Double]) -> Result {
        let targetClamped = max(0, target)
        guard targetClamped >= bar else {
            return Result(perSide: [], loadedTotal: bar, underBy: max(0, bar - targetClamped))
        }
        let perSideTarget = (targetClamped - bar) / 2
        // Each element of `plates` represents one physical plate available
        // on this side of the bar. Greedy descending fit that consumes each
        // plate at most once — respects finite inventory.
        let sorted = plates.sorted(by: >)
        var remaining = perSideTarget
        var used: [Double] = []
        for p in sorted {
            if p <= remaining + 1e-9 {
                used.append(p)
                remaining -= p
            }
        }
        let loaded = bar + 2 * used.reduce(0, +)
        return Result(
            perSide: used,
            loadedTotal: loaded,
            underBy: max(0, targetClamped - loaded),
        )
    }
}

enum PlateInventory {

    static let defaultPoundPlates: [Double] =
        [45, 45, 45, 45, 35, 25, 25, 10, 10, 5, 5, 2.5, 2.5]

    static let defaultKilogramPlates: [Double] =
        [25, 25, 20, 20, 15, 10, 10, 5, 5, 2.5, 2.5, 1.25, 1.25]

    static let defaultBarWeight: [WeightUnit: Double] = [
        .pounds: 45,
        .kilograms: 20,
    ]

    static func defaults(for unit: WeightUnit) -> [Double] {
        unit == .pounds ? defaultPoundPlates : defaultKilogramPlates
    }
}
