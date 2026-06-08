---
bug_id: c5a1f2
date: 2026-06-07
batch: slowboot-returning-user-guard
status: fixed
blast_radius: account
symptom: >
  A returning, signed-in user waited >1 minute on cold start: RestoringScreen._goHome
  unconditionally awaited the full since='2020-01-01' cloud restore before navigating
  to /home (the background-restore path existed but was gated behind a default-OFF
  opt-in flag bg_restore_enabled). Live on the founder's account (d7a67a37, APK +28):
  "loading took like forever, more than a minute". This is the perf follow-up flagged
  by e4a8b1. Flipping returning users to the background path then exposed a SECOND,
  data-loss-class risk: the restore runs concurrently with the user logging, and the
  exlog / wlog / nutrition / saved-meal restore writers did an UNCONDITIONAL put of the
  cloud row over the local one — overwriting a just-logged row with a stale cloud
  snapshot (a true loss if the local write had not yet synced — a network blip, the
  founder's original incident class).
concept: restore_completeness
sot_registry_entry: restore_completeness
writers: >
  RestoringScreen._goHome (restoring_screen.dart) gates the bg vs blocking path —
  flipped from opt-in `bg_restore_enabled == true` to opt-OUT `disable_bg_restore`
  kill-switch (returning users default to bg). sync/sync_workout.dart
  _restoreExerciseLogs + _restoreWorkoutLogs and sync/sync_nutrition.dart
  _restoreNutritionLogs + _restoreSavedMeals now guard their put with a local-existence
  check (additive / local-wins). WorkoutWriteService.addToExlogIndex (shared add-only
  union index-append) + reconcileExlogIndexes (post-restore orphan-heal).
readers: >
  home_screen / train read restored Hive via restoreCompletedTick → invalidateOnRetry;
  workout_read_service.exerciseLogsForIstDate finds a day's logs via
  exercise_log_index_<date> (kept intact by the additive guard + reconcile).
hive_key_prefix: "exlog_ / wlog_ / nlog_ / saved_meal_"
hive_key_formula: "exlog_<istDate>_<uuidv5(name)>; wlog_<istDate>; nlog_<istDate>_<meal>_<hash>; saved_meal_<nameHash>; index exercise_log_index_<istDate>"
sync_methods: "restoreFromCloudForUser, syncWorkoutData, syncNutritionData"
restore_methods: "_restoreExerciseLogs, _restoreWorkoutLogs, _restoreNutritionLogs, _restoreSavedMeals (now additive local-wins); _restoreScheduledWorkouts (already timestamp-merge, d9b2c5); weight/measurements/water (already additive — reference pattern, sync_health.dart:300)"
cloud_table: "workout_log_exercises, workout_logs, nutrition_logs, user_saved_meals"
cloud_columns: not_applicable (no column change — local Hive write-policy change)
contract_test_path: test/contracts/restore_local_wins_additive_test.dart
ist_handling: not_applicable (index/row keys already IST date-keyed at write)
provider_invalidations: "restoreCompletedTick → invalidateOnRetry(ref) on home (unchanged)"
telemetry_op_types:
  success: ["bg_heal_exlog_index (reconcile)"]
  failure: ["bg_heal_exlog_index (recordNonFatal on reconcile throw)"]
cross_account_guard: preserved — the bg path keeps `await HiveUserSession.openForUser` BLOCKING before navigation (APK #15.4); a fresh install (no local profile) still uses the blocking path.
forbidden_patterns_checked:
  - "opt-in bg_restore_enabled gate (returning users blocked on full restore) — replaced by opt-out disable_bg_restore kill-switch; default bg for returning users."
  - "unconditional cloud-over-local put in _restoreExerciseLogs / _restoreWorkoutLogs / _restoreNutritionLogs / _restoreSavedMeals — now guarded by a local-existence (additive) check."
  - "a per-date index lock sold as a race-fix — REMOVED: a control test (25 concurrent unlocked appends → all survived) refuted the race; Hive commits in-memory before yielding so the index read→put is atomic on the single isolate."
proposed_fix: >
  (1) Flip _goHome to opt-out: returning users (local profile present) take the
  background-restore path (home in ~3s) unless `disable_bg_restore` is set; fresh
  installs still block (§4.6 — old path preserved + reachable). (2) Make the
  loss-sensitive restore writers additive / local-wins (skip the put when the local
  row exists), mirroring the proven weight-restore pattern — so a background restore
  can only fill gaps, never overwrite a just-logged local row. (3) Defense-in-depth:
  the post-restore heal calls reconcileExlogIndexes, which rebuilds every
  exercise_log_index_<date> as the union of the exlog_ rows actually present (heals
  the e4a8b1 index-drift class for a row the additive restore left untouched).
regression_test_planned: >
  test/contracts/restore_local_wins_additive_test.dart — behavioral (addToExlogIndex
  add-only union under concurrency + repetition; reconcileExlogIndexes rebuilds a
  drifted index) + source contract (each of the 4 restore writers carries its
  local-existence additive guard). test/contracts/background_restore_test.dart updated
  for the opt-out kill-switch + fresh-install-still-blocks + reconcile-in-heal.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "gate flip + additive guards + reconcile; flutter analyze clean (info-only) on the 4 changed files" }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "restore never overwrites a present local row; addToExlogIndex union + reconcile keep the index complete; restore_local_wins_additive_test + 1656 sync/safety/contract tests green" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "restore still pulls + writes absent rows (round-trip + field-canonical + deterministic-key tests green); _restoreScheduledWorkouts merge untouched (its non-skip test still green)" }
