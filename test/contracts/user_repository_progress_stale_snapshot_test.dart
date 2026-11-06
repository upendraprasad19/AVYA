// OI-45 finding 2 / Unit 3a (progress-map-consolidation, 2026-07-30) —
// BEHAVIORAL contract for UserRepository's progress-map handling.
//
// HONEST INVESTIGATION NOTE (read before trusting any test below as a "bug
// catch" — same discipline as the usage-counter-race batch): a
// Completer-based mutex (mirroring ProfileWriteService._withLock) was
// BUILT, tested, and REMOVED from UserRepository before this file reached
// its current shape. Two things were found by testing, not assumed: (1) it
// provided NO correctness benefit — the "concurrent dispatch" group below
// still passes identically with or without it, same structural-safety
// class as UsageCounterService.increment() (Hive's Box.put() lands its
// in-memory mutation synchronously, and Future.wait([a(), b()]) runs a() to
// its own first suspend point before b() is even invoked); (2) it actively
// BROKE 2 pre-existing tests in streak_decay_reckon_permanent_ledger_test.
// dart, by serializing what were previously two independently-landing
// UNAWAITED fire-and-forget calls (StreakProgressService.commitConsume and
// WorkoutRepository._persistCurrentStreakDays both fire un-awaited
// updateProgress calls within one reckonStreakDecayAndPersist() flow) into
// a genuine queue — the second call now had to suspend waiting for the
// first to release the lock, a real timing change existing tests didn't
// expect. No proven benefit, one concrete regression — removed. See
// UserRepository.saveProgress's doc comment for the full account.
//
// The GENUINE, confirmed bug is a different mechanism, covered in the
// second group below: pro_phase_advance.dart and simulation_service.dart
// read `progress`, then awaited something REAL and slow (actual plan
// generation), then wrote the WHOLE map back from that pre-await snapshot
// via saveProgress. Any writer landing during that real await window was
// silently clobbered on the next whole-map save. The "OLD pattern" test
// reproduces this data loss directly (using UserRepository's own
// primitives to recreate the exact shape); the "NEW pattern" test proves
// the fix — converting both callers to updateProgress(delta) — survives
// the identical scenario, because updateProgress calls getProgress() fresh
// every time it runs, not because of any lock.
//
// Run: flutter test test/contracts/user_repository_progress_stale_snapshot_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
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
    tempDir = Directory.systemTemp.createTempSync('progress_stale_snapshot_');
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
    const fakeUserId = 'facecafe-5555-6666-7777-888888888888';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.userBox.clear();
  });

  group('UserRepository.updateProgress — concurrent dispatch (invariant, '
      'not a lock-dependent guarantee)', () {
    test(
        '2 concurrent updateProgress() calls with DIFFERENT fields both '
        'land — no lost update', () async {
      final repo = UserRepository.instance;

      // Fired via Future.wait, not sequentially awaited.
      await Future.wait([
        repo.updateProgress({'total_workouts_done': 3}),
        repo.updateProgress({'current_streak_weeks': 2}),
      ]);

      final result = repo.getProgress()!;
      expect(result['total_workouts_done'], 3,
          reason: 'both concurrent merges must survive. This holds because '
              'Hive\'s synchronous Box.put() + Future.wait list-order '
              'determinism already make it safe — no lock involved.');
      expect(result['current_streak_weeks'], 2);
    });

    test('5 concurrent updateProgress() calls all land (stress test)',
        () async {
      final repo = UserRepository.instance;

      await Future.wait(List.generate(
        5,
        (i) => repo.updateProgress({'field_$i': i}),
      ));

      final result = repo.getProgress()!;
      for (var i = 0; i < 5; i++) {
        expect(result['field_$i'], i, reason: 'field_$i must survive the stress');
      }
    });

    test(
        'saveProgress() and updateProgress() land deterministically under '
        'concurrent dispatch — including saveProgress\'s REPLACE semantics '
        'dropping a field updateProgress just set',
        () async {
      final repo = UserRepository.instance;
      await repo.saveProgress({'current_phase': 1});

      await Future.wait([
        repo.updateProgress({'total_workouts_done': 9}),
        repo.saveProgress({'current_phase': 1, 'current_week': 4}),
      ]);

      // Whichever ran second (list order) is the current whole-map state;
      // the assertion that matters is that this is deterministic, not
      // corrupted/partial.
      final result = repo.getProgress()!;
      expect(result['current_phase'], 1);
      expect(result['current_week'], 4,
          reason: 'saveProgress, dispatched second in the list, must fully '
              'land after updateProgress — deterministically, not corrupted.');
      // B-pass finding (progress-map-consolidation batch, 2026-07-30):
      // this test's name previously implied a general "neither call
      // corrupts the other" guarantee, but only ever asserted 2 of the 3
      // fields actually in play. Empirically checked (temporarily, then
      // reverted) what happens to the field this test's OWN updateProgress
      // call set: it comes back null. That is saveProgress's documented
      // REPLACE (not merge) contract doing exactly what it's supposed to —
      // dispatched second in the list, it fully overwrites the map with
      // its own 2 literal keys, dropping whatever updateProgress (dispatched
      // first) had merged in. Asserted explicitly here so the test is
      // honest about what it does and doesn't guarantee, rather than a
      // future reader assuming "do not corrupt" covers this field too.
      expect(result['total_workouts_done'], isNull,
          reason: 'NOT a bug this test is pinning as fixed — the opposite: '
              'this documents saveProgress\'s real, intentional REPLACE '
              'contract. A caller that races a raw saveProgress(fullMap) '
              'against a concurrent updateProgress(delta) WILL lose the '
              'delta if saveProgress lands second — see the warning on '
              'UserRepository.saveProgress\'s doc comment. Not exploitable '
              'in shipped code today: the only 2 real saveProgress callers '
              '(simulation_service.dart\'s dev-only resetJourney, '
              'onboarding_provider.dart\'s first-ever write to a brand-new '
              'account) never run concurrently with an updateProgress call '
              'on the same user session.');
    });
  });

  group('OI-45 finding 2 — the GENUINE bug: a stale snapshot across a REAL '
      'async gap, not a Future.wait race', () {
    test(
        'OLD pattern (documents the bug): saveProgress(snapshot read before '
        'a real await) silently loses a write that landed during that gap',
        () async {
      // Directly recreates what pro_phase_advance.dart / simulation_service.
      // dart did BEFORE Unit 3a — this is not testing current production
      // code (both call sites were fixed), it is proving the bug pattern
      // itself was real, using UserRepository's own primitives. Guards
      // against any future code reintroducing this exact anti-pattern.
      final repo = UserRepository.instance;
      await repo.saveProgress({'current_phase': 1, 'total_workouts_done': 0});

      final staleSnapshot = repo.getProgress()!;
      // Stands in for autoGenerateNextPhaseIfNeeded — a genuinely slow,
      // real async gap, not an artificial Future.wait pairing.
      await Future.delayed(const Duration(milliseconds: 20));
      // An independent writer lands and FULLY COMPLETES during that gap.
      await repo.updateProgress({'total_workouts_done': 7});

      // The OLD pattern: build the update from the STALE snapshot, save
      // the whole map back.
      final updated = Map<String, dynamic>.from(staleSnapshot);
      updated['current_phase'] = 2;
      await repo.saveProgress(updated);

      final result = repo.getProgress()!;
      expect(result['total_workouts_done'], 0,
          reason: 'THIS ASSERTS THE BUG: the interposed write (7) is lost, '
              'silently reset back to the pre-gap snapshot value (0) — proof '
              'the old whole-map-save-of-a-stale-snapshot pattern was a '
              'genuine, reproducible lost-update, not a theoretical concern.');
    });

    test(
        'NEW pattern (proves the fix): updateProgress(delta) survives the '
        'identical real async gap — the pro_phase_advance.dart / '
        'simulation_service.dart fix shape',
        () async {
      final repo = UserRepository.instance;
      await repo.saveProgress({'current_phase': 1, 'total_workouts_done': 0});

      final snapshot = repo.getProgress()!;
      final currentPhase = snapshot['current_phase'] as int;
      await Future.delayed(const Duration(milliseconds: 20));
      await repo.updateProgress({'total_workouts_done': 7});

      // The NEW pattern: pass ONLY the delta. updateProgress re-reads
      // getProgress() fresh internally, so it merges onto whatever is
      // ACTUALLY in Hive right now, not the pre-gap snapshot.
      await repo.updateProgress({'current_phase': currentPhase + 1});

      final result = repo.getProgress()!;
      expect(result['total_workouts_done'], 7,
          reason: 'must survive — this is the actual fix. The fix is WHERE '
              'the fresh read happens (inside updateProgress, at call '
              'time), not lock-dependent — there is no lock in production.');
      expect(result['current_phase'], 2);
    });
  });
}
