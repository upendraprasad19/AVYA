---
bug_id: c4f9a1
date: 2026-09-16
batch: obs-batch-2026-09-16
status: fixed
blast_radius: account
symptom: >-
  Founder (a PRO user, Phase III) tapped week chip "W5" on the Train
  screen's roadmap header — a week in Phase IV, the phase after his current
  one. The screen showed the generic "No workouts scheduled / This week has
  no workouts in your plan" empty state, which reads like a bug/glitch. It
  is actually intentional: Phase IV genuinely has no generated schedule
  until Phase III is finished. Founder: "Instead of this we should say pro
  users that complete previous phase to unlock this phase etc. Something
  like this. What are other apps doing?"
concept: train_screen_future_phase_empty_state
recurrence: >-
  Not a recurrence — a genuinely new UX gap, though it sits adjacent to an
  EXISTING, already-shipped pattern for a DIFFERENT trigger. Investigated
  and confirmed: `lib/features/train/widgets/week_selector.dart` +
  `preview_workout_screen.dart` already implement "Complete Phase I to
  unlock Phase II" lock messaging (with a real dry-run-generated preview
  workout) — but ONLY for the free-vs-PRO subscription gate
  (`!isProUser && week >= 5` in `screen.dart`'s week-tap handler routes to
  `/train/preview`). A PRO user tapping ahead into a not-yet-reached future
  PHASE (as opposed to a not-yet-PAID-FOR phase) falls through to
  `ref.read(selectedWeekProvider.notifier).select(week)` unconditionally,
  which just shows whatever inline empty state `weekDays.isEmpty` produces
  — the generic one, with no phase-completion framing at all. This is the
  gap the founder's screenshot exposes.
sot_registry_entry: not_applicable — a display-only empty-state copy/branch, not a Hive/Postgres writer/reader concept.
writers:
  - { file: lib/core/utils/hold_week_labels.dart, method: futurePhaseUnlockCopy, line: 208 }
readers:
  - { file: lib/features/train/screens/train/screen.dart, method: "if (weekDays.isEmpty) _buildEmptyWeek(...)", line: 368 }
  - { file: lib/features/train/screens/train/empty_states.dart, method: _buildEmptyWeek, line: 47 }
  - { file: lib/features/train/screens/train/screen.dart, method: "else if (!(isFutureUngeneratedPhase(selectedWeek) && weekDays.isEmpty)) [WardCard status-line suppression, added by plan-review round 1, refined by round 2]", line: 194 }
hive_key_prefix: n/a — no Hive key participates
hive_key_formula: n/a
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/hold_week_labels_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "the generic 'No workouts scheduled' empty state rendering for a FUTURE-PHASE week (isFutureUngeneratedPhase(selectedWeek) == true) with no phase-completion framing", absent_after_fix: true }
proposed_fix: >-
  Deliberately did NOT replicate the full free-tier flow (routing to a
  separate `/train/preview` screen with a dry-run-generated workout) — that
  mechanism exists for the subscription gate specifically and reusing it for
  the phase-progress gate would require new routing logic to distinguish
  "not reached because you haven't paid" from "not reached because you
  haven't finished the current phase," a larger change than the reported
  gap calls for. Instead, fixed the INLINE empty-state CARD itself: added
  `isFutureUngeneratedPhase(selectedWeek)` (true when the selected week
  falls in a phase group beyond the current one — the 3-phase-group rolling
  window `week_selector.dart` already renders, weeks 1-4/5-8/9-12) and
  `futurePhaseUnlockCopy(currentPhase)` (title "Complete Phase X to unlock
  Phase Y" + subtitle, always naming the user's ACTUAL current phase
  regardless of how many phases ahead they tapped, since the plan engine
  only ever generates one phase ahead at a time) to
  `lib/core/utils/hold_week_labels.dart` — the established shared home for
  pure phase/week label formatters. `screen.dart`'s empty-state call site
  now passes both through; `_buildEmptyWeek` branches to a lock icon +
  this copy instead of the generic dumbbell/"No workouts scheduled" text
  when the week is in a future phase group. A same-phase empty week (all 4
  weeks of the current phase are normally generated together, so this is a
  rarer, different situation) still falls back to the original generic
  copy — deliberately not re-explained by this fix.
  Competitor pattern check (general knowledge, no live research needed):
  Fitbod, JuggernautAI, Ladder and Renaissance Periodization apps all use
  the same shape for phase/mesocycle gating — a lock icon + one line naming
  what unlocks it — never a bare empty state for intentionally-gated
  content.
