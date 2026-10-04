---
bug_id: d4b8e2
date: 2026-06-02
batch: apk-obs-2026-06-02
status: fixed
blast_radius: catastrophic
symptom: >
  Investigating the weekly report's "0 workouts" for upendra, the cloud had
  workout_log_exercises rows through today but NO workout_logs session-summary row
  newer than 05-21. Root: the cloud sync id was seeded from the DATE ONLY
  (_deterministicId('wlog_<date>'), no user_id) — so two users completing a workout
  on the SAME calendar date generated the SAME uuid → cross-user collision on
  workout_logs_pkey (23505); the second user's row was silently dropped (10x
  upsert_workout_log 23505 in telemetry at 06-02 03:05; uuid_v5('wlog_2026-06-02')
  = b60adcc9… is owned by a DIFFERENT user, amar). Systemic: the same un-user-scoped
  id (and, for workout_log_exercises/sets, a natural-key UNIQUE lacking user_id)
  affects weight_logs / sleep_logs / body_measurements / workout_log_exercises /
  workout_log_sets. workout_log_exercises is worst — its onConflict DO UPDATE could
  overwrite ANOTHER user's row (silent cross-user CORRUPTION), not just collide.
concept: sync_fanout_workout_domain
sot_registry_entry: sync_fanout_workout_domain
recurrence: "Same family as the 23503 omit-id class (nutrition_logs c9f2a7, workout_templates a8b2c7, scheduled_workouts c8e4a1) — those omit id + use a USER-INCLUSIVE natural key already. This batch finishes the sweep for the remaining per-user tables that still sent a date-only id and/or had a natural key missing user_id."
related_bugs:
  - c9f2a7
  - a8b2c7
  - c8e4a1
writers: >
  lib/core/services/sync/sync_workout.dart _syncWorkoutLogs (workout_logs),
  _syncExerciseLogs (workout_log_exercises summary + workout_log_sets per-set);
  lib/core/services/sync/sync_health.dart _syncWeightLogs (weight_logs),
  _syncMeasurements (body_measurements), _syncSleepLogs + syncSleepNow list-path
  (sleep_logs). All previously sent SyncService._deterministicId(<date-only key>)
  as id and/or used a natural-key onConflict without user_id.
readers: >
  lib/core/services/sync_service.dart _restoreWorkoutLogs / _restoreExerciseLogs /
  health restore paths (cloud → Hive); supabase/functions/weekly-report (reads
  workout_log_exercises + workout_logs). The dropped/overwritten rows made the
  cloud projection wrong for any colliding user.
hive_key_prefix: wlog_ / exlog_ / weight_ / sleep_log_ / measurement_
hive_key_formula: >
  wlog_${istDateStr}; exlog_${istDateStr}_${nameHash}; weight_${istDateStr};
  sleep_log_${istDateStr}; measurement_${istDateStr}. None embedded user_id, so
  _deterministicId over them was identical across users for the same date.
sync_methods: _syncWorkoutLogs, _syncExerciseLogs, _syncWeightLogs, _syncMeasurements, _syncSleepLogs, syncSleepNow
restore_methods: _restoreWorkoutLogs, _restoreExerciseLogs, health restore paths
cloud_table: workout_logs, workout_log_exercises, workout_log_sets, weight_logs, sleep_logs, body_measurements
cloud_columns: >
  workout_logs(id pk, user_id, date, workout_name, …) UNIQUE(user_id,date,workout_name);
  workout_log_exercises(id pk, user_id, workout_log_id, exercise_id, set_number, …);
  workout_log_sets(id pk, user_id, workout_log_id, exercise_id, set_number, reps …);
  weight_logs/sleep_logs/body_measurements(id pk gen_random_uuid, user_id, date, …).
  Migration 082 adds UNIQUE(user_id,date) on weight/sleep/body and replaces the
  global UNIQUE(workout_log_id,exercise_id,set_number) with
  UNIQUE(user_id,workout_log_id,exercise_id,set_number) on wle + wls; widens
  wls_reps_realistic to <=1000. All id columns default gen_random_uuid() (verified live).
