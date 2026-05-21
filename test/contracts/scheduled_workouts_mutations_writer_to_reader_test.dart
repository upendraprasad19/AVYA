import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

/// Source-of-truth contract: writer/reader pairs for `scheduled_workouts_mutations`
/// from docs/sot_registry.yaml.
///
/// Writer: lib/core/services/workout_schedule_service.dart
/// Readers: home_provider (todayWorkoutProvider), train_provider (currentPlanProvider)
///
/// Forbidden pattern: never write schedule_ keys directly from a widget.
/// Completed status is write-once and guarded by WorkoutScheduleService.
void main() {
  late String schedSrc;
  late String homeSrc;
  late String trainSrc;

  setUpAll(() {
    final sf = File('lib/core/services/workout_schedule_service.dart');
    expect(sf.existsSync(), isTrue,
        reason:
            'workout_schedule_service.dart must exist (writer for scheduled_workouts_mutations)');
    schedSrc = sf.readAsStringSync();

    final hf = File('lib/features/home/providers/home_provider.dart');
    expect(hf.existsSync(), isTrue, reason: 'home_provider.dart must exist');
    homeSrc = hf.readAsStringSync();

    final tf = File('lib/features/train/providers/train_provider.dart');
    expect(tf.existsSync(), isTrue, reason: 'train_provider.dart must exist');
    trainSrc = tf.readAsStringSync();
  });

  group('scheduled_workouts_mutations writer↔reader source contract', () {
    test('writer WorkoutScheduleService exists with schedule_ key writes', () {
      expect(schedSrc.contains('WorkoutScheduleService'), isTrue,
          reason: 'writer class WorkoutScheduleService must be present');
      expect(schedSrc.contains("'schedule_"), isTrue,
          reason: 'writer must reference the schedule_ key prefix');
    });

    test('status=completed is guarded (write-once)', () {
      // The service reads status to guard completed entries (e.g. `if (map['status'] == 'completed') continue`)
      expect(schedSrc.contains("status"), isTrue,
          reason: 'writer must reference status field for write-once guard');
      expect(schedSrc.contains("'completed'"), isTrue,
          reason: "writer must reference 'completed' status value for guard checks");
    });

    test('reader todayWorkoutProvider exists in home_provider', () {
      expect(homeSrc.contains('todayWorkoutProvider'), isTrue,
          reason:
              'home_provider must define todayWorkoutProvider (reader for scheduled_workouts_mutations)');
    });

    test('reader currentPlanProvider exists in train_provider', () {
      expect(trainSrc.contains('currentPlanProvider'), isTrue,
          reason:
              'train_provider must define currentPlanProvider (reader for scheduled_workouts_mutations)');
    });

    test('readers reference schedule_ key prefix', () {
      final refsInHome = homeSrc.contains("'schedule_") ||
          homeSrc.contains('"schedule_') ||
          homeSrc.contains('schedule_');
      final refsInTrain = trainSrc.contains("'schedule_") ||
          trainSrc.contains('"schedule_') ||
          trainSrc.contains('schedule_');
      expect(refsInHome || refsInTrain, isTrue,
          reason: 'at least one reader must reference the schedule_ key prefix');
    });

    test('forbidden: no widget writes schedule_ keys directly', () {
      // Widgets must NOT write schedule_ keys — only WorkoutScheduleService
      // Source-grep: check that the only file writing 'workoutBox.put(\'schedule_' is the service itself
      // Post-C4 split: train_screen.dart was replaced by a folder of part
      // files (lib/features/train/screens/train/*); read via helper.
      final widgetSources = <String, String>{
        'home_screen.dart':
            File('lib/features/home/screens/home_screen.dart').readAsStringSync(),
        'train screen folder': readScreenSource('train'),
      };
      for (final entry in widgetSources.entries) {
        final src = entry.value;
        expect(src.contains("workoutBox.put('schedule_"), isFalse,
            reason:
                '${entry.key} must not write schedule_ keys directly; use WorkoutScheduleService');
        expect(src.contains('.put(\'schedule_'), isFalse,
            reason:
                '${entry.key} must route schedule writes through WorkoutScheduleService');
      }
    });

    test('IST date key formula: scheduleKey uses istDateStr', () {
      expect(schedSrc.contains('istDateStr'), isTrue,
          reason:
              'workout_schedule_service must use istDateStr for IST-anchored schedule_ keys');
    });
  });
}