regression_test_planned:
  - test/contracts/hold_week_labels_test.dart
  - test/contracts/train_phase_lock_empty_state_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter test test/contracts/hold_week_labels_test.dart test/contracts/train_phase_lock_empty_state_test.dart -> 40/40 passed. flutter analyze lib/ -> 0 errors/warnings, 0 issues attributed to screen.dart/empty_states.dart/hold_week_labels.dart. Mutation-proven (isFutureUngeneratedPhase): reverted to unconditionally return false -> exactly 2 of 40 assertions reddened (the 'weeks 5-8 ARE a future phase' and 'weeks 9-12 are ALSO a future phase' cases), the rest (including both structural wiring tests, which correctly stayed green since they assert the function is CALLED, not that its return value is truthful) stayed green; restored the fix and re-ran -> 40/40 green again. Mutation-proven (round-1 remediation): reverted 'else if (!isFutureUngeneratedPhase(selectedWeek))' to a bare 'else' in screen.dart, reran test/contracts/train_phase_lock_empty_state_test.dart ALONE -> exactly 1 of 4 assertions in that file reddened (the WardCard-suppression test; corrected from an earlier '1 of 3' claim here, caught stale by plan-review round 2 — the file has 4 tests, not 3); restored and reran -> 4/4 green again. Mutation-proven (round-2 remediation): reverted the refined guard 'else if (!(isFutureUngeneratedPhase(selectedWeek) && weekDays.isEmpty))' to the round-1-only 'else if (!isFutureUngeneratedPhase(selectedWeek))', reran the same file ALONE -> exactly 1 of 4 assertions reddened (the same WardCard-suppression test, now asserting BOTH conditions); restored and reran -> 4/4 green again." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive key participates" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no table read or written" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function involvement" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service call" }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "purely client-side derivation from plan.phase and selectedWeek, both already in memory; no client-server contract change" }
