// lib/features/nutrition/services/diet_plan_flags.dart
//
// Kill switch for the curated diet plan generator (diet plan Unit 1,
// 2026-11-14, CLAUDE.md §4.6). Same shape as PlateFlags
// (lib/shared/widgets/exercise_plate/plate_flags.dart):
// `configBox['disable_curated_diet_plan'] == true` routes the Diet Plan screen
// back to the legacy DietPlanGenerator; absent or anything else = curated.
//
// Honest limits: this is a LOCAL configBox key with no remote lever, and
// clearAllData() clears configBox at sign-out, so the switch does not survive
// a sign-out wipe. A fleet-wide rollback is a build whose [curatedEnabled]
// returns false. The legacy path and this switch are deleted once the founder
// device-checks the curated plan (OI board).
import 'package:icanbefitter/core/services/hive_service.dart';

class DietPlanFlags {
  DietPlanFlags._();

  static const String disableCuratedKey = 'disable_curated_diet_plan';

  /// True unless the kill switch is explicitly set. A missing or unopened
  /// box reads as ENABLED (pure unit tests have no Hive).
  static bool get curatedEnabled {
    try {
      return HiveService.instance.configBox.get(disableCuratedKey) != true;
    } catch (_) {
      return true;
    }
  }
}
