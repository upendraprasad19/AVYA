import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

Directory? _tempDir;

Future<void> wwsTestSetup() async {
  _tempDir = await Directory.systemTemp.createTemp('wws_test_');

  // Mock path_provider so Hive.initFlutter-equivalent calls resolve
  // in pure-unit-test mode.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => _tempDir!.path,
  );

  Hive.init(_tempDir!.path);

  // HiveService.instance.init() registers adapters + opens shared
  // boxes. Must be called before HiveUserSession.openForUser so the
  // user-scoped boxes pick up the same adapter registry.
  await HiveService.instance.init();

  // Test user — full UUID (HiveUserSession derives 8-hex hash).
  await HiveUserSession.openForUser(
    'test-user-id-12345678-aaaa-bbbb-cccc-dddddddddddd',
  );
}

Future<void> wwsTestTeardown() async {
  await Hive.deleteFromDisk();
  await Hive.close();
  if (_tempDir != null && await _tempDir!.exists()) {
    await _tempDir!.delete(recursive: true);
  }
  _tempDir = null;
}
