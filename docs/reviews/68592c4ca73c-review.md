---
reviewed_at: "2026-06-03T10:30:00+05:30"
blast_radius: catastrophic
lens_set:
  - writer_reader_drift
  - sync_id_correctness
  - migration_safety
  - reconciler_monotonicity
  - function_exception_swallow
  - unawaited_no_error_sink
  - blast_radius_mismatch
  - secrets_in_tree
  - widget_correctness
findings_count: 2
verdict: accepted
resolution: >
  Both findings FIXED in migration 082 before apply (2026-06-03). P1 (missing
  header) — added the 4-tag Intent/Destructive?/Rollback/Linked-diagnose header
  (the migrations CLAUDE.md-listed migration_header_contract_test.dart does not
  actually exist — stale doc ref; the fix is convention-compliance + matches
  every other migration). P2 (arbiter-less window) — reordered to CREATE the
  user-inclusive index BEFORE dropping the old global one, so the client's
  onConflict always has an arbiter (no plain-INSERT duplicate window; avoids
  nested-txn issues with apply_migration). sync_user_scoped_natural_keys_test 4/4.
diff_sha256: 68592c4ca73c3d60072c9e304d18be4e6250aba1422c59c54e85d0dc075833ff
---

# B-pass review — APK obs 2026-06-02 batch

Staged diff covers: two-Phase-1 fix (week_selector + PhaseProgressReconciler),
heading-clip FittedBox sweep, weekly-report EF canonical-target fix +
refresh-on-open, CATASTROPHIC-tier cross-user sync-ID fix (sync_workout.dart /
sync_health.dart + migration 082), new WeightTrendChart on Home.

---

## Finding 1 — P1

**lens:** migration_safety  
**file:line:** `supabase/migrations/082_user_scoped_sync_natural_keys.sql:1`  
**severity:** P1

**Claim:** Migration 082 is missing the mandatory four-line header (`-- Intent:`,
`-- Destructive?:`, `-- Rollback strategy:`, `-- Linked diagnose-doc:`) required
by `supabase/migrations/CLAUDE.md`. The file begins directly with a large
multi-line `--` comment block that is informative but does not use the four
exact tagged keys.

**Verification:**

```bash
grep -n "-- Intent:\|-- Destructive?:\|-- Rollback strategy:\|-- Linked diagnose-doc:" \
  supabase/migrations/082_user_scoped_sync_natural_keys.sql
# → no output (zero matches)
```

The CLAUDE.md spec says: "Every new migration file MUST begin with the following
four-line header (in this exact order, as SQL comments). The pre-commit hook and
any future gate scripts grep for these tags."

The existing `exercise_library_cloud_seeded_test.dart` test specifically checks
for `-- Intent:`, `-- Destructive?:`, `-- Rollback strategy:`, and
`-- Linked diagnose-doc:` on migration 074. The migration 082 header should also
declare:
- Destructive: yes — it `DROP INDEX IF EXISTS` on two indexes that an old client's
  `onConflict` target, and adds a `NOT VALID` constraint.
- Rollback strategy: a follow-up migration that re-creates the dropped global
  indexes and re-widens or re-narrows the constraint.
- Linked diagnose-doc: `d4b8e2`

**Suggested fix:**

Add the four-line header before the informative block at the top of
`supabase/migrations/082_user_scoped_sync_natural_keys.sql`:

```sql
-- Intent: Add user-inclusive UNIQUE natural-key indexes for cross-user sync-ID
--         collision fix (d4b8e2); replace global wle/wls unique indexes with
--         user-scoped ones; widen wls_reps_realistic to <=1000.
-- Destructive?: yes — drops uniq_workout_log_exercises_wlog_ex_set and
--               ux_workout_log_sets_natural_key (old clients' onConflict will
--               42P10 until they update; acceptable pre-launch, single device).
-- Rollback strategy: migration 083 — recreates the two dropped global indexes
--                    (DROP the user-scoped ones, re-CREATE global ones,
--                    re-narrow wls_reps_realistic to <=60 NOT VALID).
-- Linked diagnose-doc: d4b8e2
```

**status:** pending

---

## Finding 2 — P2

**lens:** sync_id_correctness  
**file:line:** `supabase/migrations/082_user_scoped_sync_natural_keys.sql:48`  
**severity:** P2

**Claim:** The migration drops `ux_workout_log_sets_natural_key` on
`workout_log_sets`, but the client's new `onConflict` value
(`'user_id,workout_log_id,exercise_id,set_number'`) targets the NEWLY CREATED
index `uniq_wls_user_wlog_ex_set`. There is a window between the DROP and the
CREATE where neither the old nor the new index exists. If a concurrent client
sync fires during migration execution the `onConflict` lands on no index →
Postgres treats it as a plain INSERT, potentially inserting duplicate rows
instead of merging. This is transient (the new index is created immediately
after), but in the real deployment window (single device, no concurrent users)
it is low-risk. Documenting as P2 because the migration does not execute
DROP+CREATE in a transaction or as an atomic DDL block.

