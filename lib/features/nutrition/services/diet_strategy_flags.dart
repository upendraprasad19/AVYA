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
// every screen reverts to Balanced at once (nothing strategy-specific is
// stored as targets). clearAllData() clears configBox at sign-out, so the
// switch lasts until sign-out; a fleet-wide off is a build with the constant
// false. Deleting the switch and its OFF paths after the founder's device
// check is on the OI board.
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
