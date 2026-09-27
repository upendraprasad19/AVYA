// Behavioral proof that a coach-driven swap_workout_days dispatch
// invalidates daySwapWeekProvider (CLAUDE.md §4.4 rule 21 — no coverage gap
// may ship silently). Mirrors the REAL end-to-end dispatch pattern already
// established by test/contracts/coach_completion_prompt_test.dart (the
// `_refProvider` trick + `GuardedBox.testBypassOwnership`, so no real
// Supabase auth session is needed — see that file's header for why a full
// `ToolDispatcher.execute()` test otherwise requires one).
//
// THE BUG THIS GUARDS: tool_dispatcher.dart's general 6-provider
// invalidation (`_invalidateWorkoutProviders`) does NOT cover
// `daySwapWeekProvider` (Task 12/U4's own new provider) — without the
// `swap_workout_days`-specific invalidation block this task adds, a
// coach-driven swap would leave the Train week list and the picker/confirm
// sheets showing STALE pre-swap titles until some UNRELATED rebuild.

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

      // Read the SAME container's provider again. If the invalidation
      // block under test is missing, Riverpod returns the CACHED `before`
      // list unchanged (nothing ever asked it to rebuild) — titles would
      // still read pre-swap even though the underlying Hive rows changed.
      final after = c.read(daySwapWeekProvider(weekStart));
      final afterFri = after.firstWhere((s) => s.date == fri).title;
      final afterSat = after.firstWhere((s) => s.date == sat).title;
      expect(afterFri, 'Legs + Core',
          reason: 'daySwapWeekProvider must be invalidated + recomputed '
              'after a coach-driven swap, not read from stale cache — this '
              'is exactly what the swap_workout_days invalidation block '
              '(Anchor 3) exists to guarantee.');
      expect(afterSat, 'Pull + Core');
      // The allowance family is invalidated by the same block: without it the
      // cached pre-swap value (used 0) would still be served.
      expect(c.read(daySwapAllowanceProvider(weekStart)).used, 1,
          reason: 'daySwapAllowanceProvider must be invalidated after a '
              'coach-driven swap (Provider.family keyed by IST Monday, Task 12)');
    },
  );
}
