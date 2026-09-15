import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

Directory? _tempDir;

/// Setup for NutritionWriteService unit tests. Mirrors
/// `wws_test_setup.dart` (Plan A) so both suites use identical
/// path_provider mocking + GuardedBox bypass + HiveUserSession init.
Future<void> nwsTestSetup() async {
  _tempDir = await Directory.systemTemp.createTemp('nws_test_');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => _tempDir!.path,
  );

  Hive.init(_tempDir!.path);

  GuardedBox.testBypassOwnership = true;

  await HiveService.instance.init();

  await HiveUserSession.openForUser(
    'test-user-id-12345678-aaaa-bbbb-cccc-dddddddddddd',
  );
}

Future<void> nwsTestTeardown() async {
  GuardedBox.testBypassOwnership = false;
  await HiveUserSession.closeAll();
  await Hive.deleteFromDisk();
  await Hive.close();
  if (_tempDir != null && await _tempDir!.exists()) {
    await _tempDir!.delete(recursive: true);
  }
  _tempDir = null;
}
