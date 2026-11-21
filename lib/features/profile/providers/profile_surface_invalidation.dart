import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart'
    show nutritionSummaryProvider;
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart'
    show dailyNutritionProvider, macroTargetsProvider;

import 'profile_completeness_provider.dart';
import 'profile_provider.dart' show userProfileProvider, userStatsProvider;

/// The surfaces that cache something derived from the profile's goal, target
/// weight or calorie / macro targets (OI-191). The one list both writers
/// invalidate after a goal change: Edit Profile's Save and the coach
/// `switchGoal`. `profileCompletenessProvider` is in it because a seeded target
/// changes the completeness count (`target_weight_kg` is one of its fields).
///
/// `predictionProvider` is NOT here: it is invalidated by the caller after the
/// prediction refresh settles (`PredictionService.refreshAfterProfileChange`).
final List<ProviderOrFamily> profileDerivedSurfaceProviders = [
  userProfileProvider,
  userStatsProvider,
  nutritionSummaryProvider,
  dailyNutritionProvider,
  macroTargetsProvider,
  profileCompletenessProvider,
];

/// Invalidates every profile-derived surface. Pass the `invalidate` of whatever
/// is still alive (`ref.invalidate`, `container.invalidate`). Each entry is
/// guarded on its own, so one failure never stops the rest; a failure is a
/// non-fatal tagged `profile_surface_invalidate_<source>`.
void invalidateProfileDerivedSurfaces(
  void Function(ProviderOrFamily) invalidate, {
  required String source,
}) {
  for (final provider in profileDerivedSurfaceProviders) {
    try {
      invalidate(provider);
    } catch (e, st) {
      debugPrint('[profile_surface_invalidation] $source: $provider failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'profile_surface_invalidate_$source'));
    }
  }
}
