import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('avya_test_a3_');
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
    await HiveService.instance.nutritionBox.clear();
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.syncBox.clear();
    await HiveService.instance.configBox.clear();
    await HiveService.instance.customBox.clear();
    await HiveService.instance.notificationsBox.clear();
  });

  group('cross-account isolation (B1)', () {
    test('clearAllData clears all non-seed boxes including notificationsBox', () async {
      await HiveService.instance.userBox.put('profile', {'id': 'A', 'name': 'Alice'});
      await HiveService.instance.workoutBox.put('wlog_1', {'workout': 'PUSH A'});
      await HiveService.instance.notificationsBox.put('notif_1', {'title': 'Test'});
      await HiveService.instance.coachBox.put('committed_at', '2026-01-01');
      await HiveService.instance.syncBox.put(HiveService.lastAuthenticatedUserIdKey, 'A');

      await UserRepository.instance.clearAllData();

      expect(HiveService.instance.userBox.get('profile'), isNull);
      expect(HiveService.instance.workoutBox.get('wlog_1'), isNull);
      expect(HiveService.instance.notificationsBox.get('notif_1'), isNull,
          reason: 'B1 fix: notificationsBox MUST be in clearAllData');
      expect(HiveService.instance.coachBox.get('committed_at'), isNull);
      expect(HiveService.instance.syncBox.get(HiveService.lastAuthenticatedUserIdKey), isNull);
    });

    test('lastAuthenticatedUserIdKey constant value locked', () {
      expect(HiveService.lastAuthenticatedUserIdKey, 'last_authenticated_user_id');
    });

    test('lastAuthenticatedUserIdKey can be written and read from syncBox', () async {
      await HiveService.instance.syncBox.put(HiveService.lastAuthenticatedUserIdKey, 'user-id-123');
      final read = HiveService.instance.syncBox.get(HiveService.lastAuthenticatedUserIdKey);
      expect(read, 'user-id-123');
    });
  });
}
