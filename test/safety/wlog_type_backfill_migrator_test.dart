// Bug f1c8e4 — pins the one-shot wlog `type` backfill migrator.
//
// The pre-fix markCompleted wrote `wlog_<date>` rows WITHOUT
// `type: 'workout_log'` (and with `completed_at_ms` instead of the ISO
// `completed_at`). Every count/history reader filters `type == 'workout_log'`,
// so legacy rows already on-device stay uncounted until repaired. This migrator
// adds `type: 'workout_log'` (+ derives ISO `completed_at` from
// `completed_at_ms`) on every legacy `wlog_*` row, once per device.
//
// closes-diagnose: f1c8e4

import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/wlog_type_backfill_migrator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('repairRow (pure) — f1c8e4', () {
    test('legacy type-less row + completed_at_ms → adds type + ISO completed_at',
        () {
      final ms = DateTime(2026, 6, 9, 19, 30).millisecondsSinceEpoch;
      final row = <String, dynamic>{
        'workout_name': 'Push A',
        'date': '2026-06-09',
        'duration_seconds': 1800,
        'completed_at_ms': ms,
      };
      final changed = WlogTypeBackfillMigrator.repairRow(row);
      expect(changed, isTrue);
      expect(row['type'], 'workout_log');
      expect(row['completed_at'],
          DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String());
    });

    test('already type-tagged + completed_at → no change', () {
      final row = <String, dynamic>{
        'type': 'workout_log',
        'workout_name': 'Pull A',
        'date': '2026-06-09',
        'completed_at': '2026-06-09T19:30:00.000',
        'completed_at_ms': 1,
      };
      expect(WlogTypeBackfillMigrator.repairRow(row), isFalse);
    });

    test('type-less with no completed_at_ms → adds type only', () {
      final row = <String, dynamic>{
        'workout_name': 'Legs',
        'date': '2026-06-09',
      };
      expect(WlogTypeBackfillMigrator.repairRow(row), isTrue);
      expect(row['type'], 'workout_log');
      expect(row.containsKey('completed_at'), isFalse);
    });
  });

  group('runIfNeeded (behavioral heal) — f1c8e4', () {
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('test_wlog_backfill');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      GuardedBox.testBypassOwnership = true;
    });

    tearDownAll(() async {
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    setUp(() async {
      for (final name in [
        HiveService.workoutBoxName,
        HiveService.configBoxName,
        HiveService.migrationBoxName,
        'workoutBox_aaaaaaaa',
      ]) {
        if (Hive.isBoxOpen(name)) await Hive.box(name).close();
        try {
          await Hive.deleteBoxFromDisk(name);
        } catch (_) {}
      }
      await Hive.openBox(HiveService.configBoxName);
      await Hive.openBox(HiveService.migrationBoxName);
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    });

    test('heals a legacy type-less wlog row + is idempotent', () async {
      final wb = HiveService.instance.workoutBox;
      final ms = DateTime(2026, 6, 9, 19, 30).millisecondsSinceEpoch;
      // Legacy shape: exactly what the pre-fix markCompleted wrote.
      await wb.put('wlog_2026-06-09', {
        'workout_name': 'Push A',
        'date': '2026-06-09',
        'duration_seconds': 1800,
        'completed_at_ms': ms,
      });

      final repaired = await WlogTypeBackfillMigrator.runIfNeeded();
      expect(repaired, 1);

      final healed = wb.get('wlog_2026-06-09') as Map;
      expect(healed['type'], 'workout_log',
          reason: 'the legacy row must now carry the type the readers filter on');
      expect(healed['completed_at'],
          DateTime.fromMillisecondsSinceEpoch(ms).toIso8601String());

      // Idempotent — second run repairs nothing (flag set).
      final again = await WlogTypeBackfillMigrator.runIfNeeded();
      expect(again, 0);
    });
  });
}
