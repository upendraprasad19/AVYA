---
bug_id: a4e2d9
date: 2026-07-18
batch: workout-adherence-8a3a1 (Batch 8 · UNIT 3-a1 · REG-1)
status: fixed
blast_radius: account
symptom: >
  REG-1 (surfaced by the Batch-8 W2.5 regression audit). A PRO user whose phase
  has expired is auto-advanced to the next phase by a SILENT splash pass
  (`_autoGenerateNextPhaseForPro`), which is fired unawaited fire-and-forget and
  swallows any error in a `debugPrint`. When that pass fails or is still in
  flight as Home/Train build (both real: it is not awaited, and it can throw),
  the PRO lands on the FREE-tier `PlanExpiredCard` — a "Deploy to Phase 2 — go
  PRO" upsell — because that branch (`home_screen.dart` `_buildTodayRow`,
  `train/screen.dart` `_buildContent`) rendered the free card unconditionally on
  `schedule == null && isPhaseExpired()`, with a stale comment asserting "PRO
  users never land here". Naively suppressing the card for PRO instead drops
  them to a silent RECOVERY rest-day card with no recourse. Either way a paying
  user is stranded with no working way to get their next phase.
concept: plan_phase_expiry
sot_registry_entry: >
  plan_phase_expiry (the existing expiry surface hardened by b6e1c3). No NEW
  data writer/reader contract — REG-1 is a UI-reachability guard on the same
  surface plus an extraction of the (already-correct) splash advance logic into
  a shared function. No gate logic, subscription state, or persisted key changes.
writers: >
  The next-phase generation itself is unchanged
  { file: lib/core/services/workout_schedule_service.dart, method: autoGenerateNextPhaseIfNeeded, line: 132 }.
  REG-1 extracts the splash read+generate+bump into the shared
  { file: lib/shared/services/pro_phase_advance.dart, method: advanceProPhaseIfExpired, line: 33 }
  (guarded by isPro() + isPhaseExpired(), so redundant/concurrent calls no-op),
  called by BOTH the splash auto-path and the card CTA
  { file: lib/features/train/widgets/phase_generating_card.dart, method: _generate, line: 51 }.
readers: >
  The expiry-surface RENDER guard now reads subscription state REACTIVELY (H-1)
  and routes a PRO to PhaseGeneratingCard instead of PlanExpiredCard:
  { file: lib/features/home/screens/home_screen.dart, method: _buildTodayRow, line: 726 } and
  { file: lib/features/train/screens/train/screen.dart, method: _buildContent, line: 146 }.
  Free users still get PlanExpiredCard (unchanged).
hive_key_prefix: "n/a — no Hive key added/changed (reuses existing user_progress reads)"
hive_key_formula: "n/a — UI guard + logic extraction only"
sync_methods: ["pushSnapshot (unchanged — fired after a successful advance, as before)"]
restore_methods: ["n/a — no persisted state added"]
cloud_table: user_progress
cloud_columns: ["current_phase", "plan_generated_at", "phase_started_at"]
contract_test_path: test/contracts/pro_phase_expiry_surface_test.dart
ist_handling: >
  n/a — no date-key handling. The advance stamps plan_generated_at/
  phase_started_at with DateTime.now().toIso8601String() exactly as the prior
  splash code did (unchanged behavior).
provider_invalidations:
  - todayWorkoutProvider
  - currentPlanProvider
  - selectedWeekProvider
telemetry_op_types:
  success:
    - pro_phase_generate_tapped
    - pro_phase_generate_succeeded
    - pro_phase_generating_card_seen
  failure:
    - splash_auto_advance_phase
    - pro_phase_generate_card
cross_account_guard: false
forbidden_patterns_checked:
  - "The expired-branch render must NOT show a PRO the free go-PRO PlanExpiredCard, and must NOT silently suppress it into a dead-end RECOVERY card. FIXED: Home + Train gate on reactive `ref.watch(subscriptionInfoProvider).isPro` → PhaseGeneratingCard (a one-tap regenerate) for PRO, PlanExpiredCard for free. Pinned by pro_phase_expiry_surface_test.dart (isPro→PhaseGeneratingCard on both surfaces; PlanExpiredCard retained for free)."
  - "The unawaited splash advance must NOT swallow its failure in a debugPrint. FIXED: the catch records ErrorTelemetry.recordNonFatal(reason: 'splash_auto_advance_phase'); the old `debugPrint('[splash._autoGenerateNextPhaseForPro]` is ABSENT (asserted by the test)."
  - "The card's generate CTA must be double-tap guarded so a re-tap cannot double-generate. FIXED: `_generate` early-returns on `_busy`; pinned by the test."
proposed_fix: >
  (a) Extract the splash read→autoGenerateNextPhaseIfNeeded→bump-progress body
  into a shared `advanceProPhaseIfExpired(WidgetRef)` in lib/shared/services/
  (guarded by isPro()+isPhaseExpired() so it is safe to call redundantly and
  cannot race the in-flight splash pass into a double-generate). (b) Add a PRO
  `PhaseGeneratingCard` (Wardroom-styled, mirrors PlanExpiredCard tokens/voice)
  whose one-tap CTA calls the shared function, double-tap guarded, telemetered on
  failure. (c) Home + Train render PhaseGeneratingCard for a PRO on the expired
  branch (reactive isPro, H-1) and PlanExpiredCard for free — no change to the
  free path. (d) The splash catch records the failure via ErrorTelemetry instead
  of a swallowed debugPrint, and its false "a race can't happen" comment is
  corrected. No flag (this is an always-on correctness fix, NOT part of the
  ship-dark enable_adherence_gate feature). No gate/subscription/schema change.
