// lib/shared/widgets/exercise_plate/exercise_monogram.dart
//
// Shown wherever an exercise has no artwork. Three populations reach it: user
// custom exercises, community exercises synced from user_custom_exercises, and
// the 127 library rows awaiting a photograph.
//
// It reads as "a plate not yet issued" rather than a failure. Rejected: falling
// back to the index number (a column mixing engravings and bare numerals reads
// as "some of these are missing"), a category glyph (nine glyphs to design, and
// a triangle beside an engraving is two visual languages), and an empty frame
// (reads as a loading state that never resolves).
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

/// The plate corner radius scales with the plate, so a 44 px thumb and a 96 px
/// empty state read as the same object at two sizes. Deliberately NOT an
/// `AppRadius` member: those are fixed Wardroom radii (2 / 4 / 6) and this is
/// proportional to one widget family. Promote it if a second family needs it.
double plateRadiusFor(double size) => size * 0.14;

class ExerciseMonogram extends StatelessWidget {
  final String name;
  final double size;

  const ExerciseMonogram({super.key, required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.bgRaise,
          borderRadius: BorderRadius.circular(plateRadiusFor(size)),
          border: Border.all(color: AppColors.accent.withValues(alpha: 0.28)),
        ),
        child: Center(
          child: Text(
            monogramFor(name),
            // Announced as the exercise name, not as three spelled-out letters.
            semanticsLabel: name,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.accent.withValues(alpha: 0.72),
              fontSize: size * 0.30,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ),
    );
  }
}
