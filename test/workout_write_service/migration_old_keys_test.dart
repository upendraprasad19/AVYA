import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('two old timestamp-keyed exlogs same date+exercise -> 1 merged entry',
      () async {
    final box = HiveService.instance.workoutBox;
    final config = HiveService.instance.configBox;

    // Seed two legacy entries with different timestamps but same
    // date + exercise — exactly the #16 bug.
    await box.put('exlog_1714560000000_${'Lat Pulldown'.hashCode}', {
      'exercise_name': 'Lat Pulldown',
      'date': '2026-05-01',
      'sets': [
        {'weight_kg': 40, 'reps': 10, 'logged_at_ms': 1714560000000},
        {'weight_kg': 60, 'reps': 10, 'logged_at_ms': 1714560090000},
      ],
      'set_number': 2,
      'reps_completed': 20,
      'weight_kg': 60,
      'volume_kg': 1000,
      'updated_at_ms': 1714560090000,
    });
    await box.put('exlog_1714560200000_${'Lat Pulldown'.hashCode}', {
      'exercise_name': 'Lat Pulldown',
      'date': '2026-05-01',
      'sets': [
        {'weight_kg': 80, 'reps': 10, 'logged_at_ms': 1714560200000},
        {'weight_kg': 100, 'reps': 7, 'logged_at_ms': 1714560290000},
      ],
      'set_number': 2,
      'reps_completed': 17,
      'weight_kg': 100,
      'volume_kg': 1500,
      'updated_at_ms': 1714560290000,
    });

    expect(
      box.keys.where((k) => k.toString().startsWith('exlog_')).length,
      2,
    );
    expect(config.get('exlog_key_migration_v6'), isNot(true));

    await ExlogKeyMigrator.runIfNeeded();

    // After migration: 1 entry under deterministic key with merged sets
    final exlogKeys =
        box.keys.where((k) => k.toString().startsWith('exlog_')).toList();
    expect(exlogKeys.length, 1);
    final newKey =
        WorkoutWriteService.exlogKey(DateTime(2026, 5, 1), 'Lat Pulldown');
    expect(exlogKeys.first, newKey);

    final m = (box.get(newKey) as Map).cast<String, dynamic>();
    expect(m['set_number'], 4);
    expect(m['reps_completed'], 37);
    expect(m['weight_kg'], 100);
    expect((m['volume_kg'] as num).toInt(), 2500);

    // Idempotent
    await ExlogKeyMigrator.runIfNeeded();
    expect(
      box.keys.where((k) => k.toString().startsWith('exlog_')).length,
      1,
    );
  });
}
