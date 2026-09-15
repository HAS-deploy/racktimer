import XCTest
@testable import RackTimer

/// Install-time trial entitlement (portfolio policy 2026-05-18): fresh
/// installs get the highest Premium tier for 14 days. After day 14 the user
/// drops back to the free tier, but all previously-saved data (workout
/// templates, history, PRs) is preserved. A paid purchase consumes the
/// trial immediately so we never double-grant.
@MainActor
final class InstallTrialTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suiteName = "racktimer.installtrial.tests"

    override func setUp() {
        super.setUp()
        UserDefaults().removePersistentDomain(forName: suiteName)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    // MARK: 0) Trial duration SoT (portfolio install-trial policy)

    func test_trialDuration_is14Days() {
        XCTAssertEqual(
            PricingConfig.annualTrialDays,
            14,
            "Install-trial SoT is 14 days; keep this assertion in lockstep with PricingConfig."
        )
    }

    // MARK: 1) Trial active on fresh install

    func test_freshInstall_grantsTrialAndEntitlement() {
        let now = Date()
        let pm = PurchaseManager(defaults: defaults, now: { now })

        XCTAssertTrue(pm.installTrialActive, "Fresh install must activate the trial.")
        XCTAssertFalse(pm.isPremium, "Trial should not flip the real-purchase flag.")
        XCTAssertTrue(pm.isEntitled, "Trial users must be entitled.")

        // First-launch timestamp must be persisted so subsequent launches
        // anchor the trial window to the original install date.
        XCTAssertNotNil(
            defaults.object(forKey: PurchaseManager.firstLaunchAtKey),
            "First-launch date must be written to UserDefaults."
        )
    }

    // MARK: 2) Trial inactive after the install-trial window

    func test_afterTrialWindow_trialEndsAndUserIsFree() {
        let install = Date(timeIntervalSince1970: 1_700_000_000)
        // Seed the install date (trialDays + 1) days in the past.
        defaults.set(install, forKey: PurchaseManager.firstLaunchAtKey)
        let later = Calendar.current.date(
            byAdding: .day,
            value: PricingConfig.annualTrialDays + 1,
            to: install
        )!

        let pm = PurchaseManager(defaults: defaults, now: { later })

        XCTAssertFalse(pm.installTrialActive,
                       "After the trial window the trial must end.")
        XCTAssertFalse(pm.isPremium, "Purchase flag still off.")
        XCTAssertFalse(pm.isEntitled, "Free tier — no entitlement after trial.")
    }

    // MARK: 3) Gate grants Pro during trial; revokes after

    func test_isEntitled_gateBehaviorAcrossTrialBoundary() {
        let install = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(install, forKey: PurchaseManager.firstLaunchAtKey)

        let trialDays = PricingConfig.annualTrialDays

        // Day 0 — entitled via trial.
        let day0 = PurchaseManager(defaults: defaults, now: { install })
        XCTAssertTrue(day0.isEntitled, "Day 0 should be entitled (trial).")

        // Day (trialDays - 1) — still entitled.
        let midDate = Calendar.current.date(byAdding: .day, value: trialDays - 1, to: install)!
        let mid = PurchaseManager(defaults: defaults, now: { midDate })
        XCTAssertTrue(mid.isEntitled,
                      "Day \(trialDays - 1) should still be entitled.")

        // Day trialDays — trial ends (strictly less than trialDays elapsed required).
        let endDate = Calendar.current.date(byAdding: .day, value: trialDays, to: install)!
        let end = PurchaseManager(defaults: defaults, now: { endDate })
        XCTAssertFalse(end.isEntitled,
                       "Day \(trialDays) should not be entitled.")
        XCTAssertFalse(end.installTrialActive)
    }

    // MARK: 3b) Trial duration is 14 days per portfolio policy 2026-05-18

    func test_trialDuration_is14Days() {
        XCTAssertEqual(PricingConfig.annualTrialDays, 14,
                       "Portfolio install-trial policy: 14 days.")
    }

    // MARK: 3c) Paid purchase consumes the install-trial (no double-trial)

    func test_paidPurchase_consumesInstallTrial() {
        let install = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(install, forKey: PurchaseManager.firstLaunchAtKey)

        let pm = PurchaseManager(defaults: defaults, now: { install })
        XCTAssertTrue(pm.installTrialActive, "Fresh install — trial active.")

        // Simulate the paid-purchase side-effect: PurchaseManager flips
        // the consumed flag in UserDefaults from inside `purchase(_:)` and
        // `refreshEntitlements()`.
        defaults.set(true, forKey: PurchaseManager.installTrialConsumedKey)
        pm.refreshInstallTrialForTesting()

        XCTAssertFalse(pm.installTrialActive,
                       "Trial must be consumed after a paid purchase.")
    }

    // MARK: 4) Data preserved across the trial boundary

    func test_trialExpiry_preservesTemplatesHistoryAndPRs() throws {
        let tmp = FileManager.default.temporaryDirectory
        let runID = UUID().uuidString
        let templatesURL = tmp.appendingPathComponent("templates-\(runID).json")
        let historyURL   = tmp.appendingPathComponent("history-\(runID).json")

        defer {
            try? FileManager.default.removeItem(at: templatesURL)
            try? FileManager.default.removeItem(at: historyURL)
        }

        // --- Inside the trial window: user creates templates + logs sets. ---
        let install = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(install, forKey: PurchaseManager.firstLaunchAtKey)
        let pmTrial = PurchaseManager(defaults: defaults, now: { install })
        XCTAssertTrue(pmTrial.installTrialActive)

        let templates = TemplateStore(fileURL: templatesURL)
        templates.add(WorkoutTemplate(name: "Upper A", exercises: ["Bench", "Row"]))
        templates.add(WorkoutTemplate(name: "Lower A", exercises: ["Squat", "RDL"]))

        let history = HistoryStore(fileURL: historyURL)
        // PR-worthy set logged during the trial.
        history.add(LoggedSet(exercise: "Bench", weight: 225, reps: 5, date: install))

        let templateCountBefore = templates.templates.count
        let historyCountBefore = history.sets.count
        let prBefore = history.sets.first { $0.exercise == "Bench" }?.weight

        // --- Trial expires past the trial window. Same files, new stores. ---
        let later = Calendar.current.date(
            byAdding: .day,
            value: PricingConfig.annualTrialDays + 1,
            to: install
        )!
        let pmPost = PurchaseManager(defaults: defaults, now: { later })
        XCTAssertFalse(pmPost.installTrialActive, "Trial must be over.")
        XCTAssertFalse(pmPost.isEntitled, "User should drop to free tier.")

        let templatesAfter = TemplateStore(fileURL: templatesURL)
        let historyAfter = HistoryStore(fileURL: historyURL)

        XCTAssertEqual(templatesAfter.templates.count, templateCountBefore,
                       "Templates must survive trial expiry.")
        XCTAssertEqual(historyAfter.sets.count, historyCountBefore,
                       "Logged sets must survive trial expiry.")
        XCTAssertEqual(historyAfter.sets.first { $0.exercise == "Bench" }?.weight, prBefore,
                       "PR data (heaviest Bench) must survive trial expiry.")
    }
}
