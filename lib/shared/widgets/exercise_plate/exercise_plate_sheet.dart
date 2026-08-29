// lib/shared/widgets/exercise_plate/exercise_plate_sheet.dart
//
// The plate. Two images for a movement that cycles, one for a hold. Free to
// every tier, matching the FORM & CUES panel it sits beside.
//
// NOTE on the "never resolve library data in build()" constraint: this widget
// DOES, deliberately. That rule exists for the Active Workout card, which
// rebuilds ~1x/second off the workout timer. A modal sheet builds once when it
// opens; paying two linear scans of exerciseBox there is the simpler trade.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/exercise_monogram.dart';
import 'package:icanbefitter/shared/widgets/exercise_plate/plate_resolver.dart';

class ExercisePlateSheet extends StatelessWidget {
  final String exerciseName;

  const ExercisePlateSheet({super.key, required this.exerciseName});

  static Future<void> show(BuildContext context, String exerciseName) {
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

  /// Cues arrive in three shapes across the 292 rows, counted 2026-08-29: a
  /// single string packed with semicolons (84), a real array (100), or one
  /// plain cue (108). Splitting on ';' renders all three as lines.
  List<String> _cues(Map<String, dynamic>? row) {
    final raw = row?['coaching_cues'];
    if (raw is! List) return const [];
    return raw
        .expand((c) => c.toString().split(';'))
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toList(growable: false);
  }

  /// `is String`, never a cast — community rows carry arbitrary JSON types.
  String? _clean(Object? v) {
    final s = v is String ? v.trim() : '';
    return s.isEmpty ? null : s;
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
                errorBuilder: (_, __, ___) =>
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

  @override
  Widget build(BuildContext context) {
    final plate = resolvePlate(exerciseName);
    final row = ExerciseRepository.instance.getByExactName(exerciseName);
    final cues = _cues(row);
    final breathing = _clean(row?['breathing_cue']);
    // 136 of 292 rows carry a bare number here — a spreadsheet column shift that
    // put met_value into breathing_cue. Suppress rather than print
    // "BREATHING / 5". coaching_content_panel applies the identical guard; the
    // data repair is OI-149, blocked on 136 cues having to be re-authored.
    final showBreathing =
        breathing != null && !RegExp(r'^\d+(\.\d+)?$').hasMatch(breathing);

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
            if (plate.hasArtwork)
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
            if (showBreathing) ...[
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
