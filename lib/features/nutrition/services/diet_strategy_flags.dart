// lib/features/nutrition/services/diet_strategy_flags.dart
//
// Ship-dark switch for the diet strategy (diet plan Unit 3a, 2026-11-14,
// docs/plans/diet-strategy.md §3.3 and §3.12; CLAUDE.md §4.6 / §4.12.4).
//
// [enabled] is FALSE in Unit 3a ([kDietStrategyDefaultOn]): the chips are
// hidden on the Diet Plan and Edit Profile screens, `effectiveMacroTargets`
// returns the stored targets, nothing writes `diet_strategy`, and no reader
// watches anything new, so 3a is byte-identical for every user. Unit 3b flips
// the constant after keto / low-carb meal templates exist (full ×2 review).
//
// After the flip, `configBox['disable_diet_strategy'] == true` is the local
// kill switch: every screen reverts to Balanced at once (nothing
// strategy-specific is stored). clearAllData() clears configBox at sign-out,
// so the switch lasts until sign-out; a fleet-wide off is a build with the
// constant false. Logged in docs/ship_dark_pending_review.yaml.
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// Unit 3a ships dark; Unit 3b flips this.
const bool kDietStrategyDefaultOn = false;

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
