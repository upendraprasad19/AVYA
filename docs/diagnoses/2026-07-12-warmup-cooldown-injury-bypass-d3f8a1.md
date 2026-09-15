---
bug_id: d3f8a1
date: 2026-07-12
batch: warmup-injury-filter
status: fixed
blast_radius: platform
symptom: >
  The warmup/cooldown attached to every generated workout day is built from
  HARDCODED per-dayType name-lists (WarmupCooldownSelector `_dynamicWarmup` /
  `_cooldownStretches` / `_bodyweightCardio` / `_gymCardio`), NOT the library
  cascade. So — unlike the MAIN exercises, which Ship 1 (a1f6c3) injury-filtered
  — the warmup/cooldown were NEVER injury-filtered: a shoulder-injured user's
  push/upper-day warmup still contained shoulder-loading moves (Dead Hang, Wall
  Push Up) and their cooldown still contained shoulder stretches (Chest Doorway /
  Cross-body / Overhead Stretch); a knee-injured user still got High Knees /
  Baithak / Jump Rope. Additionally the AI custom-template auto-warmup path
  (`template_service.dart`) read experience + equipment from the profile but not
  injuries, so its warmup was unfiltered too.
concept: injury_vocabulary_contract
sot_registry_entry: >
  Extends the `injury_vocabulary_contract` concept (added in Ship 1, a1f6c3) to
  the warmup/cooldown stage. New writer: WarmupCooldownSelector.attach applies a
  hand-authored move->injury map (`_moveInjuries`) using the SAME canonical
  InjuryVocab vocabulary. Main-cascade-selectable moves (Push Up, Band Pull
  Apart, Baithak) defer to their exact library `injury_contraindications` so a
  move is never dropped from warmup while the main plan keeps it; warmup/cooldown-
  ONLY moves use conservative tags (the library under-tags them). Not a new
  concept — closes the warmup/cooldown gap in the existing injury-filter contract.
