# SHIP_NOTES_TRIAL — Install-trial standardization (2026-05-18)

Standardized RackTimer to the portfolio install-trial policy. Surgical
edits only — StoreKit plumbing (`Transaction.updates`, restore, product
IDs, `Configuration.storekit`) untouched.

## Spec
- Reference: `/Users/tony/Documents/portfolio-audit/INSTALL_TRIAL_SPEC.md`
- Canonical pattern: `RelationOS/Core/Purchases/IntroTrialClock.swift`

## Changes

### `RackTimer/Core/Pricing/PricingConfig.swift`
- `annualTrialDays`: **14 → 7** (portfolio policy).
- `annualTrialDescription`: dropped "14-day free trial, then $19.99/year"
  → "Auto-renews yearly · cancel anytime".
- `paywallSubtitle`: dropped "with a 14-day free trial" clause.
- File-level doc comment rewritten to describe the install-trial model
  (not an ASC introductory offer).

### `RackTimer/Core/Purchases/PurchaseManager.swift`
- Added `installTrialConsumedKey` static UserDefaults key
  (`"racktimer.installTrial.consumed"`).
- `recomputeInstallTrial()` now also requires the consumed flag to be
  false. Wired so once a paid purchase lands the trial flips off
  immediately on the next recompute.
- Added `consumeInstallTrial()` private helper.
- Added `installTrialDaysRemaining()` public method — rounded-up days
  remaining, used by paywall + settings banners (zero once consumed /
  expired).
- Wired `consumeInstallTrial()` into the verified-purchase success path
  in `purchase(_:)` and the entitlement-found path in
  `refreshEntitlements()`.
- `#if DEBUG`: `debugTogglePremium()` now consumes the trial when
  toggling premium **on**; added `debugResetInstallTrial()` for QA /
  screenshot builds.
- Highest-tier verified: all gating call sites
  (`TemplatesView`, `HistoryView`, `LogView`, `TimerView`,
  `PlateCalculatorView`, Settings preset add) read `isEntitled`, which
  remains `isPremium || installTrialActive`. During the trial users get
  the same surface coverage as paid Premium — no partial unlock.

### `RackTimer/Features/Paywall/PaywallView.swift`
- Removed "14-day free trial" copy from `paywallSubtitle` fallback.
- Install-trial banner rewritten — now reads "Your 7-day free Premium
  trial is active" + "N days left. Subscribe any time to keep Premium."
  Renders only while `installTrialActive` is true (so it hides once the
  trial is consumed by a paid purchase or has expired).
- Removed the inline 3.1.2(a) free-trial forfeiture sentence under the
  yearly card (it was tied to the now-deleted ASC intro offer).
- Removed the `disclosureFreeTrial` line from the legal footer block.
- `// MARK: - Yearly (with 14-day trial)` → `// MARK: - Yearly`.

### `RackTimer/Features/Settings/SettingsView.swift`
- Settings "Free trial active" row now appends "— N days left" using
  `installTrialDaysRemaining()`.

### `RackTimerTests/InstallTrialTests.swift`
- Doc-comment updated to reflect the 7-day policy.
- 14/15-day hardcodes replaced with `PricingConfig.annualTrialDays`
  references so the tests track the constant.
- New: `test_trialDuration_is7Days` asserts the portfolio policy.
- New: `test_paidPurchase_consumesInstallTrial` asserts the consumed
  flag flips the trial off.

## Not changed (intentionally)
- `Configuration.storekit` — still contains the `P2W` intro offer.
  That's local StoreKit-testing plumbing; production behavior is
  governed by ASC, which has been stripped per the spec. Leaving the
  local file alone per the "don't touch StoreKit plumbing" constraint.
- Product IDs (`ProductIDs.swift`) — untouched.
- Restore button, `Transaction.updates` listener — untouched.
- SwiftData / model schemas — n/a (RackTimer uses Codable file stores).
- No version-bump. No xcodebuild. No push.

## Verification checklist
- [x] Duration → 7 days (`PricingConfig.annualTrialDays = 7`).
- [x] Highest tier during trial — verified via `isEntitled` audit; all
      gating call sites grant full Premium coverage.
- [x] Cancel-on-paid — `consumeInstallTrial()` wired into both the
      `purchase(_:)` success branch and `refreshEntitlements()`.
- [x] Paywall drops "14-day free trial" copy; shows install-trial
      banner with days remaining; banner hides on consumed/expired.
- [x] Settings banner shows days remaining.
- [x] Tests updated; new consumed-on-paid test added.
