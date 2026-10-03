// lib/shared/widgets/exercise_plate/plate_flags.dart
//
// The exercise-plate kill switch.
//
// WHY THIS EXISTS: the batch classifies `platform` (docs/blast_radius.yaml:324
// pins `pubspec.yaml`, and :68 pins `CLAUDE.md` — either alone is enough), and
// platform tier's `requires:` list includes `feature_flag`. Nothing mechanical
// enforces that — `check_blast_radius_coverage.dart` only asserts every path has
// SOME tier, and the keystone plan-review gate never reads `requires:` — so an
// earlier batch resolved the same gap as a written deviation (ADR-0018). This
// one carries the lever instead, because it is ~20 lines and leaves a real
// rollback path where a deviation leaves none.
//
// ⚠ THIS IS A KILL SWITCH, NOT A SHIP-DARK FLAG — the distinction matters and
// the two are easy to confuse because the repo's other flags are the other kind.
// `plan_engine_flags.dart`'s flags default OFF (§4.6 ship-dark) because each can
// change a PRESCRIPTION in an unsafe direction: graded progression can increase
// load, hold-weeks materializes new schedule rows. A plate is additive, purely
// cosmetic, free to every tier, and already degrades per-exercise to a monogram.
// Shipping it inert would mean a later flip-on commit carrying the full §4.12.4
// ×2 review for a feature whose worst failure is a drawing that does not appear.
// So it defaults ON and the flag turns it OFF.
//
// TO DISABLE IN AN INCIDENT: set `configBox['disable_exercise_plates'] = true`.
// Thumbs fall back to the monogram they already show for the 127 artwork-less
// exercises — no asset loads, no SVG parsing — and the sheet stops opening.
import 'package:icanbefitter/core/services/hive_service.dart';

class PlateFlags {
  PlateFlags._();

  /// False only when the kill switch is explicitly set. Guarded so a missing or
  /// unopened box reads as ENABLED: the failure mode of a false negative here
  /// is the feature silently vanishing for everyone, which is worse than the
  /// thing the switch exists to stop.
  static bool get platesEnabled {
    try {
      return HiveService.instance.configBox.get('disable_exercise_plates') !=
          true;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: ON
    }
  }
}
