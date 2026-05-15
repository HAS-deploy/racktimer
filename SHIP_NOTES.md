# RackTimer — Portfolio Audit Fix Report

**Date:** 2026-05-15
**Branch base:** master @ 16b34f3
**Audit doc:** `/Users/tony/Documents/portfolio-audit/02-racktimer.md`

## Summary

- **2 HARDs fixed** (in-app surfaces; ASC metadata still needs owner action)
- **4 SIGNIFICANTs fixed**
- **4 POLISH fixed**
- **0 DEFERRED** (code-side)
- **2 ASC metadata edits required** by owner (see below)

## Per-finding status

### H1 — Advertised "Premium Lifetime $14.99" cannot be purchased
**FIXED in-app** via `RackTimer/Features/Paywall/PaywallView.swift` + `RackTimer/Features/Settings/SettingsView.swift`. The lifetime button now only renders when `purchases.lifetimeProduct != nil` (StoreKit actually returned it). Paywall subtitle and Settings upsell copy both swap to a yearly/monthly-only wording when lifetime is unavailable. The "non-consumable purchase with no recurring charges" bullet in the legal footer is also gated.

**ASC ACTION REQUIRED:** Either (a) create the non-consumable IAP `com.racktimer.app.lifetime` in App Store Connect and submit for review, OR (b) remove the "Premium Lifetime $14.99 (one-time)" line from the App Store description. Until one of those happens, premium users on the live build see yearly+monthly only — the lifetime promise in the description is unfulfilled even though the in-app failure mode is now closed.

### H2 — Undisclosed 14-day install-time trial
**FIXED in-app** via `RackTimer/Features/Paywall/PaywallView.swift`. Added an explicit "Your install-time free trial is active — Premium unlocked for the first 14 days, no card required" banner inside the paywall when `installTrialActive == true`. Closes the in-app surprise gap.

**ASC ACTION REQUIRED:** Add a sentence to the App Store description's pricing block clarifying the trial, e.g. **"All Premium features are unlocked for 14 days after install — no card required. After that, choose Yearly (with its own 14-day free trial), Monthly, or stay on Free."** Without that the description still reads "Free=capped" while the install-time trial silently grants premium for 2 weeks, leaving the description ↔ implementation drift the audit flagged. Removing `installTrialActive` from `isEntitled` was the alternative but would rug-pull current trial users mid-flight — not taken.

### S1 — "Advanced timer presets" was just 4 fixed steppers
**FIXED** via `RackTimer/Features/Settings/SettingsView.swift`. Entitled users get an "Add preset" button (up to 8 total) and a "Remove last preset" destructive button (down to 1). Backed by the existing `[Int]` settings.timerPresets. New presets auto-suggest +30 s above the previous last value, clamped to 10–600 s. Fires `PortfolioEvent.presetSaved` for analytics.

### S2 — Analytics opt-out toggle missing
**FIXED** via `RackTimer/Features/Settings/SettingsView.swift`. Added a "Share anonymous usage analytics" toggle in a new "Privacy" section. Bound to `@AppStorage("portfolio.analytics.opted_out")` so flips call `PortfolioAnalytics.shared.optIn()` / `optOut()` and immediately short-circuit `track()` via the existing UserDefaults flag.

### S3 — No "Manage Subscription" link in Settings
**FIXED** via `RackTimer/Features/Settings/SettingsView.swift`. Premium users now see a "Manage subscription" button in the RackTimer Premium section that invokes `AppStore.showManageSubscriptions(in:)` on the active window scene.

### S4 — Privacy URL inconsistency
**FIXED** via `RackTimer/Core/Pricing/PricingConfig.swift` + `RackTimer/Features/Settings/SettingsView.swift`. Settings now links to `PricingConfig.privacyPolicyURL` (the same URL the paywall footer uses) and a new `PricingConfig.supportURL` constant. Removed the hard-coded `privacy.html` and `support.html` strings in SettingsView.

**Owner cleanup (no code change needed):** `docs/privacy.html` (the old short version) is now unreferenced by the app. Recommend either deleting it or 301-redirecting to `privacy-policy.html` to avoid future drift.

