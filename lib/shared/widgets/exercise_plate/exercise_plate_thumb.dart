// lib/shared/widgets/exercise_plate/exercise_plate_thumb.dart
//
// Replaces the numbered badge at the three sites that render one. The badge
// carried almost nothing — position in a vertical list is already obvious — so
// this costs ZERO new elements in a header row already at five (Hick's Law
// stays neutral). The badges are 24/24/28 px today; 44 is also the minimum
// touch target, so one change fixes two things — but it IS a +16..20 px bump in
// a header Row, so check the card height on a real device.
//
// WHY initState and not build(): the Active Workout card rebuilds ~1x/second off
// the workout timer, so resolving in build() would re-read Hive sixty times a
// minute. coaching_content_panel.dart:40-58 learned this first.
//
// The parsed picture is cached by the SVG layer itself (vector_graphics'
// _livePictureCache), so six to eight thumbs on one screen parse once, not once
// per frame.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_flags.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

class ExercisePlateThumb extends StatefulWidget {
  final String exerciseName;
  final double size;
  final VoidCallback? onTap;

  const ExercisePlateThumb({
    super.key,
    required this.exerciseName,
    this.size = 44,
    this.onTap,
  });

  @override
  State<ExercisePlateThumb> createState() => _ExercisePlateThumbState();
}

class _ExercisePlateThumbState extends State<ExercisePlateThumb> {
  late ExercisePlate _plate;

  @override
  void initState() {
    super.initState();
    _plate = resolvePlate(widget.exerciseName);
  }

  @override
  void didUpdateWidget(covariant ExercisePlateThumb old) {
    super.didUpdateWidget(old);
    // A swap reuses this State when the card is keyed by index rather than name.
    if (old.exerciseName != widget.exerciseName) {
      _plate = resolvePlate(widget.exerciseName);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Guard the SINK, not each call site — three screens construct this widget
    // and a per-site check is one forgotten site away from useless
    // (feedback_pause_flag_guard_the_sink). When the kill switch is on, fall
    // through to the monogram the 127 artwork-less exercises already show: no
    // asset load, no SVG parse, layout unchanged.
    final Widget face = (_plate.hasArtwork && PlateFlags.platesEnabled)
        ? DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.cardHi,
              borderRadius: BorderRadius.circular(plateRadiusFor(widget.size)),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: EdgeInsets.all(widget.size * 0.06),
              child: SvgPicture.asset(
                _plate.assetPaths.first,
                semanticsLabel: widget.exerciseName,
                colorFilter:
                    const ColorFilter.mode(AppColors.accent, BlendMode.srcIn),
                // A demo_slug naming an unbundled drawing must degrade, not
                // render an error box. Reachable via community rows.
                //
                // Return the monogram DIRECTLY. An earlier version also set an
                // _assetFailed flag from a post-frame callback so later builds
                // skipped the SvgPicture entirely. It bought nothing -- both
                // branches render exactly one ExerciseMonogram -- and it kept a
                // frame permanently scheduled, which stalled the widget test
                // for 6m35s and reported "did not complete" rather than a
                // failure. Sized to the PADDED box so it fills the same square.
                errorBuilder: (_, _, _) => ExerciseMonogram(
                    name: widget.exerciseName, size: widget.size * 0.88),
              ),
            ),
          )
        : ExerciseMonogram(name: widget.exerciseName, size: widget.size);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: SizedBox(width: widget.size, height: widget.size, child: face),
    );
  }
}
