// BEHAVIORAL CONTRACT TEST — program_week_projection (diagnose 2026-07-21)
//
// The DB column `user_progress.current_week` was a dead constant `1` (every
// writer set the literal; nothing incremented it). This batch projects the
// derived PROGRAM week (1..12) into it on sync, and makes the two AI-snapshot
// week fields emit the same program week, so the coach + weekly push + weekly
// report all agree. The 1..4 clamp on getCurrentWeekNumber() is UNTOUCHED.
//
// Asserts (fail if the runtime path breaks, not just the source text):
//   1. getProgramWeek(phase) returns the program week 1..12 for a given
//      (plan_start, phase) — the value that gets projected.
//   2. buildAiContext() emits ONE week value: progress.current_week ==
//      current_plan_summary.week == getProgramWeek(phase), and NOT the frozen 1.
//   3. getCurrentWeekNumber() floors at 1 even with no plan_start — so the
//      Train fallback `calendarWeek > 0 ? calendarWeek : progress['current_week']`
//      (train_provider) can never read the re-hydrated 1..12 Hive field (F1).
//   4. Kill-switch `disable_program_week_projection` ON → verbatim legacy
//      emission (phase week at :88, frozen `1` at the plan summary).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
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
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000009';
  const planStartKey = 'plan_start_date';
  const flagKey = 'disable_program_week_projection';

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    tempDir = Directory.systemTemp.createTempSync('program_week_projection_');
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
    await HiveService.instance.configBox.delete(flagKey);
  });

  tearDown(() async {
    try {
      final userBox = HiveService.instance.userBox;
      await userBox.delete(planStartKey);
      await userBox.delete('progress');
      await userBox.delete('profile');
    } catch (_) {}
    await HiveService.instance.configBox.delete(flagKey);
    await HiveUserSession.closeAll();
  });

  // Writes plan_start = `daysAgo` days before today, so getCurrentWeekNumber()
  // (clamped 1..4) reports the intended week-in-phase.
  Future<void> setPlanStart(int daysAgo) async {
    final d = DateTime.now().subtract(Duration(days: daysAgo));
    await MigratedKey.write(planStartKey, formatDateKey(d));
  }

  Future<void> setProgress({required int phase, int frozenWeek = 1}) async {
    await HiveService.instance.userBox.put('progress', {
      'current_phase': phase,
      'current_week': frozenWeek,
    });
    await HiveService.instance.userBox
        .put('profile', {'days_per_week': 4});
  }

  // ── 1. getProgramWeek derivation (the projected value) ──────────────────
  test('getProgramWeek returns the 1..12 program week for a (plan_start, phase)',
      () async {
    final svc = WorkoutScheduleReadService.instance;

    await setPlanStart(0); // week-in-phase 1
    expect(svc.getProgramWeek(1), equals(1),
        reason: 'phase 1 wk 1 → program week 1');
    expect(svc.getProgramWeek(2), equals(5),
        reason: 'phase 2 wk 1 → program week 5 (deployment progress, not reset)');
    expect(svc.getProgramWeek(3), equals(9), reason: 'phase 3 wk 1 → 9');

    await setPlanStart(14); // week-in-phase 3
    expect(svc.getProgramWeek(1), equals(3), reason: 'phase 1 wk 3 → 3');
    expect(svc.getProgramWeek(2), equals(7), reason: 'phase 2 wk 3 → 7');

    await setPlanStart(21); // week-in-phase 4 (clamp ceiling)
    expect(svc.getProgramWeek(3), equals(12),
        reason: 'phase 3 wk 4 → 12 (program-week ceiling)');

    // Deployment 2+ cycles via %3 — never > 12, never 0.
    await setPlanStart(0);
    expect(svc.getProgramWeek(4), equals(1),
        reason: 'phase 4 (deployment 2) wk 1 → 1 via %3, not 13');
    expect(svc.getProgramWeek(30), inInclusiveRange(1, 12),
        reason: 'a large rank-ladder phase must never blow past 12 or hit 0');
  });

  // ── 2. Snapshot is single-valued and = program week (the coach fix) ─────
  test('buildAiContext emits ONE week value == getProgramWeek, not the frozen 1',
      () async {
    await setPlanStart(14); // week-in-phase 3
    await setProgress(phase: 2, frozenWeek: 1); // frozen Hive field = 1

    final expected = WorkoutScheduleReadService.instance.getProgramWeek(2);
    expect(expected, equals(7), reason: 'sanity: phase 2 wk 3 → program week 7');

    final snap = AiSnapshotBuilder.instance.buildAiContext();
    final progressWeek =
        (snap['progress'] as Map)['current_week'] as int?;
    final summaryWeek =
        (snap['current_plan_summary'] as Map)['week'] as int?;

    expect(progressWeek, equals(expected),
        reason: 'progress.current_week must be the program week, not the '
            'live phase week and not the frozen 1');
    expect(summaryWeek, equals(expected),
        reason: 'current_plan_summary.week must equal progress.current_week — '
            'the coach must never see two different week numbers in one snapshot');
    expect(progressWeek, isNot(equals(1)),
        reason: 'the frozen Hive current_week (1) must NOT leak into the prompt');
  });

  // ── 3. F1: getCurrentWeekNumber floors at 1 → Train fallback stays dead ─
  test('getCurrentWeekNumber floors at 1 so the vestigial Hive field is unread',
      () async {
    final svc = WorkoutScheduleReadService.instance;

    // No plan_start at all → 1 (never 0/negative).
    expect(svc.getCurrentWeekNumber(), equals(1),
        reason: 'no plan_start must yield 1, never 0 — otherwise the Train '
            'fallback `calendarWeek > 0 ? calendarWeek : frozen` goes live');

    // Even with a re-hydrated 1..12 Hive field, the week computation ignores it.
    await setPlanStart(0);
    await setProgress(phase: 1, frozenWeek: 6); // simulate restore re-hydration
    expect(svc.getCurrentWeekNumber(), equals(1),
        reason: 'getCurrentWeekNumber derives from plan_start, never the Hive '
            'progress.current_week field — so a re-hydrated 6 cannot surface');
  });

  // ── 4. Kill-switch OFF → verbatim legacy emission ───────────────────────
  test('disable_program_week_projection restores the pre-fix snapshot exactly',
      () async {
    await HiveService.instance.configBox.put(flagKey, true);
    await setPlanStart(14); // week-in-phase 3
    await setProgress(phase: 2, frozenWeek: 1);

    final legacyPhaseWeek =
        WorkoutScheduleReadService.instance.getCurrentWeekNumber();
    expect(legacyPhaseWeek, equals(3), reason: 'sanity: phase week 3');

    final snap = AiSnapshotBuilder.instance.buildAiContext();
    expect((snap['progress'] as Map)['current_week'], equals(legacyPhaseWeek),
        reason: 'OFF: progress.current_week is the LEGACY phase week (:88)');
    expect((snap['current_plan_summary'] as Map)['week'], equals(1),
        reason: 'OFF: plan summary week is the LEGACY frozen field (1)');
  });

  // ── 5. currentWeekColumnProjection — BEHAVIORAL pin on the sync decision ─
  // (rule 21: the sync writer's SoT behavioral_test_path must fail when the
  // runtime path is mis-wired, not just when the source text drifts.)
  test('currentWeekColumnProjection: OFF → frozen passthrough, ON → program week',
      () async {
    final svc = WorkoutScheduleReadService.instance;
    await setPlanStart(14); // week-in-phase 3 → getProgramWeek(2) == 7

    // Kill-switch ON (disabled) → verbatim frozen passthrough, including null.
    expect(
        svc.currentWeekColumnProjection(
            frozenWeek: 1, phase: 2, disabled: true),
        equals(1),
        reason: 'disabled must pass the frozen value through byte-identically');
    expect(
        svc.currentWeekColumnProjection(
            frozenWeek: null, phase: 2, disabled: true),
        isNull,
        reason: 'disabled + null frozen → null (old guarded behaviour)');

    // Kill-switch OFF (enabled, default) → program week, never null.
    final on = svc.currentWeekColumnProjection(
        frozenWeek: 1, phase: 2, disabled: false);
    expect(on, equals(7),
        reason: 'enabled must project the program week (phase 2 wk 3 → 7)');
    expect(on, isNotNull,
        reason: 'enabled path is non-null → the column write is unconditional');
    // Frozen value is IGNORED when enabled (so a stale 1 cannot leak).
    expect(
        svc.currentWeekColumnProjection(
            frozenWeek: 999, phase: 2, disabled: false),
        equals(7),
        reason: 'enabled ignores the frozen field entirely');
  });

  // ── 6. Source wiring: all sites gated by the SAME flag key ──────────────
  group('source wiring', () {
    String strip(String s) => s
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'//[^\n]*'), '');

    test('sync_profile projects via the gated helper, keyed on the computed value',
        () {
      final src = strip(
          File('lib/core/services/sync/sync_profile.dart').readAsStringSync());
      expect(src.contains('currentWeekColumnProjection'), isTrue,
          reason: 'sync must write the column via the behaviorally-tested helper');
      expect(src.contains(flagKey), isTrue,
          reason: 'sync projection must be behind the kill-switch');
      // Unit 3b (e6b9c4, 2026-07-30) moved this from a conditional-omit
      // upsert map to the update_user_progress_snapshot RPC's always-
      // present params (every declared RPC parameter must be sent by
      // name — the server-side COALESCE now does what the client-side
      // `if (x != null)` omission used to do). The review-F1 contract this
      // test pins is unchanged: the write must key off the COMPUTED
      // `currentWeekOut`, never the raw frozen `p['current_week']` field.
      expect(src.contains("'p_current_week': currentWeekOut,"), isTrue,
          reason: 'column write must key off the computed value, not '
              'p[\'current_week\'] (the raw frozen field)');
      expect(src.contains("'p_current_week': p['current_week']"), isFalse,
          reason: 'would regress to writing the raw frozen field instead '
              'of the projected program week');
    });

    test('the boot replay does NOT write current_week (F1: no second writer)',
        () {
      final src = strip(
          File('lib/core/services/sync_service.dart').readAsStringSync());
      // _replayPendingOnboardingSync must not pass current_week — it would
      // stomp the projected column with the frozen Hive `1` on every boot.
      expect(src.contains("'current_week': pr['current_week']"), isFalse,
          reason: 'the onboarding replay must not re-write the frozen current_week');
    });

    test('ai_snapshot_builder emits getProgramWeek at both sites, same flag',
        () {
      final src = strip(File(
              'lib/features/ai_coach/services/ai_snapshot_builder.dart')
          .readAsStringSync());
      // Two emit sites (progress block + current_plan_summary) both branch on
      // the flag and call getProgramWeek.
      final gpw = 'getProgramWeek'.allMatches(src).length;
      expect(gpw, greaterThanOrEqualTo(2),
          reason: 'both snapshot week fields must project the program week');
      expect(flagKey.allMatches(src).length, greaterThanOrEqualTo(2),
          reason: 'both sites must gate on the SAME kill-switch key');
    });
  });
}
