import 'hive_service.dart';

/// Runtime flag for the body-measurements entry sheet, its prompts, the
/// Progress comparison card and the chat chip (L2b, §4.6 feature-flag
/// protocol).
///
/// Read from the local `configBox`. **Default ON (flipped 2026-10-16, after
/// Landings A, B and C shipped dark):** an absent key, or any value that is not
/// a `bool`, reads ON. A stored `false` is the kill switch and reads OFF; the
/// debug-only dev panel (`/dev` is `kDebugMode`-only) is the only writer, so a
/// release build can be turned off only by a new build. A stored `false` also
/// does not survive a sign-out: `UserRepository.clearAllData` clears
/// `configBox` (`user_repository.dart:1211`), after which the flag reads ON
/// again. An unopened box or a missing Hive (a pure unit test that never opened
/// Hive) reads OFF, the safe side, so those tests stay on the unchanged path.
///
/// The OFF path stays in the tree until the founder's device check is
/// recorded; its removal is tracked on the OI board
/// (`docs/ship_dark_pending_review.yaml`).
class MeasurementFlags {
  MeasurementFlags._();

  static bool get bodyMeasurementsEnabled {
    try {
      final stored =
          HiveService.instance.configBox.get('enable_body_measurements');
      return stored is bool ? stored : true; // absent or non-bool → ON
    } catch (_) {
      return false; // no Hive (pure unit test) → OFF, the safe side
    }
  }
}
