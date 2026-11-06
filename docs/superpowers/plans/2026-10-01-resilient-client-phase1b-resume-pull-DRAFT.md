# Resilient Client — Phase 1b: pull-on-resume (DRAFT — NOT CONVERGED, DO NOT EXECUTE)

> **Status:** seed material only. Split out of `2026-10-01-resilient-client-phase1.md` (revision 2 → 3) under CLAUDE.md §4.12.1: two plan-review rounds in a row found design-level defects in this unit. It needs a NEW plan, rewritten from the requirements below, then its own two context-blind review rounds, before any code. The text under "Former Task 3" is revision 2's Task 3 VERBATIM — it has known defects (listed first) and must not be copied forward unchanged.
> **Tracked by:** the Phase 1b OI minted in Phase 1's Task 8 (the closure ledger carries it as `blocked_on_user`).

**Goal (founder, 2026-10-01):** a device that has been backgrounded (Android is rarely closed) refreshes itself from the cloud when brought forward, so data logged on another device appears without a cold start — recent window only (7 days), minimal Supabase load, no periodic timer, "next time I open the app" latency is acceptable.

## Requirements the rewrite MUST satisfy (each verified against code in round 2)

1. **Pull BEFORE reckon.** `DayRolloverObserver.didChangeAppLifecycleState(resumed)` → `_checkAndRollover()` → `_doRolloverWithRef` runs `refillIfNewWeek()` then `WorkoutRepository.reckonStreakDecayAndPersist()` (`workout_repository.dart:231-262`, gated only by `restoreCompletedTick > 0` + a non-empty schedule) on STALE local completions before the new date is stored. A stale device therefore consumes streak freezes / breaks the streak for days that were completed on the other device, and persists the result to the cloud (`_persistCurrentStreakDays`). Pre-existing hazard; a pull that merely starts after `_checkAndRollover()` does not fix it. The design must run a bounded (≤ ~10 s) pull FIRST when a pull is due and a rollover is pending, then reckon.
2. **Pending-delete-aware exercise-log restore.** `_restoreExerciseLogs` writes only `if (_hive.workoutBox.get(logId) == null)` (`sync_workout.dart:1024`). An exercise log the user deleted locally whose tombstone is still queued in `PendingExlogDeletes` (`workout_write_service.dart:1242`; drained by `_drainPendingExlogDeletes`, `sync_workout.dart:216-243`, which only reports via `recordNonFatal`) is therefore RESURRECTED by the pull — and the outage is exactly when tombstones sit queued. Skip rows whose natural key `(workout_log_id, exercise_id, set_number)` is queued. The cold-start restore shares this writer: verify and fix there too.
3. **A swallowed per-set fetch must fail the pull.** The per-set fetch failure is caught at `sync_workout.dart:891-901` and the loop continues with summary-only rows; the local-wins write then stores an exercise log WITHOUT `sets`, and local-wins never heals it. Fetch exercise logs AND sets inside the pull (pass `preFetchedExercises` / `preFetchedSets`), and treat a failed sets fetch as a failed pull.
4. **Own refresh signal.** `restoreCompletedTick` is bumped only at `heal_after_restore.dart:74` (after a SUCCESSFUL background restore) and doubles as the streak-decay safety gate. A device whose background restore never completed has tick 0, so a pull that bumps only when `tick > 0` writes rows and never refreshes the UI. Use a separate `resumePullTick` that `HiveTabScaffoldMixin` (`shared/mixins/hive_tab_scaffold.dart:158,215`) and the coach screen (`ai_coach/screen.dart:184,282`) also listen to — and decide per listener what a refresh must NOT do (Train's `invalidateOnRetry` resets `selectedWeekProvider`; the coach screen scrolls).
5. **Failure signal.** The restore writers swallow their own errors (`_reportSyncFailure`, no rethrow), so a `catch` never fires. Count failures at the funnel (`_syncFailureSeq++` at the top of `_reportSyncFailure`) and compare before/after each op. (Removed from Phase 1: only the pull used it.)
6. **Water:** `_restoreWaterLogs` (`sync/sync_nutrition.dart:788`) — write only when `existing == null` (not `existing == null || 0`), the local value is a bare int with no timestamp; typed-field predicate for the window signature. Stale-device overwrite stays a Phase 2 residual.
7. **Never** pull meals (`_restoreNutritionLogs` resurrects local-only deletes) or the scheduled-workouts overlay (can wipe an unpushed swap) until Phase 2 tombstones; never route through `_safeRestoreOp` (one `client_errors` row per success until Unit E's filter); never call the catastrophic-tier `restore-user-snapshot` EF.
8. **Test lessons already paid for (round 2, R2a):** (a) the controller's cooldown starts at construction → a test that sets `now` then calls `make(...)` is `skipped`; advance the clock AFTER construction; (b) the "kill-switch on" test is vacuous if the cooldown already returns `skipped` — start it from a due state; (c) `import '../helpers/sync_stub_server.dart'` is unused when only member accesses go through the harness → `unused_import` fails the push; (d) the `supabase` SDK retries a GET answered 503/520 three times (1 s/2 s/4 s), so a stub `failReadsTo` answering 503 yields 4 requests and a "one failing request" assertion fails — answer 500/504, or use `.retry(enabled: false)` on the pull reads; (e) `test/contracts/no_silent_debugprint_in_services_test.dart:139` flags a new `lib/core/services/resume_pull_controller.dart` whose `catch` has `debugPrint` but no `ErrorTelemetry.recordNonFatal/logEvent/rethrow` — add the telemetry call, do not grandfather the file; (f) `events.clear()` ran BEFORE `h.setUp()` so the collector captured `hive_session_opened` — clear after setUp; (g) `docs/sot_registry.yaml` entries that go stale with the pull present: `day_rollover_service.dart` `:1456` (`runRolloverNow` 129-138, moves 130→145) and `compileDailySnapshot` (→1113, outside 1052-1110); (h) `sync_service_public_api_snapshot_test` needs `pullRecentWindow`; (i) wiring literals that the plan's own code line-breaks (`unawaited(ResumePullController.instance
 .pullIfDue(`) must be matched with `s*`.

## Round-1 rows that concern this unit

| # | Finding | Disposition |
|---|---|---|
| R1 | Resume pull includes `_restoreNutritionLogs` → a meal deleted locally is re-added from the cloud (delete is local-only, `NutritionWriteService.deleteLog`; cloud keeps it). `_restoreScheduledWorkouts` is an unbounded timestamp-overlay that can wipe an unpushed swap. | **Both dropped from the pull** (D10/D11). Meals logged on another device appear at the next cold start; schedule edits likewise. Nutrition-delete resurrection is an EXISTING cold-start bug → own OI (Task 8). |
| R4 | `restoreCompletedTick` is also the streak-decay safety gate (`workout_repository.dart:244-247`) and Train's `invalidateOnRetry` resets `selectedWeekProvider`. | Bump only when `tick > 0` AND a Hive window signature changed (D7). Side effects documented. |
| R8 | The writers swallow their own errors (`_reportSyncFailure`, no rethrow) so a pull `catch` never fired. | Pull measures failure with `_syncFailureSeq` (incremented at the funnel top) before/after each op. |
| R14 | Public-API snapshot goes red between Task 2 (`probeBackendReachable`) and Task 3; imports of not-yet-created files; `failReadsTo`/`requests` state leaks across tests in one file (the harness server object is shared). | Snapshot entry moved to Task 2; imports added per task; behavioral test `setUp` clears `requests`, `failReadsTo`, `getResponders`. |

## Design decisions of revision 2 (D3–D11) — re-derive, do not inherit

| # | Decision | Why |
|---|---|---|
| D3 | Resume pull = 7-day window through the EXISTING private `_restoreX(userId, since)` writers, additive / local-wins (`docs/architecture/sync.md:367-377`). No Edge Function, no migration, no RLS change. | `restore-user-snapshot` is catastrophic-tier (service_role) and hard-codes `since='2020-01-01'` (`sync_service.dart:1701`, `:1827`); a resume pull must not touch it. |
| D4 | **Water is NOT timestamp-merged in Phase 1.** `_restoreWaterLogs` (`sync/sync_nutrition.dart:788`) writes only if the local day is absent/0. | Local value is a bare `int` under `water_ml_<date>` with no modified-time, so "newer wins" is impossible without a format change. A stale device holding a non-zero total still wins locally; that residual is Phase 2's per-drink entries. |
| D5 | No periodic timer, 5-min cooldown, 7-day window. The cooldown **starts at process start** and at every attempt (success OR failure) and on account change. | Founder uses one device at a time; "next time I open the app" is acceptable. Starting the cooldown at process start means the resume event that fires at cold launch does not duplicate the cold-start restore (no in-flight flag needed — the 25 exits of `restoreFromCloudForUser` cannot be instrumented safely). A failed pull waits 5 min, so a struggling server is not hit on every resume. |
| D6 | The pull does NOT use `_safeRestoreOp`. | `_safeRestoreOp` writes one `client_errors` row per successful op (`restore_op_done`). The pull wraps each writer in `applyRestoreCeiling` (45 s) and logs failures only. |
| D7 | After a pull that CHANGED the 8-day Hive window (signature before ≠ after), bump `restoreCompletedTick` — **only if it is already > 0**. | `restoreCompletedTick > 0` is the "cloud restore has completed" safety gate for streak decay (`workout_repository.dart:231-247`); bumping from 0 would open it without a completed restore. Side effects of a bump (all four tabs invalidate; Train resets `selectedWeekProvider`; the coach screen scrolls to the bottom) are therefore limited to "data really changed on another device" and are documented. If `tick == 0` (cold restore never completed) the rows are still written; providers refresh on the next navigation. |
| D8 | Recovery does not auto-trigger a pull; the next resume does. | Keeps the active-workout guard (needs a `WidgetRef`) in exactly one place. |
| D9 | Shared failure state: while `SyncRetryController.paused` the resume pull refuses; a pull that sees any failure aborts at once. | One backoff for push and pull; no hammering. |
| D10 | `_restoreNutritionLogs` is NOT in the pull. | Meal deletes are local-only (`NutritionWriteService.deleteLog` → `box.delete`, no cloud tombstone — recorded "accepted residual"); `_restoreNutritionLogs` 3-way-unions cloud items back in, so a pull would resurrect deleted meals every resume. The same bug exists at cold start today; filed as its own OI (Task 8), fixed by Phase 2 tombstones. |
| D11 | `_restoreScheduledWorkouts` is NOT in the pull. | It is an unbounded timestamp overlay (not additive / local-wins, `d9b2c5`) and can overwrite an unpushed local swap. Completions (`_restoreScheduleCompletions`) are forward-only (`status → completed`) and are the signal that makes "workout done on web" show on Android. |

## Former Task 3 (revision 2, verbatim — KNOWN DEFECTS above; do not copy forward)

### Former Task 3: Pull a 7-day window on resume (Unit C)

**Symptom:** the Android app, kept in the background, never showed what was logged on web. Pull exists only at cold start (`restoring_screen.dart:114`); `DayRolloverObserver`'s `resumed` branch (`day_rollover_service.dart:68-79`) runs `_checkAndRollover()` and re-subscribes realtime (weight, PRO-gated) and nothing else.
**Writer/reader:** writers = the existing `_restoreWorkoutLogs` (`sync/sync_workout.dart:797`), `_restoreExerciseLogs` (`:861`, tombstone-aware `:905-910`), `_restoreScheduleCompletions` (`:1043`), `_restoreWeightLogs` (`sync/sync_health.dart:458`), `_restoreWaterLogs` (`sync/sync_nutrition.dart:788`) — all additive / local-wins (verified: each `if (box.get(key) != null) continue;` / completion is forward-only `status → completed`). Readers = the four tabs via `restoreCompletedTick` → `HiveTabScaffoldMixin` (`shared/mixins/hive_tab_scaffold.dart:158,215`).
**Recurrence check:** restore-completeness / writer-reader-drift class. This unit adds NO new writer — it calls existing ones with a different `since`; the drift surface is `since` semantics per writer (verified: wlog/weight `created_at >=`; exlog/sets/completions `completed_at >=`; water `date >=` using `since.substring(0,10)`). `since` is IST-midnight-in-UTC, so the window is never short; for water its date prefix is the UTC date (one extra day — harmless).
**Why these five and not seven (D10/D11):** meals and the schedule are excluded — see the decision rows.

**Files:**
- Create: `lib/core/services/resume_pull_controller.dart`
- Modify: `lib/core/services/sync/sync_resilience.dart` (add `pullRecentWindow`)
- Modify: `lib/core/services/sync_service.dart` (bind; reset; `_refreshAfterResumePull`; `markPulled` ×2)
- Modify: `lib/core/services/day_rollover_service.dart` (`resumed` branch)
- Modify: `test/helpers/sync_stub_server.dart` (`failReadsTo`), `test/contracts/sync_service_public_api_snapshot_test.dart`
- Test: `test/contracts/resume_pull_controller_test.dart`, `test/sync/resume_pull_window_behavioral_test.dart` (create)

**Interfaces:**
- Produces: `kResumePullCooldown` (5 min), `kResumePullWindowDays` (7), `enum ResumePullOutcome { skipped, failed, unchanged, changed }`, `bool shouldResumePull({now, lastAttemptAt, authenticated, workoutInProgress, pullInFlight, syncPaused, cooldown})`, `String resumePullSince(DateTime now, {int days})`, `List<String> resumePullDates(DateTime now, {int days})`, `String resumeWindowSignature(List<String> dates, Object? Function(String) readWorkout, Object? Function(String) readHealth)`, `class ResumePullController` — ctor `({required pull, onChanged, clock, isDisabled, isAuthenticated, isSyncPaused})`; `static instance`; `bind({pull, onChanged, isAuthenticated, isSyncPaused})`; `markPulled([DateTime?])`; `reset()`; `Future<ResumePullOutcome> pullIfDue({required bool workoutInProgress})`. `SyncService.pullRecentWindow({int days})` → `Future<ResumePullOutcome>`.
- Consumes: `SyncRetryController.instance.paused` (Task 2), `istDateStr`, `SyncService.applyRestoreCeiling`.

- [ ] **Step 1: Write the failing controller test**

Create `test/contracts/resume_pull_controller_test.dart`:

```dart
// test/contracts/resume_pull_controller_test.dart
//
// Contract — closes-diagnose e5b2a9 (Unit C). Pull-on-resume must be gated
// (cooldown that starts at process start / every attempt, in-flight, signed-out,
// active workout, backend paused), cheap (7-day IST window), account-safe, and
// must only refresh the UI when the Hive window actually changed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/resume_pull_controller.dart';

DateTime _t(int min, [int sec = 0]) => DateTime.utc(2026, 10, 1, 6, min, sec);

bool _gate({
  DateTime? last,
  DateTime? now,
  bool auth = true,
  bool workout = false,
  bool inFlight = false,
  bool paused = false,
}) =>
    shouldResumePull(
      now: now ?? _t(30),
      lastAttemptAt: last,
      authenticated: auth,
      workoutInProgress: workout,
      pullInFlight: inFlight,
      syncPaused: paused,
    );

void main() {
  group('shouldResumePull', () {
    test('no attempt yet is allowed', () => expect(_gate(), isTrue));
    test('cooldown boundary: 4:59 blocked, 5:00 allowed', () {
      expect(_gate(last: _t(25, 1), now: _t(30)), isFalse);
      expect(_gate(last: _t(25), now: _t(30)), isTrue);
    });
    test('each blocker alone blocks', () {
      expect(_gate(auth: false), isFalse);
      expect(_gate(workout: true), isFalse);
      expect(_gate(inFlight: true), isFalse);
      expect(_gate(paused: true), isFalse);
    });
    test('MIRROR: a long-stale attempt with no blockers is allowed', () {
      expect(_gate(last: _t(0), now: DateTime.utc(2026, 10, 1, 9)), isTrue);
    });
  });

  group('window helpers (IST)', () {
    test('resumePullSince is the UTC instant of IST midnight, 7 IST days back', () {
      // 2026-10-01 05:00Z = 10:30 IST Oct 1 → IST Sep 24 00:00 = Sep 23 18:30Z
      expect(resumePullSince(DateTime.utc(2026, 10, 1, 5)),
          '2026-09-23T18:30:00.000Z');
    });
    test('IST day-boundary: 18:45Z Oct 1 is already Oct 2 in IST', () {
      // 00:15 IST Oct 2 → IST Sep 25 00:00 = Sep 24 18:30Z
      expect(resumePullSince(DateTime.utc(2026, 10, 1, 18, 45)),
          '2026-09-24T18:30:00.000Z');
    });
    test('the window is never SHORT: since ≤ IST midnight of the first day', () {
      final since = DateTime.parse(resumePullSince(DateTime.utc(2026, 10, 1, 5)));
      expect(since.isAfter(DateTime.parse('2026-09-24T00:00:00+05:30')), isFalse);
    });
    test('resumePullDates lists days+1 IST dates, newest first, IST-correct', () {
      final d = resumePullDates(DateTime.utc(2026, 10, 1, 18, 45)); // IST Oct 2
      expect(d.length, 8);
      expect(d.first, '2026-10-02');
      expect(d.last, '2026-09-25');
    });
    test('constants', () {
      expect(kResumePullWindowDays, 7);
      expect(kResumePullCooldown, const Duration(minutes: 5));
    });
  });

  group('resumeWindowSignature', () {
    String sig(Map<String, Object?> w, Map<String, Object?> h) =>
        resumeWindowSignature(['2026-10-01'], (k) => w[k], (k) => h[k]);

    test('identical content → identical signature', () {
      expect(sig({'wlog_2026-10-01': {'a': 1}}, {'weight_2026-10-01': 70}),
          sig({'wlog_2026-10-01': {'a': 1}}, {'weight_2026-10-01': 70}));
    });
    test('a new wlog / weight / water / exlog-index / completed schedule row each change it', () {
      final base = sig({}, {});
      expect(sig({'wlog_2026-10-01': {'a': 1}}, {}), isNot(base));
      expect(sig({}, {'weight_2026-10-01': 70}), isNot(base));
      expect(sig({}, {'water_ml_2026-10-01': 500}), isNot(base));
      expect(sig({'exercise_log_index_2026-10-01': ['k1']}, {}), isNot(base));
      expect(sig({'schedule_2026-10-01': {'status': 'completed'}}, {}), isNot(base));
    });
    test('MIRROR: a key OUTSIDE the window does not change it', () {
      expect(sig({'wlog_2026-09-01': {'a': 1}}, {}), sig({}, {}));
    });
  });

  group('ResumePullController', () {
    late int pulls;
    late ResumePullOutcome result;
    late bool paused;
    late int changes;
    late DateTime now;
    late ResumePullController c;

    ResumePullController make({
      Future<ResumePullOutcome> Function()? pull,
      bool disabled = false,
    }) =>
        ResumePullController(
          pull: pull ??
              () async {
                pulls++;
                return result;
              },
          onChanged: () => changes++,
          clock: () => now,
          isDisabled: () => disabled,
          isAuthenticated: () => true,
          isSyncPaused: () => paused,
        );

    setUp(() {
      pulls = 0;
      result = ResumePullOutcome.changed;
      paused = false;
      changes = 0;
      now = _t(30);
      c = make();
    });

    test('the cooldown STARTS AT PROCESS START: a resume at cold launch does not pull', () async {
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.skipped);
      expect(pulls, 0);
      now = _t(35);
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.changed);
      expect(pulls, 1);
      expect(changes, 1);
    });

    test('every attempt — even a FAILED one — starts the cooldown', () async {
      now = _t(36);
      result = ResumePullOutcome.failed;
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.failed);
      expect(changes, 0);
      now = _t(38);
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.skipped,
          reason: 'a struggling server is not hit again on the next resume');
      expect(pulls, 1);
      now = _t(41);
      result = ResumePullOutcome.unchanged;
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.unchanged);
      expect(changes, 0, reason: 'unchanged data must not refresh the UI');
    });

    test('concurrent resumes dedupe to one pull', () async {
      now = _t(40);
      final a = c.pullIfDue(workoutInProgress: false);
      final b = c.pullIfDue(workoutInProgress: false);
      final r = await Future.wait([a, b]);
      expect(pulls, 1);
      expect(r, contains(ResumePullOutcome.skipped));
    });

    test('an active workout blocks the pull', () async {
      now = _t(40);
      expect(await c.pullIfDue(workoutInProgress: true), ResumePullOutcome.skipped);
      expect(pulls, 0);
    });

    test('a paused backend blocks the pull', () async {
      now = _t(40);
      paused = true;
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.skipped);
      expect(pulls, 0);
    });

    test('markPulled() — a successful cold-start restore counts as a pull', () async {
      now = _t(40);
      c.markPulled(_t(39));
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.skipped);
      expect(pulls, 0);
    });

    test('reset() restarts the cooldown (account switch)', () async {
      now = _t(40);
      c.reset();
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.skipped);
      now = _t(46);
      expect(await c.pullIfDue(workoutInProgress: false), ResumePullOutcome.changed);
    });

    test('a pull that finishes AFTER an account switch is discarded (no UI refresh)', () async {
      now = _t(40);
      late final ResumePullController cc;
      cc = make(pull: () async {
        pulls++;
        cc.reset(); // the account switches while the pull is in flight
        return ResumePullOutcome.changed;
      });
      expect(await cc.pullIfDue(workoutInProgress: false), ResumePullOutcome.skipped);
      expect(pulls, 1, reason: 'the pull ran — its RESULT is what is discarded');
      expect(changes, 0, reason: 'a stale owner\'s data must not refresh the new owner\'s UI');
    });

    test('kill-switch on → never pulls', () async {
      now = _t(40);
      final off = make(disabled: true);
      expect(await off.pullIfDue(workoutInProgress: false), ResumePullOutcome.skipped);
      expect(pulls, 0);
    });

    test('a throwing pull is swallowed and reports failed', () async {
      now = _t(40);
      final bad = make(pull: () async => throw StateError('boom'));
      expect(await bad.pullIfDue(workoutInProgress: false), ResumePullOutcome.failed);
    });
  });

  group('wiring (presence — comment-stripped; behavior is in the controller + behavioral tests)', () {
    String strip(String s) => s
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');
    final svc = strip(File('lib/core/services/sync_service.dart').readAsStringSync());
    final obs = strip(File('lib/core/services/day_rollover_service.dart').readAsStringSync());

    test('DayRolloverObserver calls pullIfDue on resume with the active-workout guard', () {
      expect(obs.contains('ResumePullController.instance.pullIfDue('), isTrue);
      expect(obs.contains('hasInProgressSession'), isTrue);
    });

    test('both cold-restore success returns mark the pull', () {
      expect(
          RegExp(r'markPulled\(\);\s*return RestoreResult\.success\(\);')
              .allMatches(svc)
              .length,
          2,
          reason: 'legacy path + single-call path');
    });

    test('the pull never uses _safeRestoreOp (D6) and never names meals / the schedule overlay (D10/D11)', () {
      final res =
          strip(File('lib/core/services/sync/sync_resilience.dart').readAsStringSync());
      final i = res.indexOf('pullRecentWindow(');
      expect(i, greaterThan(-1));
      final body = res.substring(i);
      expect(body.contains('_safeRestoreOp'), isFalse);
      expect(body.contains('_restoreNutritionLogs'), isFalse);
      expect(body.contains('_restoreScheduledWorkouts'), isFalse);
      for (final w in const [
        '_restoreWorkoutLogs',
        '_restoreExerciseLogs',
        '_restoreScheduleCompletions',
        '_restoreWeightLogs',
        '_restoreWaterLogs',
      ]) {
        expect(body.contains('$w(userId, since)'), isTrue, reason: 'missing $w');
      }
    });

    test('the tick is only bumped once the cold restore has completed (tick > 0)', () {
      final i = svc.indexOf('void _refreshAfterResumePull()');
      expect(i, greaterThan(-1));
      final body = svc.substring(i, i + 400);
      expect(body.contains('restoreCompletedTick.value > 0'), isTrue);
      expect(body.contains('bumpRestoreCompleted()'), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `flutter test test/contracts/resume_pull_controller_test.dart`
Expected: FAIL to compile — `resume_pull_controller.dart` does not exist.

- [ ] **Step 3: Implement the controller**

Create `lib/core/services/resume_pull_controller.dart`:

```dart
/// Pull-on-resume: when the app returns to the foreground, pull a small recent
/// window of the cloud so a device that sat in the background catches up with
/// what another device logged.
///
/// closes-diagnose e5b2a9. Design (docs/superpowers/plans/2026-10-01-
/// resilient-client-phase1.md, D3–D11):
///   * 7-day window through the EXISTING additive / local-wins restore writers
///     — workout logs, exercise logs, schedule completions, weight, water. NOT
///     meals (a local delete never reaches the cloud, so a pull would
///     resurrect them) and NOT the schedule overlay (it can overwrite an
///     unpushed swap). NOT the `restore-user-snapshot` Edge Function.
///   * at most one attempt per [kResumePullCooldown]; the cooldown STARTS at
///     process start (the cold-start restore is about to run), at every
///     attempt (a failed pull is not retried on the next resume) and on an
///     account change. No periodic timer.
///   * refreshes the UI only when the Hive window actually changed.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../utils/ist_date.dart';
import 'hive_service.dart';

const Duration kResumePullCooldown = Duration(minutes: 5);
const int kResumePullWindowDays = 7;

/// What a pull did. `skipped` = gated or discarded (no request was made, or the
/// result belongs to a previous account).
enum ResumePullOutcome { skipped, failed, unchanged, changed }

/// Pure gate — every input explicit so each blocker is testable alone.
bool shouldResumePull({
  required DateTime now,
  required DateTime? lastAttemptAt,
  required bool authenticated,
  required bool workoutInProgress,
  required bool pullInFlight,
  required bool syncPaused,
  Duration cooldown = kResumePullCooldown,
}) {
  if (!authenticated || workoutInProgress || pullInFlight || syncPaused) {
    return false;
  }
  if (lastAttemptAt != null && now.difference(lastAttemptAt) < cooldown) {
    return false;
  }
  return true;
}

/// ISO lower bound for the window: the UTC INSTANT of IST midnight, [days] IST
/// days back (IST has no DST). `created_at >= since` therefore never cuts the
/// first IST day short. (`UTC midnight of the IST date` would be 5h30 LATER than
/// IST midnight and WOULD cut it short.)
String resumePullSince(DateTime now, {int days = kResumePullWindowDays}) {
  final d = istDateStr(now.subtract(Duration(days: days)));
  return DateTime.parse('${d}T00:00:00+05:30').toUtc().toIso8601String();
}

/// The IST dates the window covers, newest first (today + [days] back).
List<String> resumePullDates(DateTime now, {int days = kResumePullWindowDays}) =>
    [for (var i = 0; i <= days; i++) istDateStr(now.subtract(Duration(days: i)))];

/// A string that changes iff any window-day row the pull can write changed.
/// Compared before/after a pull so the UI refreshes only on a REAL change (an
/// unconditional `restoreCompletedTick` bump resets Train's selected week and
/// scrolls the coach screen — see D7).
String resumeWindowSignature(
  List<String> dates,
  Object? Function(String key) readWorkout,
  Object? Function(String key) readHealth,
) {
  final b = StringBuffer();
  for (final d in dates) {
    for (final k in ['wlog_$d', 'schedule_$d', 'exercise_log_index_$d']) {
      b
        ..write(k)
        ..write('=')
        ..write(readWorkout(k))
        ..write(';');
    }
    for (final k in ['weight_$d', 'water_ml_$d', 'urine_color_$d']) {
      b
        ..write(k)
        ..write('=')
        ..write(readHealth(k))
        ..write(';');
    }
  }
  return b.toString();
}

bool _configDisabled() {
  try {
    return HiveService.instance.configBox.get('disable_resume_pull') == true;
  } catch (_) {
    return false;
  }
}

class ResumePullController {
  ResumePullController({
    required Future<ResumePullOutcome> Function() pull,
    void Function()? onChanged,
    DateTime Function()? clock,
    bool Function()? isDisabled,
    bool Function()? isAuthenticated,
    bool Function()? isSyncPaused,
  })  : _pull = pull,
        _onChanged = onChanged,
        _clock = clock ?? DateTime.now,
        _isDisabled = isDisabled ?? _configDisabled,
        _isAuthenticated = isAuthenticated ?? (() => false),
        _isSyncPaused = isSyncPaused ?? (() => false) {
    // D5 — the cold-start restore is about to run: start the cooldown NOW so a
    // resume event at launch does not duplicate it.
    _lastAttemptAt = _clock();
  }

  /// App-wide instance; bound by `SyncService` at construction.
  static final ResumePullController instance = ResumePullController(
    pull: () async => ResumePullOutcome.skipped,
  );

  Future<ResumePullOutcome> Function() _pull;
  void Function()? _onChanged;
  final DateTime Function() _clock;
  final bool Function() _isDisabled;
  bool Function() _isAuthenticated;
  bool Function() _isSyncPaused;

  DateTime? _lastAttemptAt;
  bool _inFlight = false;
  int _epoch = 0;

  void bind({
    required Future<ResumePullOutcome> Function() pull,
    void Function()? onChanged,
    required bool Function() isAuthenticated,
    required bool Function() isSyncPaused,
  }) {
    _pull = pull;
    _onChanged = onChanged;
    _isAuthenticated = isAuthenticated;
    _isSyncPaused = isSyncPaused;
  }

  /// A successful cold-start restore already pulled everything — restart the
  /// cooldown so the first resume right after launch does not pull again.
  void markPulled([DateTime? at]) => _lastAttemptAt = at ?? _clock();

  /// Account switch: restart the cooldown (the new owner's cold restore is next)
  /// and invalidate any pull still in flight for the old owner.
  void reset() {
    _epoch++;
    _lastAttemptAt = _clock();
  }

  Future<ResumePullOutcome> pullIfDue({required bool workoutInProgress}) async {
    if (_isDisabled()) return ResumePullOutcome.skipped;
    final now = _clock();
    if (!shouldResumePull(
      now: now,
      lastAttemptAt: _lastAttemptAt,
      authenticated: _isAuthenticated(),
      workoutInProgress: workoutInProgress,
      pullInFlight: _inFlight,
      syncPaused: _isSyncPaused(),
    )) {
      return ResumePullOutcome.skipped;
    }
    _inFlight = true;
    _lastAttemptAt = now;
    final epoch = _epoch;
    try {
      final outcome = await _pull();
      if (epoch != _epoch) return ResumePullOutcome.skipped;
      if (outcome == ResumePullOutcome.changed) _onChanged?.call();
      return outcome;
    } catch (e) {
      debugPrint('[ResumePullController] pull threw: $e');
      return ResumePullOutcome.failed;
    } finally {
      _inFlight = false;
    }
  }
}
```

- [ ] **Step 4: Add `pullRecentWindow`**

In `lib/core/services/sync/sync_resilience.dart`, inside `extension SyncServiceResilience on SyncService`, after `_probeBackend`:

```dart
  /// Pulls the last [days] days through the EXISTING additive / local-wins
  /// restore writers — wlogs, exlogs (+ sets), completions, weight, water. NOT
  /// meals / schedule (D10/D11).
  ///
  /// Deliberately NOT `_safeRestoreOp` (one `client_errors` row per SUCCESS).
  /// The writers swallow their own errors (report + return), so failure is
  /// detected by `_syncFailureSeq` moving; the first failure — or an owner
  /// change — aborts the rest, so a down server sees one failing request, not
  /// six. Returns `changed` only when the window's Hive rows really changed.
  Future<ResumePullOutcome> pullRecentWindow(
      {int days = kResumePullWindowDays}) async {
    final userId = await _ensureSessionOpen();
    if (userId == null) return ResumePullOutcome.skipped;
    try {
      await _supabase.ensureFreshToken(); // stale web token → silent empty RLS read
    } catch (_) {}
    if (ownerChangedSince(userId)) return ResumePullOutcome.skipped;

    final now = DateTime.now().toUtc();
    final since = resumePullSince(now, days: days);
    final dates = resumePullDates(now, days: days);
    String signature() => resumeWindowSignature(
          dates,
          (k) => _hive.workoutBox.get(k),
          (k) => _hive.healthBox.get(k),
        );
    final before = signature();
    final failuresBefore = _syncFailureSeq;
    bool healthy() =>
        !ownerChangedSince(userId) && _syncFailureSeq == failuresBefore;

    Future<void> step(String label, Future<void> task) async {
      try {
        // Static members must be qualified inside an extension.
        await SyncService.applyRestoreCeiling(task,
            enabled: SyncService._restoreOpTimeoutEnabled);
      } catch (e) {
        // Only the 45 s ceiling lands here; a writer's own failure was already
        // reported by the writer.
        try {
          await _reportSyncFailure(opType: 'resume_pull_$label', error: e);
        } catch (_) {}
      }
    }

    await step('wlogs', _restoreWorkoutLogs(userId, since));
    if (!healthy()) return ResumePullOutcome.failed;
    await step('exlogs', _restoreExerciseLogs(userId, since));
    if (!healthy()) return ResumePullOutcome.failed;
    // Completions stamp status onto existing schedule rows / synthesize a
    // 'logged' row — forward-only, so safe without the schedule overlay.
    await step('completions', _restoreScheduleCompletions(userId, since));
    if (!healthy()) return ResumePullOutcome.failed;
    await step('weight', _restoreWeightLogs(userId, since));
    if (!healthy()) return ResumePullOutcome.failed;
    await step('water', _restoreWaterLogs(userId, since));
    if (!healthy()) return ResumePullOutcome.failed;
    return signature() == before
        ? ResumePullOutcome.unchanged
        : ResumePullOutcome.changed;
  }
```

(`_restoreOpTimeoutEnabled` and `applyRestoreCeiling` are `static` members of `SyncService` — `sync_service.dart:2509` / `:2526` — and this part file is the SAME library, so neither library-privacy nor the `invalid_use_of_visible_for_testing_member` lint applies; `flutter analyze lib/` confirms.)

- [ ] **Step 5: Bind, reset, mark cold-start success, refresh in `sync_service.dart`**

0. Add the import `import 'package:icanbefitter/core/services/resume_pull_controller.dart';` next to the other service imports in `sync_service.dart` (this task creates and uses it).
1. In `_registerLifecycle()`, directly after the `SyncRetryController.instance.bind(...)` call:
```dart
    ResumePullController.instance.bind(
      pull: pullRecentWindow,
      onChanged: _refreshAfterResumePull,
      isAuthenticated: () => _supabase.isAuthenticated,
      isSyncPaused: () => SyncRetryController.instance.paused.value,
    );
```
2. In `_onUserChanged()`, directly after `SyncRetryController.instance.reset();`: `ResumePullController.instance.reset();`
3. Next to `bumpRestoreCompleted()` (`:1766`) add:
```dart
  /// closes-diagnose e5b2a9 — UI refresh after a resume pull that CHANGED the
  /// window. `restoreCompletedTick > 0` is also the "cloud restore has
  /// completed" safety gate for streak decay (`workout_repository.dart:231-247`):
  /// never bump FROM 0 here, or a pull would open that gate without a completed
  /// restore. Side effects of a bump: all four tabs invalidate, Train resets
  /// `selectedWeekProvider`, the coach screen scrolls to the bottom — accepted,
  /// because it only happens when data really changed on another device.
  void _refreshAfterResumePull() {
    if (restoreCompletedTick.value > 0) bumpRestoreCompleted();
  }
```
4. At BOTH real `return RestoreResult.success();` statements (legacy path ending near `path=$restorePath'));` ~`:1963`, single-call path ending near `path=singlecall'));` ~`:2179` — the two in code, not the doc comments) insert directly before each: `ResumePullController.instance.markPulled();`.

- [ ] **Step 6: Call it on resume**

In `lib/core/services/day_rollover_service.dart`, `didChangeAppLifecycleState`, inside `if (state == AppLifecycleState.resumed) {` after `unawaited(SyncService.instance.subscribeToRealtimeSync());`:

```dart
      // closes-diagnose e5b2a9 — pull-on-resume: 7-day window, ≤ 1 attempt per
      // 5 min (cooldown starts at process start), never during an active
      // workout, never while the backend is paused. Fire-and-forget; every
      // failure path inside is non-throwing.
      unawaited(ResumePullController.instance
          .pullIfDue(workoutInProgress: _hasInProgressWorkout()));
```
and add the helper next to the other private members of the observer:
```dart
  bool _hasInProgressWorkout() {
    try {
      return _ref?.read(activeWorkoutProvider).hasInProgressSession ?? false;
    } catch (_) {
      return false; // a disposed ref must not block (or crash) the pull gate
    }
  }
```
and the import `import 'package:icanbefitter/core/services/resume_pull_controller.dart';` next to the other service imports (`activeWorkoutProvider` already imported via `train_provider.dart`, `day_rollover_service.dart:23`).

- [ ] **Step 7: Extend the test helper + public-API snapshot; write the behavioral test**

`test/helpers/sync_stub_server.dart`: add next to `failWritesTo`:
```dart
  /// GETs to these tables answer 503 (a PostgREST outage), so a pull throws.
  final Set<String> failReadsTo = {};
```
and in `_handle`, BEFORE the `else if (r.method == 'GET' && r.table != null)` branch add:
```dart
    } else if (r.method == 'GET' &&
        r.table != null &&
        failReadsTo.contains(r.table)) {
      res
        ..statusCode = 503
        ..write(jsonEncode({'message': 'stub outage', 'code': 'PGRST002'}));
```
(keep the chain's `else if` structure intact; run `flutter test test/sync/sync_stub_server_test.dart` after.)

`test/contracts/sync_service_public_api_snapshot_test.dart`: add `'pullRecentWindow', // e5b2a9 pull-on-resume` to `expectedPublicApi` (`probeBackendReachable` was added in Task 2).

Create `test/sync/resume_pull_window_behavioral_test.dart` (real `SyncService` against the stub server; this is the test that gives `resume_pull_window` its Gate-42 `behavioral_test_path`):

```dart
// test/sync/resume_pull_window_behavioral_test.dart
//
// Behavioral — closes-diagnose e5b2a9 (Unit C). The REAL pullRecentWindow
// against the local PostgREST stub: which tables it reads, that it never writes
// to the cloud, that it is local-wins, that it logs nothing on success, that it
// aborts at the first failure, and that "changed" means the Hive window changed.
@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/resume_pull_controller.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  final events = <String>[]; // every ErrorTelemetry.logEvent op_type

  setUp(() async {
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests =
        (opType, {String? message}) => events.add(opType);
    await h.setUp();
    // The harness's SyncStubServer OBJECT is shared by every test in this file
    // (only its HttpServer is restarted): reset the state that would leak —
    // recorded requests (the table assertions read them), failing tables and
    // canned responders.
    h.server
      ..clear()
      ..failReadsTo.clear()
      ..getResponders.clear();
  });
  tearDown(() async {
    ErrorTelemetry.debugOnLogEventForTests = null;
    await h.tearDown();
  });

  final today = istDateStr(DateTime.now());

  Set<String> readTables() => h.server.requests
      .where((r) => r.method == 'GET' && r.table != null)
      .map((r) => r.table!)
      .toSet();

  void seedCloud() {
    h.server.getResponders['workout_logs'] = (_) => [
          {
            'date': today,
            'workout_name': 'Push Day',
            'logged_at': '${today}T05:00:00Z',
            'created_at': '${today}T05:00:00Z',
            'duration_seconds': 3000,
          }
        ];
    h.server.getResponders['weight_logs'] = (_) => [
          {
            'date': today,
            'weight_kg': 71.5,
            'created_at': '${today}T05:10:00Z',
          }
        ];
    h.server.getResponders['water_logs'] = (_) => [
          {'date': today, 'total_ml': 1500}
        ];
  }

  test('reads exactly the five safe domains — never meals, never the schedule overlay',
      () async {
    seedCloud();
    final out = await SyncService.instance.pullRecentWindow();
    expect(out, ResumePullOutcome.changed);
    expect(readTables(), {
      'workout_logs',
      'workout_log_exercises',
      'workout_log_sets',
      'workout_schedule_completions',
      'weight_logs',
      'water_logs',
    });
    expect(readTables(), isNot(contains('nutrition_logs')),
        reason: 'D10: a pull must not resurrect locally-deleted meals');
    expect(readTables(), isNot(contains('scheduled_workouts')),
        reason: 'D11: the overlay can overwrite an unpushed swap');
  });

  test('every windowed read is bounded by the IST-midnight lower bound', () async {
    seedCloud();
    final lo = resumePullSince(DateTime.now().toUtc());
    await SyncService.instance.pullRecentWindow();
    final hi = resumePullSince(DateTime.now().toUtc());
    for (final r in h.server.requests.where((r) =>
        r.method == 'GET' && r.table != 'water_logs' && r.table != null)) {
      final bound = r.query['created_at'] ?? r.query['completed_at'] ?? '';
      expect(bound.startsWith('gte.'), isTrue, reason: '${r.table}: $bound');
      expect([lo, hi], contains(bound.substring(4)), reason: r.table);
    }
  });

  test('success writes NOTHING to the cloud and logs NOTHING (no client_errors row per success)',
      () async {
    seedCloud();
    await SyncService.instance.pullRecentWindow();
    expect(h.server.requests.where((r) => r.isWrite), isEmpty);
    expect(events, isEmpty,
        reason: 'no per-success logEvent — that is the load Unit E removes '
            '(restore_op_done via _safeRestoreOp would appear here)');
    expect(h.server.requests.where((r) => r.path.contains('log-client-error')),
        isEmpty);
  });

  test('rows land in Hive; an existing local row is NEVER overwritten (local-wins)',
      () async {
    seedCloud();
    await HiveService.instance.healthBox.put('weight_$today', {
      'type': 'weight_log',
      'date': today,
      'weight_kg': 99.9, // the user's own, newer local entry
    });
    await SyncService.instance.pullRecentWindow();
    expect(
        (HiveService.instance.healthBox.get('weight_$today') as Map)['weight_kg'],
        99.9);
    expect(HiveService.instance.healthBox.get('water_ml_$today'), 1500);
    expect(HiveService.instance.workoutBox.get('wlog_$today'), isNotNull);
  });

  test('MIRROR: a second pull over unchanged data reports unchanged (no UI refresh)',
      () async {
    seedCloud();
    expect(await SyncService.instance.pullRecentWindow(), ResumePullOutcome.changed);
    h.server.clear();
    expect(await SyncService.instance.pullRecentWindow(), ResumePullOutcome.unchanged);
  });

  test('the first failing read aborts the pull — a down server sees ONE failing request',
      () async {
    seedCloud();
    h.server.failReadsTo.add('workout_logs');
    final out = await SyncService.instance.pullRecentWindow();
    expect(out, ResumePullOutcome.failed);
    expect(
        h.server.requests
            .where((r) => r.method == 'GET' && r.table == 'workout_logs')
            .length,
        1);
    expect(readTables(), isNot(contains('weight_logs')),
        reason: 'abort at the first failure — no further requests');
  });
}
```

NOTE for the executor: the `GET` filter key for `.gte('created_at', since)` arrives as query param `created_at=gte.<since>` (PostgREST); `workout_log_exercises`/`workout_log_sets`/`workout_schedule_completions` filter on `completed_at`. If the stub's `query` map differs in shape, adjust the lookup — do not weaken the assertion that each windowed read carries a bound equal to `resumePullSince`. If `workout_logs` rows require extra columns for the writer, copy them from `_restoreWorkoutLogs` (`sync_workout.dart:797-840`).

- [ ] **Step 8: Run + analyze + neighbours**

Run: `flutter test test/contracts/resume_pull_controller_test.dart test/sync/resume_pull_window_behavioral_test.dart test/contracts/sync_retry_controller_test.dart test/contracts/sync_service_public_api_snapshot_test.dart test/sync/sync_stub_server_test.dart test/contracts/restore_local_wins_additive_test.dart test/contracts/streak_decay_reckon_permanent_ledger_test.dart test/contracts/day_rollover_provider_invalidation_behavioral_test.dart` → PASS.
Run: `flutter analyze lib/` → no warnings.

- [ ] **Step 9: Mutation proof**

1. `shouldResumePull`: `< cooldown` → `<= cooldown` → boundary test RED; drop the `syncPaused` term → "each blocker alone" RED.
2. `pullIfDue`: delete `_lastAttemptAt = now;` → "every attempt starts the cooldown" RED. Change the ctor's `_lastAttemptAt = _clock();` to nothing → "STARTS AT PROCESS START" RED.
3. `pullIfDue`: delete `if (epoch != _epoch) return …` → "AFTER an account switch" RED.
4. `reset()`: delete `_epoch++;` → same RED.
5. `resumePullSince`: replace the IST parse with `DateTime.parse('${d}T00:00:00Z')` (UTC midnight — the exact wrong-direction bug) → both IST tests RED, **and** "never SHORT" RED.
6. `resumeWindowSignature`: drop the `water_ml_` key → the signature test RED.
7. `pullRecentWindow`: add `await step('nutrition', _restoreNutritionLogs(userId, since));` → behavioral "exactly the five safe domains" RED (this is the proof for D10); same for `_restoreScheduledWorkouts` (D11).
8. `pullRecentWindow`: delete the first `if (!healthy()) return …` → "first failing read aborts" RED.
9. `sync_service.dart`: remove ONE `markPulled()` → wiring (count 2) RED; change `restoreCompletedTick.value > 0` to `true` → wiring RED.
10. `pullRecentWindow`: replace `step('water', …)` with `_safeRestoreOp('water', …)` → the wiring test "never uses _safeRestoreOp" RED. (The behavioral "logs NOTHING" test would NOT catch this: after Unit E a fast `_safeRestoreOp` op logs nothing either — which is exactly why the source-level pin exists. Say so in the diagnose doc.)
Record counts; restore by reverse-edit.

---
