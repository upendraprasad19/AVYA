// lib/features/train/providers/day_swap_provider.dart
//
// The Riverpod face of the day-swap engine (spec §5.1). The Train week
// list, the shared picker, Home and the coach dispatcher call ONLY this
// controller. It supplies the two things the engine must not look up
// itself — the PRO tier and the in-progress workout date — and refreshes
// every provider a swap changes.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_allowance.dart';
import 'package:icanbefitter/core/services/day_swap/day_swap_result.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/auth/providers/auth_invalidation_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';

import 'train_provider.dart';

/// The IST date of the live workout session, or null (spec §5.1 probe).
/// A session with no stored date is treated as today's.
String? inProgressDateOf(ActiveWorkoutData active) {
  if (!active.hasInProgressSession) return null;
  final date = active.workoutDay?.date;
  return date == null ? istTodayStr() : istDateStr(date);
}

class DaySwapController {
  DaySwapController(this._ref);
  final Ref _ref;

  bool get _isPro => _ref.read(subscriptionInfoProvider).isPro;

  String? get _inProgressDate =>
      inProgressDateOf(_ref.read(activeWorkoutProvider));

  /// Display only (confirm sheet, coach card): [swap] re-checks everything.
  DaySwapPreview preview(String dateA, String dateB) =>
      _ref.read(swapServiceProvider).preview(
            dateA: dateA,
            dateB: dateB,
            isPro: _isPro,
            inProgressDate: _inProgressDate,
          );

  Future<DaySwapResult> swap({
    required String dateA,
    required String dateB,
    required DaySwapOrigin origin,
  }) async {
    final result = await _ref.read(swapServiceProvider).swapDays(
          dateA: dateA,
          dateB: dateB,
          origin: origin,
          isPro: _isPro,
          inProgressDate: _inProgressDate,
        );
    _refresh(result);
    return result;
  }

  void _refresh(DaySwapResult result) {
    // A refusal can mean the screen was stale, so the swap views refresh
    // on every outcome.
    _ref.invalidate(daySwapWeekProvider);
    _ref.invalidate(daySwapAllowanceProvider);
    if (result is! DaySwapDone) return;
    // docs/architecture/sync.md mandatory batch — the same six as
    // tool_dispatcher._invalidateWorkoutProviders. Each is independently
    // guarded so one failure cannot stop the rest.
    final batch = <(String, void Function())>[
      ('currentPlanProvider', () => _ref.invalidate(currentPlanProvider)),
      ('workoutStatsProvider', () => _ref.invalidate(workoutStatsProvider)),
      ('calendarWeekProvider', () => _ref.invalidate(calendarWeekProvider)),
      ('streakProvider', () => _ref.invalidate(streakProvider)),
      ('todayWorkoutProvider', () => _ref.invalidate(todayWorkoutProvider)),
      ('allExercisePRsProvider', () => _ref.invalidate(allExercisePRsProvider)),
    ];
    for (final (name, invalidate) in batch) {
      try {
        invalidate();
      } catch (e, st) {
        debugPrint('[DaySwapController] invalidate $name failed: $e\n$st');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'day_swap_invalidate_failed'));
      }
    }
  }
}

final daySwapControllerProvider =
    Provider<DaySwapController>(DaySwapController.new);

/// The Mon–Sun swap states of the week starting [weekStart] (IST Monday).
final daySwapWeekProvider =
    Provider.family<List<DaySwapDayState>, String>((ref, weekStart) {
  // Rebuild with every flow that refreshes the Train week: completion,
  // template assignment and regeneration all invalidate currentPlanProvider.
  ref.watch(currentPlanProvider);
  final inProgress = ref.watch(activeWorkoutProvider.select(inProgressDateOf));
  return ref
      .read(swapServiceProvider)
      .weekStates(weekStart, inProgressDate: inProgress);
});

/// Swaps used and allowed in the week starting [weekStart] (IST Monday).
/// Follows the background server reply through `DaySwapAllowance.revision`.
final daySwapAllowanceProvider =
    Provider.family<DayAllowance, String>((ref, weekStart) {
  // c4055a — rebuild on auth change. The count lives in the per-user userBox,
  // but nothing else here changes on an account switch between two users of
  // the same tier, so without this B was shown A's spent week (Hermes L16).
  ref.watch(authUserIdTokenProvider);
  final isPro = ref.watch(subscriptionInfoProvider.select((s) => s.isPro));
  final revision = DaySwapAllowance.instance.revision;
  void onChange() => ref.invalidateSelf();
  revision.addListener(onChange);
  ref.onDispose(() => revision.removeListener(onChange));
  return DaySwapAllowance.instance.current(weekStart, isPro: isPro);
});
