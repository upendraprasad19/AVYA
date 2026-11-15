---
bug_id: a7d2f4
date: 2026-11-15
batch: generator-step2d
status: fixed
blast_radius: platform
tier: l_fix
symptom: |
  Generator step 2, Unit 2D (OI-453, closure row SBF-REPEAT-PHASE-MINUTES; founder design 2026-11-03, d50, d52).
  - A repeat phase pins the previous phase's exercise list.
  - When the user's session minutes went up between phases, the allocator grew the pinned rows to its own set
    targets but could never add an exercise, so most of the raise went unused.
  - Measured on the built tree, a 30-minute phase repeated at 60 minutes: a bodyweight repeat leaves room for 350
    accessory rows (997 sets in weeks 1-2) across 41 plans that main leaves unused.
concept: repeat_phase_pinned_selection
sot_registry_entry: repeat_content_scheduling
contract_test_path: test/contracts/repeat_minutes_behavioral_test.dart
related_bugs: [e9b3d7, b3f1d8, d4a7e2]
recurrence: |
  Not a recurrence. It continues the step-2 allocator chain and reuses its readers: the week-2 pass
  (`PeriodizationEngine._weekTwoGains`, 2C-b's allowance stamp, e9b3d7), the lead (2A, d4a7e2) and the day floor's
  thin-day top-up (OI-401).
  Bug-history lookup (CLAUDE.md 4.1.5): docs/diagnoses grepped for "repeat", "pinned", "last_phase_profile",
  "session_minutes", "buildPinnedDays" and "topUpDays". Hits:
  - c3e9a4 (repeat pins strip auto-appended customs);
  - the 2-int / 2-cap repeat scheduling chain (`repeat_content_scheduling`);
  - bug class 2.158 (a field dropped by the top-up's PopulatedDay rebuild).
  None of them adds a row to a repeat. Bug class 2.158's lesson is applied: topUpDays carries the new fields, and a
  test pins it.
writers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "generateAndSchedule: last_phase_profile['session_minutes'] = resolved minutes", line: 274 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "generateAndSchedule: minutesRose read from the OLD profile before generate()", line: 228 }
  - { file: lib/shared/repositories/plan_engine/plan_generator.dart, method_or_widget: "generate() and generateV4 forward repeatMinutesRose (d50) to buildPinnedDays(appendAccessories:)", line: 210 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: "buildPinnedDays: candidates from the memoized fresh pick (_repeatCandidates)", line: 507 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: "_dropHeldCandidates after the thin-day top-up", line: 562 }
  - { file: lib/shared/repositories/plan_engine/exercise_selector.dart, method_or_widget: "topUpDays carries repeatAccessoriesA/B", line: 787 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "allocate wraps _allocateCore, then _appendRepeatAccessories", line: 260 }
  - { file: lib/shared/repositories/plan_engine/session_set_allocator.dart, method_or_widget: "_seatRepeatVariant: plain ledger, week-2 reserve, rank-major seats", line: 708 }
  - { file: lib/shared/repositories/plan_engine/models.dart, method_or_widget: "PopulatedDay.repeatAccessoriesA/B and appendedA/B", line: 368 }
readers:
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "repeatMinutesRose(stored, now): an int stored value and now > it", line: 899 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "_weekTwoGains: trailing appended rows kept out of rank and lead, visited last", line: 187 }
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method_or_widget: "weekTwoGains: the reserve's source", line: 167 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "_buildRepeatPins reads last_phase_profile (its four keys; session_minutes is ignored there)", line: 776 }
hive_key_prefix: "userBox['last_phase_profile'] (MigratedKey; user-scoped, UserConfigMigrator.userScopedKeys)"
hive_key_formula: "MigratedKey.write('last_phase_profile', {plan_goal, equipment, days_per_week, effective_exp, session_minutes})"
sync_methods:
  - "none for last_phase_profile (local only, as before); the plan push (plan_json) carries the appended rows like any row"
restore_methods:
  - "none: last_phase_profile has no cloud copy, so after a reinstall it is absent and the next repeat reads 'not raised' (today's behaviour)"