**Verification:**

```sql
-- In migration 082:
drop index if exists public.ux_workout_log_sets_natural_key;        -- line 48: old index gone
create unique index if not exists uniq_wls_user_wlog_ex_set ...;    -- line 49: new index created
-- no BEGIN/COMMIT wrapping → each statement commits independently
```

Note: `CREATE INDEX` on a live table without `CONCURRENTLY` in Postgres takes a
ShareLock (blocking writes) but is atomic within itself. The gap is real but
extremely short — likely sub-millisecond for a small pre-launch table. At
current scale (2 users, low sync frequency) the probability of a write landing
in the gap is negligible. Still, a future reviewer should know this gap exists.

**Suggested fix:** Wrap the DROP+CREATE pair in an explicit transaction:

```sql
BEGIN;
DROP INDEX IF EXISTS public.ux_workout_log_sets_natural_key;
CREATE UNIQUE INDEX IF NOT EXISTS uniq_wls_user_wlog_ex_set ...;
COMMIT;
```

(Same pattern for the wle pair at lines 43-45.)

**status:** pending

---

## Lens-by-lens clean results

### 1. writer_reader_drift

**Checked:** `WorkoutScheduleReadService.pastPhaseBlocks()` (the shared bucketing
SoT) is consumed by both `WeekSelector._toPastPhases()` and
`PhaseProgressReconciler.reconcile()`. Both read `.length` of the same list
object. The week selector no longer does its own schedule-* walk — it delegates
entirely to `pastPhaseBlocks()` (verified: `_loadPastPhases` deleted, replaced
by `_toPastPhases(service.pastPhaseBlocks(), widget.currentPhase)`). No parallel
bucketing remains → no drift vector. The `currentPhase` widget parameter is
threaded from `plan.phase` (screen.dart:742) → `CurrentPlanData.phase` →
`UserRepository.getProgress()['current_phase']` — same single SoT as the
reconciler reads. Clean.

**Checked:** `WeightTrendPoint.date` is read by `WeightTrendChart` using
`DateTime.tryParse` inside `weightTrendWindow` (filtering nulls) and then
`DateTime.parse` in `build()` at line 136. The `DateTime.parse` call is safe
because `weightTrendWindow` already removes any entry where `dayOf(e) == null`
(which uses `tryParse`). Entries that reach `build()` are guaranteed parseable.
Clean.

**Checked:** `HealthWriteService.logWeight` writes `weight_${istDateStr}` with
`type: 'weight_log', date:, weight_kg:`. `weightHistoryProvider` returns
`List<WeightEntryData>` with `.date` (YYYY-MM-DD string) and `.weight` (double).
`home_screen._buildWeightSparkline` maps to `WeightTrendPoint(date: e.date,
weight: e.weight)`. Field names preserved across the chain. Clean.

### 2. sync_id_correctness (CATASTROPHIC focus)

**(a) Every changed upsert that omitted `id` has a user-inclusive `onConflict`
AND the table has a `gen_random_uuid()` default:**

- `workout_logs`: id omitted; `onConflict: 'user_id,date,workout_name'`;
  `uniq_workout_logs_user_date_workout_name` exists from migration 068b (non-partial,
  all cols NOT NULL). gen_random_uuid default confirmed by diagdoc (live verified
  2026-06-02). CLEAN.
- `workout_log_exercises`: id omitted; `onConflict:
  'user_id,workout_log_id,exercise_id,set_number'`; migration 082 creates
  `uniq_wle_user_wlog_ex_set`. gen_random_uuid default confirmed. CLEAN.
- `workout_log_sets`: id was already omitted per existing code (no change needed);
  `onConflict` updated to include `user_id`; migration 082 creates
  `uniq_wls_user_wlog_ex_set`. gen_random_uuid default confirmed. CLEAN.
- `weight_logs`: id omitted; `onConflict: 'user_id,date'`; migration 082 creates
  `uniq_weight_logs_user_date`. gen_random_uuid confirmed. CLEAN.
- `sleep_logs` (BOTH paths — list-path in `syncSleepNow` at line 58 AND per-day
  path in `_syncSleepLogs` at line 203): id omitted in both; both use
  `onConflict: 'user_id,date'`; migration 082 creates `uniq_sleep_logs_user_date`.
  The bonus fix that both paths now merge onto one row per (user_id,date) is
  correct. CLEAN.
