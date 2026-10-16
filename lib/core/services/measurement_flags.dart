import 'hive_service.dart';

/// Runtime flag for the body-measurements entry sheet and its prompts (L2b
/// Landing B, §4.6 feature-flag protocol).
///
/// Read from the local `configBox`. **Default OFF (ship dark):** the sheet, the
/// Home banner, the Weight-sheet link and the chat handler's provider refresh
/// all stay inert until `configBox['enable_body_measurements'] == true`. The
/// getter is `== true`, so an absent key, a string `'true'` or an unopened box
/// (a pure unit test that never opened Hive) are all OFF.
///
/// Toggled in the debug-only dev panel (`/dev` is `kDebugMode`-only). The flip
/// is its own commit with its own ×2 review and B-pass
/// (`docs/ship_dark_pending_review.yaml`).
class MeasurementFlags {
  MeasurementFlags._();

  static bool get bodyMeasurementsEnabled {
    try {
      return HiveService.instance.configBox.get('enable_body_measurements') ==
          true;
    } catch (_) {
      return false; // no Hive (pure unit test) → ship-dark default: OFF
    }
  }
}
