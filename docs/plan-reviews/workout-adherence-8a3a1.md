---
branch: workout-adherence-8a3a1
scope: ⑧ Batch 8 · UNIT 3-a1 (REG-1) — PRO stuck-on-free-expired-card fix (always-on; the first of the UNIT 3 three-way split: 3-a1 always-on fix · 3-a2 ship-dark plumbing · 3-b graduation choice UI)
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/workout-adherence-8a3a1-bpass.md
---

# Plan-review record — ⑧ UNIT 3-a1 (REG-1 PRO stuck-card fix)

Plan: `scratchpad/batch8_unit3_surfaces_plan.md` (UNIT 3 focused plan + ×2). §4.12 ×2 context-blind
review. **Converged — implemented.** ACCOUNT tier (auth splash + home/train subscription-conditional UI
+ a new shared service; no plan_engine/payment/RLS/migration surface). A genuine `fix:` → diagnose-doc
`a4e2d9` (`closes-diagnose`). NO feature flag — this is an ALWAYS-ON correctness fix, deliberately
independent of the ship-dark `enable_adherence_gate` repeat-content feature (that is 3-a2/3-b).

## Ground-truth verified (against code, this session, file:line)
- **Splash** `_autoGenerateNextPhaseForPro` (`splash_screen.dart:231-287` pre-fix): fired unawaited at
  `:204`; guards isPro `:242` + isPhaseExpired `:243`; profile defaults equipment=`bodyweight` `:249`,
  experience=`intermediate` `:251`; calls `autoGenerateNextPhaseIfNeeded` `:262`; catch `:284-286` was
  **`debugPrint`-only (NO telemetry, discards the failure)**; the comment `:199-203` FALSELY claimed
  "a race here … can't happen" (nothing awaits the unawaited call).
- **Home** `_buildTodayRow` (`home_screen.dart:724-732`): rendered `PlanExpiredCard` UNCONDITIONALLY on
  `schedule == null && isPhaseExpired()`; comment `:721` "PRO users never land here" is stale/false.
- **Train** `_buildContent` (`train/screen.dart:146-158`): the expired ternary rendered `PlanExpiredCard`
  for everyone (no PRO branch). `_buildRestHeroCard`/RECOVERY is the non-expired fallback (a naive
  suppress-for-PRO would strand them there — a silent dead-end).
- `subscriptionInfoProvider` (`profile_provider.dart:412`) — reactive `isPro` (H-1 pattern already used in
  `userStatsProvider` `:308`). `ErrorTelemetry.recordNonFatal(e, st, {reason})` (`error_telemetry.dart`).
  `PlanExpiredCard` is the free 3-door card (`plan_expired_card.dart`, "Deploy to Phase 2 — go PRO").
  Related bug: **b6e1c3** (Train gained the expired state) + **a1d4f9** (isPhaseExpired honors the
  materialized schedule) — REG-1 hardens that same surface for PRO.

## ×2 review (context-blind) — folded → converged
**Round 1 (needs-changes → 3-WAY SPLIT):** reviewed the whole UNIT 3 plan; verified all cited file:lines;
key reframe: **R1 (the card guard) is NOT ship-dark — it is an ALWAYS-ON production change** not covered
by `enable_adherence_gate`. Folded findings that shaped 3-a1: **[P1-3]** split R1 out as its own always-on
unit (3-a1); **[P1-4]** a naive `!isPro()` SUPPRESS drops the PRO to a silent RECOVERY dead-end — replace
with a PRO retry-CTA (not bare suppression) + add `ErrorTelemetry` to the splash catch (it was
`debugPrint`-only, fire-and-forget, so it can fail invisibly); **[P2-5]** use REACTIVE
`ref.watch(subscriptionInfoProvider).isPro`, not static `isPro()` (in-repo H-2 lesson). Result: 3-a1 =
the always-on REG-1 fix with its own diagnose-doc + review; 3-a2 (ship-dark plumbing) + 3-b (graduation
choice UI) follow as separate branches.
**Round 2 (on the hardened 3-a1 plan → converged, 7 amendments):** (1) extract a SHARED regenerate method
so the splash auto-path AND the card CTA run ONE code path (no duplicated read+generate+bump); (2) the PRO
retry-CTA replaces the dead-end on BOTH Home and Train; (3) `ErrorTelemetry.recordNonFatal` on the splash
catch; (4) reactive `isPro` watch; (5) fix the false splash "race can't happen" comment; (6) double-tap
guard on the CTA; (7) widget tests. All 7 implemented. Reviewer surfaced no NEW material issue on the
hardened plan → convergence signal.

## Converged design (implemented)
- `lib/shared/services/pro_phase_advance.dart` — `advanceProPhaseIfExpired(WidgetRef)`: faithful
  extraction of the splash body (same profile keys/defaults, same progress bump, same pushSnapshot),
  guarded by `isPro()` + `isPhaseExpired()` so redundant/concurrent calls no-op (cannot race the in-flight
  splash pass into a double-generate — once a phase is generated, `isPhaseExpired()` is false). Never
  swallows (throws) so each caller applies its own handling.
- `lib/features/train/widgets/phase_generating_card.dart` — `PhaseGeneratingCard`: Wardroom-styled (mirrors
  `PlanExpiredCard` tokens/voice), one-tap "Generate next phase" CTA calling the shared function, `_busy`
  double-tap guarded, `ErrorTelemetry` on failure, impression + tap events.
- Home + Train render `PhaseGeneratingCard` for a PRO on the expired branch (reactive isPro), `PlanExpiredCard`
  for free — the free path is byte-behaviorally unchanged (same props, same invalidation callbacks).
- Splash: method body collapses to `await advanceProPhaseIfExpired(ref)`; catch records
  `recordNonFatal(reason:'splash_auto_advance_phase')`; comment corrected. Two now-unused imports removed.

## Verdict: converged
`flutter analyze` clean on all 5 touched files (No issues found). `pro_phase_expiry_surface_test.dart`
green — **7/7** (5 source-anchored guard pins for Home/Train/splash/shared-fn/card + a BEHAVIORAL widget
pump proving `PhaseGeneratingCard` renders the actionable CTA). Diagnose `a4e2d9` validates. Home/Train are
heavy ConsumerWidgets whose full pump needs the whole provider graph → their guard is source-anchored per
the f8c0de precedent; the live functional check is the end-of-UNIT-3 web verify (Claude-in-Chrome, temp-PRO,
temporarily surface an expired PRO). Self-initiated ≥account B-pass runs on the implemented diff BEFORE the
`--no-ff` merge (§4.3); see `bpass_review`.
