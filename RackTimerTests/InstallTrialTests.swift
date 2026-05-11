import XCTest
@testable import RackTimer

/// Install-time trial entitlement: fresh installs get full Premium for 14
/// days. After day 14 the user drops back to the free tier, but all
/// previously-saved data (workout templates, history, PRs) is preserved.
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

    // MARK: 2) Trial inactive after 14 days

    func test_afterFourteenDays_trialEndsAndUserIsFree() {
        let install = Date(timeIntervalSince1970: 1_700_000_000)
        // Seed the install date 15 days in the past.
        defaults.set(install, forKey: PurchaseManager.firstLaunchAtKey)
        let later = Calendar.current.date(byAdding: .day, value: 15, to: install)!

        let pm = PurchaseManager(defaults: defaults, now: { later })

        XCTAssertFalse(pm.installTrialActive, "After 14 days the trial must end.")
        XCTAssertFalse(pm.isPremium, "Purchase flag still off.")
        XCTAssertFalse(pm.isEntitled, "Free tier — no entitlement after trial.")
    }

    // MARK: 3) Gate grants Pro during trial; revokes after

    func test_isEntitled_gateBehaviorAcrossTrialBoundary() {
        let install = Date(timeIntervalSince1970: 1_700_000_000)
        defaults.set(install, forKey: PurchaseManager.firstLaunchAtKey)

        // Day 0 — entitled via trial.
        let day0 = PurchaseManager(defaults: defaults, now: { install })
        XCTAssertTrue(day0.isEntitled, "Day 0 should be entitled (trial).")

        // Day 13 — still entitled (< 14).
        let day13 = Calendar.current.date(byAdding: .day, value: 13, to: install)!
        let mid = PurchaseManager(defaults: defaults, now: { day13 })
        XCTAssertTrue(mid.isEntitled, "Day 13 should still be entitled.")

        // Day 14 — trial ends (strictly less than 14 days elapsed required).
        let day14 = Calendar.current.date(byAdding: .day, value: 14, to: install)!
        let end = PurchaseManager(defaults: defaults, now: { day14 })
        XCTAssertFalse(end.isEntitled, "Day 14 should not be entitled.")
        XCTAssertFalse(end.installTrialActive)
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

        // --- Trial expires 15 days later. Same files, new stores. ---
        let later = Calendar.current.date(byAdding: .day, value: 15, to: install)!
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
