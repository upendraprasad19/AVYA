// The header tile of the focused active-workout card (Batch M2b Task 2): a
// square animation flush top-left of the card's header, with an ENLARGE chip at
// its bottom-right. One 124 dp tap target that opens the plate sheet, and a
// long-press that still starts superset grouping (the header's long-press
// worked across the whole header before the tile took its corner).
//
// The tile owns the `exercise_animation_view.dart` import, so the card (a
// `part of` screen.dart) never names the view.
import 'package:flutter/material.dart';
import 'package:icanbefitter/core/copy/wardroom_copy.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_animation_view.dart';

/// The tile's side, dp (the mockup's 124 dp square).
const double kHeaderTileSize = 124;

/// Whether the tile LOOPS by itself on the focused card (founder D7). One line
/// to flip if OI-440's phone check says a low-end phone cannot loop it; it
/// stops the LOOP only, not the fetch.
const bool kHeaderTileAutoplay = true;

class ExerciseHeaderTile extends StatelessWidget {
  const ExerciseHeaderTile({
    super.key,
    required this.media,
    required this.exerciseName,
    required this.autoplay,
    required this.onEnlarge,
    this.onLongPress,
  });

  final ExerciseMedia media;
  final String exerciseName;

  /// False while the screen is covered by a sheet, and once every exercise is
  /// done: the view then shows its first frame and a play button.
  final bool autoplay;

  /// Opens the plate sheet. Null (move mode, superset grouping) renders the
  /// frame without the chip, without the tap and without the `Enlarge`
  /// semantics.
  final VoidCallback? onEnlarge;

  /// Superset grouping: a long hold on the tile reaches the header's handler.
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.card);
    // Built like the plate sheet's frame (`exercise_plate_sheet.dart`): the 1 px
    // border is a FOREGROUND decoration so the opaque child cannot cover it.
    final frame = SizedBox(
      width: kHeaderTileSize,
      height: kHeaderTileSize,
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
              size: kHeaderTileSize,
              autoplay: autoplay,
            ),
          ),
        ),
      ),
    );

    final tile = SizedBox(
      width: kHeaderTileSize,
      height: kHeaderTileSize,
      child: Stack(
        children: [
          frame,
          if (onEnlarge != null)
            Positioned(
              right: 5,
              bottom: 5,
              child: ExcludeSemantics(child: _enlargeChip()),
            ),
        ],
      ),
    );

    // ONE chain of wrappers in EVERY state, never a different root type per
    // state: superset grouping (no enlarge) and back flips the handlers on the
    // SAME focused card while its animation plays, and a changed root type
    // (SizedBox, GestureDetector, Semantics) is a different widget, so the
    // animation view's State would be thrown away and restart from the still.
    //
    // ONE semantics node for the whole tile: the Semantics carries the label and
    // both actions and the detector inside excludes itself (a plain detector
    // would add an unlabeled child node, one outside would put the actions on an
    // ancestor's merged node). Without an enlarge handler the Semantics has no
    // property at all and adds no node (an unlabeled long-press node would be
    // noise: the header's name column already carries the long press). The
    // view's own PLAY button is a deeper node and wins its own taps: it has its
    // own button flag and tap, which conflict with this node's, so it forms a
    // separate node (pinned by the frozen-tile case). No `container: true`:
    // mutation (l) of the plan removed it and every case stayed green, so
    // nothing proves it.
    final enlarge = onEnlarge;
    return Semantics(
      button: enlarge != null ? true : null,
      label: enlarge == null
          ? null
          : WardroomCopy.activeEnlargeLabelTemplate
              .replaceAll('{name}', exerciseName),
      onTap: enlarge,
      onLongPress: enlarge == null ? null : onLongPress,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: enlarge,
        onLongPress: onLongPress,
        child: tile,
      ),
    );
  }

  Widget _enlargeChip() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.bgDeep.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(AppRadius.sharp),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.fullscreen, size: 11, color: AppColors.accent),
            const SizedBox(width: 2),
            Text(
              WardroomCopy.activeEnlargeChip,
              style: AppTypography.monoXs.copyWith(
                fontSize: 8,
                color: AppColors.accent,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
