import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

final _d = DateTime.utc(2026, 9, 26);
const _k = 'schedule_2026-09-26';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  group('carriesArrangement (pure)', () {
    test('stamps when the old row was arranged and the new entry is not', () {
      expect(
          WorkoutWriteService.carriesArrangement(
              existing: {'arranged_at_ms': 1}, entry: {}, source: WriteSource.planGenerator),
          isTrue);
    });
    test('daySwap and restore never stamp', () {
      for (final s in [WriteSource.daySwap, WriteSource.restore]) {
        expect(
            WorkoutWriteService.carriesArrangement(
                existing: {'arranged_at_ms': 1}, entry: {}, source: s),
            isFalse);
      }
    });
    test('an entry that carries its own stamp is left alone', () {
      expect(
          WorkoutWriteService.carriesArrangement(
              existing: {'arranged_at_ms': 1},
              entry: {'arranged_at_ms': 5},
              source: WriteSource.aiCoach),
          isFalse);
    });
    test('no stamp on the old row → nothing to carry', () {
      expect(
          WorkoutWriteService.carriesArrangement(
              existing: {'status': 'planned'}, entry: {}, source: WriteSource.planGenerator),
          isFalse);
      expect(
          WorkoutWriteService.carriesArrangement(
              existing: null, entry: {}, source: WriteSource.planGenerator),
          isFalse);
    });
  });

  test('a regeneration of a swapped date is itself a newer arrangement (I5 prerequisite)', () async {
    final box = HiveService.instance.workoutBox;
    await box.put(_k, {'workout_name': 'Legs', 'status': 'planned', 'arranged_at_ms': 1000});
    final r = await WorkoutWriteService.instance.upsertScheduled(
      date: _d,
      entry: {'workout_name': 'Legs v2', 'status': 'planned', 'type': 'workout'},
      source: WriteSource.planGenerator,
    );
    expect(r.success, isTrue);
    final row = Map<String, dynamic>.from(box.get(_k) as Map);
    expect(row['arranged_at_ms'], row['updated_at_ms']);
    expect(row['arranged_at_ms'] as int, greaterThan(1000));
  });

  test('restore copies the source row verbatim (no fresh stamp)', () async {
    final box = HiveService.instance.workoutBox;
    await box.put(_k, {'workout_name': 'Legs', 'status': 'planned', 'arranged_at_ms': 1000});
    await WorkoutWriteService.instance.upsertScheduled(
      date: _d,
      entry: {'workout_name': 'Legs', 'status': 'planned'},
      source: WriteSource.restore,
    );
    expect((box.get(_k) as Map).containsKey('arranged_at_ms'), isFalse);
  });
}
