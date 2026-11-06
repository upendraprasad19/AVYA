part of 'screen.dart';

extension _JourneyTimeline on _ProfileScreenState {

  // ── #4 Journey Timeline ─────────────────────────────────────────

  Widget _buildJourneyTimelineInner(
    UserStatsData stats, {
    required double? currentWeightKg,
    required double? targetWeightKg,
    required String goal,
  }) {
    // Phase data
    const phaseNames = [
      'Foundation', 'Building', 'Progression', 'Strength',
      'Endurance', 'Power', 'Conditioning', 'Peak',
      'Mastery', 'Elite', 'Champion', 'Legend',
    ];
    final phaseName = stats.currentPhase <= phaseNames.length
        ? phaseNames[stats.currentPhase - 1]
        : 'Phase ${stats.currentPhase}';

    // Goal insights — sourced from userProfileProvider (single source of truth)
    final currentWeight = currentWeightKg ?? 0;
    final targetWeight = targetWeightKg ?? 0;

    // Weight trajectory (from weight logs in healthBox)
    final hive = HiveService.instance;
    final weightEntries = <MapEntry<DateTime, double>>[];
    for (final key in hive.healthBox.keys) {
      if (key is! String || !key.startsWith('weight_')) continue;
      final raw = hive.healthBox.get(key);
      if (raw is! Map) continue;
      final w = (raw['weight_kg'] as num?)?.toDouble();
      final d = DateTime.tryParse(raw['date'] as String? ?? '');
      if (w != null && d != null) weightEntries.add(MapEntry(d, w));
    }
    weightEntries.sort((a, b) => a.key.compareTo(b.key));

    // Compute weekly rate and ETA
    String? trajectoryText;
    String? etaText;
    if (weightEntries.length >= 2 && targetWeight > 0) {
      final first = weightEntries.first;
      final last = weightEntries.last;
      final weeksDiff = last.key.difference(first.key).inDays / 7.0;
      if (weeksDiff > 0.5) {
        final totalChange = last.value - first.value;
        final weeklyRate = totalChange / weeksDiff;
        final remaining = targetWeight - last.value;

        if (weeklyRate.abs() > 0.05 && !weeklyRate.isNaN && !weeklyRate.isInfinite) {
          final changeStr = totalChange.abs().toStringAsFixed(1);
          final verb = totalChange < 0 ? 'Lost' : 'Gained';
          trajectoryText = '$verb ${changeStr}kg in ${weeksDiff.toStringAsFixed(0)} weeks';

          // ETA: if moving in the right direction
          final movingRight = (goal.contains('lose') && weeklyRate < 0) ||
              (goal.contains('build') && weeklyRate > 0) ||
              (remaining.abs() < 0.5);
          if (movingRight && remaining.abs() > 0.5 && weeklyRate != 0) {
            final weeksToGo = (remaining / weeklyRate).abs().ceil();
            etaText = 'At this rate: ~$weeksToGo weeks to goal';
          }
        }
      }
    }

    // (Workout consistency data could be added here in future phases)

    // Theme C · Test #8 — inner-only: caller wraps with `_buildFlushCard`.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Text(
              'YOUR JOURNEY',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                // FOB-1 (OI-60): a holder has no honest "WEEK n OF 4" — the
                // phase's four weeks are elapsed and the hold sits outside
                // them, so the clamp printed "WEEK 4 OF 4" forever. Hn is the
                // identity. `isHolding` is false for every user while
                // `enable_hold_weeks` is OFF, so this is the pre-fix string.
                journeyWeekLabel(
                  holdOrdinal: stats.holdOrdinal,
                  weekInPhase: stats.currentWeek,
                ),
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Phase name — Fraunces
          Text(
            'Phase ${stats.currentPhase} \u2014 $phaseName',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          // Week progress bar within phase. Deliberately NOT hold-branched:
          // `currentWeek` stays clamped at 4 during a hold and the phase's four
          // weeks genuinely ARE elapsed, so a full bar is the honest reading.
          // Branching it to the hold ordinal would divide an H-number by 4.
          WardBar(pct: stats.currentWeek / 4.0, color: AppColors.accent, height: 4),
          const SizedBox(height: 10),

          // Phase dots
          Row(
            children: List.generate(12, (phase) {
              final isCompleted = phase + 1 < stats.currentPhase;
              final isCurrent = phase + 1 == stats.currentPhase;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: phase < 11 ? 3 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.ok
                        : isCurrent
                            ? AppColors.accent
                            : stats.isPro || phase == 0
                                ? AppColors.bgRaise
                                : AppColors.bgRaise.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),

          // Motivating insights
          if (targetWeight > 0 && currentWeight > 0) ...[
            _journeyInsight(
              icon: Icons.flag_outlined,
              // OBS-12 — read "Reach 70kg" (the target weight is a destination,
              // not an amount to lose); "Lose 70kg" mis-read as "lose 70 kg".
              text: 'Goal: Reach ${targetWeight.toStringAsFixed(0)}kg',
              color: AppColors.accent,
            ),
          ],
          if (trajectoryText != null)
            _journeyInsight(
              icon: Icons.trending_down,
              text: trajectoryText,
              color: AppColors.ok,
            ),
          if (etaText != null)
            _journeyInsight(
              icon: Icons.timer_outlined,
              text: etaText,
              color: AppColors.accent,
            ),
          if (trajectoryText == null && targetWeight > 0)
            _journeyInsight(
              icon: Icons.scale_outlined,
              text: 'Log your weight daily to see your trajectory',
              color: AppColors.textDim,
            ),

          // Next milestone
          if (stats.currentPhase == 1) ...[
            const SizedBox(height: 2),
            _journeyInsight(
              icon: Icons.emoji_events_outlined,
              // A holder has already completed the four weeks, so the countdown
              // resolved to a flat "0 weeks to complete Phase 1" — technically
              // true, and useless, on the one surface a holder sees most. State
              // where they actually are instead (FOB-1 / OI-60). Inert while
              // `enable_hold_weeks` is OFF.
              text: journeyPhaseOneMilestone(
                holdOrdinal: stats.holdOrdinal,
                weekInPhase: stats.currentWeek,
              ),
              color: AppColors.proGold,
            ),
          ],
      ],
    );
  }

  Widget _journeyInsight({required IconData icon, required String text, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySm.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Plan D D-10: Predictions list-row helpers ──────────────────

  String _truncatedPredictionPreview(PredictionData? prediction,
      {int maxChars = 50}) {
    final p = (prediction?.predictionText ?? '').trim();
    if (p.isEmpty) return 'Tap to generate your forecast';
    if (p.length <= maxChars) return p;
    return '${p.substring(0, maxChars).trimRight()}…';
  }
}
