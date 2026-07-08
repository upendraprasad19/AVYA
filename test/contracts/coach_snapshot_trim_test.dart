// Unit 3 (coach-memory-snapshot) — behavioral contract for the proactive
// snapshot trim.
//
// THE CHANGE: the per-request snapshot dropped 3 pure 7-day daily-series
// (step_history_7d / sleep_7d / water_7d) from the BASE map at build time so
// each coach turn is leaner (latency + total-context headroom for the Unit-2
// conversation history). Today's value is already covered by today_steps /
// today_nutrition.water_ml / sleep_logs_count_7d. A HISTORICAL query about
// them re-adds the full series on-demand via enrichContextForQuery — so there
// is NO regression for "how's my sleep this week?" (lean base + rich on-demand).
//
// Assertions FAIL against the pre-Unit-3 behavior (base always carried them):
//   (a) base snapshot OMITS the 3 series but RETAINS every load-bearing field;
//   (b) a historical sleep/steps/water query re-adds the matching series;
//   (c) a non-historical message does NOT re-add them;
//   (d) kill-switch configBox['disable_snapshot_trim'] keeps them in the base.
//
// Mirrors ai_snapshot_builder_only_test.dart's Hive setup.

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';
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
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmp = Directory.systemTemp.createTempSync('coach_snapshot_trim_').path;
    PathProviderPlatform.instance = _FakePathProvider(tmp);
    Hive.init(tmp);
    HiveService.debugMarkInitializedForTests();
    GuardedBox.testBypassOwnership = true;
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
  });

  setUp(() async {
    await HiveUserSession.closeAll();
    await HiveUserSession.openForUser('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee');
    if (!Hive.isBoxOpen('configBox')) await Hive.openBox('configBox');
    await HiveService.instance.userBox.clear();
    await HiveService.instance.coachBox.clear();
    await HiveService.instance.workoutBox.clear();
    await HiveService.instance.nutritionBox.clear();
    await HiveService.instance.healthBox.clear();
    await HiveService.instance.customBox.clear();
    await HiveService.instance.configBox.clear();
    await HiveService.instance.userBox.put('profile', {
      // Match the session user UUID so the cross-account guard doesn't fire.
      'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
      'full_name': 'Lt Test',
      'primary_goal': 'muscle_gain',
      'daily_calories': 2200,
      'protein_grams': 165,
      'tdee': 2400,
    });
    await HiveService.instance.userBox.put('progress', {
      'current_phase': 1,
      'current_week': 1,
      'current_streak_weeks': 1,
    });
  });

  test('(a) base snapshot OMITS the 3 trimmed series but RETAINS load-bearing fields',
      () {
    final ctx = AiSnapshotBuilder.instance.buildAiContext();

    for (final k in AiSnapshotBuilder.proactiveTrimKeys) {
      expect(ctx.containsKey(k), isFalse,
          reason: 'Unit 3 proactively trims "$k" from the base snapshot');
    }
    expect(AiSnapshotBuilder.proactiveTrimKeys,
        containsAll(<String>['step_history_7d', 'sleep_7d', 'water_7d']));

    // Load-bearing fields must survive the trim.
    for (final k in const [
      'is_first_ever_message',
      'profile',
      'progress',
      'daily_targets',
      'daily_calorie_target',
      'today_nutrition',
      'meals_today',
      'today_workout',
      'current_plan_summary',
      'current_rank',
      'subscription',
      'motivational_style',
      'today_steps', // today's value is kept — only the 7-day SERIES is dropped
    ]) {
      expect(ctx.containsKey(k), isTrue,
          reason: 'load-bearing field "$k" must survive the trim');
    }
  });

  // Start from a base with the 3 series EXPLICITLY removed so the ONLY thing
  // that can make containsKey pass is the on-demand re-add branch — a strong
  // regression guard (this would FAIL on pre-Unit-3 code that emitted them in
  // the base map). B-pass LOW.
  Map<String, dynamic> strippedBase() {
    final b = {...AiSnapshotBuilder.instance.buildAiContext()};
    b.removeWhere((k, _) => AiSnapshotBuilder.proactiveTrimKeys.contains(k));
    return b;
  }

  test('(b) a historical sleep / steps / water query re-adds the matching series',
      () {
    final sleep = AiSnapshotBuilder.instance
        .enrichContextForQuery('how has my sleep been this week?', strippedBase());
    expect(sleep.containsKey('sleep_7d'), isTrue,
        reason: 'a historical sleep query must re-add sleep_7d on-demand');

    final steps = AiSnapshotBuilder.instance.enrichContextForQuery(
        'how many steps did I walk last week?', strippedBase());
    expect(steps.containsKey('step_history_7d'), isTrue,
        reason: 'a historical steps query must re-add step_history_7d');

    final water = AiSnapshotBuilder.instance
        .enrichContextForQuery("what's my water intake trend?", strippedBase());
    expect(water.containsKey('water_7d'), isTrue,
        reason: 'a historical water query must re-add water_7d');
  });

  test("(b2) the natural contracted phrasing \"how's my sleep this week?\" "
      'ALSO re-adds sleep_7d (B-pass MED — keyword-gap fix)', () {
    final enriched = AiSnapshotBuilder.instance
        .enrichContextForQuery("how's my sleep this week?", strippedBase());
    expect(enriched.containsKey('sleep_7d'), isTrue,
        reason: "the contracted 'how's ... this week' phrasing must trigger the "
            'on-demand re-add — the exact phrasing in the code docstring');
  });

  test('(c) a non-historical message does NOT re-add the trimmed series', () {
    final base = AiSnapshotBuilder.instance.buildAiContext();
    // Mentions "sleep" but is not a historical query → no re-add.
    final enriched = AiSnapshotBuilder.instance
        .enrichContextForQuery('should I sleep more tonight?', {...base});
    expect(enriched.containsKey('sleep_7d'), isFalse,
        reason: 'only a HISTORICAL query re-adds the series');
  });

  test('(d) kill-switch disable_snapshot_trim keeps the series in the base', () async {
    await HiveService.instance.configBox.put('disable_snapshot_trim', true);
    final ctx = AiSnapshotBuilder.instance.buildAiContext();
    expect(ctx.containsKey('step_history_7d'), isTrue,
        reason: 'kill-switch restores the pre-Unit-3 base snapshot');
    expect(ctx.containsKey('sleep_7d'), isTrue);
    expect(ctx.containsKey('water_7d'), isTrue);
  });
}
