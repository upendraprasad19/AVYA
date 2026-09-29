---
source: CLAUDE.md §4 + §15
migrated: 2026-05-18
status: scaffold
---

# Sync + Data Architecture — Reference

> Cross-cutting concern. Fetch via Read when working on sync, Hive contracts, or restore-completeness.
> Root CLAUDE.md contains pointers but not the full content.

## Overview — Offline-first architecture

```
┌─────────────────────────────────────────────────────┐
│                    FLUTTER APP                       │
│                                                      │
│  ALL reads/writes → Hive (LOCAL-FIRST)               │
│  Zero latency. Works fully offline.                  │
│                                                      │
│  SEED DATA (bundled JSON in APK):                    │
│    assets/data/exercise_library.json (200+ exercises)│
│    assets/data/food_database.json (1431 foods)        │
│    → Parsed into Hive on first launch                │
│                                                      │
│  SYNC TO SUPABASE:                                   │
│    Immediately: custom foods/exercises (community)    │
│    Every app launch: pushSnapshot() (AI context)     │
│    Daily (app launch if >1d): full sync all logs     │
│                                                      │
│  RESTORE (new device):                               │
│    Login → pull from Supabase → populate Hive        │
│    ALL users: full history (storage per user ~1-2MB)  │
│                                                      │
│  SUPABASE ROLE (NOT primary DB):                     │
│    • Auth (Supabase Auth)                            │
│    • Backup + cross-device restore                   │
│    • AI training corpus (snapshots, conversations)   │
│    • Community DB growth (custom foods/exercises)     │
│    • Subscription verification                       │
└─────────────────────────────────────────────────────┘
```

