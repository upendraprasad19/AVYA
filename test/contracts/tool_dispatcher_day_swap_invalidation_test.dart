// Behavioral proof that a coach-driven swap_workout_days dispatch
// invalidates daySwapWeekProvider (CLAUDE.md §4.4 rule 21 — no coverage gap
// may ship silently). Mirrors the REAL end-to-end dispatch pattern already
// established by test/contracts/coach_completion_prompt_test.dart (the
// `_refProvider` trick + `GuardedBox.testBypassOwnership`, so no real
// Supabase auth session is needed — see that file's header for why a full
// `ToolDispatcher.execute()` test otherwise requires one).
//
// WHAT THIS ACTUALLY PINS (corrected post-review, Task 27 fix round —
// Mutation 3 proved the claim below false): tool_dispatcher.dart's dedicated
// `swap_workout_days` invalidation block (`ref.invalidate(daySwapWeekProvider)`
// / `ref.invalidate(daySwapAllowanceProvider)`) is REDUNDANT-BY-DESIGN — both
// providers already refresh through paths that do not depend on it:
//   - `daySwapWeekProvider` (lib/features/train/providers/day_swap_provider.dart:102)
//     watches `currentPlanProvider`, which the dispatcher's general,
//     unconditional `_invalidateWorkoutProviders(ref)` already invalidates for
//     `swap_workout_days` (it is not a nutrition intent).
//   - `daySwapAllowanceProvider` (lib/features/train/providers/day_swap_provider.dart:114)
//     listens to `DaySwapAllowance.instance.revision`, which
//     `SwapService.swapDays` bumps via `DaySwapAllowance.instance.recordSwap`
//     -> `lib/core/services/day_swap/day_swap_allowance.dart:159`, on every
//     successful swap — independent of the dispatcher entirely.
// Deleting the dedicated block reddens NOTHING in this file (Mutation 3). It
// is kept anyway as a cheap, harmless defensive guard — the same
// belt-and-braces shape `DaySwapController._refresh` already uses for its own
// origin. This test therefore pins that the dedicated block's PRESENCE is
// safe and that invalidation genuinely happens end-to-end after a
// coach-driven swap — it does NOT prove the dedicated block is what prevents
// staleness; the two paths named above already guarantee that on their own.

// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/swap_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/tool_intent.dart';
import 'package:icanbefitter/features/ai_coach/services/tool_dispatcher.dart';
import 'package:icanbefitter/features/train/providers/day_swap_provider.dart';

/// Exposes a real Riverpod [Ref], exactly as
/// coach_completion_prompt_test.dart's own `_refProvider` does.
final _refProvider = Provider<Ref>((ref) => ref);

