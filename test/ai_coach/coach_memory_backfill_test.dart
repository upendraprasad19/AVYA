import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  // Boxes touched (directly or transitively) by buildAiContext():
  // coachBox + userBox (this file), plus workoutBox / nutritionBox /
  // healthBox / configBox (via UserRepository, WorkoutRepository,
  // NutritionRepository, HiveService getters that gate on _initialized).
  const boxes = [
    'coachBox',
    'userBox',
    'workoutBox',
    'nutritionBox',
    'healthBox',
    'exerciseBox',
    'foodBox',
    'customBox',
    'syncBox',
    'configBox',
  ];

  setUp(() async {
    Hive.init('./.test_hive');
    for (final name in boxes) {
      await Hive.openBox(name);
    }
    // HiveService gates box getters on _initialized; flip it for tests
    // that exercise buildAiContext (which reads through HiveService).
    HiveService.debugMarkInitializedForTests();
  });

  tearDown(() async {
    for (final name in boxes) {
      await Hive.deleteBoxFromDisk(name);
    }
  });

  test('backfill copies legacy coaching_notes into coach_memory.coach_notes', () async {
    final box = Hive.box('coachBox');
    await box.put('coaching_notes', {
      'notes': ['Mentioned shoulder pain', 'Wants to lose weight'],
      'last_extracted': '2026-04-15T22:00:00Z',
    });
    Hive.box('userBox').put('user_id', 'u1');

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();

    final mem = CoachMemory.readFromBox(box);
    expect(mem, isNotNull);
    expect(mem!.coachNotes, contains('shoulder'));
    expect(mem.coachNotes, contains('lose weight'));
  });

  test('backfill is idempotent — second call is a no-op', () async {
    final box = Hive.box('coachBox');
    await box.put('coaching_notes', {'notes': ['a']});
    Hive.box('userBox').put('user_id', 'u1');

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();
    final firstUpdated =
        CoachMemory.readFromBox(box)?.updatedAt ?? DateTime(2000);

    await Future.delayed(const Duration(milliseconds: 10));
    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();
    final secondUpdated =
        CoachMemory.readFromBox(box)?.updatedAt ?? DateTime(2000);

    expect(secondUpdated, equals(firstUpdated));
  });

  test('backfill no-ops when coach_memory already exists', () async {
    final box = Hive.box('coachBox');
    await CoachMemory(userId: 'u1', preferredName: 'Upen').writeToBox(box);
    await box.put('coaching_notes', {'notes': ['should be ignored']});

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();

    expect(CoachMemory.readFromBox(box)!.preferredName, 'Upen');
    expect(CoachMemory.readFromBox(box)!.coachNotes, isNull);
  });

  test('buildAiContext includes coach_memory when present in Hive', () async {
    Hive.box('userBox').put('user_id', 'u1');
    await CoachMemory(
      userId: 'u1',
      preferredName: 'Upen',
      communicationStyle: 'hinglish',
      dropoutRiskScore: 0.6,
    ).writeToBox(Hive.box('coachBox'));

    final ctx = AiCoachRepository.instance.buildAiContext();
    expect(ctx['coach_memory'], isNotNull);
    expect(ctx['coach_memory']['preferred_name'], equals('Upen'));
    expect(ctx['coach_memory']['communication_style'], equals('hinglish'));
  });

  test('buildAiContext omits coach_memory when private_mode is true', () async {
    Hive.box('userBox').put('user_id', 'u1');
    await CoachMemory(userId: 'u1', preferredName: 'Upen', privateMode: true)
        .writeToBox(Hive.box('coachBox'));

    final ctx = AiCoachRepository.instance.buildAiContext();
    expect(ctx['coach_memory'], isNull);
  });
}
