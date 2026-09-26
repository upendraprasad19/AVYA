import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/services/rank_ladder_data.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/features/profile/providers/profile_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
import 'package:icanbefitter/core/utils/hold_week_labels.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet_phase_variant.dart';
import 'package:icanbefitter/shared/widgets/wardroom/ward_rank_insignia.dart';

/// 12-week + lifetime phase roadmap.
///
/// Route: `/train/roadmap` (registered in app_router.dart).
///
/// Vertical timeline. Sections (top to bottom):
///   1. Header: DEPLOYMENT 01 · FOUNDATION  WK N/12  X% complete
///   2. W1 marker (current position when user is in week 1)
///   3. Phase I — Foundation (W1-4)
///      Promotion marker at W2 (SD1)
///   4. Phase II — Strength (W5-8) — PRO 🔒 for free users
///      Promotion marker at W4 (LS — between phase blocks)
///   5. Phase III — Hypertrophy (W9-12) — PRO 🔒 for free users
///   6. W12 promotion marker → PETTY OFFICER · DEBRIEF + DEPLOYMENT 02
///   7. Year 1 divider band
///   8. W26 (CPO), W52 (MCPO 1-Year Service Pin)
///   9. Year 2 divider band
///  10. W104 (Sub Lieutenant — Officer Commission, gold stripe)
///  11. Years 3-5 divider band
///  12. W156 (LtCdr), W208 (Cdr), W260 (Captain — faint)
///
/// Tap any rank marker → small detail sheet with insignia + gate +
/// progress.
class PhaseRoadmapScreen extends ConsumerWidget {
  const PhaseRoadmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // APK Test #12 / Task C-2 — watch subscriptionInfoProvider for
    // reactive lock-glyph updates after PRO upgrade.
    final isPro = ref.watch(subscriptionInfoProvider).isPro;
    // Program week within the 12-week deployment (Phase 2 wk 3 → 7) so the
    // header counter + % + active-phase highlight reflect true progress, not
    // the 1-4 week-within-phase. Pre-fix this fed getCurrentWeekNumber (1-4),
    // pinning the Roadmap to "Phase I active / 33% complete" regardless of the
    // real phase (diagnose 2026-06-06).
    final currentPhase =
        (UserRepository.instance.getProgress()?['current_phase'] as int?) ?? 1;
    final currentWeek = ref
        .read(workoutScheduleReadServiceProvider)
        .getProgramWeek(currentPhase);
    final completePct = ((currentWeek / 12) * 100).clamp(0, 100).round();
    // FOB-1 (OI-60): getProgramWeek is programWeekFor(phase,
    // getCurrentWeekNumber()), and that inner call clamps to [1,4] — so a
    // phase-1 holder read "WK 4 / 12" at every ordinal, forever. The PERCENT
    // and the bar stay derived from currentWeek (four of twelve program weeks
    // really are done); only the week COUNTER is dishonest for a holder, so
    // only it is suppressed. Null while `enable_hold_weeks` is OFF.
    final holdOrdinal = ref.watch(weekIdentityProvider).holdOrdinal;
    // Header phase name from current_phase (was hardcoded "FOUNDATION" — wrong
    // for any non-phase-1 user; review P2 2026-06-06).
    final phaseName = ref
        .read(workoutScheduleReadServiceProvider)
        .phaseName(currentPhase);

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          'Roadmap',
          style: AppTypography.titleL.copyWith(fontSize: 20),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
        children: [
          _DeploymentHeader(
            currentWeek: currentWeek,
            completePct: completePct,
            phaseName: phaseName,
            holdOrdinal: holdOrdinal,
          ),
          const SizedBox(height: 16),

          // ── Phase I (free) ────────────────────────────
          _PhaseBlock(
            number: 'I',
            name: 'FOUNDATION',
            weekRange: 'W1 – W4',
            description: 'Push / Pull / Legs · 6 ex/day',
            isLocked: false,
            isActive: currentWeek <= 4,
          ),

          _PromotionMarker(rankCode: 'SD1', whenLabel: 'WEEK 2'),
          _PromotionMarker(rankCode: 'LS', whenLabel: 'WEEK 4'),

          // ── Phase II (PRO) ────────────────────────────
          _PhaseBlock(
            number: 'II',
            name: 'STRENGTH',
            weekRange: 'W5 – W8',
            description: 'Heavier compounds, lower reps, real progression.',
            isLocked: !isPro,
            isActive: currentWeek >= 5 && currentWeek <= 8,
            onTapPreview: isPro
                ? () => context.push('/train/preview?phase=II&week=5&day=1')
                : null,
          ),

          // ── Phase III (PRO) ───────────────────────────
          _PhaseBlock(
            number: 'III',
            name: 'HYPERTROPHY',
            weekRange: 'W9 – W12',
            description: 'Volume push. Muscle-building emphasis.',
            isLocked: !isPro,
            isActive: currentWeek >= 9 && currentWeek <= 12,
            onTapPreview: isPro
                ? () => context.push('/train/preview?phase=III&week=9&day=1')
                : null,
          ),

          _PromotionMarker(
            rankCode: 'PO',
            whenLabel: 'WEEK 12 — DEBRIEF + DEPLOYMENT 02',
            emphasised: true,
          ),

          // ── Year 1 band ───────────────────────────────
          const _YearBand(label: 'YEAR 1'),
          _PromotionMarker(rankCode: 'CPO', whenLabel: 'WEEK 26'),
          _PromotionMarker(
            rankCode: 'MCPO',
            whenLabel: 'WEEK 52 · 1-YEAR SERVICE PIN',
          ),

          // ── Year 2 band ───────────────────────────────
          const _YearBand(label: 'YEAR 2'),
          _PromotionMarker(
            rankCode: 'SubLt',
            whenLabel: 'WEEK 104 · OFFICER COMMISSION',
            emphasised: true,
          ),

          // ── Years 3-5 band ────────────────────────────
          const _YearBand(label: 'YEARS 3 — 5'),
          _PromotionMarker(rankCode: 'Lt', whenLabel: 'WEEK 130'),
          _PromotionMarker(rankCode: 'LtCdr', whenLabel: 'WEEK 156'),
          _PromotionMarker(rankCode: 'Cdr', whenLabel: 'WEEK 208'),
          _PromotionMarker(rankCode: 'Capt', whenLabel: 'WEEK 260', faint: true),
          const SizedBox(height: 20),
        ],
      ),
      bottomNavigationBar: isPro
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => showPaywallSheetPhaseVariant(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.bg,
                    elevation: 0,
                    shape: const StadiumBorder(),
                  ),
                  child: Text(
                    'UPGRADE TO PRO  →',
                    style: AppTypography.mono.copyWith(
                      fontSize: 13,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w800,
                      color: AppColors.bg,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────

class _DeploymentHeader extends StatelessWidget {
  const _DeploymentHeader({
    required this.currentWeek,
    required this.completePct,
    required this.phaseName,
    this.holdOrdinal,
  });
  final int currentWeek;
  final int completePct;
  final String phaseName;

  /// 1-based hold number when today is a live hold day, else null (FOB-1).
  final int? holdOrdinal;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'DEPLOYMENT 01 · ${phaseName.toUpperCase()}',
          style: AppTypography.mono.copyWith(
            color: AppColors.accent,
            fontSize: 11,
            letterSpacing: 2.0,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          roadmapWeekLabel(
            holdOrdinal: holdOrdinal,
            programWeek: currentWeek,
            completePct: completePct,
          ),
          style: AppTypography.h3.copyWith(
            fontSize: 15,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.input,
            borderRadius: BorderRadius.circular(2),
          ),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (currentWeek / 12).clamp(0.0, 1.0),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Phase block ───────────────────────────────────────────────────

class _PhaseBlock extends StatelessWidget {
  const _PhaseBlock({
    required this.number,
    required this.name,
    required this.weekRange,
    required this.description,
    required this.isLocked,
    required this.isActive,
    this.onTapPreview,
  });

  final String number;
  final String name;
  final String weekRange;
  final String description;
  final bool isLocked;
  final bool isActive;
  final VoidCallback? onTapPreview;

  @override
  Widget build(BuildContext context) {
    final borderColor = isActive
        ? AppColors.accent
        : (isLocked
            ? AppColors.line2
            : AppColors.accent.withValues(alpha: 0.3));

    return GestureDetector(
      onTap: isLocked
          ? () => showPaywallSheetPhaseVariant(context)
          : onTapPreview,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isActive ? 1.5 : 1),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.accent),
              ),
              alignment: Alignment.center,
              child: Text(
                number,
                style: AppTypography.mono.copyWith(
                  fontSize: 12,
                  color: AppColors.accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        name,
                        style: AppTypography.titleL.copyWith(fontSize: 14),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        weekRange,
                        style: AppTypography.mono.copyWith(
                          fontSize: 9,
                          letterSpacing: 1.0,
                          color: AppColors.textMute,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: AppTypography.bodyS.copyWith(
                      color: AppColors.textDim,
                    ),
                  ),
                ],
              ),
            ),
            if (isLocked)
              const Icon(Icons.lock, size: 14, color: AppColors.accent)
            else if (isActive)
              const Icon(Icons.check_circle, size: 16, color: AppColors.ok),
          ],
        ),
      ),
    );
  }
}

