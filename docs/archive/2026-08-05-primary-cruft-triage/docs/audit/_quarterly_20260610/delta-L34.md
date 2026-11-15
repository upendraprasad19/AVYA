# Delta Audit — Lens L34 (Silent-failure legs / unobservable error paths)

Scope: `git diff --name-only 969c117..HEAD` ∪ `git show a767725` (3 batches:
regression-prevention WI, slow-boot additive-restore c5a1f2, apk34-obs).
Focus: the silent-failure legs the prompt enumerated (a)–(e).

L34 charter applied: an error/failure path that swallows silently — empty catch,
debugPrint-only catch with no `ErrorTelemetry.recordNonFatal`, an unawaited future
whose rejection is unobservable, or a skip branch firing for an unexpected reason
without telemetry.

---

## Result: CLEAN (0 actionable findings)

All five focus legs were checked and each carries an observable error sink. The
two candidate gaps below were investigated and classified FALSE_ALARM with
evidence; recording them so a future audit doesn't re-flag the same lines.

---

### (a) restoring_screen.dart `_healAfterRestoreInBackground` unawaited chain — REAL? NO / FALSE_ALARM
`lib/features/auth/screens/restoring_screen.dart:577-630`. Every one of the 7
heal steps (exlog/nlog/saved-meal migrators, phase reconciler, plan-integrity
reconciler, refill, **`reconcileExlogIndexes`**) is individually wrapped in
`try { … } catch (e, st) { unawaited(ErrorTelemetry.recordNonFatal(e, st, reason: 'bg_heal_*')); }`.
The `reconcileExlogIndexes` failure DOES surface (`reason: 'bg_heal_exlog_index'`,
line 624-627). The chain entry itself — `unawaited(restoreFuture.then((result) {
if (result.succeeded) _healAfterRestoreInBackground(); }))` (line 196-198) — is
gated on `result.succeeded`, and the gate is the deliberate B-pass F-3 design
(heals never run on a cancelled/failed restore). The `restoreFuture` rejection
path is owned inside `restoreFromCloudForUser` (telemetered there). No silent leg.

### (b) sync_realtime.dart channelError recovery (a7f2e9) — REAL? NO / FALSE_ALARM
`lib/core/services/sync/sync_realtime.dart:74-123`. A failed re-subscribe is
observable on three legs: (1) `onError` always fires `_reportSyncFailure(opType:
'realtime_stream_weight_logs')` BEFORE deciding to reconnect (line 77);
(2) the bounded reconnect (`attempt < 2`, line 97) means a persistent
channelError still emits a sync-failure telemetry op each attempt, then falls
back to the 24h batch pull — it does not "silently stop syncing"; (3) the
reconnect's own `refreshSession()` failure records a non-fatal
(`reason: 'sync_service_catch_4'`, line 118) and returns. The only un-telemetered
exit is the deliberate `attempt >= 2` fall-through, which is preceded by the
per-attempt `_reportSyncFailure` — so the dead stream IS observable in
`client_errors`. No silent leg.

### (c) sync_service token-refresh (d3a1c7) — REAL? NO / FALSE_ALARM
All five `ensureFreshToken()` callsites (`sync_service.dart:423, 659, 938, 1048,
1510`) delegate the failure-observability to `SupabaseService.ensureFreshToken`
(`lib/core/services/supabase_service.dart:176-206`). On an OFFLINE refresh
failure the method's internal catch fires
`ErrorTelemetry.recordNonFatal(reason: 'supabase_service_ensure_fresh_token_refresh')`
(line 194-195) and returns the stale/null token rather than throwing — so a
refresh FAILURE is recorded, not swallowed. The bare `await ensureFreshToken()`
at line 1048 (restore preamble) therefore cannot lose observability even though
that single call has no local try/catch: the sink is inside the callee. No silent leg.

### (d) additive-restore skip-if-local-exists branches — REAL? NO / FALSE_ALARM
`sync_workout.dart:605,787`, `sync_nutrition.dart:443,535`. The skip predicate is
`box.get(key) == null` (or `!= null) continue`). A skip is NOT independently
telemetered, but that is the *intended* local-wins terminal state (ADR-0014,
diagnose c5a1f2) — a skip means "a local row already exists; keep it," which is
the designed-for-common case, not an error. The narrow "skip for an UNEXPECTED
reason" worry (a CORRUPT non-Map local row at `key` causes the cloud row to be
skipped silently) is real in theory but: (1) NOT introduced by these batches —
the guard mirrors the pre-existing weight pattern (`sync_health.dart:300`);
(2) self-healing — `reconcileExlogIndexes` (called post-restore) and every reader
guard `is! Map` / null-coalesce, so a corrupt row is dropped by readers rather
than rendered; (3) on the exlog path the row is always re-indexed regardless of
skip (`addToExlogIndex`, line 790-791), so an orphan-but-present row is healed.
A skip-path counter would be a *nice-to-have* observability add, not a fix for a
silent failure. Out of DELTA scope as an L34 finding.

### (e) workout_write_service addToExlogIndex / reconcileExlogIndexes error legs — REAL? NO / FALSE_ALARM
`lib/core/services/workout_write_service.dart:338-391`. `addToExlogIndex` and
`reconcileExlogIndexes` do not contain their own try/catch — by design: every
*caller* wraps them. The `logExercise` callsite of `_appendToIndex` runs inside
the method-level `try/catch` that records `reason:
'workout_write_service_log_exercise'` (line 216) and returns
`WriteResult.fail`. The background-heal callsite of `reconcileExlogIndexes` is
wrapped at `restoring_screen.dart:618-627` (`bg_heal_exlog_index`). The restore
callsite (`addToExlogIndex` at `sync_workout.dart:790`) sits inside
`_restoreExerciseLogs`' outer try/catch (`reason: 'sync_service_for_14'` +
`_reportSyncFailure(opType: 'restore_exercise_logs')`, line 793-800). Every
error leg has a sink one frame up. No silent leg.

---

## Verification commands
- (a) `rg -n "recordNonFatal|reconcileExlogIndexes" lib/features/auth/screens/restoring_screen.dart`
- (b) `rg -n "_reportSyncFailure|sync_service_catch_4|attempt < 2" lib/core/services/sync/sync_realtime.dart`
- (c) `rg -n "ensure_fresh_token_refresh|recordNonFatal" lib/core/services/supabase_service.dart`
- (d) `rg -n "get\(.*\) == null|!= null\) continue" lib/core/services/sync/sync_workout.dart lib/core/services/sync/sync_nutrition.dart`
- (e) `rg -n "workout_write_service_log_exercise|sync_service_for_14|bg_heal_exlog_index" lib/core/services/workout_write_service.dart lib/core/services/sync/sync_workout.dart lib/features/auth/screens/restoring_screen.dart`

CLEAN — the three batches were authored with explicit L34 discipline (see the
inline `Hermes L34:` comment at `restoring_screen.dart:578`). No silent-failure
leg found in DELTA scope.