### P1 — Dead `soundEnabled` preference
**FIXED** via `RackTimer/Core/Settings/SettingsStore.swift` (already declared), `RackTimer/Features/Settings/SettingsView.swift` (now surfaced as a "Notification sound" toggle), `RackTimer/Core/Timer/BackgroundTimerNotifier.swift` (now reads a `soundEnabled` closure at schedule time and sets `content.sound = nil` when off), `RackTimer/Core/Timer/RestTimerEngine.swift` (forwards the closure to its default notifier), and `RackTimer/LiftTimerApp.swift` (wires the closure to the SettingsStore).

### P2 — Background-alert toggle has no permission-recovery affordance
**FIXED** via `RackTimer/Features/Settings/SettingsView.swift`. Reads `UNUserNotificationCenter.notificationSettings()` on appear + on `didBecomeActive`. When the user has Background alerts ON but OS notification permission is `.denied` or `.notDetermined`, a "Notifications are off — Enable in iOS Settings to receive rest-complete alerts" row appears below the toggle, tapping it deep-links to `UIApplication.openSettingsURLString`.

### P3 — Cross-app promo links use bare numeric IDs / no analytics
**FIXED** via `RackTimer/Features/Settings/SettingsView.swift`. Each cross-app row is now a Button that fires `PortfolioEvent.settingsCrossAppLinkTapped` with `target_app` before opening the App Store URL. The URLs still point to the same numeric IDs from the audit.

### P4 — `RestTimerEngine.tick()` publishes at 10 Hz
**FIXED** via `RackTimer/Core/Timer/RestTimerEngine.swift`. Added a `lastEmittedSecond: Int = -1` and only call `objectWillChange.send()` when `Int(remaining.rounded(.down))` differs. Reset on `start()` and `resume()` so a fresh run emits immediately. Detects expiry without waiting for a second flip because the `remaining <= 0` branch still triggers state transition.

## ASC metadata edits required (no code change)

1. **App Store description — H1:** Remove the "Premium Lifetime $14.99 (one-time)" line from the description until the IAP is provisioned in ASC. Or, provision the IAP and submit it for review.
2. **App Store description — H2:** Add disclosure of the 14-day install-time trial to the description's pricing block.

## Files changed

- `RackTimer/Features/Paywall/PaywallView.swift` — H1 (lifetime button gate, subtitle, footer bullet), H2 (install-trial banner)
- `RackTimer/Features/Settings/SettingsView.swift` — H1 (upsell subtitle), S1 (add/remove preset), S2 (analytics toggle), S3 (manage subscription), S4 (PricingConfig URLs), P1 (sound toggle), P2 (notification recovery banner), P3 (cross-app button+analytics)
- `RackTimer/Core/Pricing/PricingConfig.swift` — S4 (added supportURL)
- `RackTimer/Core/Timer/BackgroundTimerNotifier.swift` — P1 (soundEnabled closure threaded through)
- `RackTimer/Core/Timer/RestTimerEngine.swift` — P1 (soundEnabled init param), P4 (lastEmittedSecond gate)
- `RackTimer/LiftTimerApp.swift` — P1 (wire SettingsStore.soundEnabled into RestTimerEngine)

## Risk notes

- StoreKit plumbing untouched. `Transaction.updates`, `currentEntitlements`, restore, typed failure mapping all left as-is per guidelines.
- No SwiftData `@Model` properties renamed; persistence schema untouched.
- Product IDs untouched (`com.racktimer.app.{monthly,yearly,lifetime}`).
- `RestTimerEngine.init` and `SystemBackgroundTimerNotifier.init` gained a `soundEnabled` parameter with a default of `{ true }`, so existing test call sites (`RackTimerTests/RestTimerEngineTests.swift`, `BackgroundTimerNotifierTests.swift`) compile unchanged and behave identically.
- Subtitle change in PaywallView is rendered from a computed property — fall-through still returns `PricingConfig.paywallSubtitle` when lifetime is available, so once the IAP is provisioned the legacy copy returns automatically without another code change.
- `installTrialActive` semantic unchanged — only the in-paywall banner was added. The audit's alternative (removing it from `isEntitled`) was deliberately not taken to avoid retroactively locking users currently in their trial window.
- Settings re-checks notification permission only on appear + foreground. A user who denies and never re-foregrounds will still see the recovery row stale=ON. Acceptable for first iteration.
