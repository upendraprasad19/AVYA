import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

void main() {
  setUp(() async {
    Hive.init('./.test_hive');
    await Hive.openBox('coachBox');
    await Hive.openBox('userBox');
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk('coachBox');
    await Hive.deleteBoxFromDisk('userBox');
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
}
