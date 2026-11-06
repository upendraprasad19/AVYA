import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

/// Fixed test user-id used by all unit-test setUp paths.
const kTestUserId = '5f0a13b2-aaaa-bbbb-cccc-dddddddddddd';

/// Shared boxes (always opened — never user-scoped). Mirrors
/// `HiveService._sharedBoxNames` (hive_service.dart:53-59): exerciseBox,
/// foodBox, syncBox, configBox, migrationBox. `migrationBox` was missing
/// here (day-swapper + sync-load batch, Task 31) — every test that opens a
/// user session via [setUpHiveForTests] triggered `HiveUserSession`'s
/// `migrationBox` read (hive_user_session.dart:328-340), which fell into
/// its `catch (e)` and logged `debugPrint('[HiveUserSession] migrationBox
/// unavailable: $e')` as unrelated non-fatal noise on every run.
const _sharedBoxes = ['exerciseBox', 'foodBox', 'syncBox', 'configBox', 'migrationBox'];

/// Set up a Hive temp dir + path_provider mock + open shared boxes +
/// open user-scoped boxes for [kTestUserId] via HiveUserSession +
/// flip [GuardedBox.testBypassOwnership] true (Supabase isn't init
/// in unit tests so the in-real-life session check would crash).
///
/// Returns the temp dir handle so [tearDownHiveForTests] can clean up.
Future<Directory> setUpHiveForTests({String userId = kTestUserId}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  final tempDir = await Directory.systemTemp.createTemp('avya_test_');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async => tempDir.path,
  );
  Hive.init(tempDir.path);
  for (final name in _sharedBoxes) {
    await Hive.openBox(name);
  }
  // Mark HiveService initialized BEFORE opening the user session: opening a
  // session makes HiveUserSession internally read HiveService.instance
  // .migrationBox / .configBox (hive_user_session.dart:328-340, :388-390) —
  // HiveService.getBox() throws `StateError('HiveService.init() must be
  // called before accessing boxes.')` while _initialized is still false, so
  // calling this AFTER openForUser (the original order) meant every session
  // open hit that catch and logged "[HiveUserSession] migrationBox
  // unavailable: ..." regardless of whether the box itself was open.
  HiveService.debugMarkInitializedForTests();
  await HiveUserSession.openForUser(userId);
  GuardedBox.testBypassOwnership = true;
  return tempDir;
}

/// Tear down: reset bypass flag + close session + close Hive + delete temp dir.
Future<void> tearDownHiveForTests(Directory tempDir) async {
  GuardedBox.testBypassOwnership = false;
  await HiveUserSession.closeAll();
  await Hive.close();
  if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
}
