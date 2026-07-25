import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

/// "KEEP TRAINING PHASE 1" tap action for the free-tier stay-on-phase-1 surface
/// (graduation screen). Extracted from graduation_screen.dart so that screen
/// stays under the god-screen line budget and so the flag-gate + H5 guard are
/// reusable.
///
/// Ship-dark: `enable_hold_weeks` flips the free-tier mechanic from the verbatim
/// `redoWeek4` to `holdWeek` (default OFF). **H5:** on a materialize failure it
/// surfaces a snackbar and STAYS PUT — it must NEVER blind-navigate to `/train`
/// (the exact dead-end `redoWeek4` was originally added to cure).
/// The free-tier "give me another week of this phase" WRITE — the single place
/// the `enable_hold_weeks` branch lives.
///
/// Ship-dark: OFF → the verbatim legacy [redoWeek4] (trailing-week copy);
/// ON → [holdWeek] (Peak/deload-by-date, Monday-aligned, plan_json-durable).
///
/// Extracted because this branch previously existed in TWO independently-edited
/// call sites ([keepTrainingPhase1] and `plan_expired_card._handleHoldWeek`) —
/// exactly the shape that drifts. Callers own their own UX (snackbar copy,
/// analytics, navigation); only the write decision is shared.
Future<void> runFreeTierRepeatWrite(WidgetRef ref) async {
  final svc = ref.read(workoutScheduleWriteServiceProvider);
  if (PlanEngineFlags.holdWeeksEnabled) {
    await svc.holdWeek();
  } else {
    await svc.redoWeek4();
  }
}

Future<void> keepTrainingPhase1(BuildContext context, WidgetRef ref) async {
  try {
    await runFreeTierRepeatWrite(ref);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't schedule again. Please try again.",
            style: AppTypography.body.copyWith(fontSize: 13),
          ),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    return;
  }
  if (context.mounted) context.go('/train');
}