### Hive Boxes
| Box | Contents |
|-----|----------|
| `userBox` | user profile, preferences, progress |
| `workoutBox` | workout_logs, scheduled_workouts, templates, exercise_logs |
| `nutritionBox` | nutrition_logs, saved_meals |
| `healthBox` | weight_logs, measurements, streaks, sleep_logs |
| `exerciseBox` | exercise_library (seeded from bundled JSON) |
| `foodBox` | food_database (seeded from bundled JSON) |
| `customBox` | user_custom_exercises, user_custom_foods |
| `coachBox` | ai_coach_interactions, coaching_notes |
| `syncBox` | last_sync_timestamps + `pending_sync_<id>` rows (the retry queue — **corrected 2026-09-16**: this row said "planned, not yet implemented" for months after `lib/core/services/sync_queue.dart` shipped; see that file's header for the drain triggers and diagnose docs/diagnoses/ for the auto-drain gap this same date closed) |
| `configBox` | subscription status, feature flags, app config |

#### SyncBanner display policy (2026-09-17)

The "N changes waiting to sync" count is NOT the raw queue depth: it shows
**pending ops older than the 6-minute grace window**
(`syncBannerGraceWindow` in `lib/shared/providers/sync_state_provider.dart`,
applied by one state funnel `_stateFor` behind the
`disable_sync_banner_grace` kill-switch — which restores the raw count).
Rationale: a login-time `user_progress` version conflict enqueues an op
that the next 5-min auto-drain tick typically self-heals (observed live
2026-09-17, test2/web: enqueue 23:17:40 IST → cleared 23:22:38 IST); the
banner flashing for that window reads as an error when nothing needs the
user. Consequence: the banner can **undercount** transiently (an aged op
succeeds while a young op is still queued) — the intended tradeoff. The
manual **Retry** tap issues a FORCED drain (`drain(force: true)`,
`disable_sync_force_retry` kill-switch): it retries ops even inside their
backoff window, so the tap can never be a silent no-op; auto drains
(app-launch, connectivity, 5-min timer) stay unforced.

#### workoutBox Key Patterns
| Key Pattern | Value |
|-------------|-------|
| `schedule_YYYY-MM-DD` | Schedule entry (type, status, workout_name, exercises, week) |
| `exercise_log_index_YYYY-MM-DD` | List of exercise log IDs for that date |
| `exlog_<timestamp>_<hash>` | Exercise log: exercise_name, logging_type, weight_kg, reps_completed, sets_completed, volume_kg, is_pr |
| `wlog_<timestamp>` | Workout log: workout_name, date, duration_seconds, sets_completed |
| `tmpl_<uuid-v4>` | Workout template (single-day) — fields: id, name, exercises[], exercise_count, type:'template', assigned_days:[int], created_at. OI-252 (2026-09-27): the uuid is client-minted ONCE at create time (`WorkoutWriteService.newTemplateKey()`), never re-derived from name/content — stable across rename/delete/recreate. Supersedes the legacy `tmpl_<ms>` / `tmpl_<nameHash>` schemes (`TemplateIdentityMigrator` rekeys any surviving legacy row). Delete is a rename-on-delete tombstone (`deleted_at` set server-side), not a row drop. Multi-day AI templates (from `createCustomTemplate` tool) split into N rows tagged with `group_id`/`group_day_index`/`group_total_days` for cross-row identification. |

## Sync schedule + SoT rules

| When | What | Where |
|------|------|-------|
| Immediately | Custom foods/exercises added | → Supabase (community contribution) |
| Immediately (fire-and-forget) | Every nutrition mutation (log meal, water, urine, edit/delete food, scan meal save, barcode save, custom exercise create) fires `SyncService.syncNutritionData()` + `pushSnapshot()` | → Supabase + AI snapshot |
| Immediately (fire-and-forget) | Every workout mutation (complete, edit log, template save/delete, schedule change) fires `SyncService.syncWorkoutData()` + `pushSnapshot()` | → Supabase + AI snapshot |
| Every app launch | user_daily_snapshot (AI context) via pushSnapshot() | → Supabase |
| Daily 11PM IST | coaching_notes extraction — watermark-bounded (conversations since the last successful extraction, NOT "that day's"; single-owner a2b-1, 2026-09-27) + metered 1/6h via `consume_quota` | → Hive + Supabase |
| Daily (app launch if >1d) | Full sync: all logs, progress, preferences | → Supabase |
| Periodically | Check for new approved community items | ← Supabase → Hive |
| On restore | Pull full history (all users) | ← Supabase → Hive |

### Fire-and-Forget Sync Pattern
All mutation paths use `unawaited()` from `dart:async` to push changes without blocking UI:

```dart
import 'dart:async';
import 'package:icanbefitter/core/services/sync_service.dart';

// In any mutation (logFood, addWater, saveMeal, completeWorkout, etc.):
await hiveBox.put(key, value);            // 1. Hive-first (blocking)
ref.invalidate(dependentProvider);        // 2. Refresh UI (blocking)
unawaited(SyncService.instance.syncNutritionData());  // 3. Push to Supabase (background)
unawaited(SyncService.instance.pushSnapshot());       // 4. Refresh AI context (background)
```

**Never `await` the sync calls** — they must not block the UI. Failures are logged via `debugPrint` inside the service and silently ignored; the local Hive write is the source of truth. Use `syncWorkoutData()` for workout mutations and `syncNutritionData()` for nutrition mutations (parallels the workout method, syncs `nutrition_logs` + `water_logs` in one batch).

### Sync Deduplication Rules
- **Streaks:** `onConflict: 'user_id,week_start'` (UNIQUE constraint in DB). Restore dedupes by `week_start` — cloud row replaces local if conflict found. Never dedup by cloud `id` alone (causes same-week duplicates).
- **Workout logs/exercises:** Upserted by deterministic UUID (`_deterministicId(localKey)`). Safe for re-sync.
- **Water logs:** `onConflict: 'user_id,date'` (UNIQUE constraint added migration 013). One row per user per day.
- **Scheduled workouts:** `onConflict: 'user_id,scheduled_date'` (UNIQUE constraint added migration 013). One schedule per user per date.

### Sync skip pattern: `SyncSkipIndex` (day-swapper + sync-load batch — supersedes the per-domain OI-204 fingerprint code)

**Problem this closes (OI-204, diagnose `d3f8a6`):** a coalesced, fire-and-forget sync entry
(`syncWorkoutData()` / `syncNutritionData()`, fired after every single mutation) re-walked the
caller's **entire** historical Hive log on **every** call — not just what changed since the
last successful push — and `await`ed a network upsert per row, sequentially. As a user's
history grew, a single pass routinely took 14-40s, tripping `SyncService.restoreOpTimeout`
(45s, diagnose `b7e4c1`).

**1. The one helper — `lib/core/services/sync/sync_skip_index.dart`.** Every history push in
the sync layer now goes through `SyncSkipIndex.pushIfChanged(rowKey, fingerprint, push,
{opType})`:
- Computes `fingerprint()` and compares it to the last CONFIRMED value stored for `rowKey`; a
  match skips the push entirely (fail-open: a fingerprint-computation exception pushes anyway
  and records nothing).
- Owns the `push()` try/catch itself — the domain loop cannot record a row as sent after a
  swallowed failure, the exact false-skip gap the pre-`SyncSkipIndex` per-domain OI-204 code
  (three hand-rolled fingerprint indexes, one per domain, each with its own swallowing-catch
  bookkeeping) could reach. `push()` throwing, or returning `false` (unconfirmed), both forget
  any stored fingerprint for that row and leave it unrecorded for the next pass.
- **Owner check:** `_ownerChangedNow()` is checked before AND after every push; once true the
  index is `aborted` and pushes/writes no more for the rest of the pass (an in-flight
  sign-out/account-swap cannot leak a write across accounts).
- **Kill switch:** each `SyncSkipDomain` carries its own `configBox` flag (below); when set,
  `pushIfChanged` never reads or writes the fingerprint (push every row, verbatim pre-pattern
  behaviour), and `commit()` deletes that domain's stored index outright.
- **`forcePushKeys`** (constructor, default empty; B-pass R1-F1, diagnose `a9d3f6`): row keys
  that push even when their fingerprint matches the stored one — for a caller that KNOWS the
  cloud lost a row the index still records as sent. Its one caller is the scheduled-workouts
  FK self-heal (`sync_workout.dart` `_syncScheduledWorkouts` → `_syncWorkoutTemplates(forceKeys:
  {rawTemplateId})`), which forces exactly the missing template. Deliberately not the kill
  switch: a disabled index deletes itself at `commit`, which would re-push EVERY row of that
  domain on the next pass. A forced push still records its fingerprint on success.
- **`commit({required liveKeys})`** persists the index ONCE per pass: prunes rows not in
  `liveKeys`, writes Hive only when something changed (`_dirty`), and no-ops entirely once the
  pass is `aborted`.
- **First failure per pass, per DISTINCT opType (D13):** a domain that shares one index across
  several underlying tables (`customItem`, for both `user_custom_exercises` and
  `user_custom_foods`) can see two different `opType` overrides fail in the same pass — both are
  reported once each. A single-opType domain still reports exactly once per pass, matching the
  pre-`SyncSkipIndex` behaviour.
- `Gate G1` (`scripts/check_sync_hash_skip_atomicity.dart`) is a structural rule, not a hand
  count: every `.upsert(`/`.insert(` inside a Hive-row loop in `lib/core/services/sync/**` and
  `sync_service.dart` must sit inside a `pushIfChanged(` closure (a short allowlist covers the
  single-row steps and the coach loop, which skips by its own stamped cloud id), and no code
  outside `sync_skip_index.dart` may write a `*_payload_hash_index` key.

**2. The domain table.** 17 `SyncSkipDomain` values (`lib/core/services/sync/sync_skip_index.dart`),
each `(indexKey, killSwitchKey, opType, box)`:

| Domain | Hive index key | box | Kill switch | Wraps |
|---|---|---|---|---|
| `sched` | `sync_sched_payload_hash_index` | workout | `disable_sched_hash_skip` | `_syncScheduledWorkouts` (`sync_workout.dart`) |
| `exlog` | `sync_exlog_payload_hash_index` | workout | `disable_exlog_hash_skip` | `_syncExerciseLogs` (`sync_workout.dart`) |
| `nlog` | `sync_nlog_payload_hash_index` | nutrition | `disable_nlog_hash_skip` | `_syncNutritionLogs` (`sync_nutrition.dart`) |
| `wlog` | `sync_wlog_payload_hash_index` | workout | `disable_wlog_hash_skip` | `_syncWorkoutLogs` (`sync_workout.dart`) — SoT concept `sync_workout_log_payload_hash_index` (the Hive key stays the short `wlog` form; only the SoT registry concept name spells it out) |
| `completion` | `sync_completion_payload_hash_index` | workout | `disable_completion_hash_skip` | `_syncScheduleCompletions` (`sync_workout.dart`) — SoT `sync_schedule_completion_payload_hash_index` |
| `template` | `sync_template_payload_hash_index` | workout | `disable_template_hash_skip` | `_syncWorkoutTemplates` (`sync_workout.dart`) — SoT `sync_workout_template_payload_hash_index` |
| `plan` | `sync_plan_payload_hash_index` | workout | `disable_plan_hash_skip` | `_syncWorkoutPlan` (`sync_workout.dart`, public entry `pushWorkoutPlanForSyncDomain`) — one row, key `kPlanBundleRowKey = 'bundle'`; SoT `sync_workout_plan_payload_hash_index`, aliased `plan_bundle_cloud_fingerprint` |
| `streak` | `sync_streak_payload_hash_index` | health | `disable_streak_hash_skip` | `_syncStreaks` (`sync_workout.dart`) |
| `water` | `sync_water_payload_hash_index` | health | `disable_water_hash_skip` | `_syncWaterLogs` (`sync_nutrition.dart`) — SoT `sync_water_log_payload_hash_index` |
| `steps` | `sync_steps_payload_hash_index` | health | `disable_steps_hash_skip` | `_syncStepsLogs` (`sync_health.dart`) — SoT `sync_daily_steps_payload_hash_index` |
| `urine` | `sync_urine_payload_hash_index` | health | `disable_urine_hash_skip` | `_syncUrineColorLogs` (`sync_health.dart`) — SoT `sync_urine_color_log_payload_hash_index` |
| `sleep` | `sync_sleep_payload_hash_index` | health | `disable_sleep_hash_skip` | `_syncSleepLogs` (`sync_health.dart`) — SoT `sync_sleep_log_payload_hash_index` |
| `weight` | `sync_weight_payload_hash_index` | health | `disable_weight_hash_skip` | `_syncWeightLogs` (`sync_health.dart`) — SoT `sync_weight_log_payload_hash_index` |
| `measurement` | `sync_measurement_payload_hash_index` | health | `disable_measurement_hash_skip` | `_syncMeasurements` (`sync_health.dart`) — SoT `sync_body_measurement_payload_hash_index` |
| `readiness` | `sync_readiness_payload_hash_index` | health | `disable_readiness_hash_skip` | `_syncReadiness` (`sync_health.dart`) — SoT `sync_readiness_daily_payload_hash_index` |
| `savedMeal` | `sync_saved_meal_payload_hash_index` | nutrition | `disable_saved_meal_hash_skip` | `_syncSavedMeals` (`sync_nutrition.dart`) |
| `customItem` | `sync_custom_item_payload_hash_index` | custom | `disable_custom_item_hash_skip` | `_syncCustomItems` (`sync_community.dart`, one shared index for `user_custom_exercises` + `user_custom_foods`, split by `opType` override) |

`sched`, `exlog` and `nlog` are the original OI-204 domains and deliberately kept their
pre-existing index/kill-switch names so already-stored fingerprints stay valid across this
batch. The other 14 are new to this batch. `sched` additionally dropped its old status-based
carve-out (never skip a `completed` row, d9b2c5's A-fix-1): a completed row now skips on a
fingerprint match like any other domain, because the server-side completed-day guard
(migration 149, below) refuses a stale overwrite of a completed row — migration 149 must
therefore be live BEFORE any build carrying this change of `sched`'s behaviour ships.

**3. What each fingerprint excludes.** Every fingerprint is computed via
`SyncFingerprint.of(value)` (UUID-v5 over canonical, key-sorted JSON) over the exact push
payload MINUS its own "sent-at" stamp — the field that would otherwise change every pass with
no other content change and defeat the skip on every call: `updated_at` on water and urine
logs, `synced_at` on steps and the plan bundle. A domain whose writer stamps a genuinely fresh
sent-at column on every push (water, steps) cannot be suppressed server-side either (point 4 below)
for the same reason — the client-side skip index is its only protection for those two tables.

**4. Server rules (migration `149_sync_noop_suppress_completed_guard_sync_epoch.sql`).**
Three independent fixes, one file:
1. **No-op suppression on 19 tables** — a `BEFORE UPDATE` trigger running Postgres's built-in
   `suppress_redundant_updates_trigger()` (no extension, not `SECURITY DEFINER`) on
   `workout_logs`, `workout_log_exercises`, `workout_log_sets`, `workout_schedule_completions`,
   `streaks`, `workout_templates`, `template_exercises`, `nutrition_logs`,
   `nutrition_log_items`, `water_logs`, `user_saved_meals`, `readiness_daily`, `sleep_logs`,
   `weight_logs`, `body_measurements`, `daily_steps`, `user_custom_exercises`,
   `user_custom_foods`, `ai_coach_interactions`. An identical UPDATE payload then creates no new
   row version at all — a backstop for app versions already installed. `user_profile` is
   deliberately excluded (its sole writer chains `.upsert(...).select()`, and a `RETURN NULL`
   trigger would make PostgREST see zero rows and throw PGRST116 on `.single()`).
2. **`scheduled_workouts` never demotes a completed day.** A dedicated `SECURITY INVOKER`
   trigger function (`private.scheduled_workouts_completed_guard`) folds the same no-op check
   PLUS: `RETURN NULL` (never RAISE) when `OLD.status = 'completed' AND NEW.status IS DISTINCT
   FROM OLD.status` — the whole write is dropped, not just the status column, so a caller
   trying to demote AND correct another field in the same statement gets neither. A
   `completed_at`-only correction on an otherwise-unchanged completed row is NOT caught by that
   branch and still lands. `RETURN NULL` (not `RAISE`) matters structurally: `pushIfChanged`'s
   `push()` still resolves normally (no thrown error), so the row is recorded as sent and never
   retried for no reason, where a raised error would make a stale device retry the same refused
   write forever.
3. **`sync_epoch`.** `user_progress.sync_epoch integer NOT NULL DEFAULT 0` — the operator-driven
   "resend everything once" repair lever. See point 5 (launch reads) and
   `docs/operations/SYNC_EPOCH_RESYNC.md`.

**5. Launch reads.** `SyncService.restoreLightweightAlways` makes **one** `user_progress`
select and hands the SAME row to `_restoreUserProgress` and `_restoreWorkoutPlan` (or, on the
single-call restore path, to `_fetchSyncEpochRowForRestore`) via their existing pre-fetched
injection parameters — previously two independent network reads of the same row on every
returning-user launch. `_restoreUserProgress` (`sync/sync_profile.dart`) removes `plan_json`
AND `sync_epoch` from the cloud row before `UserRepository.mergeCloudProgress`, so neither
control-plane value lands inside `userBox['progress']` — the whole-blob `plan_json` copy that
used to be spread there on every restore is gone (the migrator below deletes the copy already
on disk for existing installs). `sync_epoch` is read separately and compared against
`workoutBox['sync_epoch_seen']` (`SyncService.kSyncEpochSeenKey`) by
`_applySyncEpochFromRestoreRow`: on first sight (no `sync_epoch_seen` key at all) it just
stores the baseline; once a baseline exists, a STRICTLY GREATER cloud epoch calls
`SyncSkipIndex.clearAll` (below) and only advances `sync_epoch_seen` when
`ClearAllResult.allSucceeded` — a partial clear leaves the seen-epoch untouched so the very
next launch retries the whole clear. The plan merge itself then follows point 6's L2: skip entirely
when nothing bundled is new.

**6. The restore merge (`PlanIntegrityReconciler`, `lib/core/services/plan_integrity_reconciler.dart`)
— L1, L2, L3, the normalizer, and the accepted residual.** `mergeScheduleEntry` is the ONE merge
function shared by `_restoreWorkoutPlan` and the boot-heal `reconcile` path, so the two
consumers of the same cloud snapshot can never disagree:
- A local `status: completed` row is always kept untouched — this guard runs FIRST, so nothing
  below it can ever demote a completed day.
- **L1 — never refill a rest row with workout content**
  (`SyncFlags.restRowRefillGuardEnabled`, opt-out kill switch `disable_rest_row_refill_guard`):
  a local row whose `type` is a rest type, or whose `status` is `'rest'`, is kept as-is rather
  than filled from the snapshot's workout content. NOT a verbatim revert of the old behaviour —
  the merge-output normalizer (next bullet) stays live even with L1 off, so a refill that brings
  NO exercises still comes out `type: 'rest'`; only a refill whose snapshot row carries
  exercises reproduces the old hybrid.
- **The merge-output normalizer** (`_normalizeHybrid`, deliberately UNSWITCHED — no kill switch)
  — applied to every `mergeScheduleEntry` return path: a row that would render `type: workout` +
  `status: rest` + no exercises is corrected to `type: rest`. `isRestHybrid` is the ONE hybrid
  predicate, shared with `ScheduleHybridRepairMigrator` (below) so the merge and the one-time
  repair can never disagree about what a hybrid is. Its body lives in
  `DaySwapRules.isRestHybrid` (`PlanIntegrityReconciler.isRestHybrid` delegates), so the swap
  engine's `DaySwapRules.isRest` counts a not-yet-normalized hybrid as rest too (Hermes h4F3,
  diagnose `c2d8e5`).
- **L3 — the newer arrangement wins, per Mon–Sun IST week**
  (`SyncFlags.swapArrangementMergeEnabled`, kill switch `disable_swap_arrangement_merge`):
  `snapshotArrangementWinsKeys` compares the MAX `arranged_at_ms` per week between local and
  downloaded rows (missing = 0; only dates stamped on either side and present on the snapshot
  side are eligible; a TIE keeps local — strictly newer required) and forces the snapshot's row
  WHOLESALE (content, status, markers) for every winning key. A `swap_merge_conflict` telemetry
  event fires ONCE per merge call (never per row) when at least one non-completed, previously
  `arranged_at_ms`-stamped local row was discarded this way.
  **Carry-forward makes this last-writer-wins per week, by design (spec §5.7; Hermes h4F1,
  2026-09-28).** `upsertScheduled`'s `carriesArrangement` re-stamps `arranged_at_ms = now` when a
  non-swap, non-restore writer (plan regeneration, coach edit, template change, manual edit)
  rewrites a date that ALREADY carries a stamp. A date that was never arranged is NOT re-stamped,
  so an edit to an unrelated, unstamped date cannot move the week's MAX. The consequence: if device
  B edits one of its own arranged dates AFTER device A's swap in the same week, B's week is newer,
  and when the two meet in a merge, B's rows win the whole week and A's swap is discarded
  (`swap_merge_conflict` fires). That is the spec's accepted residual ("the later swap wins that
  whole week"), extended to a later edit of an arranged date, which the spec counts as a newer
  arrangement. A stale device that never saw any arrangement in that week has no stamps, reads as
  0, and cannot win. Same-device coverage: `restore_merge_invariants_test.dart` I5.
- **L2 — merge only what is new**, one flag (`disable_plan_merge_skip_when_known`) gating BOTH
  halves: (a) `_restoreWorkoutPlan` skips the WHOLE bundle merge when the downloaded bundle's
  fingerprint equals the recorded one AND every bundled `schedule_<date>` key still exists
  locally — a locally-deleted row defeats the whole-bundle skip (commit `18183762`; a
  fingerprint match alone says the CLOUD is unchanged, not that local still holds it). An
  OI-252 ghost day (its template was deleted) is filtered out of every merge and so never
  written; an absent row whose `tmpl_<uuid>` template key is also absent locally therefore
  counts as present, or one ghost day would defeat the skip forever (merge review F3, diagnose
  `a3e7d9`). Residual: a real row deleted locally whose template is also missing locally is not
  put back until the bundle changes; (b)
  `mergeScheduleBundleIntoHive` writes a row only when the merged result's canonical fingerprint
  differs from the existing row's, even when the whole-bundle skip above did not fire.
- **Per-launch restore write-if-changed** (Hermes h7F1/h7F2, diagnose `f1c6b4`; kill switch
  `disable_restore_write_if_changed`, `SyncFlags.restoreWriteIfChangedEnabled`) — the same idea
  applied to the three other restore writers that run on EVERY launch via
  `restoreLightweightAlways`: `_restoreWorkoutTemplates` (per template), `_restoreUserProgress`
  (`userBox['progress']`) and `_restoreUserProfile` (`userBox['profile']`). Each compares the value
  it would write with the stored one via `SyncFingerprint.canonicalJson` and skips an identical
  write. The profile comparison drops `updated_at` from both sides, because
  `ProfileWriteService.updateProfile` re-stamps it on every call and it would otherwise never
  match (the field is server-set and never pushed). A declined progress demotion is still
  reported when the write is skipped.
- **The one-time `ScheduleHybridRepairMigrator`** (`lib/core/services/schedule_hybrid_repair_migrator.dart`,
  diagnose `b6e1c8`) — gated by `workoutBox['hybrid_schedule_repair_v1_done']` (per-user, NOT
  `migrationBox`, so a second account signing into the same device is repaired too). Walks every
  `schedule_<date>` row once: a `status: rest` + workout `type` + no-exercises row (the hybrid
  `isRestHybrid` predicate, shared with the normalizer above) is corrected to `type: 'rest'` (28
  live rows found 2026-09-26); the SAME shape but WITH exercises is the one ambiguous live case
  and is left alone (telemetry only — choosing a winner for the past would be a guess). Also
  deletes the dead `swaps_this_week` / `swap_week_start` keys (superseded by
  `DaySwapAllowance`) and the stale `plan_json` copy already sitting in
  `userBox['progress']` for pre-existing installs.

**7. The past-timestamp rule (never "now") and Gate G2.** A sync payload never sends `DateTime.now()`
as a fallback for a timestamp describing the past. Resolution order: (1) the recorded value; (2)
derived from a `*_ms` sibling or a timestamp embedded in the Hive key (`coach_<ms>`,
`tmpl_<ms>`); (3) otherwise OMIT the field so the database keeps what it has (insert applies the
column default) — the same "absence beats null on the wire" convention already used elsewhere
in `sync_workout.dart`. **Completion time** gets its own resolver order:
`entry['completed_at']` (ISO) → `entry['completed_at_ms']` → the matching `wlog_<date>`'s
`completed_at` → omit — never `updated_at_ms` (recurrence of `5a36ad`).
`scripts/check_sync_no_now_fallback.dart` (Gate G2) fails a comment-stripped `?? DateTime.now()`
literal anywhere in sync payload code.

**8. The schedule-row field contract.** `arranged_at_ms` — the swap timestamp; computed by the
pure `DaySwapRules.landed`/`buildSwap` (`day_swap/day_swap_rules.dart`) with ONE `nowMs` for
both rows (same value on both sides), inside the build function `SwapService.swapDays` hands to
`WorkoutWriteService.swapScheduledDays` (which writes the rows it is given and never sets the field)
and carried forward by `upsertScheduled` whenever an already-arranged row is rewritten by a
non-swap, non-restore writer (`carriesArrangement`) — a swap writes its own stamp directly, a
restore copies the source row's; NEVER removed by a swap-back. `is_swapped: true` +
`original_date` — set together, `original_date` is the FIRST origin (kept across a chain of
swaps if the content already carries one); both are removed together only when content lands
back on its `original_date`. `displaced_<date>` — the backup a swap writes when the destination
date already carried a template link; travels WITH the template so a swap-back can restore it.

**9. Kill switches (all local `configBox` flags; no remote config for any of them):**
`disable_sched_hash_skip` / `disable_exlog_hash_skip` / `disable_nlog_hash_skip` /
`disable_wlog_hash_skip` / `disable_completion_hash_skip` / `disable_template_hash_skip` /
`disable_plan_hash_skip` / `disable_streak_hash_skip` / `disable_water_hash_skip` /
`disable_steps_hash_skip` / `disable_urine_hash_skip` / `disable_sleep_hash_skip` /
`disable_weight_hash_skip` / `disable_measurement_hash_skip` / `disable_readiness_hash_skip` /
`disable_saved_meal_hash_skip` / `disable_custom_item_hash_skip` (per-domain, point 2 table);
`disable_rest_row_refill_guard` (L1); `disable_swap_arrangement_merge` (L3);
`disable_plan_merge_skip_when_known` (L2, both halves); `disable_restore_write_if_changed`
(template / progress / profile restore writes); `disable_restore_single_plan_fetch`;
`disable_day_swap_train_ui` (Train UI only — see `lib/features/train/CLAUDE.md`).

**M1 (unchanged limitation):** two overlapping sync passes for the same domain can still both
read the OLD stored fingerprint before either writes the new one, so a genuinely concurrent
double-push is not fully closed by `SyncSkipIndex` alone — the mutex per Hive key at the
WriteService layer is the actual serialization point; the skip index is an optimization on top
of it, not a replacement for it.

Full detail: `docs/sot_registry.yaml` (search `payload_hash_index`),
`docs/diagnoses/2026-09-19-full-rescan-sync-timeout-d3f8a6.md`,
`docs/adr/0020-sync-sends-only-what-changed.md`.

### Restore conflict policy — local-wins / additive (ADR-0014, diagnose c5a1f2)
Since the slow-boot guard, returning users reach /home WHILE the cloud restore runs in
the **background** — so the restore is concurrent with the user logging. Loss-sensitive
restore writers are therefore **additive / local-wins**: they only fill gaps, never
overwrite a present local row (`if (box.get(key) != null) continue;`).
- **Additive (skip-if-local-exists):** `_restoreExerciseLogs`, `_restoreWorkoutLogs`,
  `_restoreNutritionLogs`, `_restoreSavedMeals`, plus weight / measurements / water
  (already so — reference pattern `sync_health.dart:300`).
- **Timestamp-merge (per-writer exception):** `_restoreScheduledWorkouts` reconciles
  schedule *status* cloud↔local (keep-local-when-cloud-stale, d9b2c5) — it is NOT
  additive because schedule status genuinely needs merging.
- **Trade-off:** offline-first local-wins — a row edited on a 2nd device won't overwrite
  the local copy. Revisit with cloud-newer-wins if true multi-device editing is a goal.
- **Deletion survives restore via a server-side rename-on-delete trigger, NOT via the
  additive/skip-if-local-exists policy above.** `_restoreExerciseLogs` is additive, so a
  cloud row for a natural key the device no longer has locally would normally be treated
  as "new" and restored — a genuine `workout_log_exercises` delete instead lands as a
  cloud row whose `exercise_id` is suffixed (`workout_log_exercises_delete_final_rename`,
  migrations 150+151; same pattern as `workout_templates`' tombstone at the table above),
  which frees the natural key and makes the row invisible to every normal reader. OI-246
  (2026-09-29, diagnose `e1c8b4`): migration 150 only fired `BEFORE UPDATE`, so a client
  upsert that landed as a plain INSERT (no pre-existing cloud row for that natural key —
  exactly the shape a fresh device sync produces) never suffixed at all, and the additive
  restore then legitimately treated the un-suffixed deleted row as new data, resurrecting
  it. Migration 151 extends the trigger to `BEFORE INSERT OR UPDATE`. **Any future
  soft-delete-via-rename trigger on a natural-keyed table must fire on INSERT too, not
  just UPDATE** — an UPSERT from the client is a real INSERT whenever no conflicting row
  exists yet.

### Restore Pagination
- All restore queries use paginated fetch (1,000 rows per page, offset-based).
- Safety ceiling: 50,000 rows per table to prevent runaway fetches.
- No hardcoded `.limit(5000)` — truly full-history restore for all users.

### Source of Truth Rules (NON-NEGOTIABLE)
> Multiple-source bugs are the #1 cause of "UI says X but data says Y" issues. Establish ONE reader per derived concept.

- **Workout receipt:** `WorkoutReceiptData.fromExerciseLogs(date)` (in `workout_receipt_card.dart`) is the ONLY way to build receipt data after the fact. Reads from Hive `exlog_*` keys via `WorkoutRepository.getExerciseLogsForDate()`. Deduplicates by exercise name (sum sets, max weight). Never hand-build receipt data from a widget's in-memory state.
- **Workout log edit:** `EditWorkoutLogSheet` (in `lib/features/train/widgets/edit_workout_log_sheet.dart`) is the ONLY edit surface. Every entry point (receipt sheet Edit button, Home "View Card", calendar day detail, Train expanded view) routes through it. Save:
  1. Rewrites the Hive log map in place
  2. Recomputes `volume_kg = weight_kg × reps_completed`
  3. Chronologically rescans `is_pr` flags for the exercise (sorts by `date + created_at`, walks forward, strict `>` comparison)
  4. Invalidates: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`
  5. Fires `SyncService.instance.syncWorkoutData() + pushSnapshot()` (fire-and-forget)
- **Exercise logs:** `WorkoutRepository.getExerciseLogsForDate()` is the ONLY read path. Uses O(1) index `exercise_log_index_YYYY-MM-DD` with legacy full-scan fallback. Never iterate `workoutBox.keys` manually to find logs for a date.
- **Home "View Card" state:** `todayWorkoutProvider` is the single source for the "DONE + View Card" state on home. Always derived from Hive schedule + exercise logs — never cached in the widget.
- **Scheduled workouts:** `WorkoutScheduleService` owns all schedule mutations (generate, clean-sync on template edit, reschedule on days/week change). Never write `schedule_YYYY-MM-DD` keys directly from a widget or repository.
- **Nutrition total calories:** After a meal is logged, `total_calories` comes from summing `items[]` with per-item Atwater fallback (`raw > 0 ? raw : 4P+4C+9F`). Never read `result['total_calories']` at the top level of an AI response — it's routinely missing.
- **AI snapshot:** `AiCoachRepository.buildAiContext()` is the ONE builder. `AiService._compactContext()` is the ONE trimmer. Never construct ad-hoc snapshots in provider code.
- **Subscription status:** `SubscriptionService.isPro()` + `gate()` are the ONLY entry points. Never read `configBox.get('isPro')` directly from a widget. High-value features (`phases_2_to_12`, `ai_coach_unlimited`, `progress_photos`) go through `verifyFromServer()`.
- **User-scoped Hive keys (MigratedKey discipline):** Anything user-specific that previously lived in shared `configBox` now reads/writes through `MigratedKey` (in `lib/core/services/migrated_key.dart`). The 31-key migrated set is enumerated in `UserConfigMigrator.userScopedKeys` (Test #10.1 + #11.1). Two keys deliberately stay in shared `configBox` and are listed in `_intentionallyShared`: `pending_referral_code` and `logout_in_progress`. When adding a new user-specific key, append it to `userScopedKeys`, bump `_flagKey` (`_v2_done` → `_v3_done` etc.) so existing devices re-run, and add the contract test pin. Never write directly to `configBox` for user-specific data.
- **Water target:** `WaterTargetService.instance.currentTargetMl()` (in `lib/core/services/water_target_service.dart`) is the ONLY way to read the daily water goal. Never hardcode `3000`. Read precedence: user override (`userBox['water_target_override_ml']`) → computed (`weight × 35 + 500 if 4+ training days + 300 if active lifestyle`, clamped 2500–4000 ml per founder direction 2026-05-04) → 2500 floor. Widgets must `ref.watch(waterTargetProvider)` (in `nutrition_provider.dart`) so manual override changes trigger rebuilds. Onboarding seed routes through `WaterTargetService.computeFromProfile(profile)`.
- **Provider invalidation after mutation:** Any write that changes workout state (log, edit, delete, complete) MUST invalidate the full batch: `currentPlanProvider`, `workoutStatsProvider`, `calendarWeekProvider`, `streakProvider`, `todayWorkoutProvider`, `allExercisePRsProvider`. One missing invalidation = stale UI.
- **Muster answers (narrowed 2026-09-19, diagnose d6f1b8 — was a stale description of the PRE-restructure bridge):** `InductionService.recordMusterAnswer` (in `lib/features/ai_coach/services/induction_service.dart`) now accepts only `body_part_priorities` — its `_allowedMusterKeys` guard REJECTS (`ArgumentError`, no write on either side) `why_now`, `definition_of_winning`, `known_injuries`, `typical_wake_time`, and `preferred_workout_time` outright, closing a live clobber bug where muster's injuries answer silently overwrote onboarding Details' answer on every completion (muster always ran after onboarding, so muster's write always won). The one surviving key is ALSO bridged into `userBox['profile']` via `_bridgeToProfile`: `body_part_priorities[0]→physique_focus` (single-element only; legacy multi-select skipped). Injuries stays Details screen's job; wake/workout-time stays Edit Profile's job — neither is collected by muster anymore. `ai_snapshot_builder._getInductionAndMusterKeys()` reads all 4 non-`why_now`/`definition_of_winning` fields (`known_injuries`, `typical_wake_time`, `preferred_workout_time`, `body_part_priorities`) straight off `userBox['profile']` now, not the coachBox mirror, so the AI coach's context can't go stale relative to whichever screen (onboarding, muster, or a later Edit Profile change) last touched the data. Never write `body_part_priorities` to coachBox from anywhere else. `backfillMusterToProfileIfNeeded` (same class) is UNCHANGED — still a one-shot migration of any pre-restructure user's stored answers for the 5 retired keys. Pinned by `test/contracts/muster_profile_bridge_test.dart` + `test/contracts/muster_to_profile_bridge_behavioral_test.dart` + `test/ai_coach/snapshot_keys_test.dart`.
- **Auth/Hive owner agreement (cross-account guard):** `authUserIdTokenProvider` (in `lib/features/auth/providers/auth_invalidation_provider.dart`) returns `'<anon>'` whenever Supabase `currentUser.id` disagrees with `HiveUserSession.currentOwnerFullId` (the live signOut+signUp race window). The 56 user-scoped Riverpod providers from c4055a all watch this token — they automatically render empty during disagreement and rebuild when the listenable confirms `openForUser` completed. Belt-and-suspenders: `wrapUserScopedBox` (in `lib/core/services/guarded_box.dart`) ALSO checks the same agreement and returns `GuardedBox.empty(authUid)` on disagreement, so reads serve null/empty even if the token-rebuild loop is broken. Never read user-scoped Hive without going through `wrapUserScopedBox`. Pinned by `test/contracts/auth_invalidation_timing_test.dart` + `test/contracts/wrap_user_scoped_box_disagreement_test.dart`.
- **AI coach memory upward sync (audit-2026-05-16 F3-1.1):** `coach_memory.coach_notes` cloud column is populated by `SyncService.syncCoachMemoryNow` projecting Hive `coachBox['coaching_notes']` (Hive key intentionally singular, cloud column intentionally singular too but DIFFERENT word). Pre-fix the upward projection was missing → AI memory lost on every reinstall (9th writer/reader drift instance). Pinned by `test/contracts/coach_notes_upward_sync_test.dart`. Never rename either side without updating BOTH and the contract test.
- **AI coach derive-only surface (2026-05-31, ADR-0012):** The `logPR` tool was **removed** — PRs are never AI-asserted, only derived. A coach `logSet` routes through `WorkoutWriteService.logExercise` (single-set `ExerciseSet`, same canonical writer as the UI active-workout flow); PR detection happens inside the WriteService via `_rescanPrFor`, and the home/profile PR snapshot computes best-per-set from `exlog_*` via `WorkoutRepository.loadAllExercisePRs`. Completion is likewise **derived**: the dispatcher's `_maybeCompleteScheduledDay` auto-calls `WorkoutWriteService.markCompleted` after a coach `logSet` on a date that has a `schedule_*` row (idempotent — skips if already `completed`), replacing the removed `markWorkoutComplete` tool. Never call the legacy `WorkoutRepository.logSetWithPrRescan` from the dispatcher; that path was one of Test #16.1 Bug A's rogue exlog_* key formulas and bypasses the WriteService mutex + telemetry — its declaration is now deleted. Pinned by `test/contracts/derive_only_tool_surface_test.dart`, `test/contracts/coach_derived_pr_and_completion_test.dart`, and `test/contracts/no_legacy_log_set_with_pr_rescan_declaration_test.dart`.
- **AI coach chat photo references do NOT sync (OI-77, 2026-07-30):** `SyncService._syncCoachInteractions` push (`lib/core/services/sync/sync_coach.dart:149-157`) and `_restoreCoachInteractions` restore (`:204-217`) payloads carry no `media_*` field at all — not `media_url`/`media_type` (pre-existing), and not the coach-media-consent batch's `media_storage_path`/`media_save_state`. A historical AI-coach chat message with a photo degrades to caption-only text after a cross-device restore; the photo itself survives in Storage (an already-saved copy still renders in `SavedCoachPhotosScreen`, which lists directly from Storage, not restored Hive state) — only the inline chat-bubble thumbnail and save-consent chip are lost. Tracked, not yet fixed — see `docs/audit/open_issues.md` OI-77.
- **WorkoutScheduleService (audit-2026-05-16 E.6):** All 9 schedule mutations (markCompleted, markSkipped, activateTravelMode, swapExerciseInDay, shortenDay, copy week × 2, assignTemplateToDate, unscheduleTemplateFromDate) route through `WorkoutWriteService.upsertScheduled` for mutex + fan-out. 3 non-schedule writes (2 `_planKey` plan upserts + 1 template `last_used_at` stamp) stay direct + fire explicit `unawaited(SyncService.instance.syncWorkoutData())` adjacent. 1 internal `displacedKey` backup stays direct (rollback state, no cloud sync needed). Pinned by `test/contracts/workout_schedule_service_uses_write_service_test.dart`.
- **HealthWriteService (audit-2026-05-16 E.7):** Canonical writer for the health domain (sleep, weight, measurement, water, urine, hydration) mirroring `WorkoutWriteService` + `NutritionWriteService`. Per-(kind, date) mutex via `_acquireLock`. Every key uses `istDateStr(date)` (closes the F2-R2 IST drift in `profile_provider.logSleep`). Sole writer for all UI-layer health mutations — `profile_provider.BiometricNotifier.logSleep`, `nutrition_provider.WaterIntakeNotifier`, `nutrition_provider.UrineColorNotifier`, `nutrition_provider.HydrationSaveNotifier`, `home_provider.WeightLogNotifier`, `onboarding_provider` initial weight, `conversational_log_handler._logMeasurement`. The list key `coachBox['sleep_logs']` write in `conversational_log_handler._logSleep` is intentionally direct (list-append semantics) — documented with audit comment. Pinned by `test/contracts/health_write_service_writer_to_reader_test.dart` (15 tests).

### Hive field-name contract

WriteService output keys are a contract with every consumer. Field renames must:

1. Update the writer.
2. Update every consumer in the same PR (grep for the old field name).
3. Update or add a round-trip test in `test/contracts/`.

Current contracts:

- **`exlog_*`** (`WorkoutWriteService`) — fields: `exercise_name`, `date`, `sets[]` (List of Map), `set_number`, `reps_completed`, `weight_kg`, `volume_kg`, `logging_type`, `is_pr`, `source`, `updated_at_ms`, optional `notes`.
  Consumers: `WorkoutReceiptData.fromExerciseLogs`, `WorkoutRepository.getExerciseLogsForDate`, `AiCoachRepository.buildAiContext` (recent_logs section), calendar week provider, `WorkoutWriteService._rescanAllPrsFor` PR detector, `SyncService.syncWorkoutData` cloud projection.

- **`nlog_*`** (`NutritionWriteService`) — fields: `log_key`, `date`, `meal_type`, `total_calories`, `total_protein`, `total_carbs`, `total_fat`, `total_fiber`, `items[]` (List of Map; per-item keys: `name`, `quantity_g`, `calories`, `protein`, `carbs`, `fat`, `fiber`), `source`, `logged_at`, `created_at`. Consumers: `TodaysMealsCard`, `NutritionRepository`, `home_provider` daily-completion ring, `AiCoachRepository.buildAiContext` (meals_today / nutrition_trend_7d), `SyncService.syncNutritionData`.

If you rename a field in a WriteService, the corresponding contract test in `test/contracts/<x>_write_to_read_contract_test.dart` must be updated in the same commit. The receipt-rendering bug in APK Test #7 (set_number vs sets_completed) is the canonical failure mode this contract prevents.

### Sync fan-out contract

Two domain entry points are the contract for "everything in the
{workout, nutrition} domain is now in cloud":

- `SyncService.syncWorkoutData()` MUST fan out to every workoutBox
  prefix and the workout-domain healthBox keys. Currently:
  `_syncWorkoutLogs`, `_syncExerciseLogs`, `_syncScheduleCompletions`,
  `_syncWorkoutTemplates`, `_syncScheduledWorkouts`, `_syncStreaks`.
- `SyncService.syncNutritionData()` MUST fan out to every nutritionBox
  prefix. Currently: `_syncNutritionLogs`, `_syncWaterLogs`,
  `_syncSavedMeals`.

Adding a new Hive prefix in either domain requires updating the matching
`syncX()` AND the contract test
(`test/contracts/sync_fanout_contract_test.dart`).

The 2026-05-03 sync gap (templates / schedules / streaks invisible to
cloud for >24h, **with `scheduled_workouts.template_id` and
`user_saved_meals.id` silently uuid-rejecting since 2026-04-18**) was the
canonical multi-failure-mode this contract prevents. `weeklyFullSync()`
remains the safety net but is no longer the only path for workout-domain
or nutrition-domain rows reaching cloud.

### `plan_json` push is NOT part of the workout fan-out (OI-189, 2026-09-13)

`user_progress.plan_json` (the whole-blob mirror of the workout box's
`plan_start_date`/`plan_end_date`/`schedule_*`/`displaced_*` keys, restored
verbatim by `_restoreWorkoutPlan`) is pushed by a SEPARATE, targeted method —
`SyncService.pushWorkoutPlanForSyncDomain()` (`sync/sync_workout.dart`) — that
is **not** one of `syncWorkoutData()`'s fan-out targets above. A caller that
only fires `syncWorkoutData()`/`syncWorkoutDataNow()` after touching the plan
window does NOT push `plan_json`; `weeklyFullSync()` is the only other caller.

**Invariant established by OI-189 (diagnose `b9e4d1`):** every writer that
SWEEPS non-completed rows past `plan_end` or MOVES the window
(`plan_start_date`/`plan_end_date`) must call `pushWorkoutPlanForSyncDomain()`
immediately after, or the swept/moved state is invisible to the cloud copy
and `_restoreWorkoutPlan`/`PlanWindowReanchor` can resurrect it on the next
restore. Two exceptions, both deliberate: (1) `generateAndSchedule` (writer A)
pushes only when explicitly told to (`pushPlanWindow: true`, passed only at
the two live phase-advance sites) — its reinstall/repair callers generate a
plan on a fresh Hive BEFORE the cloud restore runs, and a push there would
overwrite the only real copy; (2) the push guards on
`SyncService.pausedForSimulation` first, so the dev year-sim harness's
in-loop advances no-op it (its own end-of-run flush pushes once instead).

### Restore-completeness sync (Theme A — Test #11, 2026-05-04)

Three additional ad-hoc sync methods exist outside the workout/nutrition
domain fan-outs. These cover surfaces that were Hive-only before Test #11
and silently lost on reinstall:

- `SyncService.syncFreezes()` — pushes `streak_freezes_{available, used_dates, last_refill}` into `user_progress`. Called from `WorkoutRepository.consumeMissedDayIfFreezeAvailable` (consume freeze; the query-named `calculateCurrentStreak` shim was deleted in OI-44 Unit 6) + `home_provider.StreakFreezeNotifier._refillIfNewWeek` (weekly refill).
- `SyncService.syncNotificationsInboxEntry(Map entry)` — upserts a single inbox entry to `notifications_inbox`. Called from `NotificationInboxService.record` after every Hive write.
- `SyncService.syncSavedDietPlan(Map planJson)` — upserts to `saved_diet_plans` (one row per user). Called from `diet_plan_screen._savePlan` after `UserRepository.saveDietPlan`.

Restore (`SyncService.restoreFromCloudForUser`) pulls these 3 surfaces +
`rank_promotions` history (last 20) + `coaching_notes` from `coach_memory`
+ folds `SubscriptionService.verifyFromServer(force: true)` as the final
restore step (was previously a separate post-auth hook in
`auth_provider.dart` — that callsite is kept as a fast-path fallback).

The `_*` private helpers in `sync_service.dart` are: `_restoreFreezes`,
`_restoreNotificationsInbox`, `_restoreSavedDietPlan`,
`_restoreRankPromotions`, `_restoreCoachMemory` (extended in Test #11 to
also pull `coaching_notes`).

Adding a new Hive-only surface that paying users would lose on reinstall
requires (1) a cloud column/table, (2) a `syncX()` method on SyncService,
(3) a `_restoreX()` method called from `restoreFromCloudForUser`, AND
(4) a contract test in `test/contracts/restore_completeness_writes_test.dart`
(currently 7 tests).
