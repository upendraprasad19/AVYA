import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_b4_');
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
    await HiveService.instance.userBox.clear();
    await HiveService.instance.workoutBox.clear();
  });

  group('B4: rank ETA non-negative', () {
    test('daysUntilNextRank is always non-negative', () {
      final days = RankService.instance.daysUntilNextRank();
      expect(days, greaterThanOrEqualTo(0),
          reason: 'B4 fix: ETA must never be negative');
      expect(days, lessThanOrEqualTo(365),
          reason: 'B4 fix: ETA clamped to 365 max');
    });

    test('getNextRank daysUntilEligible is always non-negative when not null', () {
      final next = RankService.instance.getNextRank();
      if (next?.daysUntilEligible != null) {
        expect(next!.daysUntilEligible!, greaterThanOrEqualTo(0),
            reason: 'B4: daysUntilEligible from getNextRank must be non-negative');
        expect(next.daysUntilEligible!, lessThanOrEqualTo(365),
            reason: 'B4: daysUntilEligible from getNextRank must be <= 365');
      }
    });
  });
}
