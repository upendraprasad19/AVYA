---
bug_id: a9f3c7
date: 2026-09-08
batch: regen-wave-alignment
status: fixed
blast_radius: account
related_bugs: [e3b7d1]
recurrence: >
  Fourth instance of the writer/reader drift class in the schedule-row family, and the first found
  by RUNNING a proposed detection heuristic rather than reasoning about it. The OI-166 inventory
  named three implementations of "lay out schedule rows for a phase"; three plan-review rounds and
  two versions of that inventory all missed a fourth. One command
  (`grep -rl "'week_character':" lib/ | xargs grep -l "'day_of_week':"`) returned it immediately.
symptom: >
  A hotel workout written by the AI coach stamped `'week': 1` and
  `'week_character': 'baseline'` unconditionally, and `'day_of_week': d.weekday` (Dart's 1..7)
  where every reader expects 0..6. So a hotel day scheduled inside a `deload` week 4 announced
  itself as a baseline week-1 day, and its Train-screen day badge read one too high — Monday
  rendering `D2`, a Sunday `D8` inside a seven-day week.
concept: >
  Three hardcoded stamps in a row constructor that nobody had listed as a row constructor. The
  planner writes up to SEVEN consecutive days (`hotel_workout_planner.dart:79`,
  `n = days.clamp(1, 7)`) from a possibly-future supplied start, so it can straddle a plan-week
  boundary — which is why the fix could not simply read today's week either.

  That second half is the instructive part. The first draft of this fix proposed
  `rawWeekNumber()` (clock-derived) for the `week` stamp, while the very next line of the same
  plan said the character should be "the week the row actually lands in". Two adjacent bullets
  contradicting each other, and the clock-derived one would have reproduced the same defect class
  on a plan spanning two weeks. Caught by plan-review round 5, fixed by deriving BOTH from the
  row's own date.
sot_registry_entry: phase_arc_display
sot_registry_note: >
  No registry change. This batch adds no new concept: `week_character` and the `'week'` stamp are
  already registered under `phase_arc_display`, and the hotel planner becomes a conforming writer
  of the existing contract rather than a new one. The shared `schedule_row_builder` that would
  warrant a new entry belongs to OI-166 Unit 2, which is being re-planned.
writers:
  - { file: lib/features/ai_coach/services/hotel_workout_planner.dart, method: "plan — the row map; now derives week + character per row date", line: 193 }
  - { file: lib/features/ai_coach/services/hotel_workout_planner.dart, method: "plan — day_of_week now weekday-1 (0=Mon..6=Sun canon)", line: 201 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "planWeekAndCharacterFor — NEW; plan week + wave character for an arbitrary date, guards explicit and no catch above them", line: 1308 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: "rawWeekNumberFor — NEW; the one copy of the week arithmetic", line: 1269 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "reads row['day_of_week'] and computes dayNumber", line: 619 }
  - { file: lib/features/train/screens/train/week_rows.dart, method_or_widget: "renders the D<n> badge from dayNumber", line: 54 }
hive_key_prefix: schedule_
hive_key_formula: "workoutBox['schedule_<yyyy-MM-dd>'] — keys 'week', 'week_character', 'day_of_week' on the row the hotel planner writes."
sync_methods: >
  Unchanged by this fix. The hotel rows are applied by the coach dispatcher through
  `WorkoutWriteService.upsertScheduled`, which already fires its own `syncWorkoutData()` +
  `pushSnapshot()` fan-out.
restore_methods: >
  Unchanged here. The sibling `day_of_week` corruption on the cloud round-trip is a separate
  defect fixed in the same batch and documented at `2026-09-08-day-of-week-round-trip-c4e8b2.md`.
cloud_table: scheduled_workouts
cloud_columns: [week_number, day_of_week, scheduled_date]
contract_test_path: test/contracts/plan_week_for_date_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/workout_schedule_read_service.dart, line: 1279, fn: "rawWeekNumber reads nowWall() (seam-aware). planWeekAndCharacterFor takes an explicit date and reads NO clock, which is the point. No date KEY is built here; the hotel planner formats its own via _fmt/istDateStr, unchanged." }
provider_invalidations: >
  None added. The hotel planner writes through `upsertScheduled`, whose existing invalidation path
  refreshes the Train surface; this fix changes only the VALUES three keys carry.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable — reads and writes flow through `HiveService` user-scoped boxes via the existing
  service layer, unchanged by this batch.