impact_analysis: >-
  Account-tier by the classifier (`lib/core/utils/hold_week_labels.dart`
  falls under the `lib/core/** -> account` catch-all, not the
  `lib/features/train/** -> feature` rule the other two touched files match
  — corrected 2026-09-16 by B-pass Finding 2, `docs/reviews/08821dc5a27b-review.md`;
  self-declared `feature` here was wrong, the classifier's `account` is the
  real tier). Substantively still cosmetic, no data-integrity risk — this
  fix already received `code_review_b_pass` (that same review) and has a
  genuine `behavioral_test_path` (`hold_week_labels_test.dart`), so
  account-tier's discipline requirements were met in practice; only the
  self-declared field was wrong. Does not touch the existing free-tier
  `/train/preview` paywall-gate flow at all — that routing branch
  (`!isProUser && week >= 5`) is untouched, verified by re-reading it after
  the fix. Only the FALLBACK path (a week that reaches
  `ref.read(selectedWeekProvider.notifier).select(week)` and then renders
  empty) changes, and only its icon/copy — no navigation change, no new
  route, no new provider. A same-phase empty week (the rarer case this fix
  does not attempt to explain) is unaffected: `isFutureUngeneratedPhase`
  returns false for weeks 1-4 of the display window, so it falls through to
  the original unchanged generic copy.
  **Corrected 2026-09-16 by plan-review round 1**
  (`docs/plan-reviews/obs-batch-2026-09-16-round1.md`): a SECOND,
  pre-existing widget (`screen.dart`'s top-of-screen status `WardCard`,
  ~line 194, not cited in this doc's original `writers`/`readers`) fires on
  the SAME condition — `selectedWeek > plan.currentWeek` is unconditionally
  true for weeks 5-12, since `plan.currentWeek` is hard-clamped to `[1,4]`
  by `getCurrentWeekNumber()` — and rendered "Week N hasn't started yet"
  directly above the new lock card, producing two un-reconciled messages
  about the identical condition in one scroll view. Suppressed that card
  when `isFutureUngeneratedPhase(selectedWeek)` is true (structural test +
  mutation-proof added to `train_phase_lock_empty_state_test.dart`).
  Round 1 also raised two narrower, explicitly non-blocking edge cases,
  left out of scope for this fix (same disposition as the Nordic
  Curl/Dumbbell-Kickback residual gaps elsewhere in this batch): (1) the
  new copy names `plan.phase` while "future" is computed from
  `plan_start_date` — in the rare pre-existing drift scenario between those
  two (2 known accounts, unrelated to this fix), the copy could name a
  phase the user has already completed; (2) `selectedWeekProvider` isn't
  reset on a mid-session subscription downgrade, so a PRO user previewing a
  future week who loses PRO mid-session could see the lock copy with no
  mention of the now-also-relevant subscription requirement. Both are
  narrow, pre-existing conditions this fix does not create and does not
  make meaningfully worse; fixing either would mean touching the
  phase/subscription-state machinery well beyond this cosmetic empty-state
  card.
  **Corrected 2026-09-16 by plan-review round 2**
  (`docs/plan-reviews/obs-batch-2026-09-16-round2.md`): round 1's own
  suppression guard (`!isFutureUngeneratedPhase(selectedWeek)` alone) was
  itself a regression this fix introduced, unlike the two edge cases above
  — it created a NEW blank-UI case. `weekDays.isEmpty` is what actually
  gates the phase-lock card further down; a future-phase week that already
  HAS data (structurally possible via a hold row extending past week 4 for
  `phase > 1`, per `train_provider.dart`) would hit neither this card's
  original branch nor the hero-card branch above, leaving the top of the
  screen silently blank. Refined the guard to
  `!(isFutureUngeneratedPhase(selectedWeek) && weekDays.isEmpty)` — this
  card now only suppresses when the phase-lock card below is GUARANTEED to
  render in its place, falling back to its original, unsuppressed
  behaviour for the rare has-data case.
---

# The Train screen's future-phase empty state read like a bug, not an intentional gate

## What was actually wrong

A PRO user (the founder) tapped ahead to a week in the phase AFTER their
current one (Phase IV, while on Phase III). The screen showed the generic
`_buildEmptyWeek()` card — dumbbell icon, "No workouts scheduled / This
week has no workouts in your plan" — which reads exactly like an empty-data
bug rather than the intentional gate it actually is: Phase IV genuinely has
no generated schedule until Phase III finishes.

The app already has the RIGHT pattern for this shape of problem, just
wired to a different trigger: `week_selector.dart` + `preview_workout_screen.dart`
show a "Complete Phase I to unlock Phase II" lock banner with a real
dry-run-generated preview workout — but only for the FREE-vs-PRO
subscription gate. `screen.dart`'s week-tap handler only special-cases
`!isProUser && week >= 5`; a PRO user tapping any future week — regardless
of whether that phase has actually been reached yet — just falls through to
selecting the week inline, with no phase-completion framing at all.

## The fix

Reused the established COPY PATTERN (lock icon + "Complete Phase X to
unlock Phase Y" + a line about the AI coach generating the next block) but
NOT the full preview-screen MECHANISM — building that would mean new
routing logic to distinguish "not reached because you haven't paid" from
"not reached because you haven't finished the current phase," which is a
larger change than this gap calls for.

Added two pure functions to `lib/core/utils/hold_week_labels.dart` (the
established shared home for phase/week label formatters):

- `isFutureUngeneratedPhase(selectedWeek)` — true when the selected week
  falls in a phase group beyond the current one, given the 3-phase rolling
  display window `week_selector.dart` already renders (weeks 1-4 current
  phase, 5-8 next, 9-12 the phase after).
- `futurePhaseUnlockCopy(currentPhase)` — always names the user's ACTUAL
  current phase as the unlock action, regardless of how far ahead they
  tapped, since the plan engine only ever generates one phase ahead at a
  time ("the moment you finish").

`screen.dart`'s empty-state call site now passes both through;
`_buildEmptyWeek` in `empty_states.dart` branches to a lock icon and this
copy instead of the generic dumbbell/"no workouts" text when the gate
applies — falling back to the original unchanged copy for a same-phase
empty week (a rarer, different situation this fix does not attempt to
re-explain).

## Regression tests

`test/contracts/hold_week_labels_test.dart` gained full behavioral coverage
of the two new pure functions (phase-roman mapping, the phase-boundary
decision on all three week ranges, and the copy for phase 1 and phase 3 —
matching the founder's exact screenshot). `test/contracts/train_phase_lock_empty_state_test.dart`
pins the WIRING structurally (source-grep, since `empty_states.dart` is a
`part of` file with no independent constructor surface a widget test can
drive without standing up the whole Train screen's provider graph).
**Mutation-proven:** reverted `isFutureUngeneratedPhase` to unconditionally
return `false` — exactly 2 of 39 assertions reddened (the two "future
phase" cases), the rest — including both structural wiring tests, which
correctly stayed green since they assert the function is CALLED rather
than that its answer is truthful — stayed green; restored the fix, 39/39
green again.
