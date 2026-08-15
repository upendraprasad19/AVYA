---
bug_id: b6e1d4
date: 2026-08-15
batch: sync-e2e
status: fixed
blast_radius: platform
symptom: >-
  Three tests in `test/supabase/sync_service_test.dart` fail against the live
  project: T3 with `PGRST204` (no `exercise_name` column on `workout_logs`), T4
  and T5 with `22P02` (a client string id into a `uuid` column). All three
  hand-rolled their own `.upsert()` payloads instead of calling the writers they
  claim to test, so the payloads drifted from production and nothing detected
  it. They drifted INVISIBLY because per OI-121 they had never once executed —
  `setUpAll` always died on a missing QA account until `e4121c14` supplied real
  credentials. What the tests had frozen was not a typo: it is the exact
  pre-2026-06-02 payload shape whose cross-user PK collision made the second
  user's row vanish, and (nutrition, 2026-04-18) kept `nutrition_logs` at 0 rows
  despite dozens of Hive food logs. The tests were preserving bugs the writers
  had already shed.
concept: sync_domain_push_writer_to_cloud
sot_registry_entry: not_applicable
writers:
  - "lib/core/services/sync/sync_workout.dart:_syncWorkoutLogs — scans workoutBox
     for `wlog_` keys; skips (with telemetry) any row whose `date` or
     `workout_name` is null/empty; projects user_id/workout_name/date/logged_at/
     duration_seconds/created_at; OMITS id; onConflict 'user_id,date,workout_name'."
  - "lib/core/services/sync/sync_health.dart:206 _syncWeightLogs — scans healthBox
     for `weight_` keys; requires log['type'] == 'weight_log'; OMITS id;
     onConflict 'user_id,date'."
  - "lib/core/services/sync/sync_nutrition.dart:201 _syncNutritionLogs — scans
     nutritionBox for `nlog_` keys via _nutritionLogsRaw():428; slot-merges on
     (date, meal_type) unless configBox['disable_nutrition_slot_merge']; OMITS
     id; onConflict 'user_id,date,meal_type'; THEN writes child rows to
     nutrition_log_items keyed (log_id, item_index)."
readers:
  - "test/supabase/sync_service_test.dart T3/T4/T5 — previously re-implemented
     the payloads above rather than reading them. Now seed Hive and call the
     production forwarders, asserting the cloud row."
  - ".github/workflows/test.yml:389 — the `Supabase Integration Tests` step that
     runs both files in this directory against the live project."
hive_key_prefix: "wlog_ (workoutBox), weight_ (healthBox), nlog_ (nutritionBox)"
hive_key_formula: >-
  All three boxes are USER-SCOPED. HiveService.workoutBox -> workoutBoxGuarded ->
  wrapUserScopedBox -> HiveUserSession.namespacedBoxName(root, uid) =
  '<root>_<first 8 hex of uid, dashes stripped>'. A raw Hive.openBox('workoutBox')
  therefore writes to a box the writer never opens — the single most important
  fact in this fix, and the one an earlier draft of the plan got wrong.
sync_methods: >-
  pushWorkoutLogsForSyncDomain() (sync_workout.dart:2017),
  pushNutritionLogsForSyncDomain() (sync_nutrition.dart:846),
  pushWeightLogsForSyncDomain() (sync_health.dart:545). Each is
  `_ensureSessionOpen()` then the private writer. Chosen over weeklyFullSync()
  deliberately — see impact_analysis.
restore_methods: not_applicable
cloud_table: workout_logs, nutrition_logs, nutrition_log_items, weight_logs
cloud_columns: >-
  workout_name (NOT exercise_name), date, duration_seconds, meal_type,
  total_calories, total_protein, weight_kg, notes, food_name, item_index
contract_test_path: test/supabase/sync_service_test.dart
ist_handling: >-
  The seeds use a FIXED synthetic date ('2026-01-15'), not DateTime.now().
  Deliberate: cloud `date` columns are IST (CLAUDE.md §4.5) while DateTime.now()
  in CI is UTC, so a "today" key would disagree with itself across the IST
  midnight window and flake for ~5.5h a day. cleanup() wipes every row for this
  user in setUp, so a fixed date cannot collide with seed data.
provider_invalidations: not_applicable
telemetry_op_types: >-
  Unchanged. Noted because it is load-bearing for falsifiability: each writer's
  try/catch is PER-KEY and sits INSIDE the loop, so a rejected payload is
  swallowed into telemetry and the row simply never lands.
cross_account_guard: >-
  GuardedBox.testBypassOwnership is deliberately left FALSE, and
  HiveUserSession.debugCurrentUidResolverForTests deliberately left NULL. Both
  exist and both would have worked. The test signs in as the same user it
  namespaces for, so the real ownership check (guarded_box.dart:74, reading
  Supabase.instance.client.auth.currentUser?.id) passes on its own. Setting the
  bypass would mask a genuine ownership mismatch — the one thing that guard is for.
