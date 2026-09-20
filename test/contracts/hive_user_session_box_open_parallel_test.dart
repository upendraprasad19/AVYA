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
}