contract_test_path: test/contracts/sync_user_scoped_natural_keys_test.dart
ist_handling: not_applicable (no date math changed; ids/onConflict only)
provider_invalidations: not_applicable (background cloud-replay; local Hive + providers already updated at write time)
telemetry_op_types: >
  unchanged sinks: upsert_workout_log / upsert_workout_log_sets / upsert_weight_log /
  upsert_sleep_log / upsert_body_measurement via _reportSyncFailure +
  recordNonFatal. The fix removes the 23505/23514 causes so those stop firing.
cross_account_guard: >
  This bug WAS a cross-account guard hole at the cloud layer (date-only ids let one
  user's upsert collide with / overwrite another's). The fix closes it: ids are now
  unique per user (omit id → gen_random_uuid) and every onConflict arbiter includes
  user_id, so an upsert can only ever touch the syncing user's own row.
forbidden_patterns_checked:
  - "A per-user sync upsert that sends a date-only deterministic id (collides cross-user on the PK) — eliminated: id is OMITTED everywhere (gen_random_uuid default); pinned by test/contracts/sync_user_scoped_natural_keys_test.dart."
  - "A per-user table's onConflict arbiter without user_id (cross-user merge/overwrite) — eliminated: every arbiter now leads with user_id; migration 082 backs them with user-inclusive UNIQUE indexes."
proposed_fix: >
  Apply the proven omit-id + user-inclusive-natural-key pattern to every remaining
  per-user sync table. Client (sync_workout.dart + sync_health.dart): OMIT id from
  the upsert payload (gen_random_uuid on insert / existing id kept on conflict) and
  switch onConflict to a USER-INCLUSIVE natural key — weight/sleep/body →
  'user_id,date'; workout_log_exercises + workout_log_sets →
  'user_id,workout_log_id,exercise_id,set_number'. (workout_logs already had
  UNIQUE(user_id,date,workout_name); just omit its id.) Migration 082 adds the
  missing user-inclusive UNIQUE indexes (and drops the old global ones on wle/wls)
  + widens wls_reps_realistic <=60 → <=1000 (the sibling wle was widened by 080;
  this table was missed → 23514 on high-rep per-set rows). NO historical re-key:
  existing rows keep their ids and merge via the now-user-inclusive natural key on
  next sync (their key is unchanged because workout_log_id stays date-only — only
  the INDEX gains user_id); only never-synced / collided rows insert fresh. Verified
  live before writing the migration: all arbiter columns NOT NULL (no 42P10 — the
  indexes are non-partial) and ZERO existing duplicates on every new key.
  Deploy-ordering: migration 082 ships WITH the matching APK (dropping the old
  global wle/wls unique makes an old client's onConflict 42P10 until it updates —
  acceptable pre-launch, single device).
regression_test_planned: >
  test/contracts/sync_user_scoped_natural_keys_test.dart (comment-stripped
  source-grep): every affected upsert OMITS id; weight/sleep/body use
  onConflict 'user_id,date'; wle/wls use onConflict with user_id leading; migration
  082 creates the user-inclusive UNIQUE indexes + widens wls_reps_realistic.
  Behavioral proof: live rollback-txn arbiter check post-migration (INSERT … ON
  CONFLICT (user_id,date) … in a rolled-back txn) — the sync layer has no fakeable
  Supabase-client harness, so the cross-user-retention proof is the live schema +
  the b60adcc9 collision evidence + the post-deploy re-sync (upendra's 06-02
  workout_logs row lands once ids are user-scoped).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "sync_workout.dart (workout_logs/exlog/sets) + sync_health.dart (weight/body/sleep x2) omit id + user-inclusive onConflict; flutter analyze clean on the changed files" }
  - { tier: 3, layer: postgres_schema, status: fixed_in_this_batch, evidence: "migration 082 written: UNIQUE(user_id,date) on weight/sleep/body; UNIQUE(user_id,wlog,ex,set) replacing the global ones on wle/wls; wls_reps_realistic <=1000. Apply pending (deploy phase, with the APK)" }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "live 2026-06-02: workout_logs_pkey is the only collision arbiter; uuid_v5('wlog_2026-06-02')=b60adcc9 owned by amar (upendra had NO 06-02 summary row); 10x 23505 in telemetry; all new-key arbiter cols NOT NULL + 0 existing dups (safe index create, no re-key)" }
  - { tier: 6, layer: edge_function_vs_deploy, status: verified, evidence: "weekly-report reads workout_log_exercises (which DID reach cloud) — its '0 workouts' was stale cache (fixed separately, c7a1f5); the workout_logs collision is the deeper data-loss this doc fixes" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "post-fix, two users on the same date each retain their own rows (unique gen_random_uuid id + user-inclusive arbiter); upendra's 06-02 workout_logs summary lands on next sync" }
