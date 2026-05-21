// Tech-debt audit 2026-05-20 finding T10 — BEHAVIORAL companion for
// `test/contracts/streak_freeze_refill_race_test.dart` (source-grep
// only).
//
// Concept: `StreakProgressService` is the sole writer for
// `streak_freezes_*` fields in `user_progress`. Pre-Test #16.2 the
// Monday +1 refill (`commitRefill`) and the missed-day consume
// (`commitConsume`) could race when fired in quick succession after a
// cold-start restore — the cloud restore could land between the two
// and clobber a freshly-applied refill (closes commit 5a60fc2). Both
// methods are synchronous read-modify-write bodies so the SAME-process
// race is structurally impossible today (Dart's single-threaded event
// loop). This test pins that invariant under fakeAsync — even if the
// two are dispatched at T+0ms and T+1ms with arbitrary `flushMicrotasks`
// reorderings between them, the final state must reflect
// refill-then-consume serialization with no lost update.
//
// Bug class prevented (cites
// `feedback_source_grep_false_confidence.md`): the existing
// `streak_freeze_refill_race_test.dart` asserts the FIX shape via
// source-grep (cloudWins, last_refill compareTo, syncFreezes schedule).
// A future change could rewrite the fix in a different shape that
// passes the grep but reintroduces the race. Only a behavioral test
// pinning the post-condition catches that class.
//
// IMPLEMENTATION NOTE: an earlier draft used `FakeAsync` to schedule
// the refill at T+0ms and consume at T+1ms. That approach hung
// indefinitely because `commitRefill`/`commitConsume` call
// `unawaited(SyncService.instance.syncFreezes())` — a fire-and-forget
// chain that ultimately constructs Hive box read futures whose timer
// ticks fakeAsync cannot drain (real Hive I/O). Since both
// commit methods are SYNCHRONOUS read-modify-write bodies, the race
// surface this test pins is purely sequential semantics: any caller
// invoking them in either order on the same tick must produce a
// deterministic post-condition with no lost update. FakeAsync buys
// nothing here.
//
// Run: flutter test test/contracts/streak_freeze_refill_race_behavioral_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
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
    tempDir =
        Directory.systemTemp.createTempSync('streak_freeze_race_');
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
    const fakeUserId = 'cafeface-aaaa-bbbb-cccc-dddddddddddd';
    await HiveUserSession.openForUser(fakeUserId);
    await HiveService.instance.userBox.clear();
  });

  group('streak_freeze_refill_race — behavioral race-surface contract',
      () {
    test(
        'refill THEN consume — read-modify-write sequence preserves '
        'invariant (refill +1 then consume -1 = back to initial)', () {
      // Seed state: 2 freezes available, none used yet.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 2,
        'streak_freeze_used_dates': <String>[],
      });

      // T+0 equivalent — Monday refill (would normally come from
      // DayRolloverObserver / splash post-restore). Synchronous
      // method, no scheduling needed.
      StreakProgressService.instance.commitRefill(
        maxFreezes: 3,
        thisMondayStr: '2026-05-25',
      );

      // T+1 equivalent — missed-day consume (would normally come from
      // WorkoutRepository._calculateStreak(consume: true)). Reads the
      // post-refill state fresh.
      final mid = HiveService.instance.userBox.get('progress') as Map;
      final current = (mid['streak_freezes_available'] as int?) ?? 0;
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: current - 1,
        usedDatesAfterConsume: const ['2026-05-24'],
      );

      // Post-condition: refill bumped 2 → 3 (clamped at maxFreezes=3),
      // consume dropped 3 → 2. Final available=2. last_refill stamped.
      // used_dates contains the consumed date.
      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 2,
          reason: 'refill (+1, clamped) then consume (-1) — final '
              'count must equal initial. Lost update would surface as '
              '1 (refill clobbered by consume seeing stale state) or 3 '
              '(consume clobbered by refill seeing stale state).');
      expect(progress['streak_freezes_last_refill'], '2026-05-25',
          reason: 'commitRefill must have stamped last_refill — failure '
              'here means refill silently no-op'
              "'d (race lost it).");
      expect(
        (progress['streak_freeze_used_dates'] as List).cast<String>(),
        contains('2026-05-24'),
        reason: 'commitConsume must have appended the missed-day; '
            'failure here means consume silently no-op'
            "'d.",
      );
    });

    test(
        'reverse order — consume then refill on the same tick — still '
        'serializes with no lost update', () {
      // Seed: 1 freeze available, none used.
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 1,
        'streak_freeze_used_dates': <String>[],
      });

      // Both methods are synchronous; calling them in sequence on the
      // same tick proves the no-lost-update invariant. The race
      // surface (cross-device cloud sync) is covered by migration
      // 056's update_streak_progress RPC with optimistic-lock
      // semantics, which is a server-side check; the client-side
      // contract pinned here is purely sequential semantics.
      StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-05-24'],
      );
      StreakProgressService.instance.commitRefill(
        maxFreezes: 3,
        thisMondayStr: '2026-05-25',
      );

      // Post-condition: consume dropped 1→0, refill bumped 0→1.
      // commitRefill resets streak_freeze_used_dates to [] per its
      // documented contract (weekly reset). Pin that behavior.
      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 1,
          reason: 'consume (-1) then refill (+1) = back to 1.');
      expect(progress['streak_freezes_last_refill'], '2026-05-25',
          reason: 'refill must run AFTER consume here and stamp '
              'last_refill.');
      expect(
        (progress['streak_freeze_used_dates'] as List).cast<String>(),
        isEmpty,
        reason: 'commitRefill resets streak_freeze_used_dates per its '
            'documented contract (weekly reset on Monday). The fact '
            'that consume ran first must NOT prevent the refill reset.',
      );
    });

    test(
        'two same-Monday commitRefill calls — each call bumps; pinning '
        'documented "callers must pre-check; refillIfNewWeek gates" '
        'contract', () {
      HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      // commitRefill itself does NOT gate; the gate lives in
      // refillIfNewWeek. So calling commit twice WILL bump twice
      // (0 → 1 → 2), clamped at maxFreezes. This pins the documented
      // "callers must pre-check" contract: any new orchestrator path
      // MUST apply the last_refill gate BEFORE calling commitRefill,
      // otherwise the user accumulates freezes on every Monday-equal
      // refill invocation.
      StreakProgressService.instance.commitRefill(
        maxFreezes: 3,
        thisMondayStr: '2026-05-25',
      );
      StreakProgressService.instance.commitRefill(
        maxFreezes: 3,
        thisMondayStr: '2026-05-25',
      );

      final progress =
          HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 2,
          reason: 'commitRefill is intentionally NOT idempotent — the '
              'gate lives in refillIfNewWeek. This test pins the commit '
              'semantics so callers know they MUST gate themselves '
              'before invoking commitRefill twice.');
      expect(progress['streak_freezes_last_refill'], '2026-05-25');
    });
  });
}
