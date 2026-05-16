import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for Hive key agreements.
///
/// These tests scan the actual source code to verify that all WRITERS and
/// READERS of Hive keys use the same key formats. If someone changes a key
/// pattern in one file but not another, these tests break immediately.
///
/// **WHY:** Bugs #4, #6, #7, #8 in the 2026-04-07 audit were all caused
/// by writers and readers using different Hive key formats. These tests
/// prevent that class of bug from ever recurring.
void main() {
  final libDir = Directory('lib');

  /// Recursively reads all `.dart` files under [dir] and returns their
  /// contents as a map of {relativePath: source}.
  Map<String, String> readAllDartFiles(Directory dir) {
    final files = <String, String>{};
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        files[entity.path] = entity.readAsStringSync();
      }
    }
    return files;
  }

  late Map<String, String> allSources;

  setUpAll(() {
    expect(libDir.existsSync(), isTrue, reason: 'Run from project root');
    allSources = readAllDartFiles(libDir);
  });

  /// refactor/sync-service-part-split (2026-05-13) — SyncService is now
  /// split across `sync_service.dart` plus N part files under
  /// `lib/core/services/sync/`. Helper returns the concatenated source so
  /// contract `expect(syncSource, contains(...))` checks still find strings
  /// that may have moved into a part file.
  String syncServiceUnion() {
    final root = allSources.entries
        .firstWhere(
          (e) => e.key.endsWith('sync_service.dart') &&
              !e.key.contains('health_sync'),
        )
        .value;
    final parts = allSources.entries
        .where((e) =>
            e.key.replaceAll(r'\', '/').contains('/core/services/sync/'))
        .map((e) => e.value)
        .toList();
    return [root, ...parts].join('\n\n');
  }

  // ── Weight Keys ────────────────────────────────────────────────

  group('Contract: weight key format', () {
    test('all weight writers use "weight_\$dateStr" key prefix', () {
      // audit-2026-05-16 E.7 — `HealthWriteService.logWeight` is the
      // canonical writer; it builds `final key = 'weight_$dateStr';`
      // then calls `box.put(key, payload)`. The literal
      // `healthBox.put('weight_` shape no longer appears at any callsite.
      // Pin the routing through the canonical WriteService instead.
      bool foundWeightWriter = false;
      for (final entry in allSources.entries) {
        final source = entry.value;
        // Canonical post-E.7: HealthWriteService.logWeight callsite OR
        // the WriteService body containing the `'weight_$dateStr'` key.
        if (source.contains('HealthWriteService.instance.logWeight') ||
            RegExp(r"'weight_\$dateStr'").hasMatch(source) ||
            RegExp(r"healthBox\.put\('weight_").hasMatch(source)) {
          foundWeightWriter = true;
          break;
        }
      }
      expect(foundWeightWriter, isTrue,
          reason: 'Must have at least one weight writer — either '
              'HealthWriteService.logWeight callsite or the WriteService '
              'body using `weight_\$dateStr` key.');

      // Verify no writer uses the OLD list-based key 'weight_logs'
      for (final entry in allSources.entries) {
        final source = entry.value;
        final hasOldPut = source.contains("healthBox.put('weight_logs'");
        expect(hasOldPut, isFalse,
            reason:
                '${entry.key}: Uses stale "weight_logs" list key. Must use per-day "weight_\$dateStr" keys.');
      }
    });

    test('sync reader scans weight_* prefix (not list key)', () {
      final syncSource = syncServiceUnion();

      // Must iterate keys with startsWith('weight_')
      expect(syncSource, contains("startsWith('weight_')"),
          reason:
              'sync_service._syncWeightLogs must iterate per-day weight_* keys');

      // Must NOT read a single 'weight_logs' list
      expect(syncSource.contains("healthBox.get('weight_logs')"), isFalse,
          reason:
              'sync_service must not read stale "weight_logs" list key');
    });

    test('health_sync_service weight writer uses weight_\$dateStr', () {
      final healthSyncSource = allSources.entries
          .firstWhere((e) => e.key.contains('health_sync_service.dart'))
          .value;

      // HealthSyncService builds the key as a variable: weightKey = 'weight_$todayStr'
      // then calls hive.healthBox.put(weightKey, {...})
      expect(
          healthSyncSource.contains("'weight_\$todayStr'") ||
              healthSyncSource.contains("healthBox.put('weight_"),
          isTrue,
          reason:
              'HealthSyncService must write weight data with weight_\$dateStr key');
    });
  });

  // ── Water Keys ─────────────────────────────────────────────────

  group('Contract: water key format', () {
    test('water writer uses "water_ml_\$todayStr" key', () {
      final nutritionProviderSource = allSources.entries
          .firstWhere((e) => e.key.contains('nutrition_provider.dart'))
          .value;

      expect(nutritionProviderSource, contains("'water_ml_\$todayStr'"),
          reason: 'WaterIntakeNotifier must write with water_ml_ prefix');
    });

    test('AI context reader uses "water_ml_\$todayStr" key', () {
      final aiRepoSource = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_repository.dart'))
          .value;

      expect(aiRepoSource, contains("'water_ml_\$todayStr'"),
          reason: 'AI context must read with water_ml_ prefix');

      // Must NOT use the old wrong key 'water_$todayStr' (without 'ml_')
      // Check for the exact wrong pattern: 'water_$ (not followed by 'ml')
      // i.e. healthBox.get('water_$todayStr') — missing the 'ml_' part
      final wrongPattern = RegExp(r"'water_\$(?!ml)");
      expect(wrongPattern.hasMatch(aiRepoSource), isFalse,
          reason:
              'AI context must NOT use "water_\$todayStr" — must be "water_ml_\$todayStr"');
    });

    test('AI context reader handles int water value (not just Map)', () {
      final aiRepoSource = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_repository.dart'))
          .value;

      // Writer (WaterIntakeNotifier) stores a plain int.
      // Reader must handle `int` first, then fall back to `Map`.
      expect(aiRepoSource, contains('waterData is int'),
          reason:
              'AI context reader must check for int first — '
              'WaterIntakeNotifier stores water as a plain int, not a Map');
    });
  });

  // ── Sleep Keys ─────────────────────────────────────────────────

  group('Contract: sleep key format', () {
    test('sleep writer uses "sleep_log_\$dateStr" key', () {
      // At least one file must write sleep_log_ keys
      final writers = allSources.entries
          .where((e) => e.value.contains("'sleep_log_\$"))
          .map((e) => e.key)
          .toList();
      expect(writers, isNotEmpty,
          reason: 'Must have at least one sleep_log writer');
    });

    test('sync reader scans sleep_log_* prefix (not list key)', () {
      final syncSource = syncServiceUnion();

      expect(syncSource, contains("startsWith('sleep_log_')"),
          reason:
              'sync_service._syncSleepLogs must iterate per-day sleep_log_* keys');

      // _syncSleepLogs (the inner helper) must use prefix iteration, not the
      // stale list key. Extract just the helper body to verify it doesn't use
      // the old list-key pattern. Note: syncSleepNow() is allowed to read
      // healthBox.get('sleep_logs') as a SUPPLEMENTAL path for the
      // conversational AI tool path (chat-logged sleep); that dual-path was
      // added in APK Test #4 (commit 4afc5e0) and is intentional. The
      // invariant is that _syncSleepLogs never bypasses prefix iteration.
      final helperStart = syncSource.indexOf('Future<void> _syncSleepLogs(');
      expect(helperStart, isNot(-1),
          reason: '_syncSleepLogs helper must exist');
      // Take enough chars to cover the helper body (~800 chars) but not the
      // enclosing syncSleepNow that comes before it.
      final helperBody = syncSource.substring(helperStart, helperStart + 800);
      expect(helperBody.contains("healthBox.get('sleep_logs')"), isFalse,
          reason:
              '_syncSleepLogs inner helper must not read the stale list key '
              '— it must iterate per-day sleep_log_* keys via startsWith.');
    });
  });

  // ── Measurement Keys ───────────────────────────────────────────

  group('Contract: measurement key format', () {
    test('measurement writers use "measurement_\$dateStr" key', () {
      final writers = allSources.entries
          .where((e) =>
              e.value.contains("'measurement_\$dateStr'") ||
              e.value.contains("'measurement_\$date'"))
          .map((e) => e.key)
          .toList();
      expect(writers, isNotEmpty,
          reason: 'Must have at least one measurement writer');
    });

    test('sync reader scans measurement_* prefix (not list key)', () {
      final syncSource = syncServiceUnion();

      expect(syncSource, contains("startsWith('measurement_')"),
          reason:
              'sync_service._syncMeasurements must iterate per-day measurement_* keys');

      // Must NOT read the stale 'body_measurements' list key
      expect(
          syncSource.contains("healthBox.get('body_measurements')"), isFalse,
          reason:
              'sync_service must not read stale "body_measurements" list key');
    });
  });

  // ── Schedule Type Values ───────────────────────────────────────

  group('Contract: workout schedule type values', () {
    test('schedule writer uses type "workout" for workout days', () {
      final scheduleSource = allSources.entries
          .firstWhere(
              (e) => e.key.contains('workout_schedule_service.dart'))
          .value;

      // Verify the schedule service writes type: 'workout' (not 'scheduled')
      expect(scheduleSource, contains("'type': 'workout'"),
          reason:
              'WorkoutScheduleService must write type: "workout" for workout days');
    });

    test('schedule writer uses type "rest" for rest days', () {
      final scheduleSource = allSources.entries
          .firstWhere(
              (e) => e.key.contains('workout_schedule_service.dart'))
          .value;

      expect(scheduleSource, contains("'type': 'rest'"),
          reason:
              'WorkoutScheduleService must write type: "rest" for rest days');
    });

    test('AI context reader checks type "workout" (not "scheduled")', () {
      final aiRepoSource = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_repository.dart'))
          .value;

      // Must check for 'workout' to count planned workouts
      expect(aiRepoSource, contains("log['type'] == 'workout'"),
          reason:
              'AI context must check type == "workout" to match scheduler');

      // Must NOT check for the old wrong value 'scheduled'
      expect(aiRepoSource.contains("== 'scheduled'"), isFalse,
          reason:
              'AI context must not check type == "scheduled" (stale value)');
    });

    test(
        'conversational_log_handler delegates schedule-completion to WorkoutWriteService',
        () {
      // C-8 (audit-2026-05-11) — chat-confirmed workouts now route
      // through `WorkoutWriteService.markCompleted`, which finds the
      // schedule by the deterministic `schedule_<date>` key (no need
      // to iterate `workoutBox.values` filtering by `type == 'workout'`).
      // Pre-fix the handler hand-rolled that scan + wrote `exlog_*` /
      // `wlog_*` rows directly with the legacy field shape.
      final handlerSource = allSources.entries
          .firstWhere(
              (e) => e.key.contains('conversational_log_handler.dart'))
          .value;

      expect(
        handlerSource,
        contains('WorkoutWriteService.instance.markCompleted('),
        reason: 'submitWorkoutDraft must route the schedule-status flip '
            'through WorkoutWriteService.markCompleted so it stays '
            'consistent with active-workout completion and the receipt '
            'field shape (Test #8 contract).',
      );

      // Must NOT check for the old wrong value 'scheduled_workout'.
      expect(handlerSource.contains("== 'scheduled_workout'"), isFalse,
          reason:
              'Log handler must not check type == "scheduled_workout" (stale value)');

      // Must NOT hand-roll the legacy entry iteration that this contract
      // originally pinned — that path is gone now that WriteService owns
      // it.
      expect(
        handlerSource.contains("entry['type'] == 'workout'"),
        isFalse,
        reason: 'Legacy `entry["type"] == "workout"` iteration was '
            'replaced by WriteService.markCompleted (deterministic '
            '`schedule_<date>` key lookup). The literal check should '
            'no longer appear in the handler.',
      );
    });
  });

  // ── Step Keys ──────────────────────────────────────────────────

  group('Contract: step key format', () {
    test('step writer and reader agree on "step_\$dateStr" key', () {
      final healthSyncSource = allSources.entries
          .firstWhere((e) => e.key.contains('health_sync_service.dart'))
          .value;

      // Writer: HealthSyncService uses step_$todayStr
      expect(healthSyncSource, contains("'step_\$todayStr'"),
          reason: 'HealthSyncService must write step data with step_\$todayStr');

      // Reader: ai_coach_repository reads step_$dateStr
      final aiRepoSource = allSources.entries
          .firstWhere((e) => e.key.contains('ai_coach_repository.dart'))
          .value;
      expect(aiRepoSource, contains("'step_\$dateStr'"),
          reason: 'AI repo must read step data with step_\$dateStr key');
    });
  });
}