cloud_table: user_progress
cloud_columns:
  - plan_json
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "no date key or counter reset is touched", line: 1 }
provider_invalidations:
  - "none: generation only"
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: session_minutes rides inside the existing user-scoped last_phase_profile write (MigratedKey -> userBox)."
forbidden_patterns_checked:
  - { pattern: "a change with the flag false (golden 1,010 personas, the 2A / 2B / 2C kill-switch goldens, 185 tests of the allocator, periodization and repeat files)", absent: true }
  - { pattern: "a pinned row lost or with different sets / reps in any of the four weeks (the gate: 768 personas, 0 failures)", absent: true }
  - { pattern: "an extra row that is not a library isolation, a duplicate in a day, or different between weeks 1 / 3 or 2 / 4 (the gate)", absent: true }
  - { pattern: "a week-1 day above the level's exercise count, or main work past the plain budget where the flag-off day was within it (the gate)", absent: true }
  - { pattern: "a new .getAll() seam site in exercise_selector.dart (the count stays 8: the text moved into _sameMovementOf)", absent: true }
  - { pattern: "plan_generator.dart changed beyond d50's one argument at its two signatures and two forwards", absent: true }
proposed_fix: |
  Plan docs/plans/2026-11-15-generator-step2d-repeat-minutes.md (v4; three review rounds; round 4 on the built diff).
  - S1 / S2: generateAndSchedule stores the resolved minutes and decides `rose` from the OLD profile before it
    rewrites it. No caller changes.
  - S3 (d50): the one pass-through argument.
  - S4: candidates beside each day (budgeted library isolations, screened by name, same-movement partner and
    (pattern, first muscle), then by every row of the variant after the top-up).
  - S5: a wrapper over allocate appends them into the PLAIN leftover budget (d44), after reserving week 2's +1 sets.
    The week-2 pass keeps appended rows out of the lead and visits them last.
  - d52: the founder keeps "sets first" as the allocator's own set targets (the sets a fresh plan at the new minutes
    gets), not sets to the 5-set maximum.
regression_test_planned: |
  test/contracts/repeat_minutes_behavioral_test.dart (16 tests); test/contracts/repeat_accessory_candidates_test.dart
  (9 tests, real library); test/core/repeat_minutes_profile_test.dart (7 tests, real generateAndSchedule in Hive);
  test/plan_generator/repeat_minutes_gate_test.dart (16 blocks, 768 personas, reach pinned exactly).
impact_analysis: |
  Platform tier (plan engine). Only a repeat phase whose stored minutes are below the new minutes changes; every other
  generation is byte-identical (the golden and the three kill-switch goldens are unchanged).
  - The reach per (pair, tier) is in the plan's §3 table.
  - Every profile written before 2D lacks session_minutes, so its first repeat after the release is unchanged. The app
    is pre-launch with testers only.
  - Appended accessories get no history-based starting weight (stage 0 runs before the allocation; a second
    plan_generator.dart edit d50 does not cover).
touched_layers_checked:
  - { layer: client_code, status: fixed_in_this_batch, evidence: "workout_schedule_read_service, plan_generator (d50), exercise_selector, session_set_allocator, periodization_engine, models; flutter analyze clean; tests and mutations below" }
  - { layer: hive_local_state, status: fixed_in_this_batch, evidence: "last_phase_profile gains session_minutes (user-scoped MigratedKey write); repeat_minutes_profile_test reads it back through the real generateAndSchedule" }
  - { layer: postgres_schema, status: not_applicable, evidence: "no column, table or migration; plan_json's shape is unchanged (extra rows are ordinary exercises)" }
  - { layer: client_server_contract, status: verified, evidence: "plan_json rows are ordinary PlannedExercise maps; the golden is unchanged" }
---

## Root cause

- **Writer:** `SessionSetAllocator` grows rows only up to its weekly targets (base sets, the band bottom, the focus
  top). It never adds a row.
- **Reader:** `buildPinnedDays` hands the allocator exactly the pinned rows.
- **Mechanism:** a repeat at more minutes therefore keeps the previous phase's row count.
- **Missing input:** the minutes the pinned rows were built at were stored nowhere, so nothing could tell that the
  minutes rose.

## Fix

See `proposed_fix`. Execution mode: inline.

## Measured on the built tree

- **Flag false.**
  - Byte-identical: the generator golden (1,010 personas) is unchanged, and so are the lead-first, loaded-wins and
    balanced-week kill-switch goldens.
  - 185 tests across the allocator, day-floor, minimum, allowance, repeat and wiring files are green.
- **The gate** (768 personas: 4 minute pairs, 4 tiers, goals x levels x 3-6 days).
  - 0 invariant failures on its first run.
  - Reach is pinned in plan §3. Summary:
    - 30 -> 45: 25-41 of 48 plans per tier gain accessories;
    - 30 -> 60: all 41 measured;
    - 45 -> 60: 2-8;
    - 60 -> 90: 1-6.
  - 7 personas per tier crossing 60 go fresh (S8).

