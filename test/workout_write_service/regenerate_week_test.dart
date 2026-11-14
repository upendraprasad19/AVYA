import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('regenerateWeek replaces 7 schedule entries from fromDate forward',
      () async {
    final mon = DateTime(2026, 5, 4);
    final box = HiveService.instance.workoutBox;

    // Seed an old plan (incomplete)
    for (var i = 0; i < 7; i++) {
      final d = mon.add(Duration(days: i));
      await box.put(WorkoutWriteService.scheduleKey(d), {
        'workout_name': 'OLD Plan Day ${i + 1}',
        'status': 'pending',
        'type': 'plan',
      });
    }

    final r = await WorkoutWriteService.instance.regenerateWeek(
      fromDate: mon,
      params: {
        'days_per_week': 6,
        'goal': 'build_muscle',
        'experience': 'intermediate',
        'equipment': 'basic_gym',
        'workouts': List.generate(
          7,
          (i) => {
            'workout_name': i == 6 ? 'Rest' : 'NEW Plan Day ${i + 1}',
            'status': i == 6 ? 'rest' : 'pending',
            'type': 'plan',
          },
        ),
      },
      source: WriteSource.editSheet,
    );
    expect(r.success, isTrue);

    for (var i = 0; i < 7; i++) {
      final d = mon.add(Duration(days: i));
      final entry = (box.get(WorkoutWriteService.scheduleKey(d)) as Map)
          .cast<String, dynamic>();
      expect(entry['workout_name'],
          i == 6 ? 'Rest' : 'NEW Plan Day ${i + 1}');
      expect(entry['source'], 'edit_sheet');
    }
  });
}
