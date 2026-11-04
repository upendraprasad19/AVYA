// lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
//
// The plate. Two images for a movement that cycles, one for a hold. Free to
// every tier, matching the FORM & CUES panel it sits beside.
//
// Since Batch M2a a row with an animation (`resolveMedia`) shows ONE animated picture in place of START and END while
// `PlateFlags.animationsEnabled` holds; with the animations switched off the sheet is exactly what it was (the drawings, or
// the monogram and NO DRAWING YET). The animation is fetched when the sheet opens, one file, never before.
//
// NOTE on the "never resolve library data in build()" constraint: this widget
// DOES, deliberately. That rule exists for the Active Workout card, which
// rebuilds ~1x/second off the workout timer. A modal sheet builds once when it
// opens; paying two linear scans of exerciseBox there is the simpler trade.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_animation_view.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_cues.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_media_resolver.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_flags.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

class ExercisePlateSheet extends StatelessWidget {
  final String exerciseName;

  const ExercisePlateSheet({super.key, required this.exerciseName});

  static Future<void> show(BuildContext context, String exerciseName) {
    // Every route into the sheet goes through here — the three badge sites and
    // the FORM & CUES door — so one check covers them all.
    if (!PlateFlags.platesEnabled) return Future<void>.value();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => ExercisePlateSheet(exerciseName: exerciseName),
    );
  }

  Widget _plateBox(String assetPath, String caption, String name) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cardHi,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: SvgPicture.asset(
                assetPath,
                semanticsLabel: '$name, $caption position',
                colorFilter:
                    const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
                errorBuilder: (_, _, _) =>
                    ExerciseMonogram(name: name, size: 64),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(caption,
            style: AppTypography.monoXs
                .copyWith(color: AppColors.accent, letterSpacing: 2)),
      ],
    );
  }

  Widget _label(String text) => Text(text,
      style: AppTypography.monoXs
          .copyWith(color: AppColors.textMute, letterSpacing: 2));

  /// The one animated picture, in a square frame as wide as the sheet allows. `size` is the frame's measured width: it drives
  /// the decode width, and the sheet's width differs from one device to the next.
  Widget _animationBox(ExerciseMedia media) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth;
        final radius = BorderRadius.circular(AppRadius.card);
        return AspectRatio(
          aspectRatio: 1,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: ColoredBox(
                color: AppColors.cardHi,
                child: ExerciseAnimationView(
                  media: media,
                  exerciseName: exerciseName,
                  size: side,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final plate = resolvePlate(exerciseName);
    // Both conditions, always: the kill switch must also close the sheet's door to the animation.
    final media =
        PlateFlags.animationsEnabled ? resolveMedia(exerciseName) : null;
    final row = ExerciseRepository.instance.getByExactName(exerciseName);
    // ONE parser for the sheet, the FORM & CUES panel and the logging viewer:
    // the split on ';' of a packed cue, the numeric-breathing guard and the
    // never-hard-cast rule live in exerciseCuesOf, not here.
    final parsed = exerciseCuesOf(row);
    final cues = parsed.cues;
    final breathing = parsed.breathing;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(exerciseName.toUpperCase(),
                style: AppTypography.mono.copyWith(
                    color: AppColors.textPrimary, letterSpacing: 2.2)),
            const SizedBox(height: 14),
            if (media != null)
              _animationBox(media)
            else if (plate.hasArtwork)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: plate.isPair
                    ? [
                        Expanded(
                            child: _plateBox(
                                plate.assetPaths[0], 'START', exerciseName)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _plateBox(
                                plate.assetPaths[1], 'END', exerciseName)),
                      ]
                    // A single hold gets half the width (1:2:1), not the third
                    // it would get by reusing the pair's sizing.
                    : [
                        const Spacer(),
                        Expanded(
                          flex: 2,
                          child: _plateBox(plate.assetPaths.single,
                              'HOLD THIS POSITION', exerciseName),
                        ),
                        const Spacer(),
                      ],
              )
            else
              Center(
                child: Column(
                  children: [
                    ExerciseMonogram(name: exerciseName, size: 96),
                    const SizedBox(height: 8),
                    _label('NO DRAWING YET'),
                  ],
                ),
              ),
            if (cues.isNotEmpty) ...[
              const SizedBox(height: 18),
              _label('FORM'),
              const SizedBox(height: 6),
              ...cues.map((c) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('–  ',
                            style: AppTypography.bodySm
                                .copyWith(color: AppColors.accent)),
                        Expanded(
                          child: Text(c,
                              style: AppTypography.bodySm
                                  .copyWith(color: AppColors.textPrimary)),
                        ),
                      ],
                    ),
                  )),
            ],
            if (breathing != null) ...[
              const SizedBox(height: 14),
              _label('BREATHING'),
              const SizedBox(height: 4),
              Text(breathing,
                  style: AppTypography.bodySm
                      .copyWith(color: AppColors.textPrimary)),
            ],
          ],
        ),
      ),
    );
  }
}
