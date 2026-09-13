// Behavioral — OI-189 (diagnose b9e4d1): every phase-layout writer stops at
// the STORED plan_end, both regen paths SWEEP non-completed rows already past
// it, and every writer that moves the window pushes plan_json immediately.
//
// Why a sweep is needed at all: both regen writers stop their WRITE range at
// plan_end (generateAndScheduleFromDate — Unit 2; RegeneratePlanPlanner.plan
// — this unit), so a row already past plan_end is neither rewritten nor
// deleted by a regen. Such rows exist(ed) from the pre-Unit-2 Edit-Profile
// loop, the coach path before its bound, and three user-directed writers that
// accept an arbitrary date. Left alone they keep the OLD goal's workouts after
// a goal change AND keep isPhaseExpiredFrom reporting the phase alive, which
// blocks the next phase from ever generating (OI-174's advance-delay half).
//
// Why the pushes: pushSnapshot is the daily-snapshot EF and syncWorkoutData
// runs _syncScheduledWorkouts only — neither carries plan_json — while
// _restoreWorkoutPlan mirrors the cloud plan_json back on EVERY launch. A
// sweep that is not pushed comes back tomorrow; a window move that is not
// pushed can be reverted by PlanWindowReanchor (diagnose c9e4b7).
//
// Groups: the shared sweep helper; writer B (Edit-Profile regen); writer C
// (RegeneratePlanPlanner.plan() + both ToolDispatcher commit sites, driven
// through the REAL plan() -> cache() -> execute() contract); and a source-pin
// group for the plan_json pushes, which no offline test can observe.
//
// Harness copied from oi166_unit2_regen_content_cycling_behavioral_test.dart
// (:25-129) — the file that already seeds these boxes and drives the same
// dispatch path.

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
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/regenerate_plan_planner.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/ai_coach/widgets/diff_preview/phase_note.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

