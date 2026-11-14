// OI-45 (usage-counter-race batch, 2026-07-29) — BEHAVIORAL invariant-pinning
// companion for the source-grep test in `usage_counter_service_mutex_test.dart`.
//
// HONEST INVESTIGATION NOTE (read before assuming this pins a "fixed race"):
// `UsageCounterService.increment` was a bare
// `final current = read(); await write(current + 1)` with no explicit lock.
// The hypothesis was that two same-device callers firing via `Future.wait`
// (not sequentially awaited) could both read the pre-write value before
// either write landed, losing one increment. Tested directly against the
// PRE-fix code (mutex temporarily removed) — **both concurrent increments
// still landed correctly; the pre-fix test did not fail.** Root cause of
// the non-race: `MigratedKey.read` is fully SYNCHRONOUS (no await at all),
// and Hive's `Box.put()` mutates its in-memory keystore SYNCHRONOUSLY before
// its own first internal `await` (the disk flush is what's actually async).
// Since Dart is single-threaded and cooperative, and `increment()`'s only
// `await` comes AFTER its read, nothing can preempt a caller between its
// read and its write's in-memory landing — the same structural-safety class
// already documented in `streak_freeze_refill_race_behavioral_test.dart` for
// a different pair of methods.
//
// This test therefore pins an INVARIANT (concurrent same-key increments must
// never lose an update — true today, and now enforced explicitly by
// `UsageCounterService._withLock` rather than relying on an implicit
// Hive/Dart execution-order coincidence that a future refactor could quietly
// break), not a bug-catch. The mutex is kept as defense-in-depth matching
// this codebase's established convention for shared Hive-backed state
// (`ProfileWriteService`, `WorkoutWriteService`) — see the class's own doc
// comment on `_locks` for the full reasoning.
//
// Round-1 review of this batch raised a SECOND, distinct concern:
// `checkAndResetCounters()` (a second, previously-unlocked writer of the
// same 3 keys, firing on every app-resume per `day_rollover_service.dart`)
// has 4 sequential real-awaiting writes, unlike `increment()`'s
// single-await-after-mutation shape — a plausible mechanism for a genuine
// reset-vs-increment race. Investigated with the same rigor: see the
// "checkAndResetCounters vs increment" group below — for exactly ONE
// resetter vs ONE increment, this did NOT reproduce a corrupted outcome via
// `Future.wait` dispatch (per-key lock kept as defense-in-depth, not a
// confirmed bug fix for THIS specific pairing).
//
// B-pass review then found a THIRD, distinct shape that DOES reproduce: TWO
// independently-dispatched `checkAndResetCounters()` calls (reachable via a
// duplicate `AppLifecycleState.resumed` event — `DayRolloverObserver` has no
// re-entrancy guard) racing ONE `increment()`. See the "double-dispatched
// checkAndResetCounters" group below — this is a GENUINE, reliably
// reproducible lost-update (not a non-race like the others in this file),
// confirmed by reverting the fix and re-running: 20/20 runs lost the
// increment pre-fix, 20/20 preserved it post-fix. Closed by wrapping
// [checkAndResetCounters]'s entire staleness-check-and-reset body in one
// outer lock with the staleness condition re-checked after acquiring it
// (double-checked locking) — see the method's own doc comment for why this
// is a general, timing-independent guarantee, not just an empirical patch.
//
// Scope note: this file covers the LOCAL DISPLAY-counter invariant only. The
// real daily caps are enforced server-side by Postgres triggers (migrations
// 026/113/111/114) regardless of this counter's accuracy — a separate,
// already-live guarantee this test does not (and does not need to) exercise.
//
// Run: flutter test test/contracts/usage_counter_service_race_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('usage_counter_race_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    const fakeUserId = 'facecafe-1111-2222-3333-444444444444';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.userBox.clear();
  });

  group('UsageCounterService.increment — race-surface contract', () {
    test(
        '2 concurrent increment() calls on the SAME feature both land — '
        'no lost update', () async {
      final svc = UsageCounterService.instance;

      // Fire both WITHOUT awaiting either individually first — this is the
      // exact interleaving that loses an update pre-fix: both reads can
      // observe `current=0` before either write lands.
      await Future.wait([
        svc.increment(AppConstants.featureAiTextLogPro, false),
        svc.increment(AppConstants.featureAiTextLogPro, false),
      ]);

      expect(
        svc.used(AppConstants.featureAiTextLogPro, false),
        2,
        reason: 'both concurrent increments must be counted — the mutex '
            'must serialize the read-modify-write, not just the writes.',
      );
    });

    test('5 concurrent increment() calls all land (stress the lock queue)',
        () async {
      final svc = UsageCounterService.instance;

      await Future.wait(List.generate(
        5,
        (_) => svc.increment(AppConstants.featureScanMealPro, true),
      ));

      expect(svc.used(AppConstants.featureScanMealPro, true), 5);
    });

    test(
        'concurrent increments on DIFFERENT features do not block each '
        'other into a shared lost-update', () async {
      final svc = UsageCounterService.instance;

      await Future.wait([
        svc.increment(AppConstants.featureScanMealPro, false),
        svc.increment(AppConstants.featureCartAuditorPro, false),
        svc.increment(AppConstants.featureScanMealPro, false),
        svc.increment(AppConstants.featureCartAuditorPro, false),
      ]);

      expect(svc.used(AppConstants.featureScanMealPro, false), 2);
      expect(svc.used(AppConstants.featureCartAuditorPro, false), 2);
    });
  });

  // Round-1 review raised a theoretical concern (2026-07-29): UNLIKE
  // increment-vs-increment (disproven above), checkAndResetCounters()'s 4
  // sequential `await MigratedKey.write(...)` calls each genuinely yield to
  // the event loop — a plausible mechanism (unlike increment()'s
  // single-await-after-mutation shape) for a reset and an in-flight
  // increment() to interleave and corrupt the final value.
  //
  // Round-2 review sharpened the original version of this test (which
  // asserted `anyOf(0, 1)` on a single call order): with the CODED order
  // `Future.wait([checkAndResetCounters(), increment()])`, the outcome is
  // not merely "not observed to corrupt in N runs" — it is DETERMINISTIC,
  // provably, from Dart's own language semantics, independent of the lock:
  // a list literal `[a(), b()]` calls `a()` then `b()` in that order, and
  // calling an async function runs it SYNCHRONOUSLY up to its first true
  // suspend point. `checkAndResetCounters()`'s reset of THIS key resolves
  // to a `MigratedKey.write` call whose own synchronous prefix (Hive's
  // `Box.put()` landing the new value in its in-memory keystore) completes
  // before `checkAndResetCounters()` hits its first genuine `await`
  // (buried inside `Box.put()`'s own internal disk-flush await) — so by
  // the time `increment()` (the second list element) is even INVOKED, the
  // reset has already landed in memory. `increment()`'s own read is
  // therefore guaranteed to observe the fresh (reset) value, never the
  // stale seed. Reversing the argument order reverses the deterministic
  // outcome (increment's write lands first; the subsequent reset then
  // zeroes it). Both directions verified empirically (20 runs each,
  // 20/20 in both cases) AND by tracing the actual call chain — this is a
  // structural guarantee of Dart's single-threaded, non-preemptive
  // scheduler applied to this synchronous-read/synchronously-landing-write
  // code shape, not a probabilistic "didn't happen in a small sample"
  // result. The two tests below assert the deterministic outcome directly
  // in each order, rather than a permissive `anyOf` that would silently
  // keep passing if a future change flipped which order is deterministic.
  // The lock is kept as defense-in-depth against a shape this dispatch
  // pattern doesn't reach (e.g. a future refactor adding a genuine `await`
  // before a read, or independently-scheduled callers whose synchronous
  // prefixes could someday stop being atomic) — not because either order
  // is actually racy today; neither is.
  group('checkAndResetCounters vs increment — deterministic-order contract',
      () {
    test(
        '[checkAndResetCounters, increment] (coded order): reset always '
        'lands first, increment always reads the fresh value', () async {
      final svc = UsageCounterService.instance;
      const key = 'ai_text_log_count_today';

      // Seed: yesterday's stale last-reset stamp + a nonzero stale count,
      // forcing checkAndResetCounters() down its reset branch.
      await MigratedKey.write('last_daily_reset', '2020-01-01');
      await MigratedKey.write(key, 5);

      await Future.wait([
        svc.checkAndResetCounters(),
        svc.increment(AppConstants.featureAiTextLogPro, false),
      ]);

      expect(
        svc.used(AppConstants.featureAiTextLogPro, false),
        1,
        reason: 'checkAndResetCounters() is list element 0 — its reset of '
            'this key synchronously lands in Hive\'s in-memory keystore '
            'before increment() (element 1) is even invoked, so increment '
            'always reads the fresh post-reset value (0) and writes 1. '
            'Verified deterministic across 20 runs, not merely "usually".',
      );
    });

    test(
        '[increment, checkAndResetCounters] (reversed order): increment '
        'always lands first, the reset always zeroes it after', () async {
      final svc = UsageCounterService.instance;
      const key = 'ai_text_log_count_today';

      await MigratedKey.write('last_daily_reset', '2020-01-01');
      await MigratedKey.write(key, 5);

      await Future.wait([
        svc.increment(AppConstants.featureAiTextLogPro, false),
        svc.checkAndResetCounters(),
      ]);

      expect(
        svc.used(AppConstants.featureAiTextLogPro, false),
        0,
        reason: 'increment() is list element 0 here — its stale-seed read '
            '(5) and write (6) land before checkAndResetCounters() '
            '(element 1) is invoked, and the reset then unconditionally '
            'zeroes the key. Confirms the ordering is fully determined by '
            'list-literal evaluation order, not scheduler luck: reversing '
            'the arguments reverses the outcome, 20/20 both directions.',
      );
    });
  });

  // B-pass finding (usage-counter-race batch, 2026-07-30): DayRolloverObserver
  // has no re-entrancy guard, and its staleness gate (`last_known_date`) is
  // only written well after checkAndResetCounters() returns — a duplicate
  // `resumed` lifecycle event before the first rollover completes dispatches
  // a SECOND, independent checkAndResetCounters() call. Unlike the single
  // resetter-vs-increment groups above (deterministically safe), THIS shape
  // is a genuine, reliably reproducible lost-update: verified by reverting
  // checkAndResetCounters()'s outer lock and re-running — 20/20 runs lost the
  // increment, vs 20/20 preserved it with the outer lock restored. Not flaky:
  // the outcome is fully determined by list-evaluation order + Completer
  // FIFO wake order, same class of determinism as the groups above, just
  // requiring 3 concurrent operations (2 resetters + 1 increment) instead of
  // 2 to surface. The fix (double-checked locking — see
  // [UsageCounterService.checkAndResetCounters]'s own doc comment) makes the
  // staleness READ itself require holding the outer lock, so a second
  // resetter can never observe stale state once any resetter has started —
  // a general, timing-independent guarantee, not merely "didn't reproduce in
  // N runs" like the other findings in this file.
  group('double-dispatched checkAndResetCounters — genuine lost-update, '
      'closed by the outer lock', () {
    test(
        '[reset A, increment, reset B]: the redundant second resetter must '
        'not clobber the interposed increment', () async {
      final svc = UsageCounterService.instance;
      const key = 'ai_text_log_count_today';

      await MigratedKey.write('last_daily_reset', '2020-01-01');
      await MigratedKey.write(key, 5);

      await Future.wait([
        svc.checkAndResetCounters(),
        svc.increment(AppConstants.featureAiTextLogPro, false),
        svc.checkAndResetCounters(),
      ]);

      expect(
        svc.used(AppConstants.featureAiTextLogPro, false),
        1,
        reason: 'PRE-FIX this was 0, 20/20 runs: the first resetter zeroes '
            'the key and releases; increment() reads the fresh 0 and writes '
            '1; but the SECOND resetter had already (wrongly) decided a '
            'reset was needed from its own earlier stale read, and its '
            'unconditional write(0) — issued with no re-check — clobbers '
            'the increment back to 0 on its way through the same key\'s '
            'lock queue. POST-FIX the second resetter blocks on the outer '
            '__daily_reset__ lock for its ENTIRE body (including the '
            'staleness read itself), so by the time it can read '
            'last_daily_reset it always observes the first resetter\'s '
            'already-fresh write and no-ops before touching any per-key '
            'lock at all.',
      );
    });

    test('2 resetters + 1 increment, resetters listed first: still safe',
        () async {
      final svc = UsageCounterService.instance;
      const key = 'ai_text_log_count_today';

      await MigratedKey.write('last_daily_reset', '2020-01-01');
      await MigratedKey.write(key, 5);

      await Future.wait([
        svc.checkAndResetCounters(),
        svc.checkAndResetCounters(),
        svc.increment(AppConstants.featureAiTextLogPro, false),
      ]);

      expect(svc.used(AppConstants.featureAiTextLogPro, false), 1,
          reason: 'sanity check on a second list ordering — this one was '
              'already safe even pre-fix (the redundant resetter loses the '
              'lock-requeue race to the increment in this ordering), kept '
              'here so a future refactor that changes the lock-acquire '
              'order can\'t silently regress it without a test noticing.');
    });

    test('3 concurrent resetters + 1 increment all still land correctly',
        () async {
      final svc = UsageCounterService.instance;
      const key = 'ai_text_log_count_today';

      await MigratedKey.write('last_daily_reset', '2020-01-01');
      await MigratedKey.write(key, 5);

      await Future.wait([
        svc.checkAndResetCounters(),
        svc.checkAndResetCounters(),
        svc.checkAndResetCounters(),
        svc.increment(AppConstants.featureAiTextLogPro, false),
      ]);

      expect(svc.used(AppConstants.featureAiTextLogPro, false), 1,
          reason: 'stress case — the outer lock guarantee does not depend '
              'on there being exactly 2 resetters; any number queue on the '
              'same outer lock and every one after the first sees fresh '
              'state.');
    });
  });
}