const fri = '2026-09-25';
const sat = '2026-09-26';
const weekStart = '2026-09-21';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('test_swap_invalidation');
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
      HiveService.coachBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
      'workoutBox_aaaaaaaa',
      'coachBox_aaaaaaaa',
      'configBox_aaaaaaaa',
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
    // Same hermetic guard coach_completion_prompt_test.dart uses: execute()'s
    // fire-and-forget syncWorkoutData()/pushSnapshot() short-circuit under
    // this flag, so the test has no Supabase touch and no dangling timers.
    SyncService.pausedForSimulation = true;
    // The fixture days must be in the future, or the engine refuses them as
    // `past` (Task 10 lock precedence). Thu 24 Sep 2026, 10:00 IST — the same
    // clock Task 11's engine tests use.
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30));
    // No network: the allowance keeps its phone copy, the plan push is a no-op.
    DaySwapAllowance.debugConsumeForTests = (_) async => null;
    SwapService.debugOnPlanPushForTests = () {};

    final wb = HiveService.instance.workoutBox;
    await wb.put('schedule_$fri', {
      'date': fri,
      'type': 'custom_template',
      'workout_name': 'Pull + Core',
      'status': 'planned',
      'exercises': <Map<String, dynamic>>[],
    });
    await wb.put('schedule_$sat', {
      'date': sat,
      'type': 'custom_template',
      'workout_name': 'Legs + Core',
      'status': 'planned',
      'exercises': <Map<String, dynamic>>[],
    });
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    DaySwapAllowance.debugConsumeForTests = null;
    SwapService.debugOnPlanPushForTests = null;
    resetTestClock();
    await HiveUserSession.closeAll();
  });

  test(
    'a successful coach swap invalidates daySwapWeekProvider so the NEXT '
    'read reflects the swap, not a cached pre-swap value',
    () async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final ref = c.read(_refProvider);

      // Materialize + KEEP ALIVE the provider via an explicit listener — a
      // bare `c.read(...)` on an autoDispose family provider can be torn
      // down the instant nothing watches it, which would make this test
      // pass regardless of whether the dispatcher ever invalidates
      // anything (a false-positive green). `fireImmediately` also gives us
      // the pre-swap snapshot as `before` without a second read.
      DaySwapDayState? beforeFri0;
      DaySwapDayState? beforeSat0;
      c.listen(daySwapWeekProvider(weekStart), (prev, next) {},
          fireImmediately: true);
      c.listen(daySwapAllowanceProvider(weekStart), (prev, next) {},
          fireImmediately: true);
      expect(c.read(daySwapAllowanceProvider(weekStart)).used, 0);
      final before = c.read(daySwapWeekProvider(weekStart));
      beforeFri0 = before.firstWhere((s) => s.date == fri);
      beforeSat0 = before.firstWhere((s) => s.date == sat);
      expect(beforeFri0.title, 'Pull + Core');
      expect(beforeSat0.title, 'Legs + Core');

      final intent = ToolIntent(
        id: 'swap_1',
        type: 'swap_workout_days',
        payload: {'dateA': fri, 'dateB': sat},
        confirmationClass: ConfirmationClass.reviewable,
        previewSummary: 'Swap $fri and $sat',
        createdAt: DateTime.now(),
      );
      final res = await ToolDispatcher.instance.execute(ref, intent);
      expect(res.success, isTrue,
          reason: 'The swap_workout_days dispatch must succeed.');

      // Read the SAME container's provider again. This proves invalidation
      // genuinely happens end-to-end (via the general
      // `_invalidateWorkoutProviders(ref) -> currentPlanProvider` path, see
      // this file's header) — NOT that the dedicated `swap_workout_days`
      // block is what causes it; Mutation 3 showed that block is redundant.
      final after = c.read(daySwapWeekProvider(weekStart));
      final afterFri = after.firstWhere((s) => s.date == fri).title;
      final afterSat = after.firstWhere((s) => s.date == sat).title;
      expect(afterFri, 'Legs + Core',
          reason: 'daySwapWeekProvider must be invalidated + recomputed '
              'after a coach-driven swap, not read from stale cache — via '
              '`currentPlanProvider` (watched at day_swap_provider.dart:102), '
              'which the general _invalidateWorkoutProviders(ref) already '
              'invalidates; the dedicated swap_workout_days block is a '
              'redundant defensive guard, not the cause (see file header).');
      expect(afterSat, 'Pull + Core');
      // The allowance family refreshes via DaySwapAllowance.instance.revision
      // (day_swap_provider.dart:114), which SwapService.swapDays bumps
      // through DaySwapAllowance.recordSwap -> day_swap_allowance.dart:159 —
      // independent of the dedicated dispatcher block (see file header).
      expect(c.read(daySwapAllowanceProvider(weekStart)).used, 1,
          reason: 'daySwapAllowanceProvider must be invalidated after a '
              'coach-driven swap (Provider.family keyed by IST Monday, Task 12)');
    },
  );

  // B-pass R2-F3. Unlike the success case above, the dedicated block is the
  // ONLY path on a refusal: execute() returns before the general workout
  // invalidation, and a refused swap never bumps the allowance revision. A
  // refusal is the typical sign the cached week is stale, so it must refresh.
  test('a REFUSED coach swap still refreshes daySwapWeekProvider', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ref = c.read(_refProvider);
    c.listen(daySwapWeekProvider(weekStart), (prev, next) {},
        fireImmediately: true);
    final cachedSat =
        c.read(daySwapWeekProvider(weekStart)).firstWhere((s) => s.date == sat);
    expect(cachedSat.lock, isNull, reason: 'premise: Sat is swappable when cached');

    // Sat is completed elsewhere; nothing invalidates the cached week.
    final wb = HiveService.instance.workoutBox;
    final satRow = Map<String, dynamic>.from(wb.get('schedule_$sat') as Map)
      ..['status'] = 'completed';
    await wb.put('schedule_$sat', satRow);
    expect(
        c.read(daySwapWeekProvider(weekStart)).firstWhere((s) => s.date == sat).lock,
        isNull,
        reason: 'premise: without an invalidation the provider still serves '
            'the stale cached week');

    final res = await ToolDispatcher.instance.execute(
        ref,
        ToolIntent(
          id: 'swap_refused',
          type: 'swap_workout_days',
          payload: {'dateA': fri, 'dateB': sat},
          confirmationClass: ConfirmationClass.reviewable,
          previewSummary: 'Swap $fri and $sat',
          createdAt: DateTime.now(),
        ));
    expect(res.success, isFalse, reason: 'a completed day cannot be swapped');

    final satAfter =
        c.read(daySwapWeekProvider(weekStart)).firstWhere((s) => s.date == sat);
    expect(satAfter.lock, DaySwapRefusal.completed,
        reason: 'the refusal must refresh the week so the list shows Sat locked');
  });
}