writers: >
  lib/shared/repositories/plan_engine/warmup_cooldown.dart — attach() (~:100)
  now injury-filters the cardio pool, the dynamic-warmup list, and the cooldown
  stretches via `_moveInjuries` + `_moveIsContra`, with a non-empty FLOOR (a
  universally-safe Slow Walking cardio fallback + a Deep Breathing anchor if the
  dynamic warmup is fully dropped). Kill-switch via
  `PlanEngineFlags.warmupInjuryFilterEnabled` (default ON), read internally so
  both callers inherit it. THREADING: plan_generator.dart generateV4 (~:177)
  passes `normalizedInjuries` (Ship 1's central-normalized list);
  template_service.dart (~:150) now reads `profile['injuries']` via
  `InjuryVocab.normalize(InjuryVocab.fromProfile(...))` and passes it (was
  UNFILTERED). Coach regen + hotel route through generateV4 → covered
  automatically (verified: only 2 lib call-sites of attach exist).
readers: >
  WorkoutDay.warmup / WorkoutDay.cooldown (models.dart) — consumed by the
  schedule-row warmup/cooldown JSON (workout_schedule_read_service /
  regenerate_plan_planner) and rendered by the Active Workout warmup/cooldown
  section. Unchanged by this fix (the rows now simply carry fewer, injury-safe
  moves).
hive_key_prefix: schedule_
hive_key_formula: "schedule_<yyyy-mm-dd> — warmup/cooldown ride inside the schedule_* row's warmup/cooldown arrays (WorkoutDay.toMap). This fix changes WHICH moves populate them (injury-safe), not the key."
sync_methods: >
  syncScheduledWorkouts / _syncWorkoutPlan embed the warmup/cooldown arrays in
  user_progress.plan_json.schedules (the cloud scheduled_workouts table has no
  warmup/cooldown column). This fix changes the array CONTENTS only; no new sync
  surface.
restore_methods: >
  _restoreWorkoutPlan applies plan_json.schedules (including warmup/cooldown).
  No new restore path — the injury-safe moves travel with the existing plan_json
  round-trip; a re-generation on a restored profile re-filters via the same seam.
cloud_table: scheduled_workouts
cloud_columns: >
  n/a — no column added/changed. warmup/cooldown are Hive-row-local, cloud-carried
  only inside user_progress.plan_json (verified, backups/live_schema_columns.json
  has no warmup/cooldown column on scheduled_workouts).
contract_test_path: test/contracts/warmup_injury_filter_behavioral_test.dart
ist_handling: >
  n/a — no new date key; the warmup/cooldown durations are static.
provider_invalidations: >
  n/a to this fix — plan (re)generation invalidations fire on the downstream
  write path, unchanged.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  n/a to change — template_service reads userBox['profile'] via HiveService
  (user-scoped, guarded); warmup_cooldown is a pure function over the injuries
  passed in. No new box access.
forbidden_patterns_checked: []
proposed_fix: >
  Add a hand-authored `_moveInjuries` map (canonical InjuryVocab tokens) over the
  ~25 fixed warmup/cooldown/cardio moves; main-cascade-selectable moves use their
  library tags (consistency), warmup-only moves use conservative tags (the
  library under-tags them). attach() drops a move whose tags intersect the user's
  (already-normalized) injuries, with a guaranteed non-empty floor (safe cardio
  fallback + Deep Breathing anchor). DROP-not-substitute (a negative "don't load
  the injury" posture, not a positive "this swap is safe" medical claim).
  Kill-switch disable_warmup_injury_filter (default ON). Thread injuries into the
  2 attach callers (generateV4 already normalizes; template_service reads the
  profile). The main-move library UNDER-tagging (e.g. Push Up not shoulder-tagged)
  is left to a separate deliberate library-audit batch (founder-directed).
regression_test_planned: >
  test/contracts/warmup_injury_filter_behavioral_test.dart (Hive + real library,
  via PlanGenerator.generate) — the SOLE proof since the Batch-0 scorecard scores
  only main exercises: a shoulder plan drops the shoulder-loading moves but KEEPS
  Push Up (library wrist-only, consistent with the main plan); a knee plan drops
  the knee-loading moves; an uninjured plan retains them (non-vacuity); an
  irrelevant injury (wrist) leaves leg moves untouched; a broad multi-injury never
  empties any day's warmup OR cooldown (floor); the kill-switch OFF reverts; and a
  drift guard asserts every emittable fixed move has a `_moveInjuries` entry.
touched_layers_checked:
  - "tier: 1_client_code, status: fixed_in_this_batch — warmup_cooldown.dart + plan_generator.dart + template_service.dart + plan_engine_flags.dart edited; flutter analyze clean."
  - "tier: 2_hive_local_state, status: fixed_in_this_batch — warmup_injury_filter_behavioral_test.dart seeds the real library + asserts the generated schedule rows' warmup/cooldown arrays contain no contraindicated move; 7/7 green."
  - "tier: 12_client_server_contract, status: verified — warmup/cooldown are Hive-row-local (no scheduled_workouts column, backups/live_schema_columns.json); no cloud-contract change, round-trips via plan_json."
impact_analysis: >
  Blast radius platform (lib/shared/repositories/plan_engine/**). Behavior change:
  an injured user's generated warmup/cooldown (main-app generateV4, coach regen +
  hotel via generateV4, AND custom templates via template_service) now excludes
  moves that load the injury, with a guaranteed non-empty floor. The Batch-0
  scorecard is BLIND to this (it scores only plan.allExercises) — the behavioral
  test is the sole proof. Uninjured users are byte-identical to pre-U3 (default-
  empty injuries + kill-switch). Ships behind disable_warmup_injury_filter
  (default ON). Consistency preserved with the shipped main filter: main-cascade-
  selectable moves defer to the library tags (Push Up kept for a shoulder injury
  in BOTH). Surfaced-but-separate: the exercise library under-tags injury
  contraindications on MAIN moves too (Push Up not shoulder-tagged), so Ship-1's
  main filter is itself under-inclusive — this is a founder-directed separate
  library-audit batch (Option A), NOT expanded here to avoid changing the shipped
  main plan inside a warmup fix. Ship 2 of the workout-generator injury batch
  (Ship 3 = U5 onboarding chip).
---

# Warmup/cooldown injury bypass — hardcoded move-lists never injury-filtered (d3f8a1)

## What happened
Ship 1 (a1f6c3) injury-filtered the main exercise cascade, but the warmup/cooldown
stage builds from hardcoded per-dayType name-lists, so it was never filtered — an
injured user still got contraindicated warmup/cooldown moves (a shoulder user's
Dead Hang + shoulder stretches; a knee user's High Knees/Baithak). The custom-
template auto-warmup path also dropped injuries.

## Root cause
`WarmupCooldownSelector.attach` is not library-driven; it emits fixed move-lists.
No injury awareness existed there, and 2 of its callers (generateV4 threaded
injuries only after Ship 1; template_service never did).

## Fix
A canonical-vocabulary move->injury map + a DROP-not-substitute filter with a
non-empty floor in attach(), threaded from both call sites, behind a kill-switch.
Main-selectable moves defer to library tags for main+warmup consistency. See
`proposed_fix` + the Ship-2 plan `docs/plans/warmup-injury-filter-batch.md`.

## Related
Ship 2 of the workout-generator injury batch; sibling of a1f6c3 (Ship 1). ×2
plan review converged. The main-move library under-tagging surfaced by the review
is a separate founder-directed library-audit batch (Option A).
closes-diagnose: d3f8a1
