---
bug_id: e3b7d1
date: 2026-09-05
batch: phase-arc-flip
status: fixed
blast_radius: platform
related_bugs: [e2d6b8]
recurrence: >
  Not a recurrence of a named class, but the THIRD ship-dark flip to find that the dark code was
  not actually ready (e2d6b8 found the equipment-exclusion collection UI shipped lit while its
  consumption stayed dark; the 2026-09-01 readiness flip found three Android-side defects
  invisible to `flutter test`). The pattern worth naming: ship-dark code is, by construction,
  code no user has ever exercised, so the flip commit is where its first real review happens.
symptom: >
  Three latent defects in `PhaseArcStrip`, none of them user-visible before this batch because the
  widget was dark. (1) The wave vocabulary is FIVE tokens but `_labels` mapped four — `working`,
  written by `deload_evaluator.dart:231` whenever a deload is lifted, rendered only via the
  unknown-token fallback. (2) The label lookup normalised (`.toLowerCase().trim()`) while its
  fallback used the RAW token, so a whitespace-only `week_character` missed the map, fell through
  untrimmed, and `'  '.isEmpty` is FALSE — a node with a dot and no visible label. (3) The
  provider guarded `waves.length < 2`, so a 2- or 3-week blob rendered a strip on which the
  highlight (clamped to 1..4) could mark NO node as current — every node dim, which reads as a
  rendering fault rather than as missing data.
concept: >
  Ship-dark code is code nobody has run. `enable_phase_arc` shipped 2026-07-17 and stayed OFF for
  50 days, so its three defects were unreachable and therefore undetected — the widget's own
  behavioral test seeded only well-formed 4-entry blobs with canonical tokens.

  Each defect is a guard whose mirror was missing. (1) A label map that covers the tokens its
  author knew about, next to a fallback that quietly rescues the ones they did not — which works
  until the rescued value stops being a real English word. (2) A normalisation applied on the
  lookup side and not on the fallback side, so the fallback re-opens exactly the hole the lookup
  closes. (3) A length guard chosen against the wrong invariant: `< 2` guards "is there a
  degenerate plan", but the invariant that matters is "can the clamped highlight address a node",
  which needs 4.
sot_registry_entry: phase_arc_display
sot_registry_note: >
  Updated in this commit: the ship-dark claim became the `disable_phase_arc` kill-switch, the
  five-token vocabulary and the `>= 4` render rule are recorded, and the writer citation
  `periodization_engine.dart` line 129 was corrected to 164 (the gate does not range-check the
  block form, so it had passed silently). The sibling `deload_decision_reason` entry gained the
  new `enable_deload_reason_line` split note.
writers:
  - { file: lib/shared/repositories/plan_engine/periodization_engine.dart, method: "apply — stamps weekCharacter per week from _waveNames (baseline/overreach/peak/deload)", line: 164 }
  - { file: lib/core/services/deload_evaluator.dart, method: "_liftWeekFour — REWRITES week_plans[3].week_character to 'working' when a deload is lifted; the fifth token, live since 2026-09-01", line: 231 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "currentWaveCharacters — synthesises '' for an entry that is not a Map or whose key is null; the sixth state", line: 1229 }
  - { file: lib/core/services/sync/sync_workout.dart, method: "restore — puts current_plan wholesale from the cloud bundle, seeded only when the local blob is absent", line: 1108 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "phaseArcProvider — flag gate, length guard, take(4)", line: 906 }
  - { file: lib/features/train/widgets/phase_arc_strip.dart, method_or_widget: "labelFor — normalises once, then maps or floors", line: 48 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method_or_widget: "getCurrentWeekNumber — the highlight, clamped 1..4; the reason the length guard must be 4", line: 1214 }
hive_key_prefix: current_plan
hive_key_formula: "workoutBox['current_plan']['week_plans'][i]['week_character'] — read-only for this batch; no writer added."
sync_methods: not_applicable — the strip and its provider are pure reads; no write, no fan-out.
restore_methods: >
  `sync_workout.dart:1108` restores the whole `current_plan` blob when the local one is absent. It
  echoes a bundle this client pushed, so it cannot introduce a week count the generator never
  produced — but it is the only writer that could, which is why the length guard exists rather
  than an assertion.
