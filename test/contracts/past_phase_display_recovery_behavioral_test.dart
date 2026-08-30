// BEHAVIORAL TEST — past-phase display recovery (diagnose c9e4b7)
//
// Concept:  past_phase_display_read_path
// Writer:   plan_start_date / plan_end_date (MigratedKey) + schedule_* rows
//           (WorkoutWriteService.upsertScheduled)
// Reader:   WorkoutScheduleReadService.pastPhaseBlocksForDisplay()
//           → week_selector._toPastPhases → the Train phase strip
//
// The bug, reproduced below exactly as it exists on the founder's live account
// (queried 2026-08-07): `current_phase = 2`, but `plan_start_date` is still the
// ORIGINAL onboarding Monday 2026-04-27 (cloud `plan_json` agreed:
// plan_start 2026-04-27 / plan_end 2026-05-24), while schedule_* rows run all
// the way to 2026-07-23. `pastPhaseBlocks()` keeps only rows STRICTLY BEFORE
// plan_start — and the earliest row IS plan_start — so the set is necessarily
// empty, `_toPastPhases` computes showCount 0, and PHASE I renders nowhere.
//
// A source-grep test cannot catch this class: every call was present and
// correctly spelled: the DATA made the filter vacuous. Hence a real Hive
// round-trip through the real writer.
//
// Group D is the anti-regression half and matters as much as the fix: a healthy
// account (plan_start correctly advanced) must get byte-identical results from
// the wrapper and the strict method, so the recovery can never invent history
// for a user who does not have any.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
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
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-0000000000c9';

  // The founder's real window, to the day.
  final onboardingMonday = DateTime(2026, 4, 27);
  final originalPlanEnd = DateTime(2026, 5, 24);

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('pastphase_recovery_');
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    Hive.init(tempDir.path);
    await Hive.openBox(HiveService.exerciseBoxName);
    await Hive.openBox(HiveService.foodBoxName);
    await Hive.openBox(HiveService.syncBoxName);
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await HiveUserSession.openForUser(fakeUserId);
  });

  tearDown(() async {
    final box = HiveService.instance.workoutBox;
    for (final k in box.keys
        .where((k) => k.toString().startsWith('schedule_'))
        .toList()) {
      await box.delete(k);
    }
    await HiveUserSession.closeAll();
  });

  /// Writes 4 weeks of rows from [start] through the REAL writer.
  /// [phase] null → no `phase` key at all, which is what a cloud-restored row
  /// looks like: `scheduled_workouts` has no phase column (verified against
  /// information_schema 2026-08-07), so restore cannot rehydrate the stamp.
  Future<void> writeBlock(DateTime start, {int? phase}) async {
    for (int week = 1; week <= 4; week++) {
      for (int d = 0; d < 7; d++) {
        final date = start.add(Duration(days: (week - 1) * 7 + d));
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: {
            'type': 'workout',
            'date': formatDateKey(date),
            'week': week,
            if (phase != null) 'phase': phase,
            'status': 'planned',
            'workout_name': 'Upper Body',
            'exercises': const <Map<String, dynamic>>[],
          },
          source: WriteSource.planGenerator,
        );
      }
    }
  }

  /// The founder's account: plan_start frozen at onboarding, rows well past it.
  Future<void> seedDriftedAccount({required bool stamped}) async {
    await MigratedKey.write(
        'plan_start_date', onboardingMonday.toIso8601String());
    await MigratedKey.write(
        'plan_end_date', originalPlanEnd.toIso8601String());
    // Phase 1 block: 2026-04-27 .. 2026-05-24
    await writeBlock(onboardingMonday, phase: stamped ? 1 : null);
    // Phase 2 block: 2026-06-29 .. 2026-07-26 (past plan_end, as observed)
    await writeBlock(DateTime(2026, 6, 29), phase: stamped ? 2 : null);
  }

  group('A · the bug — strict filter is vacuous when plan_start never moved',
      () {
    test('pastPhaseBlocks() returns EMPTY despite 8 weeks of rows', () async {
      await seedDriftedAccount(stamped: true);

      // Sanity: the rows really are there. If this ever fails the test is
      // vacuous and would "pass" group B for the wrong reason.
      final rowCount = HiveService.instance.workoutBox.keys
          .where((k) => k.toString().startsWith('schedule_'))
          .length;
      expect(rowCount, 56, reason: '8 weeks × 7 days must be materialized');

      expect(
        read.pastPhaseBlocks(),
        isEmpty,
        reason: 'the earliest row IS plan_start, and the filter is '
            'STRICTLY-before, so nothing can ever qualify — this is the '
            'founder-observed root cause, pinned so a future change to the '
            'strict filter is a deliberate act.',
      );
    });
  });

  group('B · the fix — display recovers the blocks the strict filter cannot',
      () {
    test('phase-identity path (rows carry a `phase` stamp)', () async {
      await seedDriftedAccount(stamped: true);

      final shown = read.pastPhaseBlocksForDisplay(2);
      expect(shown, isNotEmpty,
          reason: 'a user on phase 2 must be able to see phase 1');
      expect(shown.length, 1,
          reason: 'two blocks exist; the NEWEST is the window being trained '
              'in now, so exactly one is genuinely past');
      // The recovered block must be the OLD one, not the current one.
      expect(shown.single.startDate, onboardingMonday);
    });

    test('28-day fallback path (cloud-restored rows carry NO `phase`)',
        () async {
      await seedDriftedAccount(stamped: false);

      final shown = read.pastPhaseBlocksForDisplay(2);
      expect(shown, isNotEmpty,
          reason: 'restored rows have no phase stamp — bucketPastRows falls '
              'back to 28-day calendar bucketing, which must still recover '
              'history. The founder is on WEB, where every cold tab is a '
              'restore, so this is the path that actually runs for them.');
      expect(shown.first.startDate, onboardingMonday);
    });
  });

  group('C · bounds — never invent history', () {
    test('phase 1 user gets nothing even with rows present', () async {
      await seedDriftedAccount(stamped: true);
      expect(
        read.pastPhaseBlocksForDisplay(1),
        isEmpty,
        reason: 'currentPhase <= 1 means no phase has been completed; the '
            'recovery must not manufacture a past group from the current '
            "phase's own rows.",
      );
    });

    test('a single block yields nothing — it IS the current window', () async {
      await MigratedKey.write(
          'plan_start_date', onboardingMonday.toIso8601String());
      await MigratedKey.write(
          'plan_end_date', originalPlanEnd.toIso8601String());
      await writeBlock(onboardingMonday, phase: 1);

      expect(
        read.pastPhaseBlocksForDisplay(2),
        isEmpty,
        reason: 'with only one block there is nothing behind the user, even '
            'though current_phase claims otherwise. Showing the phase they '
            'are training in as "past" would be worse than showing nothing.',
      );
    });
  });

  group('D · anti-regression — healthy accounts are untouched', () {
    test('when plan_start HAS advanced, wrapper == strict', () async {
      // A correctly-advanced account: plan_start moved to the phase-2 block,
      // so the phase-1 rows are genuinely before it and the strict filter works.
      final phase2Start = DateTime(2026, 6, 29);
      await MigratedKey.write(
          'plan_start_date', phase2Start.toIso8601String());
      await MigratedKey.write('plan_end_date',
          phase2Start.add(const Duration(days: 27)).toIso8601String());
      await writeBlock(onboardingMonday, phase: 1);
      await writeBlock(phase2Start, phase: 2);

      final strict = read.pastPhaseBlocks();
      final shown = read.pastPhaseBlocksForDisplay(2);

      expect(strict, isNotEmpty,
          reason: 'precondition: the strict filter works on a healthy account');
      expect(shown.length, strict.length);
      expect(shown.single.startDate, strict.single.startDate);
      expect(shown.single.endDate, strict.single.endDate,
          reason: 'the wrapper must short-circuit to the strict result the '
              'moment it is non-empty — the recovery branch must never run '
              'for, or alter, an account that is not drifted.');
    });
  });

  group('E · tripwire telemetry (diagnose b7f1c8)',
      () {
    final events = <String>[];

    setUp(() {
      events.clear();
      ErrorTelemetry.debugOnLogEventForTests = (opType, {message}) {
        events.add('$opType|${message ?? ''}');
      };
    });

    tearDown(() {
      ErrorTelemetry.debugOnLogEventForTests = null;
    });

    test('fires once when strict is empty on a drifted phase-2+ account',
        () async {
      await seedDriftedAccount(stamped: true);

      read.pastPhaseBlocksForDisplay(2);
      final fired = events
          .where((e) => e.startsWith('past_phase_blocks_strict_empty|'))
          .toList();
      expect(
        fired.length,
        1,
        reason: 'the anomaly this account hits (strict empty + '
            'currentPhase>1) must be observable in client_errors — no '
            'organic Phase-2+ user has ever been confirmed in this shape, '
            'so the first real one must be catchable without re-deriving '
            'this whole investigation again.',
      );

      // Plan-review round 2 finding 3 — the assertion above only pins that
      // the event FIRES. Demonstrated: replacing the whole message with a
      // literal left all 9 tests in this file green, i.e. the tripwire's
      // entire diagnostic payload could regress to nothing (a renamed Hive
      // key, a typo, a throwing interpolation) while still reporting
      // "working". The event's stated purpose is to make the first real
      // occurrence diagnosable WITHOUT re-deriving this investigation, and
      // an event with no context does not do that — bad news and no news
      // must not collapse into the same signal.
      final message = fired.single.split('|').skip(1).join('|');
      expect(message, contains('currentPhase=2'),
          reason: 'the phase is what distinguishes this anomaly from an '
              'ordinary empty history — without it the event cannot be '
              'triaged from client_errors alone.');
      expect(message, contains('recoveredBlocks='),
          reason: 'whether the recovery salvaged anything separates "the '
              'display is degraded" from "the display is empty".');
      expect(message, contains('phaseStartedAt='),
          reason: 'phase_started_at vs the schedule rows is the exact '
              'comparison that identifies the drifted shape — it is the '
              'single most load-bearing field in the payload.');
    });

    test('does NOT fire again on a second call in the same session',
        () async {
      await seedDriftedAccount(stamped: true);

      read.pastPhaseBlocksForDisplay(2);
      read.pastPhaseBlocksForDisplay(2);
      read.pastPhaseBlocksForDisplay(2);
      expect(
        events.where((e) => e.startsWith('past_phase_blocks_strict_empty|'))
            .length,
        1,
        reason: 'pastPhaseBlocksForDisplay is called from '
            'WeekSelector.build(), which rebuilds on every scroll frame — '
            'without a dedup guard this would post a real network call per '
            'rebuild instead of once per account per session.',
      );
    });

    test('does NOT fire for a healthy (non-drifted) account', () async {
      final phase2Start = DateTime(2026, 6, 29);
      await MigratedKey.write(
          'plan_start_date', phase2Start.toIso8601String());
      await MigratedKey.write('plan_end_date',
          phase2Start.add(const Duration(days: 27)).toIso8601String());
      await writeBlock(onboardingMonday, phase: 1);
      await writeBlock(phase2Start, phase: 2);

      read.pastPhaseBlocksForDisplay(2);
      expect(
        events.where((e) => e.startsWith('past_phase_blocks_strict_empty|')),
        isEmpty,
        reason: 'a healthy account short-circuits on the non-empty strict '
            'result before the tripwire — this must stay silent for every '
            'account that is not actually anomalous, or it stops being a '
            'signal.',
      );
    });
  });
}
