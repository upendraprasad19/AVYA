// lib/shared/widgets/exercise_plate/plate_flags.dart
//
// The exercise-plate kill switch.
//
// WHY THIS EXISTS: the batch classifies `platform` (docs/blast_radius.yaml
// pins `pubspec.yaml` and `CLAUDE.md` as platform by exact path — either alone is enough; cited by path
// because a line number moves every time the registry grows), and
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
//
// THE ANIMATION KILL SWITCH (Batch M2a, same kind: default ON, the flag turns it
// OFF): `configBox['disable_exercise_animations'] = true` stops every download of
// an exercise animation and every animated view, and it takes the bundled still
// tile with them (the still is an animation surface, design call C22). The plates
// keep working, so the faces are exactly what they were before this batch: the
// plate where the row has a drawing, else the monogram. The 617 rows that have an
// animation have no drawing, so with only this switch set their tiles show the
// monogram and their sheet says NO DRAWING YET. `animationsEnabled` also follows
// the plates switch, because an animation replaces a plate and has nothing to
// replace when plates are off. It is read at the SINK (the repository checks it
// before any client call or store read, so a flag flipped mid-session takes
// effect on the next open, not the next launch). `clearAllData()` clears
// `configBox`, so the switch does not survive a sign-out wipe (G4); a build that
// must stay off ships the compile-time platform switches instead.
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

  /// False when the animation switch is set OR plates are off. Same guard as
  /// [platesEnabled]: a missing or unopened box reads as ENABLED.
  static bool get animationsEnabled {
    try {
      return HiveService.instance.configBox
                  .get('disable_exercise_animations') !=
              true &&
          platesEnabled;
    } catch (_) {
      return true; // no Hive (pure unit test) → safe default: ON
    }
  }
}
