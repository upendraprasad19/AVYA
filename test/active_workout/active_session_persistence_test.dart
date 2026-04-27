import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/train/services/active_workout_persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_a7_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveService.instance.workoutBox.clear();
  });

  group('ActiveWorkoutPersistence', () {
    test('write + read roundtrip returns same fields', () async {
      await ActiveWorkoutPersistence.writeState(
        exerciseName: 'Bench Press',
        currentSet: 3,
        totalSets: 4,
        weight: 60.0,
        repsTarget: 8,
        repsCompleted: 8,
        rpeHistory: [7.0, 7.5, 8.0],
        restRemainingSecs: 145,
      );
      final state = ActiveWorkoutPersistence.readState();
      expect(state, isNotNull);
      expect(state!['exercise'], 'Bench Press');
      expect(state['current_set'], 3);
      expect(state['total_sets'], 4);
      expect(state['weight'], 60.0);
      expect(state['reps_target'], 8);
      expect(state['reps_completed'], 8);
      expect(state['rpe_history'], [7.0, 7.5, 8.0]);
      expect(state['rest_remaining_secs'], 145);
      expect(state['updated_at'], isA<String>());
    });

    test('clearState removes the key', () async {
      await ActiveWorkoutPersistence.writeState(
        exerciseName: 'Bench Press',
        currentSet: 1, totalSets: 4, weight: 60, repsTarget: 8, repsCompleted: 8,
        rpeHistory: [], restRemainingSecs: null,
      );
      expect(ActiveWorkoutPersistence.readState(), isNotNull);
      await ActiveWorkoutPersistence.clearState();
      expect(ActiveWorkoutPersistence.readState(), isNull);
    });

    test('readState returns null and clears stale (>2h) entries', () async {
      // Write a state with updated_at = 3 hours ago
      final threeHoursAgo = DateTime.now().subtract(const Duration(hours: 3));
      await HiveService.instance.workoutBox.put('active_session', {
        'exercise': 'Squat',
        'current_set': 1, 'total_sets': 4,
        'weight': 100, 'reps_target': 5, 'reps_completed': 5,
        'rpe_history': [], 'rest_remaining_secs': 60,
        'updated_at': threeHoursAgo.toIso8601String(),
      });
      // Read should return null AND auto-clear
      expect(ActiveWorkoutPersistence.readState(), isNull);
      // Confirm cleared
      expect(HiveService.instance.workoutBox.get('active_session'), isNull);
    });

    test('readState returns null when no state exists', () async {
      expect(ActiveWorkoutPersistence.readState(), isNull);
    });

    test('readState returns null on malformed (non-Map) entry', () async {
      await HiveService.instance.workoutBox.put('active_session', 'not a map');
      expect(ActiveWorkoutPersistence.readState(), isNull);
    });
  });
}
