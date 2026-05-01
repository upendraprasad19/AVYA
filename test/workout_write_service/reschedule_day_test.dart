import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import 'helpers/wws_test_setup.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  test('rescheduleDay swaps from→to atomically; original becomes rest',
      () async {
    final friday = DateTime(2026, 5, 1);
    final today = DateTime(2026, 4, 30);

    final box = HiveService.instance.workoutBox;
    await box.put(WorkoutWriteService.scheduleKey(friday), {
      'workout_name': 'Pull Day',
      'status': 'pending',
      'type': 'plan',
    });
    await box.put(WorkoutWriteService.scheduleKey(today), {
      'workout_name': 'Push Day',
      'status': 'pending',
      'type': 'plan',
    });

    final r = await WorkoutWriteService.instance.rescheduleDay(
      fromDate: friday,
      toDate: today,
      source: WriteSource.aiCoach,
    );
    expect(r.success, isTrue);

    final fri = (box.get(WorkoutWriteService.scheduleKey(friday)) as Map)
        .cast<String, dynamic>();
    final tod = (box.get(WorkoutWriteService.scheduleKey(today)) as Map)
        .cast<String, dynamic>();

    expect(tod['workout_name'], 'Pull Day');
    expect(fri['workout_name'], 'Push Day');
    expect(fri['source'], 'ai_coach');
    expect(tod['source'], 'ai_coach');
  });
}
