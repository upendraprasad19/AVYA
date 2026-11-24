// Kill switch for the unit-preference push (OI-348 B9, diagnose e9a6c1).
//
// configBox `disable_unit_pref_sync == true` stops `units_system` and
// `measurement_unit` from being pushed (the profile payload is then
// byte-identical to the one before B9). Reads and the restore merge are not
// affected: a value already in the cloud still arrives on every device.
import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/hive_service.dart';

class UnitPrefFlags {
  UnitPrefFlags._();

  static const String disableKey = 'disable_unit_pref_sync';

  /// THE test seam for every flag test. Reset it to null in tearDown.
  @visibleForTesting
  static bool? debugPushEnabledOverride;

  /// True unless the local kill switch is set.
  static bool get pushEnabled {
    final override = debugPushEnabledOverride;
    if (override != null) return override;
    try {
      return HiveService.instance.configBox.get(disableKey) != true;
    } catch (_) {
      return true;
    }
  }
}
