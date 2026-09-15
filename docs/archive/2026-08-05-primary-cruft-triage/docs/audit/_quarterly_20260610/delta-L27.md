# Delta audit — L27 (Concurrency on shared state)

**Scope:** `git diff 969c117..HEAD` ∪ `git show a767725` (slow-boot flip + additive/local-wins restore).
**Charter:** every `getX()→modify→setX()` on shared Hive/Postgres state; ≥2 unserialized writers ⇒ lost-update. Precedent: streak-freeze refill↔consume race.
**New surface:** bg cloud restore now runs WHILE the user is on /home (ADR-0014). Writers in scope: restore `_restoreXxx`, `WorkoutWriteService`, realtime handler, `DayRolloverObserver`, key migrators, `reconcileExlogIndexes`, streak refill/consume.

---

## Finding 1 — `_restoreFreezes` clobbers a concurrent `commitConsume` write to the shared `progress` map  [P2 — REAL]

**File:** `lib/core/services/sync/sync_restore_completeness.dart:142-184` vs `lib/core/services/streak_progress_service.dart:100-134` (`commitConsume`).

Verbatim (`_restoreFreezes`, treats cloud used_dates as authoritative, full-map overwrite):
```
176   // used_dates is consume-only state; take cloud as authoritative
179   final usedRaw = res['streak_freezes_used_dates'];
180   existingMap['streak_freeze_used_dates'] = (usedRaw is List)
181       ? usedRaw.map((e) => e.toString()).toList() : <String>[];
184   await box.put('progress', existingMap);
```

Both `_restoreFreezes` and `commitConsume`/`commitRefill` (`UserRepository.updateProgress`, user_repository.dart:133-143) are read-modify-write on the single `userBox['progress']` map. Each individually is isolate-atomic (no `await` between the `get` and the `put`). The defect is **task-level**, not interleave-level:

**Interleave:** bg path lands /home at `restoring_screen.dart:190` *before* restore Step C runs `_restoreFreezes` (sync_service.dart:1122). On /home, the streak walk (`_calculateStreak(consume:true)`, workout_repository.dart:196-311) runs via rollover/`completeWorkout` and `commitConsume` writes `used_dates=[D], available=N-1` to local Hive. That consume hasn't yet propagated to cloud (`syncFreezes` is fire-and-forget, line 118). `_restoreFreezes` then reads `existingMap` (line 142, sees the fresh consume) but **unconditionally replaces** `streak_freeze_used_dates` with the *stale cloud* snapshot (line 180) — silently discarding date D. The `available` count is similarly clobbered when `cloudWins` (line 164).

This is the L27 precedent class (refill↔consume) recurring. The `available`/`last_refill` leg got a max-merge guard (Bug 9c4a17, line 147-174); the **`used_dates` leg has no merge** — it is the unguarded half. The additive/local-wins fix from c5a1f2 does NOT cover this: that guard is skip-if-local-exists on *log rows* (exlog/wlog/nutrition/saved-meal), not on the shared `progress` map.

**Impact:** a freeze consumed on /home during the restore window is lost → spurious streak break or a freeze "refunded" it shouldn't be. Low frequency (needs a missed-day consume firing inside the ~Step-C window) → P2, not P1.

**Verification cmd:**
`flutter test test/contracts/restore_local_wins_additive_test.dart` (does NOT cover the progress map) — add a harness: seed cloud used_dates=[], local consume writes used_dates=[D], run `_restoreFreezes`, assert D survives. Current behavior: D is dropped.

**Verdict: REAL** (P2 lost-update on `streak_freeze_used_dates`).

---

## Attacks tried and found CLEAN

- **`exercise_log_index_<date>` (restore `addToExlogIndex` ↔ `logExercise` ↔ `reconcileExlogIndexes`)** — `workout_write_service.dart:338-391`. Union (add-only) read→put with no `await` between get and put → isolate-atomic; reconcile is idempotent union-rebuild. The hypothesised race was control-tested (25 concurrent unlocked appends, all survived) and refuted in diagnose c5a1f2. CLEAN.
- **Log-row overwrite (restore `put` over a just-logged local row)** — `_restoreExerciseLogs:787`, `_restoreWorkoutLogs:605`, `_restoreNutritionLogs:443`, `_restoreSavedMeals:535`, `_restoreWaterLogs:475`. All gated `if (box.get(key) == null)` / `== 0`. Additive/local-wins. CLEAN.
- **`schedule_<date>` (restore `_restoreScheduledWorkouts` ↔ `markCompleted`)** — sync_workout.dart:1653-1794. Per-key `get`→merge→`put` is isolate-atomic; the merge is timestamp-aware and local-`completed`-wins-over-cloud-`planned` (Bug B.2, d9b2c5). A concurrent `markCompleted` (which holds `_acquireLock(dateStr)`, wws.dart:408) writing between the restore's row-fetch and per-key `get` is read fresh and merged correctly. CLEAN.
- **`_restoreScheduleCompletions` synthesize-orphan (e9b4a2) ↔ `markCompleted`** — sync_workout.dart:819-857. Synthesizes only when `existing` absent; if a concurrent `markCompleted` wrote the row first, the `existing is Map` branch updates only when `status != 'completed'`. No clobber of a completed row. CLEAN.
- **EF token refresh stampede (d3a1c7)** — `supabase_service.dart:176-206` `ensureFreshToken` has NO in-flight dedup; concurrent callers (pushSnapshot, `_reportSyncFailure`, realtime `refreshSession`, ai_service direct) within the 5-min buffer each call `client.auth.refreshSession()`. However GoTrue (`supabase_flutter`) serializes refresh internally (single-flight on the auth client) and rotates one refresh token; redundant calls are wasteful, not a lost-update on app-owned state. No shared *Hive/Postgres* state is read-modify-written here. CLEAN for L27 (a minor efficiency note, not a race).
- **`reconcileExlogIndexes` running after `restoreFuture.then` (restoring_screen:196-198) guarded on `result.succeeded`** — runs only post-restore-success, so it never overlaps the restore's own index writes. CLEAN.

---

**Net: 1 REAL (P2).** The slow-boot concurrency flip is well-covered for log rows and the exlog index (additive guards + reconcile, c5a1f2), but the shared `streak_freeze` `progress` map's `used_dates` leg was left outside that coverage — `_restoreFreezes` overwrites it without merging a concurrent local consume.
