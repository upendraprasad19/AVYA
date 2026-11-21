# Workout Write Service Verification (APK Test #6 Plan A)

**Date:** 2026-05-01  
**Branch:** `feat/apk-test-6-batch` (commit `ff2796f` + concurrency + verification tasks)  
**Reference Spec:** `docs/superpowers/specs/2026-04-30-workout-write-service.md` §12.2 (C1–C4 success criteria)

---

## Success Criteria (C1–C4)

### C1: Single Exercise Log → ONE Row (idempotent)

**Test:** `test/workout_write_service/log_exercise_appends_sets_test.dart`

**Passing test:** `appends sets across calls: 4 calls → 1 row, sets[].length=4`

**On-device verification:**
1. Sign up / log in (fresh account)
2. Navigate to Train → Start Active Workout (if available) → log a Bench Press set (1×60kg×10reps)
3. Immediately log another set (1×70kg×8reps) of the same exercise
4. Query Supabase: `SELECT * FROM workout_log_exercises WHERE exercise_id='Bench Press' AND completed_at::DATE=today;`
5. **Expect:** Exactly ONE row with `set_number=2` (not two rows). `weight_kg=70` (max across sets), `sets` JSONB column contains both set records.

---

### C2: Concurrent Logs → Mutex Serializes to Single Upsert

**Test:** `test/workout_write_service/concurrency_test.dart` → `two simultaneous logExercise for same (date, exerciseName) → mutex serializes`

**Passing test:** 3/3 concurrency tests (all ~3 sec)

**On-device verification:**
1. Open AI Coach
2. Rapidly send two workout-logging tool-calls for the same exercise (e.g., "Log 2 sets of curls: 10kg×12 and 15kg×8") within 1 second
3. Both should land on the same row in `workout_log_exercises` (merged sets, no duplicate rows)
4. Query Supabase to verify: ONE row with 2 sets, `set_number=2`

---

### C3: Different Exercises → Separate Rows (no false merging)

**Test:** `test/workout_write_service/concurrency_test.dart` → `two simultaneous logExercise for same date, DIFFERENT exercises → no mutex contention, 2 rows`

**Passing test:** Concurrent calls to Bench Press + Squats → 2 separate rows

**On-device verification:**
1. Start Active Workout → log Bench Press (1×60kg×10reps) + Squats (1×100kg×5reps) in rapid succession (~1 sec apart)
2. Query Supabase: `SELECT COUNT(*), exercise_id FROM workout_log_exercises WHERE completed_at::DATE=today GROUP BY exercise_id;`
3. **Expect:** 2 rows, one per exercise (Bench Press, Squats), `set_number=1` each

---

### C4: Concurrent Edit + Log → No Data Loss (mutex guards both paths)

**Test:** `test/workout_write_service/concurrency_test.dart` → `concurrent logExercise + edit (via _applyMutations) → mutex serializes, final state consistent`

**Passing test:** Appending a new set while editing the existing set → final row has both changes

**On-device verification:**
1. Log a Deadlift set (1×100kg×5reps)
2. Immediately open the Edit sheet + change the weight to 110kg (tap-to-edit on receipt card)
3. At the same time, AI Coach logs another set via tool-call (1×120kg×3reps)
4. **Expect:** Final row has 2 sets, weight_kg=120 (max), both edits preserved (no data loss)

---

## Regression Tests (Unit Suite)

All tests under `test/workout_write_service/`:

- `log_exercise_appends_sets_test.dart` (2 tests) — appending sets, batch inserts
- `log_exercise_dedup_60s_test.dart` (2 tests) — 60s dedup window, time boundaries
- `log_exercise_new_day_test.dart` (1 test) — new day → reset row count
- `edit_log_pr_rescan_test.dart` (1 test) — edit weight → PR flag rescan
- `delete_log_undo_test.dart` (1 test) — delete + restore via temp key
- `mark_completed_test.dart` (1 test) — workout completion
- `upsert_scheduled_test.dart` (1 test) — schedule upsert
- `regenerate_week_test.dart` (1 test) — week regen
- `reschedule_day_test.dart` (1 test) — day reschedule
- `sync_three_tier_test.dart` (1 test) — 3-tier sync order
- `migration_old_keys_test.dart` (2 tests) — legacy key migration
- **`concurrency_test.dart`** (3 tests) — mutex serialization, concurrent edits

**Total:** 19 tests, 0 failures

---

## Related Commits

| Commit | Task | Summary |
|---|---|---|
| (A-17) | Concurrency tests | `test/workout_write_service/concurrency_test.dart` — 3 mutex/contention tests |
| (A-19) | Verification doc | This file — on-device verification steps for C1–C4 |

---

## Notes

- **Mutex scope:** Per `(date, exerciseName)` pair. Different exercises on same date = no contention, separate rows.
- **Set aggregation:** `set_number` = count of unique sets (order-independent). `weight_kg` = max. `volume_kg` = sum of weight×reps.
- **Dedup window:** 60s — two calls within 60s of each other on same exercise are merged; beyond 60s they create separate rows (per `log_exercise_dedup_60s_test.dart`).
- **SSRF safeguard:** All Hive mutations remain local; sync to Supabase is fire-and-forget (`unawaited`). No blocking on cloud writes.
