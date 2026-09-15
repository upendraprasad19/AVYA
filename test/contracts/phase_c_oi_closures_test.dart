// Contract test — consolidated Phase C closures (Hermes audit 2026-05-17).
//
// Covers OI-32 / OI-33 / OI-34 / OI-38 / OI-39 / OI-40 / OI-41 with
// source-grep assertions. OI-35 (doc internal consistency) is gated by
// the runtime script `scripts/check_doc_internal_consistency.dart` —
// not source-grepped here.

import 'dart:io';
import 'package:test/test.dart';

/// Strip TS/Dart line + block comments before source-grep.
/// Source-grep tests routinely false-positive on quoted patterns inside
/// explanatory comments (the OI-29/OI-36 fixes hit this same pattern).
String _stripComments(String src) =>
    src
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  group('OI-32 delete-account recursive Storage purge', () {
    final src = File('supabase/functions/delete-account/index.ts')
        .readAsStringSync();

    test('listAllObjectsRecursive helper exists', () {
      expect(
        RegExp(r'function\s+listAllObjectsRecursive').hasMatch(src),
        isTrue,
        reason:
            'delete-account must define listAllObjectsRecursive(bucket, prefix) '
            'to walk subfolders. Pre-fix purge only listed top-level entries '
            'and silently skipped nested user paths — DPDP §17 violation.',
      );
    });

    test('purge loop uses recursive helper, not flat list', () {
      expect(
        src.contains('await listAllObjectsRecursive(bucket, userId)'),
        isTrue,
        reason:
            'purge loop must call listAllObjectsRecursive(bucket, userId). '
            'A flat `.list(userId)` regression breaks recursive deletion.',
      );
      // Pre-fix shape `.list(userId)` without further depth. Strip comments
      // first since the OI-32 explanatory block quotes the old pattern.
      final stripped = _stripComments(src);
      final flatListPattern = RegExp(r'\.list\(userId\)(?!\s*,)');
      expect(
        flatListPattern.hasMatch(stripped),
        isFalse,
        reason:
            'flat `.list(userId)` without options re-introduced in CODE. Use '
            'listAllObjectsRecursive instead.',
      );
    });
  });

  group('OI-33 APK size gate --release strict mode', () {
    final src = File('scripts/check_apk_size_within_bounds.dart')
        .readAsStringSync();

    test('--release flag is parsed', () {
      expect(
        src.contains("args.contains('--release')"),
        isTrue,
        reason: 'expected `args.contains(\'--release\')` parse',
      );
    });

    test('missing APK in --release mode exits 1', () {
      expect(
        RegExp(r'if\s*\(releaseMode\)\s*\{[^}]*exit\(1\)', dotAll: true)
            .hasMatch(src),
        isTrue,
        reason:
            'releaseMode branch must `exit(1)` when APK file is missing. '
            'Pre-fix the script silent-skipped (exit 0) regardless of mode.',
      );
    });
  });

  group('OI-34 check_migrations_live.dart exists', () {
    test('script file exists with --release-style live verify', () {
      final f = File('scripts/check_migrations_live.dart');
      expect(f.existsSync(), isTrue,
          reason: 'expected scripts/check_migrations_live.dart');
      final src = f.readAsStringSync();
      expect(
        src.contains('api.supabase.com/v1/projects/') &&
            src.contains('/database/migrations'),
        isTrue,
        reason:
            'live verify script must hit Supabase Management API '
            '/v1/projects/<id>/database/migrations endpoint',
      );
    });
  });

  group('OI-38 StreakFreezeNotifier.build is read-only', () {
    final src = File('lib/features/home/providers/home_provider.dart')
        .readAsStringSync();

    test('build body does not call _refillIfNewWeek or commitRefill', () {
      final classStart = src.indexOf('class StreakFreezeNotifier');
      expect(classStart, greaterThan(0));
      final buildStart = src.indexOf('int build()', classStart);
      expect(buildStart, greaterThan(0));
      final buildEnd = src.indexOf('\n  }', buildStart);
      // Strip comments — the OI-38 fix explains the move in prose and
      // quotes the old method name in the comment block.
      final buildBody = _stripComments(src.substring(buildStart, buildEnd));
      expect(
        buildBody.contains('_refillIfNewWeek'),
        isFalse,
        reason:
            'StreakFreezeNotifier.build must NOT call _refillIfNewWeek (write-on-read).',
      );
      expect(
        buildBody.contains('commitRefill'),
        isFalse,
        reason:
            'StreakFreezeNotifier.build must NOT call commitRefill (write-on-read).',
      );
    });

    test('StreakProgressService.refillIfNewWeek exists', () {
      final svc =
          File('lib/core/services/streak_progress_service.dart')
              .readAsStringSync();
      expect(
        RegExp(r'int\?\s+refillIfNewWeek\s*\(').hasMatch(svc),
        isTrue,
        reason:
            'StreakProgressService.refillIfNewWeek() must exist as the new '
            'orchestration entry point.',
      );
    });

    test('DayRolloverObserver invokes refillIfNewWeek', () {
      final dr =
          File('lib/core/services/day_rollover_service.dart').readAsStringSync();
      expect(
        dr.contains('StreakProgressService.instance.refillIfNewWeek'),
        isTrue,
        reason:
            'day_rollover_service must invoke '
            'StreakProgressService.instance.refillIfNewWeek() inside '
            '_doRolloverWithRef so the weekly refill fires off-build.',
      );
    });
  });

  group('OI-39 train_provider migrated to WorkoutReadService', () {
    final src = File('lib/features/train/providers/train_provider.dart')
        .readAsStringSync();

    test('_getLastPerformance delegates to WorkoutReadService.logsForExercise',
        () {
      final fnStart = src.indexOf('LastPerformanceData _getLastPerformance(');
      expect(fnStart, greaterThan(0));
      final fnEnd = src.indexOf('\n}', fnStart);
      final fnBody = src.substring(fnStart, fnEnd);
      expect(
        fnBody.contains('WorkoutReadService.instance.logsForExercise'),
        isTrue,
        reason:
            '_getLastPerformance must delegate to '
            'WorkoutReadService.instance.logsForExercise(exerciseName). '
            'Pre-fix it iterated workoutBox.values inline.',
      );
      expect(
        fnBody.contains('hive.workoutBox.values'),
        isFalse,
        reason:
            '_getLastPerformance must NOT iterate hive.workoutBox.values '
            'directly — that is the OI-39 anti-pattern.',
      );
    });

    test('exerciseHistoryProvider delegates to WorkoutReadService', () {
      final marker = src.indexOf('final exerciseHistoryProvider');
      expect(marker, greaterThan(0));
      final providerEnd = src.indexOf('});', marker);
      final providerBody = src.substring(marker, providerEnd);
      expect(
        providerBody.contains('WorkoutReadService.instance.logsForExercise'),
        isTrue,
        reason:
            'exerciseHistoryProvider must delegate to WorkoutReadService.',
      );
      expect(
        providerBody.contains('hive.workoutBox.values'),
        isFalse,
        reason:
            'exerciseHistoryProvider must NOT iterate hive.workoutBox.values.',
      );
    });

    test('WorkoutReadService.logsForExercise exists', () {
      final svc = File('lib/core/services/workout_read_service.dart')
          .readAsStringSync();
      expect(
        RegExp(r'List<Map<String,\s*dynamic>>\s+logsForExercise\s*\(')
            .hasMatch(svc),
        isTrue,
        reason:
            'WorkoutReadService.logsForExercise must exist as the canonical '
            'cross-date exlog scan + name match.',
      );
    });
  });

  group('OI-40 paywall_sheet_phase_variant escalates to canonical paywall',
      () {
    final src = File('lib/shared/widgets/paywall_sheet_phase_variant.dart')
        .readAsStringSync();

    test('CTA calls showPaywallSheet with feature key', () {
      expect(
        src.contains("showPaywallSheet(context, feature: 'Phases 2-12')"),
        isTrue,
        reason:
            'phase variant CTA must escalate to the canonical '
            '`showPaywallSheet(context, feature: ...)` from paywall_sheet.dart. '
            'Pre-fix it just `Navigator.pop()`d with a TODO — free user dead-end.',
      );
    });

    test('phase variant imports paywall_sheet (canonical)', () {
      expect(
        src.contains("import 'package:icanbefitter/shared/widgets/paywall_sheet.dart'"),
        isTrue,
        reason: 'expected import of canonical paywall_sheet.dart',
      );
    });
  });

  group('OI-41 streak single source — Profile uses WorkoutRepository', () {
    final src = File('lib/features/profile/providers/profile_provider.dart')
        .readAsStringSync();

    test('currentStreak reads from WorkoutRepository.currentStreak()', () {
      expect(
        src.contains('currentStreak: WorkoutRepository.instance.currentStreak()'),
        isTrue,
        reason:
            'UserStatsData.currentStreak must read from '
            'WorkoutRepository.instance.currentStreak() — the canonical live '
            'walk-back source. Pre-fix it read cached `current_streak_weeks`.',
      );
    });

    test('forbidden: reading cached current_streak_weeks for the streak field',
        () {
      // The field name may still exist for other contexts (e.g. legacy
      // weekly rollup) — but it must NOT be the source for currentStreak.
      // Source-grep that the literal `currentStreak: (progress['current_streak_weeks']`
      // does NOT appear.
      expect(
        src.contains("currentStreak:\n          (progress['current_streak_weeks']"),
        isFalse,
        reason:
            'pre-fix pattern reintroduced. Use '
            'WorkoutRepository.instance.currentStreak() instead.',
      );
    });
  });
}