- `body_measurements`: id omitted; `onConflict: 'user_id,date'`; migration 082
  creates `uniq_body_measurements_user_date`. gen_random_uuid confirmed. CLEAN.

**(b) Migration 082 indexes EXACTLY match client onConflict column tuples:**

| Table | Client onConflict | Migration index columns | Match? |
|---|---|---|---|
| workout_log_exercises | user_id,workout_log_id,exercise_id,set_number | user_id,workout_log_id,exercise_id,set_number | YES |
| workout_log_sets | user_id,workout_log_id,exercise_id,set_number | user_id,workout_log_id,exercise_id,set_number | YES |
| weight_logs | user_id,date | user_id,date | YES |
| sleep_logs | user_id,date | user_id,date | YES |
| body_measurements | user_id,date | user_id,date | YES |
| workout_logs | user_id,date,workout_name | (pre-existing 068b index) | YES |

All column tuples match exactly. No 42P10 risk from mismatched arbiters.

**(c) No upsert still sends a date-only deterministic id:**  
`sync_health.dart`: all three calls to `SyncService._deterministicId` removed.
`sync_workout.dart`: the `_deterministicId` call for `workout_logs` removed; for
`workout_log_exercises` removed; for `workout_log_sets` the id was already absent.
Source-grep test `sync_user_scoped_natural_keys_test.dart` pins
`h.contains('SyncService._deterministicId')` is false. CLEAN.

**(d) Migration drops the OLD global unique before/with creating the user-inclusive
one (else the old one still rejects cross-user rows):**  
Migration 082 lines 43-45: `DROP INDEX IF EXISTS public.uniq_workout_log_exercises_wlog_ex_set`
THEN `CREATE UNIQUE INDEX uniq_wle_user_wlog_ex_set`. Lines 48-50: same for wls.
The old global indexes are dropped — cross-user rows from before the fix can be
re-synced without the old constraint rejecting them. CLEAN.

### 3. migration_safety

**Arbiter column nullability:**  
All arbiter columns for the new indexes are verified NOT NULL:
- `workout_log_exercises.user_id`, `workout_log_id`, `exercise_id`, `set_number`: 
  all NOT NULL by existing schema (core natural-key columns).
- `workout_log_sets` same columns: same.
- `weight_logs/sleep_logs/body_measurements.user_id` and `date`: both NOT NULL
  (RLS requires user_id; date is the primary domain key).
Non-partial indexes + NOT NULL arbiters = no 42P10. CLEAN.

**FK references to dropped indexes:**  
No FK constraint in the schema references these natural-key unique indexes
directly (FKs reference PKs, not unique indexes). CLEAN.