forbidden_patterns_checked: >-
  Enumerated every caller of the changed helper rather than assuming: `grep -rn
  "SupabaseTestHelper.init(" test/` returns exactly two live callers
  (sync_service_test.dart:30, auth_restore_test.dart:25); the two edge_functions
  files only MENTION it in comments explaining they deliberately do not call it.
  Also `grep -rn "init(url:" test/` -> ZERO, which refuted the stated rationale
  for the override branch (see impact_analysis).
proposed_fix: >-
  T3/T4/T5 seed the user-scoped Hive boxes through HiveService.instance and call
  the three push*ForSyncDomain() forwarders, asserting the cloud row by VALUE
  with rows.single. setUpAll opens the shared boxes, marks HiveService
  initialised, then opens the user session for the signed-in uid.
  SupabaseTestHelper.init() routes through SupabaseService.instance.initialize()
  on the non-override path. T1's box accessor is repointed. setUp additionally
  clears workoutBox/nutritionBox. test.yml gains --concurrency=1.
regression_test_planned: >-
  The test file IS the regression test — that is the point of the change. Its
  discriminating property is that all three writers swallow per-key, so a broken
  writer yields zero rows and rows.single throws. See impact_analysis for
  exactly what is and is not proven about that.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "No lib/ code changed. `flutter analyze test/supabase/` clean (1 pre-existing deprecation info on the untouched override branch). The three writers and both session helpers were read at file:line, not inferred." }
  - { tier: 2, name: hive, status: fixed_in_this_batch, evidence: "Seeds now go through HiveService.instance.{workoutBox,nutritionBox,healthBox,userBox}, which resolve to the namespaced boxes the writers read. Previously the file raw-opened userBox/healthBox — user-scoped ROOTS that openForUser closes and deleteBoxFromDisk's." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "No migration. Column names taken from the writers and from backups/live_schema_columns.json: workout_logs has workout_name and no exercise_name; nutrition_log_items has item_index and no user_id." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data migration. The tests write and delete only test6@gmail.com's own rows." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration applied." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function changed or deployed." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job involved." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "No policy changed. nutrition_log_items SELECT is EXISTS(... nl.user_id = auth.uid()), so the new .eq('log_id', ...) child query is authorised for the signed-in QA user and cannot read another user's items." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets, status: verified, evidence: "Unchanged. Confirmed the QA credentials exist ONLY as GitHub secrets: local .env holds SUPABASE_URL / SUPABASE_ANON_KEY / RAZORPAY_KEY_ID and no test email or password. This is why the live run happens in CI — see impact_analysis." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "The tests now exercise the real client->server contract end to end: Hive seed -> production writer -> PostgREST -> cloud row read back by value. That is the whole change." }
impact_analysis: >-
  WHY THESE FORWARDERS AND NOT weeklyFullSync(). An earlier design drove
  weeklyFullSync() and accumulated three independent unconditional-failure
  mechanisms across three review rounds: it never calls _ensureSessionOpen(), so
  the user-scoped boxes stay shut; its 20-way fan-out would have needed nine
  cleanupTables additions in FK order, two of which have no user_id and would
  have yielded a swallowed 42703 (coverage that reads green and deletes
  nothing); and every sub-sync is wrapped in _safeRestoreOp inside
  Future.wait(eagerError: false), so failures never propagate. The narrow
  forwarders have none of those properties: each calls _ensureSessionOpen(),
  each touches one domain already inside cleanup()'s table list, and none is
  wrapped — a box-access StateError reddens the test loudly.
  .
  WHAT IS PROVEN, AND WHAT IS NOT. Proven locally: the file compiles
  (flutter analyze clean); the suite loads and takes its skip branch; the whole
  test/supabase/ directory is 20/20 green with no dart-defines, including the
  14-test credential-free guard suite, so the helper change did not break the
  define-less Unit Tests path. NOT proven locally: that the three tests PASS
  against live Supabase, and that they REDDEN when a writer breaks. Both need
  the QA credentials, which exist only as GitHub secrets and which I do not
  handle. The live pass is settled by CI on push. The discrimination control is
  NOT settled by CI either — it would require pushing a deliberately broken
  writer. What is available instead is a link-by-link argument, and it should be
  read as strictly weaker than a run: (1) the failure modes are OBSERVED, not
  hypothesised — the current tests fail with exactly PGRST204 and 22P02 against
  today's correct writers, which is the live cloud rejecting those exact shapes;
  (2) each writer's catch is per-key inside the loop, verified at three
  file:line by me and independently by round 2, so a rejected payload leaves
  zero rows; (3) queryTable then returns [] and rows.single throws. Each link is
  verified; the composition has not been executed.
  .
  A CORRECTION WORTH RECORDING. Round 2 caught that the T4 discrimination
  control as first written could not fire the mechanism it named:
  mergeNutritionLogsBySlot builds a FRESH map (sync_nutrition.dart:23-33) with
  no Hive key and no id, so "reinstate the Hive string id" would evaluate to
  null and give 23502, not the 22P02 it claimed to reproduce. It would still
  have reddened — which is exactly why it mattered. A control that reddens for
  the wrong reason still reads as proof.
  .
  PRE-EXISTING RACE FIXED IN PASSING (round-2 P1). test.yml:389 ran `flutter
  test test/supabase/` — both sync_service_test.dart and auth_restore_test.dart
  — with no --concurrency, and dart_test.yaml sets none. Both sign in as the
  same QA uid and both call SupabaseTestHelper.cleanup() in setUp, a DELETE
  across 12 tables. The dart runner defaults to parallel suites, so one file's
  setUp could wipe the other's rows between its write and its read, failing with
  a correct writer. This pre-dates this batch (today's `expect(rows, isNotEmpty)`
  fails the same way) but this batch WIDENS the window, because the nutrition
  path now does parent upsert -> id lookback -> child upsert -> two selects.
  Fixed with --concurrency=1, which also restores the stated meaning of
  rows.single. Surfaced by review, so fixed here rather than recorded (§4.2).
  .
  AND THE MIRROR (B-pass P2). I fixed that race on the `Run Supabase tests`
  step, wrote the governing principle in a comment above it — "integration
  suites sharing one cloud account cannot run concurrently" — and left the
  `Run Edge Function tests` step in the SAME JOB unpinned, where
  ai_proxy_test.dart:67 and pgvector_test.dart:79 sign in as the same QA
  account and pgvector_test.dart:98,110 DELETEs memory_embeddings in setUp and
  tearDown. Fixing the instance and leaving the mirror is this repo's most
  recurrent self-inflicted class (feedback_mistake_guard_without_its_mirror,
  12 instances across 4 sessions), and this is a textbook case: the general
  rule was written down and then applied to one of the two places it governs.
  Both steps now carry the flag. The lesson is the one already in the file —
  after writing a guard, enumerate the sites it should cover and check EACH,
  rather than checking the one that prompted it.
related_bugs:
  - "2026-06-02 cross-user PK collision family — workout_logs and weight_logs
     (migration 082), same cure (omit id + user-inclusive natural key). The
     tests had frozen the pre-fix shape."
  - "c9f2a7 / 2026-04-18 — nutrition_logs stayed at 0 rows because the payload
     spread the Hive map including the string id; PostgREST 400-rejected every
     call and the catch swallowed it. T4 was reproducing this bug."
  - "a8b2c7 (workout_templates), c8e4a1 (scheduled_workouts) — same omit-id class."
  - "3b7e1c — the TestWidgetsFlutterBinding HttpOverrides 400 stub, which is why
     this file must not reuse test/helpers/hive_test_setup.dart."
  - "OI-121 — zero assertions in these files had ever executed, which is what
     let the drift stay invisible."
recurrence: >-
  Yes — writer/reader drift, the repo's most recurrent class (§4.1, >=15
  instances). The distinguishing feature here is that the READER was a TEST, and
  a test that re-implements its writer is drift-blind by construction: it cannot
  fail when the writer changes, because it never reads the writer. That is the
  general lesson, not the three column names.