impact_analysis: >
  Catastrophic blast radius — touches the cloud identity of every per-user log table
  (workouts, sets, weight, sleep, measurements). With a date-only id and (for
  wle/wls) a natural key lacking user_id, any two users acting on the same calendar
  date collided: workout_logs / weight_logs / sleep_logs / body_measurements lost
  the second user's row to a 23505 PK collision (silently swallowed), and
  workout_log_exercises could DO-UPDATE another user's row (reassigning user_id) —
  silent cross-user data corruption. Latent at one real user; the collision
  probability scales with the user base (any shared calendar date + common exercise
  name). The cure is the codebase's established omit-id + user-inclusive-natural-key
  pattern (already used by nutrition_logs / workout_templates / scheduled_workouts),
  now applied to the last holdouts. Crucially it needs NO historical re-key: because
  workout_log_id stays date-only and only the INDEX gains user_id, existing rows'
  natural keys are unchanged → they merge on next sync (keeping their ids), while
  collided/never-synced rows insert fresh under a unique gen_random_uuid. Verified
  safe before writing the migration (NOT NULL arbiters, zero dup blockers,
  non-partial indexes → no 42P10). Found via the Obs-3 weekly-report audit + a
  read-only background sub-agent trace, then independently re-verified live (I caught
  one wrong sub-agent claim: it said the (user_id,date,workout_name) index was
  missing — it exists; the real collision is on the global PK).
---

# Cross-user sync-ID collision — date-only deterministic ids on per-user tables

## What happened
The weekly-report audit found upendra's cloud `workout_logs` had no
session-summary row since 05-21 despite recent workouts. The cloud sync id was
`uuid_v5('wlog_<date>')` — **date-only, no user** — so two users on the same date
produced the **same uuid** → PK collision (23505); the loser's row was silently
dropped. `uuid_v5('wlog_2026-06-02')` is already owned by amar; upendra got 10×
23505. The same un-user-scoped identity affects `weight_logs`, `sleep_logs`,
`body_measurements`, and (worse, via a natural key lacking `user_id`)
`workout_log_exercises` / `workout_log_sets` — where `DO UPDATE` could overwrite
another user's row outright.

## Fix
Apply the proven **omit-id + user-inclusive natural-key** pattern everywhere:
clients OMIT `id` (gen_random_uuid default) and `onConflict` on a user-inclusive
key; **migration 082** adds the missing `UNIQUE(user_id,date)` (weight/sleep/body)
and replaces the global `UNIQUE(wlog,ex,set)` with `UNIQUE(user_id,wlog,ex,set)`
on wle/wls, and widens `wls_reps_realistic` to 1000. **No historical re-key** —
existing rows merge via their (unchanged) natural key on next sync. Verified live:
NOT NULL arbiters, zero dup blockers, non-partial indexes.

## Verification
- Live: `workout_logs` PK is the collision arbiter; `b60adcc9` owned by amar; 10×
  23505 telemetry; all new-key arbiter cols NOT NULL; 0 existing dups.
- `sync_user_scoped_natural_keys_test.dart` (source-grep) + post-deploy rollback-txn
  arbiter check + post-sync re-verification (upendra's 06-02 summary lands).

## Lesson / class
A per-user sync row's identity MUST include the user — both the PK id (omit it →
gen_random_uuid) and every `onConflict` arbiter. A date-only id silently loses or
corrupts rows the moment two users share a date. This finishes the omit-id sweep
the 23503 fixes started.

## See also
- `lib/core/services/sync/sync_workout.dart`, `lib/core/services/sync/sync_health.dart`
- `supabase/migrations/082_user_scoped_sync_natural_keys.sql`
- Prior omit-id instances: `c9f2a7`, `a8b2c7`, `c8e4a1`
- `feedback_partial_unique_arbiter_trap.md`, `feedback_writer_reader_field_drift_recurring.md`