cloud_table: user_progress
cloud_columns: [plan_json]
contract_test_path: test/contracts/phase_arc_reader_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 1214, fn: "getCurrentWeekNumber uses nowWall() and a day-difference from plan_start; no date KEY is built or compared here, so §4.5's IST rule does not bind. The strip renders no date." }
provider_invalidations: >
  `phaseArcProvider` watches `currentPlanProvider`, so it rebuilds on (re)materialisation. The
  dev-panel kill-switch toggle calls `ref.invalidate(currentPlanProvider)` — added after the
  B-pass observed that `setState` rebuilds the DEV screen and not the Train tab, so the switch
  would have looked inert. Every sibling toggle achieves the same thing via
  `runRolloverNow(ref)`; this one has no rollover work to do, so it invalidates directly.
telemetry_op_types:
  success: []
  failure: [phase_arc_truncated_week_plans]
cross_account_guard: >
  not_applicable — reads flow through `WorkoutScheduleService` → `HiveService` user-scoped boxes,
  unchanged by this batch.
forbidden_patterns_checked: >
  - `recordNonFatal` deliberately NOT used for the length guard. It fires at length 0, which is the
    ordinary no-plan state for every pre-onboarding user on every rebuild, and
    `error_telemetry.dart:241` records that `recordNonFatal` is reserved for actual exceptions and
    treated as HIGH priority, bypassing the cooldown. `logEvent` on the truncated (1..3) case only.
  - Gate 15 (`check_generic_error_telemetry.dart`): the reason string is specific
    (`phase_arc_truncated_week_plans`), not a generic numbered label.
  - The flag inversion changes BOTH halves — key and catch-block default. Flipping only the key
    would leave a no-Hive context rendering nothing while a Hive context renders, i.e. the fallback
    silently contradicting the flag. Pinned by `readiness_flag_no_hive_default_test.dart`.
proposed_fix: >
  Map `working` explicitly; normalise once in a single `labelFor` so the lookup and the fallback
  cannot diverge, flooring empty/whitespace to an em dash; and raise the length guard to `>= 4`
  (matching `deload_evaluator.dart:228`) while rendering `take(4)`, since the clamp can never
  address a fifth node.
regression_test_planned:
  - test/contracts/phase_arc_reader_behavioral_test.dart
  - test/contracts/readiness_flag_no_hive_default_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ — 44 issues, 0 warnings, 0 errors (grepped, not eyeballed); none in the touched files. 22 behavioral tests green across the two contract files." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "Read-only. The tests seed real current_plan blobs through HiveService and assert the provider's output, including the 5-week and 3-week shapes." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows written." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads week_character." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret in this path." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Local display only." }
  - { tier: 12, name: client_to_server_contract, status: verified, evidence: "plan_json round-trips unchanged; the batch adds no field and reads no new column. sync_workout.dart:1108 was traced as the third blob writer and is a restore echo, not a producer." }
impact_analysis: >
  User impact of the FLIP is a new permanent card on the Train tab showing the periodization wave
  with the current week in Campaign Gold. User impact of the three FIXES is that the card is
  correct on states it would otherwise have rendered wrongly — a lifted deload week, a malformed
  entry, and a short blob.

  WHAT THE REVIEW PROCESS COST AND BOUGHT, recorded because the ratio is the interesting part.
  Two context-blind rounds produced 13 then 20 findings on a change whose headline is a
  one-line flag inversion. Round 2's most valuable finding was that ROUND 1's correction was
  itself defective: a proposed change to `DeloadEvaluator` would have altered live shipped
  behaviour (`enable_triggered_deload` has been on since 2026-09-01) to fix a contradiction that
  the batch's own length and label fixes already made unreachable, while introducing a reachable
  one — emitting "Recovery week logged — you're recovered" over rows stamped
  `week_character: 'working'`. It was dropped entirely.

  That is also what triggered the SPLIT. §4.12.1 says successive rounds surfacing new material
  issues means the unit is too large; the founder chose to split, so the week-4 deload-reason line
  stayed dark behind a new `enable_deload_reason_line` and became Unit B. Its blocking defect is
  recorded there and in the ledger: `deload_reason_phase_<P>` is never deleted anywhere in `lib/`,
  a mid-phase regen re-stamps week 4 as `deload`, and the idempotency flag blocks correction — so
  the line would sit under a DELOAD node saying "Working week", permanently.
