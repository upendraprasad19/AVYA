// Diagnose c2f7d1: the PR list follows a completed restore.
//
// A restore writes `exlog_*` rows into Hive. `AllExercisePRsNotifier` read the
// box once per build and nothing rebuilt it after a restore (Home's
// `invalidateOnRetry` never listed it), so a returning user kept an empty PR
// card until a workout was logged or the day rolled over. The notifier now
// watches `restoreCompletedTickProvider`, the tick the post-restore heal bumps
// LAST (class 9c8958 / b3c9d4, harness of streak_chip_restore_tick).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/home/providers/pr_series_provider.dart';

import '../sync/sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.clear();
  });
  tearDown(() => h.tearDown());

  test('rows a restore wrote reach the PR list and the charts on the tick', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(c.read(allExercisePRsProvider), isEmpty, reason: 'built before the restore');
    final tick0 = c.read(restoreCompletedTickProvider);

    // What `_restoreExerciseLogs` leaves behind.
    await HiveService.instance.workoutBox.put('exlog_2026-10-12_squat', {
      'exercise_name': 'Squat', 'date': '2026-10-12', 'type': 'exercise_log',
      'logging_type': 'weight_reps', 'weight_kg': 100.0, 'set_number': 3,
    });
    await HiveService.instance.workoutBox.put('exlog_2026-10-15_squat', {
      'exercise_name': 'Squat', 'date': '2026-10-15', 'type': 'exercise_log',
      'logging_type': 'weight_reps', 'weight_kg': 105.0, 'set_number': 3,
    });
    expect(c.read(allExercisePRsProvider), isEmpty,
        reason: 'no tick yet: the notifier reads Hive once per build');

    SyncService.instance.bumpRestoreCompleted(); // the LAST step of the post-restore heal
    expect(c.read(restoreCompletedTickProvider), isNot(tick0),
        reason: 'the tick provider is live here (not its no-SyncService fallback)');

    final prs = c.read(allExercisePRsProvider);
    expect(prs.single.exerciseName, 'Squat');
    expect(prs.single.bestValue, 105.0);
    expect(c.read(exercisePrSeriesProvider)['squat']!.points.length, 2);
  });
}