impact_analysis: >
  Account blast radius. The slow boot hit every returning user whose cold-start ran the
  full restore (≈49s observed). The flip removes that wait. The flip's own risk — a
  concurrent restore overwriting a just-logged local row — is closed by the additive
  local-wins policy (founder-chosen; consistent with weight/measurements/water, which
  were already additive, and with _restoreScheduledWorkouts, which already merges).
  Trade-off documented in ADR: a row edited on a SECOND device will not overwrite a
  local copy on this one (pure offline-first local-wins) — acceptable for the current
  single-primary-device assumption. related_bugs: 4e8b1d (cold-start blocking restore
  — this is its real fix), e4a8b1 (fire-and-forget index durability — same data-loss
  class; reconcile heals its drift).
---

# Slow boot (returning user) + additive local-wins restore (c5a1f2)

## What happened
The founder (APK +28) saw a >1-minute cold-start boot. Root cause: `RestoringScreen._goHome`
unconditionally `await`s the full `since='2020-01-01'` cloud restore before navigating to
/home for returning users. A background-restore path already existed (a7d3f1) but was gated
behind a default-OFF opt-in flag, so returning users always blocked on the full restore. This
is the perf follow-up that the e4a8b1 diagnose explicitly flagged.

## The flip — and the risk it exposed
Flipping returning users to the background path (home immediately, restore in the background)
makes the restore run **concurrently with the user logging on /home**. The exlog / wlog /
nutrition / saved-meal restore writers did an **unconditional `put`** of the cloud row over the
local one. With restore now concurrent, a just-logged row could be overwritten by the stale
cloud snapshot — and if the local write had not yet synced (a network blip, the founder's
original incident), the data would be **truly lost**.

A hypothesised index read-modify-write "race" was investigated and **refuted**: a control test
(25 concurrent UNLOCKED index appends → all 25 survived) showed Hive commits the value
in-memory before it yields for the disk flush, so the index read→put has no gap on the single
isolate. The real loss vector was the unconditional row overwrite, not the index.

## Fix
1. **Gate flip** — `_goHome` uses an opt-OUT `disable_bg_restore` kill-switch; returning users
   default to the background path; fresh installs still block; ownership gate stays blocking
   (APK #15.4). §4.6 — old path preserved + reachable.
2. **Additive / local-wins restore** — `_restoreExerciseLogs`, `_restoreWorkoutLogs`,
   `_restoreNutritionLogs`, `_restoreSavedMeals` skip the `put` when the local row exists.
   Mirrors the weight-restore pattern (`sync_health.dart:300`). A restore only fills gaps.
3. **Defense-in-depth** — the post-restore heal calls `reconcileExlogIndexes`, rebuilding each
   `exercise_log_index_<date>` as the union of the present `exlog_` rows.

## Verification
- `test/contracts/restore_local_wins_additive_test.dart` (behavioral union/reconcile + source
  contract for all 4 additive guards).
- `test/contracts/background_restore_test.dart` updated (opt-out kill-switch, fresh-install
  blocks, reconcile-in-heal).
- `flutter analyze` clean (info-only); 1656 sync + safety + contract tests green.

## See also
- lib/features/auth/screens/restoring_screen.dart (`_goHome`, `_healAfterRestoreInBackground`)
- lib/core/services/sync/sync_workout.dart + sync/sync_nutrition.dart (additive guards)
- lib/core/services/workout_write_service.dart (`addToExlogIndex`, `reconcileExlogIndexes`)
- docs/diagnoses/2026-06-05-cold-start-blocking-restore-4e8b1d.md (slow boot, prior)
- docs/diagnoses/2026-06-06-exlog-index-fire-and-forget-durability-e4a8b1.md (data-loss class)
- docs/adr/ (local-wins / additive restore decision)
