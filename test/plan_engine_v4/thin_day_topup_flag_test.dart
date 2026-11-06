// OI-401 kill-switch `disable_thin_day_topup`, default ON.
//
// The FIRST test runs before any Hive.init so the getter's catch branch (no Hive
// -> safe default ON) is what answers; the later tests open a config box. Same
// ordering rule as test/contracts/readiness_flag_no_hive_default_test.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults TRUE when Hive is unavailable (catch branch)', () {
    expect(PlanEngineFlags.thinDayTopupEnabled, isTrue);
  });

  group('with a config box', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_thin_day_flag');
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
      await Hive.openBox(HiveService.configBoxName);
      HiveService.instance.markInitializedForTests();
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      await HiveService.instance.configBox.clear();
    });

    test('unset -> ON', () {
      expect(PlanEngineFlags.thinDayTopupEnabled, isTrue);
    });

    test('disable_thin_day_topup: true -> OFF', () async {
      await HiveService.instance.configBox.put('disable_thin_day_topup', true);
      expect(PlanEngineFlags.thinDayTopupEnabled, isFalse);
    });

    test('disable_thin_day_topup: false -> ON', () async {
      await HiveService.instance.configBox.put('disable_thin_day_topup', false);
      expect(PlanEngineFlags.thinDayTopupEnabled, isTrue);
    });
  });
}
