// `exercisePrSeriesProvider` follows the PR list (plan
// docs/plans/pr-strength-charts.md, 5.3): it is derived from
// `allExercisePRsProvider`, so every site that refreshes the PR list refreshes
// the charts, and a signed-out session reads no box.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/home/providers/pr_series_provider.dart';

import '../sync/sync_domain_skip_harness.dart';

Future<void> _putBench(String day, double kg) =>
    HiveService.instance.workoutBox.put('exlog_${day}_bench', {
      'exercise_name': 'Bench Press', 'date': day,
      'logging_type': 'weight_reps', 'weight_kg': kg,
      'sets': [
        {'weight_kg': kg, 'reps': 5},
      ],
    });

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.clear();
  });
  tearDown(() => h.tearDown());

  test('the series is rebuilt when the PR list is invalidated', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);

    expect(c.read(exercisePrSeriesProvider), isEmpty, reason: 'no logs yet');

    await _putBench('2026-10-12', 60);
    await _putBench('2026-10-14', 65);
    expect(c.read(exercisePrSeriesProvider), isEmpty,
        reason: 'a raw Hive write rebuilds nothing by itself');

    c.invalidate(allExercisePRsProvider);
    final pts = c.read(exercisePrSeriesProvider)['bench press']!.points;
    expect([for (final p in pts) '${p.date}=${p.value}'],
        ['2026-10-12=60.0', '2026-10-14=65.0']);
  });

  test('a signed-out session gets an empty map', () async {
    await _putBench('2026-10-12', 60);
    final c = ProviderContainer(overrides: [
      authUserIdTokenProvider.overrideWithValue('<anon>'),
    ]);
    addTearDown(c.dispose);
    expect(c.read(allExercisePRsProvider), isEmpty);
    expect(c.read(exercisePrSeriesProvider), isEmpty);
  });
}
