import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';

/// Coach memory backfill tests.
///
/// Plan A (APK Test #5) introduced per-user Hive box namespacing
/// (`coachBox_<8hex>`) + GuardedBox ownership assertions. These tests
/// were originally written against pre-namespacing shared boxes; the
/// setUp below now drives the namespaced path via HiveUserSession +
/// `GuardedBox.testBypassOwnership` to skip the Supabase session check
/// (Supabase isn't initialised in unit tests).
const _testUserId = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';
const _sharedBoxes = [
  'exerciseBox',
  'foodBox',
  'syncBox',
  'configBox',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_coach_memory_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    for (final name in _sharedBoxes) {
      await Hive.openBox(name);
    }
    await HiveUserSession.openForUser(_testUserId);
    GuardedBox.testBypassOwnership = true;
    HiveService.debugMarkInitializedForTests();
  });

  tearDown(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('backfill copies legacy coaching_notes into coach_memory.coach_notes', () async {
    final box = HiveService.instance.coachBox;
    await box.put('coaching_notes', {
      'notes': ['Mentioned shoulder pain', 'Wants to lose weight'],
      'last_extracted': '2026-04-15T22:00:00Z',
    });
    await HiveService.instance.userBox.put('user_id', 'u1');

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();

    final mem = CoachMemory.readFromBox(box);
    expect(mem, isNotNull);
    expect(mem!.coachNotes, contains('shoulder'));
    expect(mem.coachNotes, contains('lose weight'));
  });

  test('backfill is idempotent — second call is a no-op', () async {
    final box = HiveService.instance.coachBox;
    await box.put('coaching_notes', {'notes': ['a']});
    await HiveService.instance.userBox.put('user_id', 'u1');

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
    final box = HiveService.instance.coachBox;
    await CoachMemory(userId: 'u1', preferredName: 'Upen').writeToBox(box);
    await box.put('coaching_notes', {'notes': ['should be ignored']});

    await AiCoachRepository.instance.backfillCoachMemoryIfNeeded();

    expect(CoachMemory.readFromBox(box)!.preferredName, 'Upen');
    expect(CoachMemory.readFromBox(box)!.coachNotes, isNull);
  });

  test('buildAiContext includes coach_memory when present in Hive', () async {
    await HiveService.instance.userBox.put('user_id', 'u1');
    await CoachMemory(
      userId: 'u1',
      preferredName: 'Upen',
      communicationStyle: 'hinglish',
      dropoutRiskScore: 0.6,
    ).writeToBox(HiveService.instance.coachBox);

    final ctx = AiCoachRepository.instance.buildAiContext();
    expect(ctx['coach_memory'], isNotNull);
    expect(ctx['coach_memory']['preferred_name'], equals('Upen'));
    expect(ctx['coach_memory']['communication_style'], equals('hinglish'));
  });

  test('buildAiContext omits coach_memory when private_mode is true', () async {
    await HiveService.instance.userBox.put('user_id', 'u1');
    await CoachMemory(userId: 'u1', preferredName: 'Upen', privateMode: true)
        .writeToBox(HiveService.instance.coachBox);

    final ctx = AiCoachRepository.instance.buildAiContext();
    expect(ctx['coach_memory'], isNull);
  });
}
