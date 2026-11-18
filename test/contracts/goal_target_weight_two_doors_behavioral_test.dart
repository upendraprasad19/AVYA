// OI-191: the goal and the target weight agree on EVERY door that changes the goal.
//
// Door 1 (this file, part 1): the coach `switch_goal`, driven end to end through
// the real planner -> cache -> `ToolDispatcher.execute` contract on real Hive
// (the harness of `oi189_plan_end_bound_behavioral_test.dart`). The expired-phase
// scenario has no schedule rows to write, so the profile write is the only
// effect under test. Door 2 (Edit Profile) is in part 2 below.
//
// The oracle for the recomputed targets is `recomputeDerivedTargets` on the
// healed inputs: the SAME function Edit Profile's `recalculateTargets` calls, so
// "both doors write the same numbers" is what the assertions say.
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
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/regenerate_plan_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/profile/services/profile_target_recompute.dart';

final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const first = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  const second = 'dddddddd-0000-0000-0000-000000000000';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_oi191_two_doors');
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
      'userBox_dddddddd',
      'workoutBox_dddddddd',
      'nutritionBox_dddddddd',
      'healthBox_dddddddd',
      'coachBox_dddddddd',
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
    final rows =
        jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put((r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(first);
    SyncService.pausedForSimulation = true;
  });

  tearDown(() async {
    ToolDispatcher.debugBeforeSwitchGoalProfileWrite = null;
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  group('coach switch_goal writes goal, target weight and targets together', () {
    ProviderContainer makeContainer() {
      final c = ProviderContainer(overrides: [
        authStateProvider.overrideWith((ref) => const Stream.empty()),
        authUserIdTokenProvider.overrideWithValue(first),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    int idSeq = 0;
    ToolIntent intentFor(String id, String goal) => ToolIntent(
          id: id,
          type: 'switch_goal',
          payload: {'new_goal': goal},
          confirmationClass: ConfirmationClass.reviewable,
          previewSummary: '',
          createdAt: DateTime.now(),
        );

    /// An EXPIRED phase: the plan window ended 35 days ago, so the regenerated
    /// block is empty and the profile write is the only effect.
    Future<void> seedExpiredWindow() async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final start = today.subtract(const Duration(days: 62));
      await MigratedKey.write('plan_start_date', start.toIso8601String());
      await MigratedKey.write('plan_end_date',
          start.add(const Duration(days: 27)).toIso8601String());
    }

    Map<String, dynamic> profile({
      String goal = 'lose_fat',
      double target = 71.0,
    }) =>
        {
          'primary_goal': goal,
          'current_weight_kg': 75.0,
          'target_weight_kg': target,
          'height_cm': 175.0,
          'gender': 'male',
          'date_of_birth': '1995-06-15',
          'activity_level': 'moderate',
          'days_per_week': 4,
          'fitness_experience': 'intermediate',
          'pace_preference': 'balanced',
          // Stale values from the OLD goal, so a write is visible.
          'daily_calories': 2000,
          'protein_grams': 150,
        };

    Future<ToolExecutionResult> switchTo(
      String goal, {
      ProviderContainer? container,
    }) async {
      final id = 'intent_oi191_${idSeq++}';
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 4,
        goal: goal,
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      RegeneratePlanPlanner.instance.cache(
        id,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );
      return ToolDispatcher.instance.execute(
        (container ?? makeContainer()).read(_refProvider),
        intentFor(id, goal),
      );
    }

    Map<dynamic, dynamic> stored() =>
        HiveService.instance.userBox.get('profile') as Map;

    test('Cut 71 kg -> Build: the target is seeded and the targets are recomputed', () async {
      await seedExpiredWindow();
      final before = profile();
      await HiveService.instance.userBox.put('profile', before);
      final res = await switchTo('build_muscle');
      expect(res.success, isTrue, reason: '${res.data}');
      final p = stored();
      expect(p['primary_goal'], 'build_muscle');
      expect(p['target_weight_kg'], 78.0, reason: 'Build needs a target above 75 kg');
      final expected = recomputeDerivedTargets(
        <String, dynamic>{...before, 'primary_goal': 'build_muscle', 'target_weight_kg': 78.0},
        now: DateTime.now(),
        bodyFatCalcDisabled: false,
      )!;
      for (final k in ['daily_calories', 'protein_grams', 'carb_grams', 'carbs_grams', 'fat_grams']) {
        expect(p[k], expected[k], reason: k);
      }
      expect(p['daily_calories'], isNot(2000), reason: 'the old goal\'s calories were replaced');
      expect(p['previous_goal'], 'lose_fat');
      expect(p['goal_changed_via'], 'ai_coach');
    });

    test('a target that already fits the new goal is kept', () async {
      await seedExpiredWindow();
      await HiveService.instance.userBox.put('profile', profile(goal: 'general_fitness', target: 80.0));
      final res = await switchTo('build_muscle');
      expect(res.success, isTrue);
      expect(stored()['target_weight_kg'], 80.0);
      expect(stored()['primary_goal'], 'build_muscle');
    });

    test('a profile with no birth date gets the goal and the seed, never a partial target set', () async {
      await seedExpiredWindow();
      final p = profile()..remove('date_of_birth');
      await HiveService.instance.userBox.put('profile', p);
      final res = await switchTo('build_muscle');
      expect(res.success, isTrue);
      expect(stored()['target_weight_kg'], 78.0);
      expect(stored()['daily_calories'], 2000, reason: 'no overlay without a complete profile');
    });

    test('a switch to the goal the profile already has moves no stored value', () async {
      await seedExpiredWindow();
      await HiveService.instance.userBox.put('profile', profile(goal: 'lose_fat', target: 70.0));
      final res = await switchTo('lose_fat');
      expect(res.success, isTrue);
      expect(stored()['daily_calories'], 2000);
      expect(stored()['target_weight_kg'], 70.0);
    });

    test('the profile readers are refreshed: a cached userProfileProvider sees the new goal', () async {
      await seedExpiredWindow();
      await HiveService.instance.userBox.put('profile', profile());
      final c = makeContainer();
      expect(c.read(userProfileProvider)['primary_goal'], 'lose_fat');
      final res = await switchTo('build_muscle', container: c);
      expect(res.success, isTrue);
      expect(c.read(userProfileProvider)['primary_goal'], 'build_muscle');
    });

    test('a free user\'s cached prediction is marked stale by the switch', () async {
      await seedExpiredWindow();
      await HiveService.instance.userBox.put('profile', profile());
      await switchTo('build_muscle');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(MigratedKey.read<bool>('prediction_stale'), isTrue);
    });

    test('an account switch after the sweep and before the write: nothing is written to either account', () async {
      await seedExpiredWindow();
      await HiveService.instance.userBox.put('profile', profile());
      // The switch lands where a real one would. The second account holds a Cut
      // profile too, so a write that read the owner at write time would land there.
      ToolDispatcher.debugBeforeSwitchGoalProfileWrite = () async {
        await HiveUserSession.openForUser(second);
        await HiveService.instance.userBox.put('profile', profile());
      };
      final res = await switchTo('build_muscle');
      expect(res.success, isFalse);
      expect(stored()['primary_goal'], 'lose_fat', reason: 'the second account was not written');
      expect(stored()['target_weight_kg'], 71.0);
      await HiveUserSession.openForUser(first);
      expect(stored()['primary_goal'], 'lose_fat', reason: 'nor the first');
      expect(stored()['target_weight_kg'], 71.0);
      expect(stored()['daily_calories'], 2000);
    });
  });

  group('source order pins (presence only; the behaviour is above)', () {
    final src = File('lib/features/ai_coach/services/tool_dispatcher.dart').readAsStringSync();
    final a = src.indexOf('Future<ToolExecutionResult> _executeSwitchGoal(');
    final b = src.indexOf('Future<ToolExecutionResult> _executeCreateCustomTemplate(');
    final body = src.substring(a, b);

    test('the owner is captured before the sweep, and the write is patchProfileWith', () {
      final capture = body.indexOf('HiveUserSession.currentOwnerFullId');
      final sweep = body.indexOf('.sweepNonCompletedRowsPastPlanEnd()');
      expect(capture, isNonNegative);
      expect(capture, lessThan(sweep));
      expect(body.contains('patchProfileWith('), isTrue);
      expect(body.contains('stillOwner: owned'), isTrue);
      expect(RegExp(r'patchProfile\(').hasMatch(body), isFalse,
          reason: 'the unguarded write must not come back');
    });

    test('the profile readers are invalidated right after the write, before any schedule write', () {
      final inv = body.indexOf('invalidateProfileDerivedSurfaces(ref.invalidate');
      final loop = body.indexOf('for (final schedule in rawSchedules)');
      final write = body.indexOf('patchProfileWith(');
      expect(inv, greaterThan(write));
      expect(inv, lessThan(loop),
          reason: 'every outcome after the write (a failed plan regeneration too) leaves the readers fresh');
    });
  });
}
