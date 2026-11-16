import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import '../providers/train_provider.dart';

/// "KEEP TRAINING PHASE 1" tap action for the free-tier stay-on-phase-1 surface
/// (graduation screen). Extracted from graduation_screen.dart so that screen
/// stays under the god-screen line budget.
///
/// **H5:** on a failure it surfaces a snackbar and STAYS PUT — it must NEVER
/// blind-navigate to `/train` (the dead-end the free-tier repeat was originally
/// added to cure).
/// The free-tier "give me another week of this phase" WRITE: `holdWeek()`
/// (Peak / deload by date, Monday-aligned, plan_json-durable). Unit 3D-b
/// (OI-175, d57) deleted the `enable_hold_weeks` flag and the old `redoWeek4`,
/// so there is no branch left; the function stays the ONE write both callers
/// ([keepTrainingPhase1] and `plan_expired_card._handleHoldWeek`) share. Callers
/// own their own UX (snackbar copy, analytics, navigation) per outcome.
Future<HoldWeekOutcome> runFreeTierRepeatWrite(WidgetRef ref) {
  return ref.read(workoutScheduleWriteServiceProvider).holdWeek();
}

Future<void> keepTrainingPhase1(BuildContext context, WidgetRef ref) async {
  // Round 4 F1: the screen can be popped during the awaited write, and a
  // disposed element's `ref` can no longer invalidate. Capture the container
  // first and refresh through it.
  final container = ProviderScope.containerOf(context, listen: false);
  HoldWeekOutcome outcome;
  try {
    outcome = await runFreeTierRepeatWrite(ref);
  } catch (_) {
    outcome = HoldWeekOutcome.failed;
  }
  switch (outcome) {
    case HoldWeekOutcome.written:
      // Round 3 B-F2: the hold counts only once plan_end moved (its last
      // write), and a reader built in between saw no hold; nothing else
      // invalidates on this path (the graduation screen only navigates).
      // Round 4 F2: Home's today card watches only the auth token.
      container.invalidate(currentPlanProvider);
      container.invalidate(selectedWeekProvider);
      container.invalidate(todayWorkoutProvider);
      if (context.mounted) context.go('/train');
    case HoldWeekOutcome.alreadyHolding:
      // The double tap (defect A): the hold is already in place; say so and
      // go to it.
      _snack(context, 'Already holding this week.', AppColors.card);
      if (context.mounted) context.go('/train');
    case HoldWeekOutcome.inFlight:
      break; // the first tap is still writing and will navigate
    case HoldWeekOutcome.noPlan:
    case HoldWeekOutcome.failed:
      _snack(context, "Couldn't schedule again. Please try again.", AppColors.red);
  }
}

void _snack(BuildContext context, String text, Color background) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        text,
        style: AppTypography.body.copyWith(fontSize: 13),
      ),
      backgroundColor: background,
      behavior: SnackBarBehavior.floating,
    ),
  );
}
