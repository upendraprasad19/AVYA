import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/features/ai_coach/services/induction_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_b5_');
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
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.userBox.clear();
  });

  test('all 5 muster answers persist to coachBox', () async {
    await InductionService.instance
        .recordMusterAnswer('why_now', 'wedding October');
    await InductionService.instance
        .recordMusterAnswer('definition_of_winning', 'feel strong');
    await InductionService.instance
        .recordMusterAnswer('known_injuries', ['lower back', 'right knee']);
    await InductionService.instance
        .recordMusterAnswer('typical_wake_time', '06:30');
    await InductionService.instance
        .recordMusterAnswer('preferred_workout_time', '07:00');
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', ['back', 'shoulders']);

    expect(
        HiveService.instance.coachBox.get('why_now'), 'wedding October');
    expect(HiveService.instance.coachBox.get('definition_of_winning'),
        'feel strong');
    expect(HiveService.instance.coachBox.get('known_injuries'),
        ['lower back', 'right knee']);
    expect(HiveService.instance.coachBox.get('typical_wake_time'), '06:30');
    expect(
        HiveService.instance.coachBox.get('preferred_workout_time'), '07:00');
    expect(HiveService.instance.coachBox.get('body_part_priorities'),
        ['back', 'shoulders']);
  });

  test('completeMuster sets induction_completed_at', () async {
    await InductionService.instance.recordCommitment();
    await InductionService.instance.completeMuster();
    expect(
        HiveService.instance.coachBox.get('induction_completed_at'),
        isA<String>());
    expect(InductionService.instance.inductionCompleted, true);
  });

  test('unknown muster key throws ArgumentError', () async {
    expect(
      () => InductionService.instance.recordMusterAnswer('bad_key', 'value'),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('Q3 NONE/SKIP stores [none]', () async {
    // Simulates the skip path in _onSubmitQ3(skipped: true)
    await InductionService.instance
        .recordMusterAnswer('known_injuries', ['none']);
    expect(
        HiveService.instance.coachBox.get('known_injuries'), ['none']);
  });

  test('Q5 None chip stores empty list', () async {
    // When user selects 'None' chip, body_part_priorities stores []
    await InductionService.instance
        .recordMusterAnswer('body_part_priorities', <String>[]);
    expect(
        HiveService.instance.coachBox.get('body_part_priorities'),
        isEmpty);
  });
}