## Mutations

Each mutant was applied (the runner refuses a pattern that does not occur exactly once). It was run against the
behavioral, candidate and profile files, then the files were restored and sha-checked (`scratchpad/step2d/mut/`).
Every mutant reddened at least one test. None reddened by a compile error.

| id | mutation | red |
|---|---|---|
| M1 | `nowMinutes > then` -> `>=` | 1 |
| M2 | absent stored minutes read as raised | 2 |
| M3 | compare against the NEW profile (read after the write) | 1 |
| M4 | drop the `generate()` forward | 1 |
| M5 | `appendAccessories: false` in generateV4 | 1 |
| M6 | drop the generateAndSchedule forward | 1 |
| M7 | store the raw `sessionDuration` | 1 |
| M8 | drop the isolation check | 2 |
| M9 | drop the pinned names from the screen | 1 |
| M10 | drop the (pattern, first muscle) check | 1 |
| M11 | drop the same-movement expansion | 1 |
| M12 | drop the custom / timed check | 1 (after the test fix below) |
| M13 | drop the topUpDays carry | 1 |
| M14 | bypass the final screen at its call site | 1 (after the test fix below) |
| M15 | seat on the allowance ledger | 1 |
| M16 | drop the count check | 1 |
| M17 | fit check without groups | 1 |
| M18 | drop the lead cap | 1 |
| M19 | no reserve for variant B | 1 (after the test fix below) |
| M19b | no reserve on the 6-day path | 1 (after the test fix below) |
| M20 | appended rows ranked in `_weekTwoGains` | 1 |
| M21 | day-major instead of rank-major | 1 (after the test fix below) |
| M22 | the step only on the lead-first path | 1 |
| M24 | drop the same-name check in the seat | 1 |
| M25 | drop the budgeted check in the seat | 1 |
| M26 | drop the allowance stamp from the output | 1 |
| M27 | no growth past 2 sets | 2 |
| M28 | break the 6-day alias | 1 |
| M29 | `appendedA` / `appendedB` swapped | 1 (after the test fix below) |
| M23 | `fresh()` after the feeder update | 0: equivalent on the 30 -> 45 gate block (below) |
| M30 | an alias day's candidates not taken in B | the gate run after commit 2 (recorded with the B-pass) |
| M31 | the final screen reads A's rows for B | 1 |

**The first run had 6 survivors, each a test that could not see its case. All were fixed in the tests:**
- M12: the custom fixture shared a library name, so its row screen hid the check. Now a same-name custom alone, and
  Wall Sit (a timed isolation).
- M14: the direct test called the screen, not its call site. Now pins on day 0 only, with fresh-filled days 1-2. A
  probe under the mutant measured the hit: Russian Twist on build_muscle beginner 3-day.
- M19 / M19b: the week-2 fixture was not tight. Now a custom filler of 0-12 sets at 45 / 60 / 90 minutes, on both the
  6-day and the 5-day path.
- M21: day 1's candidate trained another group. Now a shared Biceps weekly top that fits two seats.
- M29: the fixture had symmetric counts. Now only B appends.
- M18: its first form failed to compile (11 compile errors), so it was rewritten as an always-true guard.

**M23, the `fresh()` call order (plan S4, round 2 A-9), survives.**
- It was run against the gate's four 30 -> 45 blocks (192 personas): the reach tuples are identical.
- The order cannot touch a pinned row. When an empty variant needs a fill, the fill calls `fresh()` first and memoizes
  it before either order. Otherwise the pick feeds only the candidates.
- Under the mutant, this frame's own rows soft-avoid their slot in that pick. The selector screen removes exactly
  those names anyway.
- So the order is kept for its stated reason (one pick per frame, the one a fill would use), and its effect is not
  observable on the measured grid.

## Review round 4 (the built diff)

No P0 or P1. Fixed in the branch's second commit:
- two doc blocks attached to the wrong function;
- the gate now checks weeks 1-2, each extra's session cap and weekly top, and duplicates across the week (partners
  included);
- the ledger-pricing test;
- mutants M30 and M31.

The first run of the extended gate reported cap and top failures in bodyweight and home_dumbbells. They were the
gate's own: it counted timed holds and customs toward a group, which the ledger never credits. With budgeted rows
only (the ledger's rule) every block passes.

## Not covered by a crafted fixture (stated)

- The coach `regenerate_plan` and a mid-phase reschedule leave `session_minutes` different from some pinned rows (plan
  S1). Both directions are named there. Neither changes the rows a test can build without a phase advance.