regression_test_planned: >
  test/contracts/pro_phase_expiry_surface_test.dart — (1) SOURCE-anchored
  (comment-stripped): Home + Train route a PRO to PhaseGeneratingCard via
  reactive subscriptionInfoProvider.isPro while retaining PlanExpiredCard for
  free; splash calls advanceProPhaseIfExpired + records
  'splash_auto_advance_phase' and the old debugPrint swallow is absent; the
  shared function is isPro()+isPhaseExpired() gated; the card is `_busy` double-
  tap guarded + telemetered. (2) BEHAVIORAL widget pump: PhaseGeneratingCard
  renders the actionable "Generate next phase" CTA (proves the paying user has a
  tappable way forward — the crux of REG-1). Home/Train are heavy ConsumerWidgets
  whose full pump needs the whole provider graph, so their guard is source-
  anchored per the f8c0de precedent; end-of-batch web verify is the live check.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "new lib/shared/services/pro_phase_advance.dart + lib/features/train/widgets/phase_generating_card.dart; home_screen + train screen PRO-branch guards; splash telemetry + comment fix. flutter analyze clean on all 5 touched files (No issues found). pro_phase_expiry_surface_test.dart green (7/7 incl. the widget pump)." }
  - { tier: 2, layer: hive_local, status: not_applicable, evidence: "no Hive key added/changed; the advance reuses the existing user_progress reads/writes verbatim." }
  - { tier: 12, layer: client_to_server_contract, status: not_applicable, evidence: "no request/body/gate change; pushSnapshot fires after a successful advance exactly as the prior splash code did." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "no schema change." }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: not_applicable, evidence: "client-only; no Edge Function touched." }
  - { tier: 8, layer: rls_policies, status: not_applicable, evidence: "no RLS-touching change." }
impact_analysis: >
  Account blast radius (subscription-conditional UI on Home + Train + a splash
  telemetry fix). Every PRO user whose silent splash auto-advance failed or raced
  used to be stranded on the free "go PRO" PlanExpiredCard (or, under naive
  suppression, a dead-end RECOVERY card) with no working way to get their next
  phase — a paying-user dead-end that was ALSO invisible (the failure was
  swallowed in a debugPrint). Post-fix they get a one-tap PhaseGeneratingCard and
  the failure is recorded. Free-tier behavior is unchanged (still the 3-door
  PlanExpiredCard). This is an always-on correctness fix, independent of the
  ship-dark adherence-gate repeat-content feature (UNIT 3-a2/3-b). Related:
  b6e1c3 (Train gained the expired state) and a1d4f9 (isPhaseExpired honors the
  materialized schedule) — REG-1 hardens that same surface for PRO users.
---

# a4e2d9 — PRO stranded on the free "go PRO" card when the silent phase auto-advance fails/races (REG-1)

See YAML frontmatter for the full diagnosis.

## Root cause (one line)
The PRO next-phase advance runs as an unawaited, debugPrint-swallowing splash
pass; when it fails or is still in flight, Home + Train rendered the free-tier
`PlanExpiredCard` unconditionally on `schedule == null && isPhaseExpired()` (a
comment even claimed "PRO users never land here") — so a paying user hit a
"go PRO" upsell, or, under naive suppression, a silent RECOVERY dead-end.

## Fix (always-on, no flag)
1. Extract the splash read→generate→bump logic into a shared
   `advanceProPhaseIfExpired(WidgetRef)` (`lib/shared/services/pro_phase_advance.dart`),
   guarded by `isPro()` + `isPhaseExpired()` so redundant/concurrent calls no-op
   (it cannot race the in-flight splash pass into a double-generate).
2. New `PhaseGeneratingCard` (`lib/features/train/widgets/`) — a Wardroom-styled
   one-tap regenerate CTA (double-tap guarded, telemetered) that calls the shared
   function.
3. Home + Train render `PhaseGeneratingCard` for a PRO on the expired branch
   (reactive `subscriptionInfoProvider.isPro`, H-1) and `PlanExpiredCard` for
   free — the free path is untouched.
4. The splash catch records `ErrorTelemetry.recordNonFatal(reason:
   'splash_auto_advance_phase')` instead of a swallowed `debugPrint`; the false
   "a race can't happen" comment is corrected to describe the real fallback.

## Test
`test/contracts/pro_phase_expiry_surface_test.dart` — source-anchored guard pins
(Home/Train/splash/shared-fn/card) + a behavioral widget pump proving
`PhaseGeneratingCard` renders the actionable CTA. End-of-batch web verify (via
Claude-in-Chrome, temp-PRO) is the live functional check.

## See also
- b6e1c3 — Train gained the plan-expired state (the surface this hardens).
- a1d4f9 — `isPhaseExpired()` honors the materialized schedule.
- UNIT 3-a2/3-b — the ship-dark adherence-gate repeat-content feature this fix is
  deliberately independent of.