mutation_evidence: >
  Rule 21, three mutations, all file-scoped per the plan (pre-existing tests in
  `test/plan_engine_v4/hypertrophy_archetype_test.dart` already index `weeks[3]`, so a suite-wide
  count would credit this batch with other files' coverage).

  M1 inverted the flag polarity (`get('disable_phase_arc') != true` → `== true`), verified applied
  by grep count 1: 4 tests reddened, 14 still passed. M2 reverted `labelFor` to the pre-fix
  split normalisation (`_labels[raw.toLowerCase().trim()] ?? raw.toUpperCase()`), verified applied:
  3 reddened, 15 passed. M3 weakened the length guard to `< 2`, verified applied: 1 reddened, 17
  passed. All three reverted; 22/22 green afterwards across both contract files.

  ⚠ Each mutation left the file COMPILING — the passing counts (14/15/17) are the evidence for
  that, and they matter: §4.4 rule 21's 2026-09-04 clause records that a mutation which reddens a
  run by breaking compilation proves the file is invalid, not that any assertion detects the
  defect.
---

# e3b7d1 — three latent defects found by flipping a 50-day-old ship-dark flag

## What happened

`enable_phase_arc` shipped dark on 2026-07-17 and was flipped live on 2026-09-05 as OI-53 flag 3
of 12. The flip itself is one line. Reviewing it surfaced three defects in the code the flag had
been hiding, plus one in a sibling that made the batch split.

## Why none of them were visible

Ship-dark code is code no user has run. The widget's existing behavioral test seeded well-formed
4-entry blobs with canonical tokens — the shape the generator produces on the happy path — so
every defect sat in a state the test never constructed and no user could reach.

The `working` token is the sharpest example. It has been written by `deload_evaluator.dart:231`
since that evaluator went live on 2026-09-01, and it rendered *correctly* the whole time, because
`'working'.toUpperCase()` is `'WORKING'`, which is exactly the label anyone would have chosen.
The fallback was doing real work and nobody knew. That is not a bug that testing finds; it is a
bug that only shows up when someone asks what the vocabulary actually is.

## The one that mattered most, and it was not in this widget

Plan-review round 2 found that the week-4 deload-reason line — which lives inside the same widget,
and which the flip would therefore have lit — carries a defect neither round 1 nor the author had
seen. `deload_reason_phase_<P>` is never deleted anywhere in `lib/`, while
`workout_schedule_read_service.dart:388` rewrites the plan blob unconditionally on a mid-phase
regen, re-stamping week 4 as `deload`. The idempotency flag at `deload_evaluator.dart:79` then
prevents re-evaluation from correcting the stale string.

The result would have been a `DELOAD` node with "Working week — you've recovered" underneath it,
permanently, for any user who edited their profile mid-phase. The founder split the batch: the
strip ships, the line stays dark behind `enable_deload_reason_line`, and Unit B fixes the staleness
before flipping it.

## The fix

`labelFor` normalises once and both branches read the same normalised token, which is what stops
the fallback re-opening the hole the lookup closes. The length guard moved to `>= 4` — matching
`deload_evaluator.dart:228` rather than inventing a stricter rule — and renders `take(4)`, because
`getCurrentWeekNumber()` clamps to 4 and can never address a fifth node.

The truncated-blob case emits `logEvent`, not `recordNonFatal`. That distinction is the plan's own
corrected mistake: the first draft said `recordNonFatal`, which fires at length 0 — the ordinary
no-plan state for every pre-onboarding user on every rebuild — through a channel its own source
reserves for real exceptions and exempts from the cooldown.