**NOT VALID on wls_reps_realistic:** Correct. `NOT VALID` skips a full-table
scan for existing rows (matching migration 080's pattern for wle_reps_realistic).
New inserts and updates will be checked; existing rows ≤60 are untouched. CLEAN.

**Existing duplicates:**  
Diagnose-doc d4b8e2 states: "Verified live 2026-06-02: all arbiter columns NOT
NULL and zero existing duplicates on every new key." This is required for a
non-CONCURRENTLY CREATE UNIQUE INDEX to succeed. Accepted as verified (live
rollback-txn check documented in the diagnose-doc).

### 4. reconciler_monotonicity

**`reconciledPhase(currentPhase, completedBlocks)`:**  
Returns `completedBlocks + 1` only when `currentPhase < completedBlocks + 1`,
else null. The monotonic invariant holds: the function only returns a value
STRICTLY greater than `currentPhase`. Verified by behavioral tests:
- `reconciledPhase(2, 1)` = null (current ahead → no-op).
- `reconciledPhase(3, 1)` = null (current ahead → never demotes).
- `reconciledPhase(1, 0)` = null (free user → no-op).

**`reconcile()` boot path:**  
Guards: kill-switch check → plan_start null check → progress null check. All
three guards cause early return (no write). The `updateProgress({'current_phase':
target})` call only fires when `target != null`. `updateProgress` in
`UserRepository` stamps `deployments_complete = max(prior, current_phase-1)` (a
separate monotonic guard). CLEAN.

**restoring_screen wiring order:**  
The reconciler runs AFTER `nlogMigrator` and `exlogMigrator` (both key migrators)
complete, at line ~244 of restoring_screen.dart. This is after the restore phase
so `schedule_*` Hive entries are hydrated. The `PhaseProgressReconciler.reconcile`
call is awaited before `/home` routing. CLEAN.

**No schedule-row rewrites or deletes:**  
The reconciler only calls `UserRepository.updateProgress({'current_phase': target})`.
No schedule rows are touched. CLEAN.

### 5. function_exception_swallow

**`reports_screen._generateReport(silent:true)`:**  
On silent error (line 157-159): catches, prints, returns. This is intentional —
the cached report stays visible. The non-silent path at line 161-166 surfaces the
error correctly. `_isGeneratingReport` is never set to `true` in the silent path
(guarded by `if (!silent)` at line 97), so the UI spinner can't get stuck.
The `callFunction` call via `SupabaseService.instance.callFunction` is the same
path used by the non-silent invocation. Any `FunctionException` (non-2xx) would
be caught by the outer `catch (e)` and handled per the silent/non-silent branch.
CLEAN.

### 6. unawaited_no_error_sink

**New `unawaited(` calls in the diff:**

- `phase_progress_reconciler.dart:81`: `unawaited(ErrorTelemetry.logEvent(...))` —
  telemetry fire-and-forget; failure is acceptable (telemetry is best-effort). CLEAN.
- `phase_progress_reconciler.dart:87`: `unawaited(ErrorTelemetry.recordNonFatal(...))` —
  same pattern used everywhere; failure is acceptable. CLEAN.
- `restoring_screen.dart:1124`: `unawaited(ErrorTelemetry.logEvent('restoring_screen_migrator_done', ...))` —
  telemetry only. CLEAN.

No new `unawaited` call that requires an error sink is added without one.

### 7. blast_radius_mismatch

The diagnose-doc d4b8e2 is correctly marked `blast_radius: catastrophic`.
Migration 082 is included in the staged diff. The commit will include both the
client changes and the migration file. The deployment note in the migration
comments the deploy-ordering requirement (APK + migration together). Behavioral
contract test `sync_user_scoped_natural_keys_test.dart` added. Source-grep pins
all affected upserts. The existing `sync_onconflict_natural_key_test.dart` is
updated to reflect the new user-inclusive arbiter. CLEAN at the blast-radius
treatment level (other than Finding 1 — missing migration header).

### 8. secrets_in_tree

Scanned the full diff. No credential-shaped literals (JWT, API keys, service-role
keys, Razorpay secrets) are present. CLEAN.

### 9. widget_correctness

**WeightTrendChart — null-deref / RangeError:**

- Empty `entries` list: `weightTrendWindow(entries, null)` returns `[]` → early
  return renders the "Log your weight" empty state. No null deref. CLEAN.
- Single point, no prior history: `allPts.isEmpty` is false; `shown =
  weightTrendWindow(entries, window)` = 1 point (carry-forward finds no prior point,
  inWindow has 1 point → returns it). `_buildChart([singlePoint])` hits
  `shown.length < 2` → renders the "log again" hint. CLEAN.
- `maxX <= 0`: guarded at line 234 `maxX <= 0 ? 1 : maxX`. Two entries on the
  same calendar date → both `x = 0` → `maxX = 0 → 1`. CLEAN.
- `DateTime.parse(p.date)` at line 136: safe because `weightTrendWindow` already
  filters entries via `tryParse`, so only parseable dates reach `build()`. CLEAN.
- `interval: (maxX / 4).clamp(1, 100000).toDouble()` — when maxX=1 (two points,
  one day apart) → interval=0.25 → clamped to 1. Correct. CLEAN.

**FittedBox edits — layout correctness:**  
All four header sites wrap the Text in `FittedBox(fit: BoxFit.scaleDown,
alignment: Alignment.centerLeft)` inside an `Expanded`. `scaleDown` only shrinks
(never enlarges), so a title that already fits renders at its natural size with
no layout change. Long titles scale down to fit instead of clipping. No change to
Row/Column nesting — the `Expanded` remains in place. CLEAN.

---

## Summary

**findings_count: 2**

| # | Severity | Lens | File:line | One-line claim |
|---|---|---|---|---|
| 1 | P1 | migration_safety | `supabase/migrations/082_user_scoped_sync_natural_keys.sql:1` | Migration 082 missing the mandatory four-line header (Intent/Destructive/Rollback/Diagnose-doc) required by `supabase/migrations/CLAUDE.md`. |
| 2 | P2 | sync_id_correctness | `supabase/migrations/082_user_scoped_sync_natural_keys.sql:48` | DROP+CREATE for wle/wls unique indexes are not wrapped in a transaction — a concurrent sync in the gap (however brief) would INSERT instead of upsert-merge. Negligible at current scale (2 users) but a correctness gap. |

All other lenses (writer/reader drift, sync-id column-tuple correctness,
migration arbiter nullability, reconciler monotonicity, exception swallowing,
unawaited sinks, blast-radius treatment, secrets, widget safety) checked clean
with specific evidence above.
