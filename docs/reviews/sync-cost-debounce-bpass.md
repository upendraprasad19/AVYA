---
branch: sync-cost-debounce
review_type: B-pass (adversarial, context-blind)
reviewer: context-blind Sonnet
date: 2026-06-27
review_rounds: 1
verdict: accepted
bpass: accepted
---

# B-Pass Review — sync-cost-debounce (Unit H: H1a + H3 + H5)

## Changed files
- `lib/core/services/sync_coalescer.dart` (NEW — `SyncCoalescer`, in-flight + dirty do-while)
- `lib/core/services/sync_service.dart` (coalescer fields + 2 kill-switch getters + `flushPendingSyncs`; `pushSnapshot` → `callFunction`)
- `lib/core/services/sync/sync_workout.dart` + `sync/sync_nutrition.dart` (coalesced entry → `*Now()` split)
- `lib/core/services/hive_service.dart` (`onAppPaused` hook)
- `lib/shared/mixins/hive_tab_scaffold.dart` (skeleton clears on first Hive frame + kill-switch)
- `lib/core/services/scheduled_workouts_resync_migrator.dart` + `lib/features/dev/simulation_service.dart` (awaited callers → `*Now()`)
- 7 contract/safety test files re-pointed at the `*Now()` variants + the new `sync_coalescer_behavioral_test.dart`.

Diagnose-doc: `docs/diagnoses/2026-06-27-sync-debounce-cost-h1a-c4f8d2.md`

## Lenses
1. **writer_reader_drift** — CLEAN. Fan-out body moved verbatim into `*Now()`; no Hive field / cloud column renamed; SoT registry updated in the same diff.
2. **function_exception_swallow** — CLEAN. `pushSnapshot` wraps `callFunction` in try/catch → `recordNonFatal` + `_reportSyncFailure`; no naked swallow.
3. **blast_radius** — CLEAN. All 3 kill-switches present (`disable_sync_debounce`, `disable_pushsnapshot_via_callfunction`, `disable_skeleton_first_frame`); the OLD path is preserved verbatim in each branch.
4. **secrets** — CLEAN. No credential-shaped literals.
5. **unawaited_no_error_sink** — see Finding 1.
6. **H1a correctness** — the do-while drains a trigger that lands mid-pass (no loss); in-flight/dirty bookkeeping is AFTER the `pausedForSimulation` guard; both awaited callers use `*Now()`; `_onUserChanged` resets both coalescers. CLEAN.
7. **H3** — `response.data['coach_memory']` mirror unchanged; the redundant `ensureFreshToken()` is correctly dropped (callFunction refreshes first, preserving BUG-C d3a1c7). CLEAN.
8. **H5** — `isLoading || isSessionTearingDown` OR preserved at all 4 tabs; the new configBox read is defensive (try/catch → fix-active). CLEAN.

## Findings (both RESOLVED in-batch)
**Finding 1 — [P1] `flushPendingSyncs` started a CONCURRENT fan-out.** It fired raw
`unawaited(syncWorkoutDataNow())` / `unawaited(syncNutritionDataNow())` without checking
`isInFlight` — so if a coalescer was mid-drain when the app backgrounded, the flush started a
second full fan-out concurrently, defeating the single-pass cost goal. **FIXED:** the flush now
routes through `_workoutCoalescer.trigger(syncWorkoutDataNow)` / `_nutritionCoalescer.trigger(...)`,
which (when in-flight) sets `_dirty` for exactly one trailing pass instead of a concurrent fan-out.

**Finding 2 — [P2] H5 swallowed `initTab()` errors.** The async-tail `catchError` only debug-printed;
the tail now always runs in the background, so a failure was invisible. **FIXED:** added
`ErrorTelemetry.recordNonFatal(e, s, reason: 'hive_tab_scaffold_init_tab')`.

## Verification
`flutter analyze` clean on the fix files; the affected tests (`session_teardown_skeleton_guard`,
`sync_coalescer_behavioral`, `promotion_celebration_wiring`) green after the fixes; full suite 3032 green.

verdict: accepted
