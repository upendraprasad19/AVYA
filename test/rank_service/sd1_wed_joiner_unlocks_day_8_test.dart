import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = await Directory.systemTemp.createTemp('sd1_wed_test_');
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    await HiveService.instance.init();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('SD1 Wed joiner with 6/week plan', () {
    test('unlocks SD1 on Wed of week 2 (8 cal days = 7 workouts)', () async {
      final svc = RankService.instance;
      // 7 consecutive completed workouts + Sun rest invisibly skipped
      // + 8 calendar days >= 7 (the spec week threshold satisfied).
      final qualified = svc.testQualify(
        code: 'SD1',
        streak: 7,
        weeksSinceSignup: 1,
      );
      expect(qualified, isTrue);
    });

    test('does NOT unlock SD1 with 6 streak even at 7 days', () async {
      final svc = RankService.instance;
      final qualified = svc.testQualify(
        code: 'SD1',
        streak: 6,
        weeksSinceSignup: 1,
      );
      expect(qualified, isFalse);
    });

    test('does NOT unlock SD1 with 7 streak but <1 week elapsed', () async {
      final svc = RankService.instance;
      final qualified = svc.testQualify(
        code: 'SD1',
        streak: 7,
        weeksSinceSignup: 0,
      );
      expect(qualified, isFalse);
    });
  });
}
