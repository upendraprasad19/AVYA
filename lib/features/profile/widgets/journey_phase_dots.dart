import 'package:flutter/material.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';

/// Number of phase dots the Profile journey card draws at once.
const int kJourneyDotsPerBlock = 12;

/// The first phase of the 12-phase block that holds [currentPhase]:
/// phases 1-12 -> 1, 13-24 -> 13, 25-36 -> 25. A phase below 1 is treated
/// as 1.
///
/// Phases do not stop at XII (OI-348 Landing 3a). Before this, the card drew
/// phases 1-12 only, so from Phase 13 every dot read completed and none read
/// current. Phases 1-12 render exactly as before.
int journeyDotBlockStart(int currentPhase) {
  final p = currentPhase < 1 ? 1 : currentPhase;
  return ((p - 1) ~/ kJourneyDotsPerBlock) * kJourneyDotsPerBlock + 1;
}

/// The journey card's phase name. Past the 12 names the list cycles (Phase 13
/// is "Foundation" again), so the line never reads "Phase 13 — Phase 13".
String journeyPhaseName(int currentPhase) {
  const phaseNames = [
    'Foundation', 'Building', 'Progression', 'Strength',
    'Endurance', 'Power', 'Conditioning', 'Peak',
    'Mastery', 'Elite', 'Champion', 'Legend',
  ];
  final p = currentPhase < 1 ? 1 : currentPhase;
  return phaseNames[(p - 1) % phaseNames.length];
}

/// The row of phase dots on the Profile journey card: the 12-phase block that
/// holds [currentPhase]. Completed phases are green, the current one gold;
/// a free user's future phases are dimmed, except Phase I (always free).
class JourneyPhaseDots extends StatelessWidget {
  const JourneyPhaseDots({
    super.key,
    required this.currentPhase,
    required this.isPro,
  });

  final int currentPhase;
  final bool isPro;

  @override
  Widget build(BuildContext context) {
    final start = journeyDotBlockStart(currentPhase);
    return Row(
      children: List.generate(kJourneyDotsPerBlock, (i) {
        final phase = start + i;
        final isCompleted = phase < currentPhase;
        final isCurrent = phase == currentPhase;
        return Expanded(
          child: Container(
            key: ValueKey('journey_dot_$phase'),
            margin: EdgeInsets.only(
                right: i < kJourneyDotsPerBlock - 1 ? 3 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: isCompleted
                  ? AppColors.ok
                  : isCurrent
                      ? AppColors.accent
                      : isPro || phase == 1
                          ? AppColors.bgRaise
                          : AppColors.bgRaise.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(AppRadius.sharp),
            ),
          ),
        );
      }),
    );
  }
}
