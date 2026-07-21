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
Future<void> keepTrainingPhase1(BuildContext context, WidgetRef ref) async {
  final svc = ref.read(workoutScheduleWriteServiceProvider);
  try {
    if (PlanEngineFlags.holdWeeksEnabled) {
      await svc.holdWeek();
    } else {
      await svc.redoWeek4();
    }
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
