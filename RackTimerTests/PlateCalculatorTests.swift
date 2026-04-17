import XCTest
@testable import RackTimer

final class PlateCalculatorTests: XCTestCase {

    func test135WithStandardLbPlates() {
        // 135 - 45 bar = 90, /2 = 45 per side → one 45.
        let r = PlateCalculator.calculate(target: 135, bar: 45, plates: PlateInventory.defaultPoundPlates)
        XCTAssertEqual(r.perSide, [45])
        XCTAssertEqual(r.loadedTotal, 135)
        XCTAssertEqual(r.underBy, 0)
    }

    func test225WithStandardLbPlates() {
        // 225 - 45 = 180, /2 = 90 per side → 45 + 45.
        let r = PlateCalculator.calculate(target: 225, bar: 45, plates: PlateInventory.defaultPoundPlates)
        XCTAssertEqual(r.perSide, [45, 45])
        XCTAssertEqual(r.loadedTotal, 225)
    }

    func test315WithStandardLbPlates() {
        // 315 - 45 = 270, /2 = 135 per side → 45+45+25+10+10 (or similar greedy).
        let r = PlateCalculator.calculate(target: 315, bar: 45, plates: PlateInventory.defaultPoundPlates)
        XCTAssertEqual(r.perSide.reduce(0, +), 135)
        XCTAssertEqual(r.loadedTotal, 315)
    }

    func testUnderBarReportsNothing() {
        let r = PlateCalculator.calculate(target: 30, bar: 45, plates: PlateInventory.defaultPoundPlates)
        XCTAssertTrue(r.perSide.isEmpty)
        XCTAssertEqual(r.loadedTotal, 45)
    }

    func testOddTargetReportsUnderBy() {
        // 100 - 45 = 55, /2 = 27.5 per side. Greedy with [25, 2.5] → 27.5 exact.
        let r = PlateCalculator.calculate(target: 100, bar: 45, plates: [45, 25, 10, 5, 2.5])
        XCTAssertEqual(r.perSide, [25, 2.5])
        XCTAssertEqual(r.underBy, 0)
    }

    func testLimitedInventoryReportsUnderBy() {
        // Only 45s available, target 225, bar 45 → 90/side needs 45+45.
        let r = PlateCalculator.calculate(target: 315, bar: 45, plates: [45, 45])
        // Only two 45s available total (per side). perSide uses them.
        XCTAssertEqual(r.perSide, [45, 45])
        XCTAssertEqual(r.loadedTotal, 225)
        XCTAssertEqual(r.underBy, 90)
    }

    func testKgPlates() {
        // 100 kg target, 20 kg bar → 80/2 = 40 per side → 20+20.
        let r = PlateCalculator.calculate(target: 100, bar: 20, plates: PlateInventory.defaultKilogramPlates)
        XCTAssertEqual(r.perSide.reduce(0, +), 40)
        XCTAssertEqual(r.loadedTotal, 100)
    }

    func testNegativeTargetSafe() {
        let r = PlateCalculator.calculate(target: -50, bar: 45, plates: PlateInventory.defaultPoundPlates)
        XCTAssertTrue(r.perSide.isEmpty)
    }
}
