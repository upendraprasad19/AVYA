import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';

import 'train_provider.dart';

/// The workout surfaces a coach write refreshes, in invalidation order
/// (OI-370). `aiInsightProvider` is left out on purpose: it watches
/// `todayWorkoutProvider` (c7e3a9), so it refreshes through that entry; the
/// unit test pins that watch.
/// `lastPerformanceProvider` is the whole family, so the "last time" values in
/// the Train preview, Active Workout and the overload indicator stop showing
/// pre-log data.
final List<ProviderOrFamily> workoutSurfaceProviders = [
  currentPlanProvider,
  workoutStatsProvider,
  calendarWeekProvider,
  streakProvider,
  todayWorkoutProvider,
  allExercisePRsProvider,
  lastPerformanceProvider,
];

/// Invalidates every workout surface after a coach write. Pass the
/// `invalidate` of whatever is still alive (`ref.invalidate`,
/// `container.invalidate`). Each entry is guarded on its own, so one failure
/// never stops the rest; a failure is reported as a non-fatal tagged
/// `workout_surface_invalidate_<source>`.
void invalidateWorkoutSurfaces(
  void Function(ProviderOrFamily) invalidate, {
  required String source,
}) {
  for (final provider in workoutSurfaceProviders) {
    try {
      invalidate(provider);
    } catch (e, st) {
      debugPrint('[workout_surface_invalidation] $source: $provider failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'workout_surface_invalidate_$source'));
    }
  }
}