/// Exposes a real Riverpod [Ref] so we can drive
/// `ToolDispatcher.execute(ref, intent)` — the REAL dispatch path — mirroring
/// `test/contracts/coach_completion_prompt_test.dart`'s established pattern.
final _refProvider = Provider<Ref>((ref) => ref);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'test_oi189_plan_end_bound',
    );
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
    final rows =
        jsonDecode(File('assets/data/exercise_library.json').readAsStringSync())
            as List;
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
    resetTestClock();
    SyncService.pausedForSimulation = false;
    await HiveUserSession.closeAll();
  });

  final svc = WorkoutScheduleReadService.instance;

  String scheduleKeyFor(DateTime d) => 'schedule_${svc.dateKey(d)}';

  Map<String, dynamic>? scheduleRow(DateTime d) {
    final raw = HiveService.instance.workoutBox.get(scheduleKeyFor(d));
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Future<void> seedWindow(DateTime planStart, {int endOffset = 27}) async {
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write(
      'plan_end_date',
      planStart.add(Duration(days: endOffset)).toIso8601String(),
    );
  }

  Future<void> seedRow(
    DateTime d, {
    String name = 'OLD_GOAL_ORPHAN',
    String status = 'planned',
    String type = 'workout',
  }) async {
    await HiveService.instance.workoutBox.put(scheduleKeyFor(d), {
      'date': svc.dateKey(d),
      'type': type,
      'workout_name': name,
      'status': status,
      'exercises': const <Map<String, dynamic>>[],
    });
  }

  group('sweepNonCompletedRowsPastPlanEnd — helper', () {
    test('removes planned + rest rows and displaced_ shadows past plan_end, '
        'keeps completed rows, never touches rows inside the window; dry run '
        'counts without deleting; idempotent', () async {
      final planStart = DateTime(2026, 6, 1); // Monday
      await seedWindow(planStart); // plan_end = +27
      final box = HiveService.instance.workoutBox;
      for (var offset = 20; offset <= 34; offset++) {
        await seedRow(
          planStart.add(Duration(days: offset)),
          status: offset == 30 ? 'completed' : 'planned',
        );
      }
      // Overwrites the +33 planned row with a rest row (same key).
      await seedRow(
        planStart.add(const Duration(days: 33)),
        type: 'rest',
        status: 'rest',
        name: 'Rest Day',
      );
      final displacedIn =
          'displaced_${svc.dateKey(planStart.add(const Duration(days: 25)))}';
      final displacedOut =
          'displaced_${svc.dateKey(planStart.add(const Duration(days: 29)))}';
      await box.put(displacedIn, {'shadow': true});
      await box.put(displacedOut, {'shadow': true});

      // Past plan_end: workout rows +28,+29,+31,+32,+34 = 5 `workouts` (+30
      // completed excluded); +33 is a rest row and displaced_+29 a shadow —
      // both REMOVED, so `removed` = 7. `workouts` is what the preview shows
      // the user and what _scheduledWorkoutDays keys the expiry on; `removed`
      // is what the dispatcher branches on (Hive changed ⇒ invalidate).
      final dry = await svc.sweepNonCompletedRowsPastPlanEnd(dryRun: true);
      expect(dry.workouts, 5);
      expect(dry.removed, 7);
      expect(
        scheduleRow(planStart.add(const Duration(days: 28))),
        isNotNull,
        reason: 'dry run must not delete',
      );

      final swept = await svc.sweepNonCompletedRowsPastPlanEnd();
      expect(swept.workouts, 5);
      expect(swept.removed, 7);
      for (var offset = 20; offset <= 27; offset++) {
        expect(
          scheduleRow(planStart.add(Duration(days: offset))),
          isNotNull,
          reason: 'in-window row +$offset must survive',
        );
      }
      for (var offset = 28; offset <= 34; offset++) {
        final row = scheduleRow(planStart.add(Duration(days: offset)));
        if (offset == 30) {
          expect(row, isNotNull, reason: 'completed history must survive');
          expect(row!['status'], 'completed');
        } else {
          expect(
            row,
            isNull,
            reason: 'row +$offset past plan_end must be swept',
          );
        }
      }
      expect(box.containsKey(displacedIn), isTrue);
      expect(box.containsKey(displacedOut), isFalse);
      expect(
        (await svc.sweepNonCompletedRowsPastPlanEnd()).removed,
        0,
        reason: 'idempotent: nothing left to sweep',
      );
    });

    // Behaviour-INVARIANT (a helper that always returned 0 would also pass
    // the first half) — the second half is the real pin: plan_end WITHOUT
    // plan_start must not count as a window (F10; restore writes the keys
    // independently, sync/sync_workout.dart:1126,1129).
    test(
      'no stored window (plan_end OR plan_start missing): no-op, returns 0',
      () async {
        final stray = DateTime(2027, 1, 4);
        await seedRow(stray, name: 'STRAY');
        expect((await svc.sweepNonCompletedRowsPastPlanEnd()).removed, 0);
        expect(scheduleRow(stray), isNotNull);
        await MigratedKey.write(
          'plan_end_date',
          DateTime(2026, 6, 28).toIso8601String(),
        );
        expect(
          (await svc.sweepNonCompletedRowsPastPlanEnd()).removed,
          0,
          reason: 'a half-restored window is not a window',
        );
        expect(scheduleRow(stray), isNotNull);
      },
    );

    // Review B-2 (bpass finding 2): the completed-row exemption used to only
    // ever look at `isSchedule` rows, so a `displaced_*` shadow carrying
    // `status: 'completed'` was swept like any other orphan — the only
    // writer of `displaced_*` (template_service.dart's assignTemplateToDate)
    // happens to refuse that shape, but the sweep must not depend on a
    // DIFFERENT file's discipline for its own safety property.
    test(
      'a displaced_ shadow with status: completed past plan_end survives',
      () async {
        final planStart = DateTime(2026, 6, 1);
        await seedWindow(planStart); // plan_end = +27
        final box = HiveService.instance.workoutBox;
        final completedDisplaced =
            'displaced_${svc.dateKey(planStart.add(const Duration(days: 30)))}';
        await box.put(completedDisplaced, {
          'shadow': true,
          'status': 'completed',
        });
        final swept = await svc.sweepNonCompletedRowsPastPlanEnd();
        expect(swept.removed, 0);
        expect(
          box.containsKey(completedDisplaced),
          isTrue,
          reason: 'a completed displaced shadow is history and stays, same '
              'rule as a completed schedule_ row',
        );
      },
    );
  });

  group('writer B — generateAndScheduleFromDate sweeps past plan_end', () {
    test('mid-window regen: orphans +28..+34 swept (completed kept), '
        'in-window planned row rewritten, plan_end unchanged', () async {
      final planStart = DateTime(2026, 6, 1);
      await seedWindow(planStart);
      setTestClockTo(planStart.add(const Duration(days: 10)));
      for (var offset = 28; offset <= 34; offset++) {
        await seedRow(
          planStart.add(Duration(days: offset)),
          status: offset == 30 ? 'completed' : 'planned',
        );
      }
      final inWindow = planStart.add(const Duration(days: 20));
      await seedRow(inWindow, name: 'OLD_GOAL_IN_WINDOW');

      await svc.generateAndScheduleFromDate(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        fromDate: planStart.add(const Duration(days: 10)),
      );

      for (var offset = 28; offset <= 34; offset++) {
        final row = scheduleRow(planStart.add(Duration(days: offset)));
        if (offset == 30) {
          expect(row, isNotNull, reason: 'completed history must survive');
          expect(row!['workout_name'], 'OLD_GOAL_ORPHAN');
        } else {
          expect(
            row,
            isNull,
            reason: 'planned orphan at +$offset must be swept',
          );
        }
      }
      final rewritten = scheduleRow(inWindow);
      expect(rewritten, isNotNull);
      expect(rewritten!['workout_name'], isNot('OLD_GOAL_IN_WINDOW'));
      expect(svc.getPlanEndDate(), planStart.add(const Duration(days: 27)));
    });

    test(
      'EXPIRED-phase regen (today > plan_end, orphans on/after today): '
      'writes nothing, sweeps the orphans, isPhaseExpired() flips false→true',
      () async {
        final planStart = DateTime(2026, 6, 1);
        await seedWindow(planStart);
        final today = planStart.add(const Duration(days: 29));
        setTestClockTo(today); // isPhaseExpired() reads nowWall()
        for (var offset = 29; offset <= 34; offset++) {
          await seedRow(planStart.add(Duration(days: offset)));
        }
        expect(
          svc.isPhaseExpired(),
          isFalse,
          reason: 'orphan workout rows on/after today keep the phase alive',
        );

        await svc.generateAndScheduleFromDate(
          goal: 'lose_fat',
          equipment: 'full_gym',
          daysPerWeek: 4,
          fromDate: today,
        );

        for (var offset = 28; offset <= 41; offset++) {
          expect(
            scheduleRow(planStart.add(Duration(days: offset))),
            isNull,
            reason:
                'nothing may exist past plan_end after the regen (+$offset)',
          );
        }
        expect(svc.isPhaseExpired(), isTrue);
      },
    );

    // Behaviour-INVARIANT (documents the first-generation boundary).
    test('first generation (no stored window): a stray far-future row is left '
        'alone — there is no horizon to sweep against', () async {
      final stray = DateTime(2027, 1, 4);
      await seedRow(stray, name: 'STRAY');
      await svc.generateAndScheduleFromDate(
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
        fromDate: DateTime(2026, 6, 3),
      );
      expect(scheduleRow(stray), isNotNull);
    });
  });

  group('writer C — RegeneratePlanPlanner.plan() stops at plan_end', () {
    ProviderContainer makeContainer() {
      final c = ProviderContainer(
        overrides: [
          authStateProvider.overrideWith((ref) => const Stream.empty()),
          // Makes todayWorkoutProvider resolvable hermetically: its Notifier
          // watches authUserIdTokenProvider (auth_invalidation_provider.dart:48)
          // which in production derives from the live session/owner edge.
          authUserIdTokenProvider.overrideWithValue(testUser),
        ],
      );
      addTearDown(c.dispose);
      return c;
    }

    ToolIntent intentFor(
      String id,
      String type, [
      Map<String, dynamic> payload = const {'goal': 'general_fitness'},
    ]) => ToolIntent(
      id: id,
      type: type,
      payload: payload,
      confirmationClass: ConfirmationClass.reviewable,
      previewSummary: '',
      createdAt: DateTime.now(),
    );

    test('4 weeks requested, 10 days left: rows stop at plan_end (inclusive), '
        'totalWeeks 2, requestedWeeks 4, phaseEndsOn stamped, clears 0; '
        'dispatch lands nothing past plan_end', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final planStart = today.subtract(const Duration(days: 14));
      final planEnd = today.add(const Duration(days: 10));
      await seedWindow(planStart, endOffset: 24);

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 4,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.rawSchedules, isNotEmpty);
      for (final s in result.rawSchedules) {
        expect(
          DateTime.parse(s['date'] as String).isAfter(planEnd),
          isFalse,
          reason: 'row ${s['date']} is past plan_end ${svc.dateKey(planEnd)}',
        );
      }
      expect(result.plan.totalWeeks, 2);
      expect(result.plan.requestedWeeks, 4);
      expect(result.plan.phaseEndsOn, svc.dateKey(planEnd));
      expect(result.plan.clearsPastPhaseEnd, 0);
      expect(
        result.rawSchedules.any((s) => s['date'] == svc.dateKey(planEnd)),
        isTrue,
        reason: 'every non-completed in-window day gets a row',
      );

      const intentId = 'intent_oi189_c1';
      RegeneratePlanPlanner.instance.cache(
        intentId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );
      final res = await ToolDispatcher.instance.execute(
        makeContainer().read(_refProvider),
        intentFor(intentId, 'regenerate_plan_block'),
      );
      expect(res.success, isTrue);
      for (var offset = 11; offset <= 28; offset++) {
        expect(
          scheduleRow(today.add(Duration(days: offset))),
          isNull,
          reason: 'no row may exist at today+$offset (past plan_end)',
        );
      }
      expect(scheduleRow(planEnd), isNotNull);
    });

    test(
      'block FITS the phase but rows exist past plan_end: clearsPastPhaseEnd '
      'reports them (D2: the preview must say what the commit sweeps)',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await seedWindow(
          today.subtract(const Duration(days: 7)),
          endOffset: 27,
        );
        final planEnd = today.add(const Duration(days: 20));
        await seedRow(
          planEnd.add(const Duration(days: 3)),
          name: 'HOTEL_PAST_END',
        );
        final result = await RegeneratePlanPlanner.instance.plan(
          weeks: 2,
          goal: 'general_fitness',
          equipment: 'full_gym',
          daysPerWeek: 4,
        );
        expect(result.plan.totalWeeks, 2);
        expect(result.plan.requestedWeeks, 2);
        expect(result.plan.clearsPastPhaseEnd, 1);
        expect(
          scheduleRow(planEnd.add(const Duration(days: 3))),
          isNotNull,
          reason: 'plan() is a preview — it must not sweep',
        );
      },
    );

    test(
      'explicit startDate past plan_end: zero rows, totalWeeks 0 — the bound '
      'applies to every plan() call',
      () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        await seedWindow(
          today.subtract(const Duration(days: 14)),
          endOffset: 24,
        );
        final planEnd = today.add(const Duration(days: 10));
        final result = await RegeneratePlanPlanner.instance.plan(
          weeks: 2,
          goal: 'general_fitness',
          equipment: 'full_gym',
          daysPerWeek: 4,
          startDate: svc.dateKey(planEnd.add(const Duration(days: 1))),
        );
        expect(result.rawSchedules, isEmpty);
        expect(result.plan.totalWeeks, 0);
        expect(
          result.regenStartWeek,
          isNull,
          reason: 'explicit-startDate contract unchanged',
        );
      },
    );

    // Behaviour-INVARIANT (pre-existing behaviour, kept).
    test('no plan_end stored: block stays unbounded', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await MigratedKey.write(
        'plan_start_date',
        today.subtract(const Duration(days: 7)).toIso8601String(),
      );
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 3,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.plan.totalWeeks, 3);
      expect(result.plan.requestedWeeks, 3);
      expect(result.plan.phaseEndsOn, isNull);
      expect(result.plan.clearsPastPhaseEnd, 0);
      expect(
        result.rawSchedules.any(
          (s) => DateTime.parse(
            s['date'] as String,
          ).isAfter(today.add(const Duration(days: 14))),
        ),
        isTrue,
        reason: 'week 3 rows exist when nothing bounds the block',
      );
    });

    test('EXPIRED phase + orphans: plan() reports clearsPastPhaseEnd; dispatch '
        'sweeps them and returns SUCCESS with count 0 / cleared 7 (so the '
        'invalidate tail runs); a second dispatch (nothing left to sweep) is '
        'the failure; isPhaseExpired() flips', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await seedWindow(today.subtract(const Duration(days: 35)), endOffset: 30);
      // plan_end = today-5; orphans today-4..today+3 (8 rows), the completed
      // one BEFORE today (a completed row can only be in the past; and
      // _scheduledWorkoutDays filters by type, not status, so a future-dated
      // completed row would itself keep the phase alive).
      for (var offset = -4; offset <= 3; offset++) {
        await seedRow(
          today.add(Duration(days: offset)),
          status: offset == -2 ? 'completed' : 'planned',
        );
      }
      expect(
        svc.isPhaseExpired(),
        isFalse,
        reason: 'planned orphan rows on/after today keep the phase alive',
      );

      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 4,
        goal: 'general_fitness',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.rawSchedules, isEmpty);
      expect(result.plan.totalWeeks, 0);
      expect(result.plan.firstWeek, isEmpty);
      expect(result.plan.clearsPastPhaseEnd, 7, reason: '8 rows, 1 completed');
      expect(
        scheduleRow(today),
        isNotNull,
        reason: 'plan() is a preview — it must not sweep',
      );

      const intentId = 'intent_oi189_c2';
      RegeneratePlanPlanner.instance.cache(
        intentId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );
      final container = makeContainer();
      final ref = container.read(_refProvider);
      // The Home expired-card gate is `todayWorkoutProvider == null &&
      // isPhaseExpired()`; the provider is non-autoDispose, so the dispatch
      // that sweeps today's row must reach execute()'s invalidation tail or
      // the card never shows. That tail runs only on SUCCESS — which is why a
      // sweep that removed something returns success (round 3 F2).
      expect(
        container.read(todayWorkoutProvider),
        isNotNull,
        reason: 'today has an orphan row before dispatch',
      );

      final res = await ToolDispatcher.instance.execute(
        ref,
        intentFor(intentId, 'regenerate_plan_block'),
      );
      expect(
        res.success,
        isTrue,
        reason: 'the sweep changed Hive — success so the invalidate tail runs',
      );
      final data = res.data as Map?;
      expect(data, isNotNull);
      expect(data!['count'], 0);
      expect(data['cleared'], 7);
      for (var offset = -4; offset <= 3; offset++) {
        final row = scheduleRow(today.add(Duration(days: offset)));
        expect(
          row,
          offset == -2 ? isNotNull : isNull,
          reason: 'commit sweeps planned orphans ($offset), keeps completed',
        );
      }
      expect(
        svc.isPhaseExpired(),
        isTrue,
        reason: 'only the past completed row remains — nothing on/after today',
      );
      expect(
        container.read(todayWorkoutProvider),
        isNull,
        reason: 'execute() invalidated the workout providers on success',
      );

      // Nothing left to sweep AND nothing to write → the honest refusal.
      // Under a NEW intent id (round 4 F1): execute() writes
      // `intent_<id>_dispatched_at` to coachBox after every success
      // (tool_dispatcher.dart:215-219) and short-circuits a re-dispatch of the
      // SAME id to success before the handler runs (:103-110) — so re-using
      // intentId here would assert against the idempotency marker, not the
      // refusal. A new id is also what the real flow produces: the model
      // emits a fresh intent when the user re-asks. Re-cached first, exactly
      // as a re-opened preview does (the success above cleared the cache).
      const retryId = 'intent_oi189_c2b';
      RegeneratePlanPlanner.instance.cache(
        retryId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );
      final again = await ToolDispatcher.instance.execute(
        ref,
        intentFor(retryId, 'regenerate_plan_block'),
      );
      expect(again.success, isFalse);
      expect(again.errorMessage, contains('Nothing left to regenerate'));
    });

    test('switch_goal on an expired phase with orphans: goal changes, orphans '
        'swept, success with count 0', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await seedWindow(today.subtract(const Duration(days: 35)), endOffset: 34);
      // patchProfile merges into this map; its _fireSync short-circuits when
      // SupabaseService.currentUser is null (uninitialised, this harness).
      await HiveService.instance.userBox.put('profile', {
        'primary_goal': 'general_fitness',
        'days_per_week': 4,
        'fitness_experience': 'intermediate',
      });
      for (var offset = 0; offset <= 3; offset++) {
        await seedRow(today.add(Duration(days: offset)));
      }
      final result = await RegeneratePlanPlanner.instance.plan(
        weeks: 4,
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
      );
      expect(result.rawSchedules, isEmpty);
      const intentId = 'intent_oi189_c3';
      RegeneratePlanPlanner.instance.cache(
        intentId,
        result.plan,
        result.rawSchedules,
        result.phase,
        result.regenStartWeek,
      );
      final res = await ToolDispatcher.instance.execute(
        makeContainer().read(_refProvider),
        intentFor(intentId, 'switch_goal', const {'new_goal': 'build_muscle'}),
      );
      expect(res.success, isTrue);
      final data = res.data as Map?;
      expect(data, isNotNull);
      expect(data!['count'], 0);
      expect(data['cleared'], 4);
      final profile = HiveService.instance.userBox.get('profile') as Map;
      expect(profile['primary_goal'], 'build_muscle');
      for (var offset = 0; offset <= 3; offset++) {
        expect(scheduleRow(today.add(Duration(days: offset))), isNull);
      }
      expect(svc.isPhaseExpired(), isTrue);
    });
  });

  // ── OI-189 — the plan_json pushes (five sites, six blocks) exist, sit AFTER
  // the writes they carry, and writer A pushes ONLY on a phase advance ─────
  //
  // Source pins, not behavioural assertions: SyncService.instance is a live
  // singleton whose _syncWorkoutPlan needs a Supabase client, so no offline
  // test can observe the push (OI-171 precedent, deload_eval_behavioral_test
  // .dart:722-763). Position IS the defect class — a push placed above the
  // rows/blob it must carry snapshots the pre-write state — and the
  // pushPlanWindow wiring is a contract about WHICH call sites push, which is
  // a census of source, not a runtime state.
  group('OI-189 — plan_json push placement + pushPlanWindow wiring', () {
    final readSrc = File(
      'lib/core/services/workout_schedule_read_service.dart',
    ).readAsStringSync();
    final aStart = readSrc.indexOf('Future<Phase> generateAndSchedule({');
    final bStart = readSrc.indexOf(
      'Future<Phase> generateAndScheduleFromDate({',
    );
    final autoStart = readSrc.indexOf('autoGenerateNextPhaseIfNeeded({');
    final aBody = readSrc.substring(aStart, bStart);
    final bBody = readSrc.substring(bStart, autoStart);
    const push = 'pushWorkoutPlanForSyncDomain()';
    const rowWrite = 'source: WriteSource.planGenerator';

    test('writer A: push exists, is gated on pushPlanWindow, and sits after '
        'the last row write', () {
      expect(aBody.contains('bool pushPlanWindow = false'), isTrue);
      expect(push.allMatches(aBody).length, 1);
      final gate = aBody.indexOf('if (pushPlanWindow)');
      final pushAt = aBody.indexOf(push);
      expect(gate, isNonNegative);
      expect(
        pushAt,
        greaterThan(gate),
        reason: 'the push must be INSIDE the pushPlanWindow gate',
      );
      expect(
        pushAt,
        greaterThan(aBody.lastIndexOf(rowWrite)),
        reason: 'a push above the rows snapshots the previous phase',
      );
    });

    test('writer B: sweep sits after the delete loop and before the window '
        'write; push sits after the last row write', () {
      final sweep = bBody.indexOf('await sweepNonCompletedRowsPastPlanEnd()');
      final windowWrite = bBody.indexOf('MigratedKey.write(_planEndKey');
      final pushAt = bBody.indexOf(push);
      expect(sweep, isNonNegative);
      expect(push.allMatches(bBody).length, 1);
      expect(
        sweep,
        lessThan(windowWrite),
        reason:
            'the sweep reads the STORED window, so it must run before a '
            'first generation writes a new one',
      );
      expect(pushAt, greaterThan(bBody.lastIndexOf(rowWrite)));
    });

    test('pushPlanWindow: true at exactly the two phase-advance sites', () {
      final autoBody = readSrc.substring(autoStart);
      expect(
        'pushPlanWindow: true'.allMatches(autoBody).length,
        1,
        reason: 'autoGenerateNextPhaseIfNeeded is a phase advance',
      );
      final pro = File(
        'lib/shared/services/pro_phase_advance.dart',
      ).readAsStringSync();
      expect(
        'pushPlanWindow: true'.allMatches(pro).length,
        1,
        reason: 'the PRO advance is the other phase advance',
      );
    });

    test('pushPlanWindow is NOT reachable from the facade or the boot/repair '
        'callers of writer A', () {
      for (final path in [
        'lib/core/services/workout_schedule_service.dart',
        'lib/core/services/auth_session_bootstrapper.dart',
        'lib/features/train/providers/train_provider.dart',
        'lib/features/onboarding/providers/onboarding_provider.dart',
        'lib/features/dev/simulation_service.dart',
      ]) {
        expect(
          File(path).readAsStringSync().contains('pushPlanWindow'),
          isFalse,
          reason:
              '$path: a push from a fresh-Hive generation REPLACES the '
              'cloud plan_json before the restore reads it (round 3 F1)',
        );
      }
    });

    final dispSrc = File(
      'lib/features/ai_coach/services/tool_dispatcher.dart',
    ).readAsStringSync();
    final regenStart = dispSrc.indexOf(
      'Future<ToolExecutionResult> _executeRegeneratePlanBlock(',
    );
    final pauseStart = dispSrc.indexOf(
      'Future<ToolExecutionResult> _executePausePlan(',
    );
    final switchStart = dispSrc.indexOf(
      'Future<ToolExecutionResult> _executeSwitchGoal(',
    );
    final templateStart = dispSrc.indexOf(
      'Future<ToolExecutionResult> _executeCreateCustomTemplate(',
    );
    final regenBody = dispSrc.substring(regenStart, pauseStart);
    final switchBody = dispSrc.substring(switchStart, templateStart);
    const splice = "box.put('current_plan', splicedBlob)";
    const wSplice = "wbox.put('current_plan', splicedBlob)";
    const clear = 'RegeneratePlanPlanner.instance.clearCache(intent.id)';

    test('regen block: two pushes — one inside the empty branch after the '
        'sweep, one after the splice and before clearCache', () {
      expect(push.allMatches(regenBody).length, 2);
      final sweep = regenBody.indexOf('.sweepNonCompletedRowsPastPlanEnd()');
      final emptyBranch = regenBody.indexOf('if (rawSchedules.isEmpty)');
      final firstPush = regenBody.indexOf(push);
      final lastPush = regenBody.lastIndexOf(push);
      expect(
        sweep,
        isNonNegative,
        reason: 'a missing sweep would make lessThan(emptyBranch) vacuous',
      );
      expect(
        sweep,
        lessThan(emptyBranch),
        reason: 'the sweep must run even when there is nothing to write',
      );
      expect(firstPush, greaterThan(emptyBranch));
      expect(
        firstPush,
        lessThan(regenBody.indexOf('Nothing left to regenerate')),
      );
      expect(
        lastPush,
        greaterThan(regenBody.indexOf(splice)),
        reason: 'a push above the splice snapshots the pre-splice blob',
      );
      expect(lastPush, lessThan(regenBody.lastIndexOf(clear)));
    });

    test('switch_goal: sweep before patchProfile; push after the splice and '
        'before clearCache', () {
      expect(push.allMatches(switchBody).length, 1);
      final sweep = switchBody.indexOf('.sweepNonCompletedRowsPastPlanEnd()');
      expect(sweep, isNonNegative);
      expect(
        sweep,
        greaterThan(switchBody.indexOf("'Profile not found.'")),
        reason: 'after the last early return',
      );
      expect(sweep, lessThan(switchBody.indexOf('patchProfile(')));
      final pushAt = switchBody.indexOf(push);
      expect(pushAt, greaterThan(switchBody.indexOf(wSplice)));
      expect(pushAt, lessThan(switchBody.indexOf(clear)));
    });

    test('redoWeek4 (the live free-tier window-mover) pushes AFTER moving '
        'plan_end — the holdWeek shape', () {
      final writeSrc = File(
        'lib/core/services/workout_schedule_write_service.dart',
      ).readAsStringSync();
      final redoStart = writeSrc.indexOf('Future<void> redoWeek4()');
      final holdStart = writeSrc.indexOf('Future<void> holdWeek()');
      final redoBody = writeSrc.substring(redoStart, holdStart);
      expect(
        push.allMatches(redoBody).length,
        1,
        reason:
            'round 4 F2: a reinstall in the ≤24h gap takes the stale '
            'cloud window and the next regen sweeps the redo week',
      );
      final endWrite = redoBody.indexOf('MigratedKey.write(_planEndKey');
      expect(endWrite, isNonNegative);
      expect(
        redoBody.indexOf(push),
        greaterThan(endWrite),
        reason: 'a push above the window write carries the OLD plan_end',
      );
    });

    test('pushWorkoutPlanForSyncDomain is guarded by pausedForSimulation '
        'BEFORE it opens a session', () {
      final syncSrc = File(
        'lib/core/services/sync/sync_workout.dart',
      ).readAsStringSync();
      final start = syncSrc.indexOf(
        'Future<void> pushWorkoutPlanForSyncDomain() async {',
      );
      expect(start, isNonNegative);
      final body = syncSrc.substring(start);
      final guard = body.indexOf(
        'if (SyncService.pausedForSimulation) return;',
      );
      final session = body.indexOf('_ensureSessionOpen()');
      expect(
        guard,
        isNonNegative,
        reason:
            'round 4 F3: the year-sim drives ~30 advances inside its '
            'paused window and each now reaches this push',
      );
      expect(guard, lessThan(session), reason: 'guard FIRST, like :31');
    });
  });

  // Review B-4 (bpass finding 4): _phaseNote's three message forms + the
  // clears==0 vs >0 branch had zero test coverage anywhere — the method was
  // library-private on a private widget State class, unreachable from any
  // test. Extracted to the shared pure `phaseNote()` (regenerate_plan_diff.dart
  // and switch_goal_diff.dart both now delegate to it) so it can be pinned
  // directly with no widget pump.
  group('phaseNote — shared pure function (review B-4)', () {
    RegeneratePlanResult fixture({
      required int totalWeeks,
      required int requestedWeeks,
      String? phaseEndsOn,
      int clearsPastPhaseEnd = 0,
    }) =>
        RegeneratePlanResult(
          firstWeek: const [],
          additionalDaysCount: 0,
          totalWeeks: totalWeeks,
          requestedWeeks: requestedWeeks,
          phaseEndsOn: phaseEndsOn,
          clearsPastPhaseEnd: clearsPastPhaseEnd,
          resolvedGoal: 'muscle_gain',
          resolvedEquipment: 'home_dumbbells',
          resolvedDaysPerWeek: 4,
        );

    test('no stored window (phaseEndsOn null): no note regardless of clears',
        () {
      expect(
        phaseNote(fixture(totalWeeks: 4, requestedWeeks: 4, clearsPastPhaseEnd: 3)),
        isNull,
      );
    });

    test('block fits the phase and nothing to clear: no note', () {
      expect(
        phaseNote(fixture(
          totalWeeks: 4,
          requestedWeeks: 4,
          phaseEndsOn: '2026-07-01',
        )),
        isNull,
      );
    });

    test('block fits the phase but rows will be cleared: "ends on" form '
        'with the clear count', () {
      final note = phaseNote(fixture(
        totalWeeks: 4,
        requestedWeeks: 4,
        phaseEndsOn: '2026-07-01',
        clearsPastPhaseEnd: 2,
      ));
      expect(note, isNotNull);
      expect(note, startsWith('This phase ends on'));
      expect(note, contains('2 workouts scheduled after that date will be cleared.'));
      expect(note, isNot(contains('nothing left')));
      expect(note, isNot(contains('Stops at')));
    });

    test('block was shortened to fit (totalWeeks < requestedWeeks, > 0): '
        '"Stops at" form', () {
      final note = phaseNote(fixture(
        totalWeeks: 2,
        requestedWeeks: 4,
        phaseEndsOn: '2026-07-01',
      ));
      expect(note, isNotNull);
      expect(note, startsWith("Stops at this phase's end on"));
      expect(note, isNot(contains('cleared')), reason: 'clears == 0 here');
    });

    test('totalWeeks == 0: the "ended on ... nothing left" form, singular '
        'vs plural clear count', () {
      final zero = phaseNote(fixture(
        totalWeeks: 0,
        requestedWeeks: 4,
        phaseEndsOn: '2026-07-01',
        clearsPastPhaseEnd: 1,
      ));
      expect(zero, isNotNull);
      expect(zero, contains('nothing left to regenerate.'));
      expect(zero, contains('1 workout scheduled after that date will be cleared.'));
      expect(zero, isNot(contains('1 workouts')), reason: 'singular, not "1 workouts"');

      final plural = phaseNote(fixture(
        totalWeeks: 0,
        requestedWeeks: 4,
        phaseEndsOn: '2026-07-01',
        clearsPastPhaseEnd: 5,
      ));
      expect(plural, contains('5 workouts scheduled after that date will be cleared.'));
    });

    test('phaseDayLabel formats an ISO date as "Weekday M/D"', () {
      // 2026-07-01 is a Wednesday.
      expect(phaseDayLabel('2026-07-01'), 'Wed 7/1');
    });
  });

  // Review B-1 (bpass finding 1): a year-sim's phase advances all fire with
  // pausedForSimulation == true, so pushWorkoutPlanForSyncDomain() no-op'd on
  // every one of them; nothing in the end-of-run flush list called it either,
  // so a full sim run left the cloud plan_json window stale.
  test(
    'simulation_service end-of-run flush pushes the workout plan window '
    '(review B-1)',
    () {
      final src = File('lib/features/dev/simulation_service.dart')
          .readAsStringSync();
      final flushStart = src.indexOf("await flush('workout',");
      expect(flushStart, isNonNegative);
      final pushIdx = src.indexOf(
        "await flush('workout plan window', sync.pushWorkoutPlanForSyncDomain);",
      );
      expect(
        pushIdx,
        greaterThan(flushStart),
        reason: 'the plan-window push must be part of the post-loop flush, '
            'after the workout flush that does NOT carry plan_json',
      );
    },
  );
}
