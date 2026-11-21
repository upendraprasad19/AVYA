// lib/features/nutrition/services/diet_supplements_flags.dart
//
// Kill switch for diet plan Unit 4 Supplements (docs/plans/diet-supplements.md
// section 2). Default ON is safe: the per-user opt-in (profile key
// `diet_supplements`) is itself off for everyone until chosen, so with the
// switch absent every output is the pre-Unit-4 one.
//
// `configBox['disable_diet_supplements'] == true` is the LOCAL kill switch:
// the section disappears and nothing is added to a plan, a snapshot or the
// push. It is read, not watched: a provider reads it when it builds. It is
// CLIENT-ONLY: the coach manual has its own server switch
// (DISABLE_DIET_SUPPLEMENTS_MANUAL_RULES), and a value already stored in
// user_profile.diet_supplements stays. Nothing in the app writes the key: it
// is set by hand (the Hive inspector). clearAllData() clears configBox at
// sign-out, so the switch lasts until sign-out; a fleet-wide off is a build
// with the constant false. Deleting the switch and its OFF paths after the
// founder's device check is on the OI board.
//
// A box that cannot be read means ON (the build default): configBox is
// opened by HiveService.init() before runApp and only cleared, never closed,
// so today only tests with no Hive reach the catch.
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

/// On from the start (the per-user opt-in is the gate).
const bool kDietSupplementsDefaultOn = true;

class DietSupplementsFlags {
  DietSupplementsFlags._();

  static const String disableKey = 'disable_diet_supplements';

  /// THE test seam for every flag test. Reset it to null in tearDown.
  @visibleForTesting
  static bool? debugEnabledOverride;

  /// True unless the build constant is off or the local kill switch is set.
  static bool get enabled {
    final override = debugEnabledOverride;
    if (override != null) return override;
    if (!kDietSupplementsDefaultOn) return false;
    try {
      return HiveService.instance.configBox.get(disableKey) != true;
    } catch (_) {
      return kDietSupplementsDefaultOn;
    }
  }
}
