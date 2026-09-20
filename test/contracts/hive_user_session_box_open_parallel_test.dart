import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this._tmp);
  final String _tmp;
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;
  @override
  Future<String?> getTemporaryPath() async => _tmp;
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('hive_user_session_parallel_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    // Open all shared boxes required by HiveService
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  tearDown(() async {
    // Clean up boxes after each test
    await HiveUserSession.closeAll();
  });

  test('user-scoped boxes open concurrently, not sequentially', () async {
    final stopwatch = Stopwatch()..start();
    await HiveUserSession.openForUser('test-user-parallel');
    stopwatch.stop();
    // With 7 boxes opening in parallel on a fast test-disk temp dir, this
    // should complete in roughly the time of ONE box open, not seven.
    // A regression to the sequential form would show as this test's
    // wall-clock time scaling with box COUNT if boxes were made
    // artificially slow to open (out of scope to fake here) — so this
    // test's primary value is the source-shape assertion below, backed
    // by this timing assertion as a secondary signal.
    expect(stopwatch.elapsedMilliseconds, lessThan(2000));
  });

  test('openForUser source uses Future.wait for the box-open loop', () {
    final src =
        File('lib/core/services/hive_user_session.dart').readAsStringSync();
    // Look for the pattern where the loop opens boxes
    expect(src, contains('await Future.wait(userScopedBoxRoots.map('),
        reason:
            'obs 4 — the 7 user-scoped boxes must open in parallel, mirroring hive_service.dart:77-82');
  });

  test(
      'disable_parallel_hive_box_open restores the sequential fallback and '
      'still opens every box (B-pass finding, 2026-09-20 — §4.6 feature-flag '
      'protocol for a platform-tier path)', () async {
    HiveService.instance.configBox.put('disable_parallel_hive_box_open', true);
    addTearDown(() =>
        HiveService.instance.configBox.delete('disable_parallel_hive_box_open'));

    await HiveUserSession.openForUser('test-user-sequential-fallback');

    for (final root in [
      HiveService.userBoxName,
      HiveService.workoutBoxName,
      HiveService.nutritionBoxName,
      HiveService.healthBoxName,
      HiveService.coachBoxName,
      HiveService.customBoxName,
      HiveService.notificationsBoxName,
    ]) {
      final boxName = HiveUserSession.namespacedBoxName(
          root, 'test-user-sequential-fallback');
      expect(Hive.isBoxOpen(boxName), isTrue,
          reason: 'the sequential fallback must open every user-scoped box, '
              'not silently skip the ones a parallel Future.wait would have '
              'caught in the same pass');
    }
  });

  test('openForUser source guards the parallel path behind '
      'disable_parallel_hive_box_open', () {
    final src =
        File('lib/core/services/hive_user_session.dart').readAsStringSync();
    // Whitespace-collapsed so a reformatted line break (e.g. the
    // defensive try/catch wrap added for diagnose f4c8b1's regression)
    // can't silently defeat this source-shape check.
    final collapsed = src.replaceAll(RegExp(r'\s+'), ' ');
    expect(
        collapsed,
        contains(
            "configBox .get('disable_parallel_hive_box_open')".replaceAll(
                RegExp(r'\s+'), ' ')),
        reason: 'platform-tier paths require a feature-flag guard (§4.6); '
            'the parallel box-open must remain reversible to the verbatim '
            'pre-Obs-4 sequential loop without a code change');
  });

  test('openForUser falls through to the parallel path when configBox '
      'is unavailable, rather than crashing session open', () async {
    // Reproduces diagnose f4c8b1's root cause directly: a shared box the
    // flag-read depends on can be missing (test-harness singleton reuse,
    // or a genuinely early cold start) without that being a session-open
    // failure. Close the shared configBox out from under the read.
    if (Hive.isBoxOpen(HiveService.configBoxName)) {
      await Hive.box(HiveService.configBoxName).close();
    }
    try {
      await expectLater(
        HiveUserSession.openForUser('test-user-configbox-unavailable'),
        completes,
      );
      final boxName = HiveUserSession.namespacedBoxName(
          HiveService.userBoxName, 'test-user-configbox-unavailable');
      expect(Hive.isBoxOpen(boxName), isTrue,
          reason: 'a configBox read failure must not prevent the '
              'user-scoped boxes from opening');
    } finally {
      // Restore shared state for any test appended after this one.
      if (!Hive.isBoxOpen(HiveService.configBoxName)) {
        await Hive.openBox(HiveService.configBoxName);
      }
    }
  });
}
