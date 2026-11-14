// lib/features/nutrition/services/diet_strategy_flags.dart
//
// Ship-dark switch for the diet strategy (diet plan Unit 3a, 2026-11-14,
// docs/plans/diet-strategy.md §3.3 and §3.12; CLAUDE.md §4.6 / §4.12.4).
//
// Unit 3a shipped this dark; Unit 3b-3 (docs/plans/diet-strategy-3b3.md)
// turns it ON ([kDietStrategyDefaultOn] true) once the keto / low-carb meal
// templates, the strategy-aware Diet Plan screen, the coach manual passage
// and the suggestMeal carb cap exist (Units 3b-1a, 3b-1b, 3b-2).
//
// `configBox['disable_diet_strategy'] == true` is the local kill switch:
// nothing strategy-specific is stored as targets, so every reader shows
// Balanced once it reads [enabled] again. It is read, not watched: the coach
// snapshot and the profile push follow it at once (both rebuild per call);
// the targets providers and an open Diet Plan screen on their next rebuild,
// in practice the next app start. clearAllData() clears configBox at sign-out, so the
// switch lasts until sign-out; a fleet-wide off is a build with the constant
// false. Deleting the switch and its OFF paths after the founder's device
// check is on the OI board.
//
// The switch is CLIENT-ONLY (B-pass, Unit 3b-3): it stops this device
// pushing the strategy, but a value already in user_profile.diet_strategy
// still drives the server: suggestMeal's carb cap (off with the Edge Function
// secret DISABLE_SUGGESTMEAL_DIET_STRATEGY) and the weekly report's strategy
// line (off with DISABLE_DIET_STRATEGY_MANUAL_RULES). No screen sets it: a
// debug build or the Hive inspector does.
//
// A box that cannot be read means ON (the build default): configBox is
// opened before runApp and only cleared, never closed, at sign-out, so the
// catch is reached only by tests with no Hive (pinned in
// test/core/diet_strategy_targets_test.dart).
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// On since Unit 3b-3 (Unit 3a shipped it off).
const bool kDietStrategyDefaultOn = true;

class DietStrategyFlags {
  DietStrategyFlags._();

  static const String disableKey = 'disable_diet_strategy';

  /// THE test seam for every flag-on test (providers, widgets, snapshot).
  /// Reset it to null in tearDown.
  @visibleForTesting
  static bool? debugEnabledOverride;

  /// True only when the strategy is switched on for this build and the local
  /// kill switch is not set. A missing or unopened box reads as the build
  /// default (pure unit tests have no Hive).
  static bool get enabled {
    final override = debugEnabledOverride;
    if (override != null) return override;
    if (!kDietStrategyDefaultOn) return false;
    try {
      return HiveService.instance.configBox.get(disableKey) != true;
    } catch (_) {
      return kDietStrategyDefaultOn;
    }
  }
}