forbidden_patterns_checked: >
  - No raw `Hive.box(` — the new read goes through `WorkoutScheduleReadService`.
  - No `catch` placed above the new guards. That is deliberate and load-bearing: this same file's
    `currentDeloadReason` records that guards buried under a swallowing `catch` made three
    separate mutations redden ZERO of twelve assertions. Every null `planWeekAndCharacterFor`
    returns has exactly one explicit source, so removing a guard throws and the test reddens for
    the right reason — verified by mutation B below.
  - The gate `check_single_schedule_row_builder.dart` shipped in an EARLIER commit per §4.11 and
    now allowlists this file BY NAME with its reason, pinned by a test asserting the allowlist's
    exact contents.
proposed_fix: >
  Derive both stamps from the row's own date. `WorkoutScheduleReadService.planWeekAndCharacterFor`
  returns `(week, character)` for an arbitrary date — week from the extracted `rawWeekNumberFor`
  clamped to 1..4 for display, character from `current_plan.week_plans[week-1]`. The planner
  passes each day's date. `day_of_week` becomes `d.weekday - 1`. The `'baseline'` fallback is kept
  ONLY for the genuinely-unknowable case (no plan start, no blob, short blob), which preserves the
  previous value for a standalone hotel plan with no phase behind it.
regression_test_planned: >
  `test/contracts/plan_week_for_date_behavioral_test.dart` — 19 assertions. Behavioral for the
  derivation (straddling a week boundary, a lifted `working` week 4, short/absent/malformed blob,
  unparseable plan start, clamping at both ends); source pins for the three literals, which a
  behavioral test of `HotelWorkoutPlanner.plan` cannot reach without a full PlanGenerator +
  profile + exercise-library fixture. MUTATION-PROVEN, and both mutations left the file compiling
  and semantically wrong rather than failing to compile:
  (A) derive the week from `nowWall()` instead of the row's date — the exact defect the first
  draft proposed — reddened 3 of 19.
  (B) delete the short-blob guard — reddened 2, both surfacing as RangeError rather than being
  swallowed, which is what proves the guard does the work.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze lib/ — 0 errors, 0 warnings, 45 pre-existing infos, none in the edited files." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "plan_week_for_date_behavioral_test.dart seeds real Hive boxes and asserts the derived pair; 19/19 green." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; scheduled_workouts.day_of_week is a pre-existing bare int." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data migration. The sibling cloud fix self-heals by deriving on restore." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "Client-only change; no Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron path touches the hotel planner." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy change." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No storage object touched." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The 0..6 canon is now shared with the sync seam via dayOfWeekFromDate; day_of_week_canon_writer_to_reader_test.dart pins both sides, 8/8 green." }
impact_analysis: >
  Affects any user who asks the coach for a hotel workout. Before the fix every such row claimed
  week 1 / baseline and carried a day number one too high; after it, the row reports the plan week
  it actually lands in and the badge is correct. No data migration is needed — hotel rows are
  short-lived and are rewritten by the next request — and no existing row is deleted or moved.

  Deliberately NOT widened: the hotel planner does NOT adopt a shared row builder. A hotel workout
  is a single ad-hoc replacement day, not a phase layout, so running it through a builder whose
  job is to lay `weekPlans[rawWeek-1..3]` across plan weeks would force an unrelated shape through
  the wrong abstraction. It is allowlisted by name in the new gate, with that reason recorded and
  the allowlist's exact contents pinned by a test — so a FIFTH implementation cannot be quietly
  added to it.
---

# Hotel workouts stamped week 1 / baseline / the wrong day number

See the frontmatter. The short version: three hardcoded values in a row constructor that no
inventory had listed as a row constructor, found by running the detection heuristic that the
accompanying gate proposes instead of reasoning about it.

The fix that nearly shipped is worth more than the fix that did. Deriving the week from the clock
reads as obviously correct — it is what `getCurrentWeekNumber()` is for — and it is wrong here for
a reason visible only once you notice that a hotel plan can span seven days from a future start.
The plan document said so in one bullet and contradicted it in the next. What caught it was a
review round asked specifically to check whether the plan could be executed as written.