// ── Promotion marker ──────────────────────────────────────────────

class _PromotionMarker extends StatelessWidget {
  const _PromotionMarker({
    required this.rankCode,
    required this.whenLabel,
    this.emphasised = false,
    this.faint = false,
  });

  final String rankCode;
  final String whenLabel;
  final bool emphasised;
  final bool faint;

  @override
  Widget build(BuildContext context) {
    final entry = rankByCode(rankCode) ?? rankByCode('SD2')!;
    final opacity = faint ? 0.4 : 1.0;

    return Opacity(
      opacity: opacity,
      child: GestureDetector(
        onTap: () => _showRankDetail(context, entry),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              const SizedBox(width: 32),
              Container(
                width: 1,
                height: 30,
                color: AppColors.line2,
              ),
              const SizedBox(width: 14),
              // audit-2026-05-16 E.11 — migrated from legacy RankInsignia.
              WardRankInsignia(
                rankCode: rankCode,
                size: emphasised ? 32 : 24,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName.toUpperCase(),
                      style: AppTypography.mono.copyWith(
                        fontSize: emphasised ? 11 : 10,
                        letterSpacing: 1.3,
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      whenLabel,
                      style: AppTypography.bodyS.copyWith(
                        color: AppColors.textDim,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showRankDetail(BuildContext context, RankLadderEntry entry) {
    final next = RankService.instance.getNextRank();
    final current = RankService.instance.getCurrentRank();
    final isEarned = entry.ordinal <= current.entry.ordinal;
    final progressText = isEarned
        ? 'Earned'
        : (next != null && next.entry.code == entry.code
            ? (next.daysUntilEligible != null
                ? '${next.daysUntilEligible} days to go'
                : 'Working toward this rank')
            : 'Locked');

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // audit-2026-05-16 E.11 — migrated from legacy RankInsignia.
                WardRankInsignia(rankCode: entry.code, size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.displayName,
                        style: AppTypography.titleL.copyWith(fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${entry.minWeeks} weeks since signup minimum',
                        style: AppTypography.bodyS.copyWith(
                          color: AppColors.textDim,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              progressText,
              style: AppTypography.mono.copyWith(
                color: AppColors.accent,
                fontSize: 11,
                letterSpacing: 1.3,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Year band ─────────────────────────────────────────────────────

class _YearBand extends StatelessWidget {
  const _YearBand({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: AppColors.line2)),
          const SizedBox(width: 12),
          Text(
            label,
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 2.0,
              color: AppColors.textMute,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Container(height: 1, color: AppColors.line2)),
        ],
      ),
    );
  }
}
