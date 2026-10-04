// Behavioral — OI-166 Unit 2: a regen (Edit Profile / AI coach) that starts
// past week 4 of an existing phase must CYCLE content (baseline/overreach/
// peak/deload repeating via contentFlavorIndex) instead of freezing on the
// last week or crashing, AND the schedule-row write range must stay bound to
// the STORED plan_end_date via a LITERAL DATE comparison — never a
// week-bucket comparison, which diverges from the date comparison whenever
// plan_end is mid-week-misaligned (the exact state a redoWeek4 tap on a
// non-Monday can produce).
//
// Regression-tests three prior review-round findings on this same document:
//   - round 4: an extended (redoWeek4) plan regenerated mid-extension must
//     write real rows through EXACTLY the stored plan_end, no more/fewer.
//   - round 5 P0: a genuinely EXPIRED plan (today > plan_end, no extension)
//     must write ZERO rows AND leave current_plan byte-identical — a blob
//     rewrite backed by zero rows is the defect this closes.
//   - round 7 P0: a MISALIGNED plan_end (not week-grid-aligned, reachable via
//     redoWeek4 on a non-Monday) must never let a row land past plan_end even
//     when the week-bucket containing plan_end still contains today.
//
// Also covers C (RegeneratePlanPlanner + the ToolDispatcher commit sites):
// the SAME cycling fix, driven through the REAL two-phase contract (plan() ->
// cache() -> ToolDispatcher.execute(), the actual Confirm-time path) rather
// than by re-deriving the splice by hand.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/regenerate_plan_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Exposes a real Riverpod [Ref] so we can drive
/// `ToolDispatcher.execute(ref, intent)` — the REAL dispatch path — mirroring
/// `test/contracts/coach_completion_prompt_test.dart`'s established pattern.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir =
        await Directory.systemTemp.createTemp('test_oi166_unit2_cycling');
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
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  setUp(() async {
    for (final name in [
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'userBox_aaaaaaaa',
      'workoutBox_aaaaaaaa',
      'nutritionBox_aaaaaaaa',
      'healthBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).close();
      try {
        await Hive.deleteBoxFromDisk(name);
      } catch (_) {}
    }
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);

    if (Hive.isBoxOpen(HiveService.exerciseBoxName)) {
      await Hive.box(HiveService.exerciseBoxName).close();
    }
    try {
      await Hive.deleteBoxFromDisk(HiveService.exerciseBoxName);
    } catch (_) {}
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in rows.whereType<Map>()) {
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
    }

    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
    // Keep dispatch hermetic — no live Supabase touch from the fire-and-forget
    // sync calls inside generateAndScheduleFromDate / execute().
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  final svc = WorkoutScheduleReadService.instance;

  String scheduleKeyFor(DateTime d) => 'schedule_${svc.dateKey(d)}';

  Map<String, dynamic>? scheduleRow(DateTime d) {
    final raw = HiveService.instance.workoutBox.get(scheduleKeyFor(d));
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  group('contentFlavorIndex — pure', () {
    test('weeks 1-4 (unextended, byte-compatible) map to indices 0-3', () {
      expect(WorkoutScheduleReadService.contentFlavorIndex(1), 0);
      expect(WorkoutScheduleReadService.contentFlavorIndex(2), 1);
      expect(WorkoutScheduleReadService.contentFlavorIndex(3), 2);
      expect(WorkoutScheduleReadService.contentFlavorIndex(4), 3);
    });

    test('weeks 5-8 (one redoWeek4 extension — round 4 scenario) cycle back',
        () {
      expect(WorkoutScheduleReadService.contentFlavorIndex(5), 0);
      expect(WorkoutScheduleReadService.contentFlavorIndex(6), 1);
      expect(WorkoutScheduleReadService.contentFlavorIndex(7), 2);
      expect(WorkoutScheduleReadService.contentFlavorIndex(8), 3);
    });

    test('arbitrary large week numbers (repeated extensions) stay in 0-3',
        () {
      expect(WorkoutScheduleReadService.contentFlavorIndex(41), 0);
      expect(WorkoutScheduleReadService.contentFlavorIndex(53), 0);
      expect(WorkoutScheduleReadService.contentFlavorIndex(100), 3);
    });
  });

  group('generateAndScheduleFromDate (B) — behavioral', () {
    Future<void> seedFirstGeneration(DateTime planStart) async {
      // Establish a normal (unextended) prior generation so the SECOND call
      // below is a genuine regen (isFirstGeneration == false), matching how
      // every one of these scenarios actually arises in production.
      await MigratedKey.write(
          'plan_start_date', planStart.toIso8601String());
      await MigratedKey.write('plan_end_date',
          planStart.add(const Duration(days: 27)).toIso8601String());
    }

    test(
        'extended: regen mid-redoWeek4-window writes exactly the stored '
        'days, real week stamp, and cycled current_plan content',
        () async {
      final planStart = DateTime(2026, 6, 1); // a Monday
      await seedFirstGeneration(planStart);
      // Simulate a redoWeek4 extension: stored plan_end pushed to day 34
      // (still week-grid-aligned: 34 % 7 == 6).
      final extendedEnd = planStart.add(const Duration(days: 34));
      await MigratedKey.write('plan_end_date', extendedEnd.toIso8601String());
      // Bogus marker so a real overwrite is provable, not assumed.
      await HiveService.instance.workoutBox.put('current_plan', {
        'week_plans': [
          for (var i = 0; i < 4; i++) {'week_character': 'STALE_MARKER'},
        ],
      });

      final today = planStart.add(const Duration(days: 30));
      await svc.generateAndScheduleFromDate(
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
        fromDate: today,
      );

      // Exactly 5 days written: today(30)..extendedEnd(34) inclusive. Zero
      // empty days, zero days outside that range.
      var written = 0;
      for (var offset = 0; offset <= 41; offset++) {
        final d = planStart.add(Duration(days: offset));
        final row = scheduleRow(d);
        if (row == null) continue;
        written++;
        expect(offset, inInclusiveRange(30, 34),
            reason: 'no row should exist outside [today, storedPlanEnd]');
      }
      expect(written, 5);

      // The row for `today` (day 30) is stamped the REAL week number (5),
      // not a loop-relative counter frozen at 4.
      final todayRow = scheduleRow(today);
      expect(todayRow, isNotNull);
      expect(todayRow!['week'], 5);

      // current_plan reflects fresh, CYCLED content — regenStartWeek(5) > 4
      // so every one of the 4 entries is replaced (preserveBefore == 0) with
      // the canonical baseline->overreach->peak->deload sequence, in order.
      final plan = HiveService.instance.workoutBox.get('current_plan');
      expect(plan, isA<Map>());
      final weekPlans = (plan as Map)['week_plans'] as List;
      expect(weekPlans.length, 4);
      const expectedCharacters = ['baseline', 'overreach', 'peak', 'deload'];
      for (var i = 0; i < 4; i++) {
        expect((weekPlans[i] as Map)['week_character'],
            expectedCharacters[i],
            reason: 'entry $i must be freshly generated, not the stale '
                'pre-regen marker');
      }
    });

    test(
        'expired: regen past storedPlanEnd with no extension writes zero '
        'rows and leaves current_plan byte-identical',
        () async {
      final planStart = DateTime(2026, 6, 1);
      await seedFirstGeneration(planStart); // plan_end = day 27, unextended
      final staleBlob = {
        'week_plans': [
          for (var i = 0; i < 4; i++) {'week_character': 'PRE_REGEN_$i'},
        ],
      };
      await HiveService.instance.workoutBox
          .put('current_plan', Map<String, dynamic>.from(staleBlob));

      final today = planStart.add(const Duration(days: 30)); // 3 days past
      await svc.generateAndScheduleFromDate(
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
        fromDate: today,
      );

      for (var offset = 25; offset <= 40; offset++) {
        expect(scheduleRow(planStart.add(Duration(days: offset))), isNull,
            reason: 'day $offset: expired plan must write ZERO rows');
      }

      final after = HiveService.instance.workoutBox.get('current_plan');
      expect(jsonEncode(after), jsonEncode(staleBlob),
          reason: 'a blob rewrite backed by zero rows is the round-5 P0 '
              'this test closes — current_plan must be untouched');
    });

    test(
        'misaligned planEnd: no schedule row lands for any date strictly '
        'after planEnd even though today shares its raw-week bucket',
        () async {
      final planStart = DateTime(2026, 6, 1); // a Monday
      await seedFirstGeneration(planStart);
      // Mid-week-misaligned plan_end (30 % 7 == 2, not 6) — the shape a
      // redoWeek4 tap on a non-Monday produces.
      final misalignedEnd = planStart.add(const Duration(days: 30));
      await MigratedKey.write(
          'plan_end_date', misalignedEnd.toIso8601String());

      // today is genuinely PAST planEnd but shares planEnd's raw-week bucket
      // (rawWeekNumberFor(31,0) == rawWeekNumberFor(30,0) == 5) — the exact
      // divergence a week-bucket comparison would miss.
      final today = planStart.add(const Duration(days: 31));
      await svc.generateAndScheduleFromDate(
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
        fromDate: today,
      );

      for (var offset = 31; offset <= 34; offset++) {
        expect(scheduleRow(planStart.add(Duration(days: offset))), isNull,
            reason: 'day $offset is strictly after planEnd(30) — the round-7 '
                'P0 overshoot this test closes');
      }
    });
  });

  group('RegeneratePlanPlanner.plan() + ToolDispatcher (C) — behavioral', () {
    ProviderContainer makeContainer() {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test(
        'late regenStartWeek: full plumbing chain — cache, dispatch, splice',
        () async {
      // planStart 5 weeks before "now" -> regenStartWeek == 6 when startDate
      // is omitted (the AI-coach "regenerate my plan" path).
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final planStart = today.subtract(const Duration(days: 35));
      await MigratedKey.write('plan_start_date', planStart.toIso8601String());

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 2,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.regenStartWeek, 6,
          reason: 'today is 35 days after planStart -> raw week 6');

      // Both a workout-day row (weekIdx 0, dayOfWeek 0 = Monday, pattern
      // [0,1,3,5]) AND a rest-day row (dayOfWeek 2 = Wednesday) must carry
      // effectiveWeek, not the old weekIdx+1 local counter.
      final week1Workout = result.rawSchedules.firstWhere(
          (s) => s['day_of_week'] == 0 && s['type'] == 'workout');
      final week1Rest = result.rawSchedules
          .firstWhere((s) => s['day_of_week'] == 2 && s['type'] == 'rest');
      expect(week1Workout['week'], 6);
      expect(week1Rest['week'], 6);
      // The second requested week is identified by its stamp, not by row
      // order — firstWhere(day_of_week == 0) may land on either week.
      final week2 = result.rawSchedules
          .where((s) => s['week'] == 7)
          .toList();
      expect(week2, isNotEmpty,
          reason: 'the second requested week must stamp effectiveWeek == 7');

      final intentId = 'intent_oi166_c1';
      RegeneratePlanPlanner.instance.cache(
        intentId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );
      expect(RegeneratePlanPlanner.instance.getCachedPhase(intentId),
          same(result.phase));
      expect(
          RegeneratePlanPlanner.instance.getCachedRegenStartWeek(intentId),
          6);

      final c = makeContainer();
      final ref = c.read(_refProvider);
      final intent = ToolIntent(
        id: intentId,
        type: 'regenerate_plan_block',
        payload: const {'goal': 'general_fitness'},
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: '',
        createdAt: DateTime.now(),
      );
      final res = await ToolDispatcher.instance.execute(ref, intent);
      expect(res.success, isTrue);

      // The schedule rows actually landed in Hive, not just the cache.
      final firstDate = week1Workout['date'] as String;
      final firstParsed = DateTime.parse(firstDate);
      final landed = scheduleRow(firstParsed);
      expect(landed, isNotNull);
      expect(landed!['week'], 6);

      // current_plan is non-null and spliced AFTER the commit-site write —
      // regenStartWeek(6) > 4 so every entry is freshly cycled.
      final plan = HiveService.instance.workoutBox.get('current_plan');
      expect(plan, isA<Map>());
      final weekPlans = (plan as Map)['week_plans'] as List;
      expect(weekPlans.length, 4);
      const expectedCharacters = ['baseline', 'overreach', 'peak', 'deload'];
      for (var i = 0; i < 4; i++) {
        expect(
            (weekPlans[i] as Map)['week_character'], expectedCharacters[i]);
      }

      // Cache cleared after execution.
      expect(RegeneratePlanPlanner.instance.getCachedPhase(intentId), isNull);
      expect(RegeneratePlanPlanner.instance.getCachedRawSchedules(intentId),
          isNull);
    });

    test(
        'explicit startDate: byte-identical to pre-fix stamping (guard '
        'excludes this branch)',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // Same late-regenStartWeek STATE as the test above...
      final planStart = today.subtract(const Duration(days: 35));
      await MigratedKey.write('plan_start_date', planStart.toIso8601String());

      // ...but an explicit startDate is supplied, which must fall straight
      // through the guard untouched (pre-fix C never read planStart at all).
      // weeks:6 (not 2) is DELIBERATE — weekIdx must reach >=4 to exercise
      // the OLD "repeat-last" content selection v10 requires this branch to
      // keep, as opposed to contentFlavorIndex's cycling. A weeks:2 run
      // cannot tell the two forms apart (post-implementation verification
      // caught a real regression here: the first draft applied
      // contentFlavorIndex unconditionally, silently starting to CYCLE this
      // out-of-scope branch's content instead of repeating the last week —
      // undetected by the narrower weeks:2 version of this exact test).
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 6,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
        startDate: DateTime(2026, 1, 5).toIso8601String(),
      );

      expect(result.regenStartWeek, isNull,
          reason: 'null signals the ToolDispatcher commit sites to skip the '
              'current_plan splice entirely — the pre-existing (unchanged) '
              'behaviour for an explicit-startDate call');

      final week1 = result.rawSchedules.firstWhere((s) => s['day_of_week'] == 0);
      final week2 = result.rawSchedules.where((s) => s['week'] == 2).toList();
      expect(week1['week'], 1, reason: 'byte-identical to pre-fix weekIdx+1');
      expect(week2, isNotEmpty);
      expect(week1['week_character'], 'baseline',
          reason: 'contentFlavorIndex(1) == 0, same index the old '
              'weekIdx<length ternary picked for weekIdx==0');

      final week5 = result.rawSchedules
          .where((s) => s['week'] == 5 && s['day_of_week'] == 0)
          .toList();
      expect(week5, isNotEmpty,
          reason: 'weekIdx==4 (real week 5) must still be written — '
              '"week" stamping is byte-identical to pre-fix regardless of '
              'content selection');
      expect(week5.first['week_character'], 'deload',
          reason: 'OLD "repeat-last" behaviour (weekIdx>=4 -> '
              'phase.weekPlans.last, the deload week) — NOT '
              'contentFlavorIndex(5)==0 ("baseline"), which is what the '
              'guarded content-selection ternary must NOT degrade to for '
              'an explicit-startDate call. This is the regression this '
              'widened test exists to pin.');
    });

    test(
        'all rows already-completed race: current_plan splice must be '
        'SKIPPED — a rewrite backed by zero written rows is the exact '
        'round-5 P0 writer B already closes via writeRangeIsNotEmpty, '
        'reopened for writer C and closed here (B-pass finding 3)',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final planStart = today.subtract(const Duration(days: 35));
      await MigratedKey.write('plan_start_date', planStart.toIso8601String());

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 1,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.regenStartWeek, isNotNull,
          reason: 'splice-relevant path — an explicit-startDate call would '
              'already skip the splice for an unrelated (pre-existing) '
              'reason');
      expect(result.rawSchedules, isNotEmpty);

      // Simulate the race the dispatcher's own "Concurrent-edit safety net"
      // comment names: every date this regen would touch was independently
      // completed between diff-preview (plan()) and confirm (dispatch), so
      // the per-row `continue` fires on ALL of them and zero rows actually
      // get written.
      for (final s in result.rawSchedules) {
        final d = DateTime.parse(s['date'] as String);
        await HiveService.instance.workoutBox
            .put(scheduleKeyFor(d), {'status': 'completed'});
      }

      final staleBlob = {
        'week_plans': [
          for (var i = 0; i < 4; i++) {'week_character': 'PRE_REGEN_RACE_$i'},
        ],
      };
      await HiveService.instance.workoutBox
          .put('current_plan', Map<String, dynamic>.from(staleBlob));

      final intentId = 'intent_oi166_c_race';
      RegeneratePlanPlanner.instance.cache(
        intentId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );

      final c = makeContainer();
      final ref = c.read(_refProvider);
      final intent = ToolIntent(
        id: intentId,
        type: 'regenerate_plan_block',
        payload: const {'goal': 'general_fitness'},
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: '',
        createdAt: DateTime.now(),
      );
      final res = await ToolDispatcher.instance.execute(ref, intent);
      expect(res.success, isTrue,
          reason: 'every row skipped via the completed-guard is not an '
              'error — a partial/empty regen still reports success');

      final after = HiveService.instance.workoutBox.get('current_plan');
      expect(jsonEncode(after), jsonEncode(staleBlob),
          reason: 'zero rows landed — current_plan must stay byte-identical, '
              'never rewritten with fresh cycled content backed by nothing');
    });

    test(
        'malformed existing week_plans (present but not a List) does not '
        'throw — degrades to fresh content, matching currentWaveCharacters\' '
        'own crash-safe posture for this exact blob (B-pass finding 4)',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      // regenStartWeek == 2 -> preserveBefore == 1, so index 0 is a genuine
      // "should preserve" candidate and the malformed read is actually
      // reached (regenStartWeek > 4 would give preserveBefore == 0 and never
      // touch the existing blob at all).
      final planStart = today.subtract(const Duration(days: 7));
      await MigratedKey.write('plan_start_date', planStart.toIso8601String());

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 1,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.regenStartWeek, 2);

      await HiveService.instance.workoutBox
          .put('current_plan', {'week_plans': 'not_a_list'});

      final intentId = 'intent_oi166_c_malformed_notalist';
      RegeneratePlanPlanner.instance.cache(
        intentId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );

      final c = makeContainer();
      final ref = c.read(_refProvider);
      final intent = ToolIntent(
        id: intentId,
        type: 'regenerate_plan_block',
        payload: const {'goal': 'general_fitness'},
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: '',
        createdAt: DateTime.now(),
      );

      // The whole point of this test: this must not throw.
      final res = await ToolDispatcher.instance.execute(ref, intent);
      expect(res.success, isTrue);

      final after = HiveService.instance.workoutBox.get('current_plan');
      expect(after, isA<Map>());
      final weekPlans = (after as Map)['week_plans'] as List;
      expect(weekPlans.length, 4);
      expect((weekPlans[0] as Map)['week_character'], 'baseline',
          reason: 'index 0 could not be preserved from a non-List '
              'week_plans — must degrade to fresh content, not throw and '
              'not propagate the malformed value');
    });

    test(
        'malformed existing week_plans entry (List, but element not a Map) '
        'does not throw — degrades to fresh content for that position '
        '(B-pass finding 4)',
        () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final planStart = today.subtract(const Duration(days: 7));
      await MigratedKey.write('plan_start_date', planStart.toIso8601String());

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 1,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.regenStartWeek, 2);

      await HiveService.instance.workoutBox.put('current_plan', {
        'week_plans': [
          'not_a_map',
          {'week_character': 'overreach'},
          {'week_character': 'peak'},
          {'week_character': 'deload'},
        ],
      });

      final intentId = 'intent_oi166_c_malformed_entry';
      RegeneratePlanPlanner.instance.cache(
        intentId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );

      final c = makeContainer();
      final ref = c.read(_refProvider);
      final intent = ToolIntent(
        id: intentId,
        type: 'regenerate_plan_block',
        payload: const {'goal': 'general_fitness'},
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: '',
        createdAt: DateTime.now(),
      );

      // The whole point of this test: this must not throw.
      final res = await ToolDispatcher.instance.execute(ref, intent);
      expect(res.success, isTrue);

      final after = HiveService.instance.workoutBox.get('current_plan');
      expect(after, isA<Map>());
      final weekPlans = (after as Map)['week_plans'] as List;
      expect(weekPlans.length, 4);
      expect((weekPlans[0] as Map)['week_character'], 'baseline',
          reason: 'index 0\'s existing entry was a String, not a Map — must '
              'degrade to fresh content, not throw');
    });
  });
}
