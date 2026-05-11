// C-15 (audit-2026-05-11) — regression test that
// `StreakProgressService` is the sole writer for `streak_freezes_*`
// fields, and that sequential refill ↔ consume operations produce
// deterministic state.
//
// The same-process race is structurally impossible today because
// both `commitRefill` and `commitConsume` are synchronous read-
// modify-write bodies — Dart's single-threaded event loop makes each
// one atomic per tick. The cross-device race (stale snapshot from
// device A overwriting device B's consume) is handled by migration
// 056's `update_streak_progress` RPC.
//
// This test pins:
//   1. The service exists with the documented surface.
//   2. Sequential refill → consume produces the expected state.
//   3. Sole-writer contract — neither workout_repository nor
//      home_provider should write to `streak_freezes_*` keys
//      directly; both must route through the service.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';

import '../helpers/hive_test_setup.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await setUpHiveForTests();
  });

  tearDown(() async {
    await tearDownHiveForTests(tempDir);
  });

  group('C-15 StreakProgressService — sole writer for streak_freezes_*', () {
    test('sequential refill then consume produces deterministic state',
        () async {
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 0,
        'streak_freeze_used_dates': <String>[],
      });

      // Refill first → available=1.
      final afterRefill = StreakProgressService.instance.commitRefill(
        maxFreezes: 3,
        thisMondayStr: '2026-05-11',
      );
      expect(afterRefill, 1);

      // Then consume one for a missed day → available=0.
      final afterConsume = StreakProgressService.instance.commitConsume(
        freezesAvailableAfterConsume: 0,
        usedDatesAfterConsume: const ['2026-05-10'],
      );
      expect(afterConsume, 0);

      final progress = HiveService.instance.userBox.get('progress') as Map;
      expect(progress['streak_freezes_available'], 0);
      expect((progress['streak_freeze_used_dates'] as List).first,
          '2026-05-10');
      expect(progress['streak_freezes_last_refill'], '2026-05-11');
    });

    test('refill clamps at maxFreezes', () async {
      await HiveService.instance.userBox.put('progress', {
        'streak_freezes_available': 3,
        'streak_freeze_used_dates': <String>[],
      });

      // Refill should NOT push above maxFreezes=3.
      final after = StreakProgressService.instance.commitRefill(
        maxFreezes: 3,
        thisMondayStr: '2026-05-11',
      );
      expect(after, 3);
    });

    test(
      'sole-writer contract — workout_repository routes through the service',
      () {
        final src = _src('lib/features/train/repositories/workout_repository.dart');
        expect(
          src.contains('StreakProgressService.instance.commitConsume'),
          isTrue,
          reason: 'workout_repository must commit freeze consumption '
              'via StreakProgressService.commitConsume — the sole writer.',
        );
      },
    );

    test(
      'sole-writer contract — home_provider routes through the service',
      () {
        final src =
            _src('lib/features/home/providers/home_provider.dart');
        expect(
          src.contains('StreakProgressService.instance.commitRefill'),
          isTrue,
          reason: 'home_provider._refillIfNewWeek must commit refill '
              'via StreakProgressService.commitRefill — the sole writer.',
        );
      },
    );

    test(
      'sole-writer contract — only StreakProgressService writes streak_freezes_available',
      () {
        // Source-grep guardrail: no STATE-MUTATION write surface (e.g.
        // `UserRepository.instance.updateProgress({...})` with the
        // key) should mention `streak_freezes_available` outside the
        // service. Reading + restore-path projection are legitimate
        // and explicitly allowlisted.
        const allowlist = <String>{
          // Sole writer.
          'lib/core/services/streak_progress_service.dart',
          // Restore + cloud-sync projection paths (cloud → Hive on
          // restore, Hive → cloud on syncFreezes). These read the
          // current state and reflect it onto the other side; not a
          // state-mutation surface.
          'lib/core/services/sync_service.dart',
          // AI snapshot read — reads the value into the snapshot
          // map (`'streak_freezes_available': _getStreakFreezesAvailable()`).
          // Pattern matches the regex but it's a read-then-emit
          // surface, not a write.
          'lib/features/ai_coach/repositories/ai_coach_repository.dart',
        };
        final root = Directory('lib');
        final offenders = <String>[];
        for (final f in root
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final rel = f.path.replaceAll('\\', '/');
          if (allowlist.any((a) => rel.endsWith(a))) continue;
          final src = f.readAsStringSync();
          // Pattern: `'streak_freezes_available':` inside a Map
          // literal — typically the LHS of a write.
          if (RegExp(r'''['"]streak_freezes_available['"]\s*:''')
              .hasMatch(src)) {
            offenders.add(rel);
          }
        }
        expect(
          offenders,
          isEmpty,
          reason: 'Only StreakProgressService should write '
              'streak_freezes_available (state mutation). Sync/restore '
              'paths and AI snapshot reads are allowlisted. New '
              'offenders:\n${offenders.join("\n")}',
        );
      },
    );
  });
}