---

# Sync tests re-implemented the writer instead of driving it

## What was wrong

`test/supabase/sync_service_test.dart` T3/T4/T5 each built their own
`.upsert()` payload and sent it to the same table the production writer targets.
They asserted that *their own payload* round-tripped. Whether the writer worked
was never in scope.

Three consequences, in increasing order of seriousness:

1. The payloads drifted (wrong column, wrong id type) and no test noticed.
2. The drift was **toward known-bad shapes** — each one is a bug that was found
   and fixed in production months earlier.
3. The tests could never have detected the fix regressing, which is the only
   reason to have them.

## The fix

Seed Hive, call the production entry point, assert the cloud row:

```dart
await HiveService.instance.workoutBox.put('wlog_$seedDate', {
  'date': seedDate, 'workout_name': 'Push A', 'duration_seconds': 3600, ...
});
await SyncService.instance.pushWorkoutLogsForSyncDomain();
final row = (await SupabaseTestHelper.queryTable('workout_logs')).single;
expect(row['workout_name'], 'Push A');
```

Whatever payload shape the writer adopts next, the row still has to arrive. That
property is drift-proof; re-implementing the payload is not.

## The one fact that makes or breaks it

The three boxes are **user-namespaced**. `HiveService.workoutBox` resolves via
`wrapUserScopedBox` to `workoutBox_<8hex(uid)>`. Seeding a raw
`Hive.openBox('workoutBox')` writes somewhere the writer never looks, the writer
finds nothing, and the test fails with a perfectly correct writer. An earlier
draft of this plan prescribed exactly that, having read
`Box get workoutBox => workoutBoxGuarded.rawBox` and stopped one hop short.

The forwarders resolve this themselves: each calls `_ensureSessionOpen()` →
`HiveUserSession.ensureOpenedForCurrentSession()` → `openForUser(uid)`, which
opens the namespaced boxes. `weeklyFullSync()` does not, which is the main
reason it is the wrong entry point here.

## What this does not prove

The QA credentials live only as GitHub secrets. Locally the suite skips, so the
live pass is settled by CI and the discrimination control is not settled
anywhere — proving it would mean running a deliberately broken writer against
the live project. The frontmatter's `impact_analysis` states the link-by-link
argument that stands in its place, and states plainly that it is weaker than a
run. Anyone with the credentials can close it in one command by mutating a
writer locally and confirming the matching test reddens.
