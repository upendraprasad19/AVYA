import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
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

// ── Pure position helpers (OI-447) ────────────────────────────────

/// 1-based deployment a phase belongs to: phases 1-3 are Deployment 01,
/// 4-6 Deployment 02, and so on. The roadmap used to print a literal
/// `DEPLOYMENT 01` for everyone (diagnose b7f1c8 fixed the same literal on the
/// Train screen). A phase below 1 is read as 1, like `programWeekFor`.
int roadmapDeploymentNumber(int phase) =>
    (((phase < 1 ? 1 : phase) - 1) ~/ 3) + 1;

/// Header eyebrow: `DEPLOYMENT 02 · FOUNDATION`.
String roadmapDeploymentEyebrow(int phase, String phaseName) =>
    'DEPLOYMENT ${roadmapDeploymentNumber(phase).toString().padLeft(2, '0')}'
    ' · ${phaseName.toUpperCase()}';

/// Weeks of program done across ALL deployments: `(phase - 1) * 4` plus the
/// week within the phase (1-4, the clamped value, so a holder reads the last
/// week they finished). `programWeekFor` folds this back into 1-12.
int roadmapAbsoluteWeek(int phase, int weekInPhase) =>
    ((phase < 1 ? 1 : phase) - 1) * 4 + weekInPhase;

/// "You are here" caption on the rank ladder. A holder sits OUTSIDE the
/// phase's weeks, so the caption says HOLDING instead of claiming a new one.
String roadmapYouAreHereLabel({required int absoluteWeek, int? holdOrdinal}) =>
    holdOrdinal != null
    ? 'YOU ARE HERE · HOLDING AFTER WEEK $absoluteWeek'
    : 'YOU ARE HERE · PROGRAM WEEK $absoluteWeek';

/// The rank ladder below the 12-week deployment, in order. `week` is the
/// number printed in `whenLabel` and is what the marker is placed against.
class _LadderRow {
  const _LadderRow(
    this.rankCode,
    this.week,
    this.whenLabel, {
    this.band,
    this.emphasised = false,
    this.faint = false,
  });
  final String rankCode;
  final int week;
  final String whenLabel;

  /// Year band drawn directly above this row.
  final String? band;
  final bool emphasised;
  final bool faint;
}

const List<_LadderRow> _ladder = [
  _LadderRow('CPO', 26, 'WEEK 26', band: 'YEAR 1'),
  _LadderRow('MCPO', 52, 'WEEK 52 · 1-YEAR SERVICE PIN'),
  _LadderRow(
    'SubLt',
    104,
    'WEEK 104 · OFFICER COMMISSION',
    band: 'YEAR 2',
    emphasised: true,
  ),
  _LadderRow('Lt', 130, 'WEEK 130', band: 'YEARS 3 — 5'),
  _LadderRow('LtCdr', 156, 'WEEK 156'),
  _LadderRow('Cdr', 208, 'WEEK 208'),
  _LadderRow('Capt', 260, 'WEEK 260', faint: true),
];

/// Index into [_ladder] the "you are here" row goes BEFORE (`_ladder.length` =
/// after the last row), or null while [absoluteWeek] is still inside the first
/// deployment: there the active phase block already says where the user is.
int? roadmapLadderMarkerIndex(int absoluteWeek) {
  if (absoluteWeek <= 12) return null;
  final i = _ladder.indexWhere((r) => r.week > absoluteWeek);
  return i == -1 ? _ladder.length : i;
}

/// 12-week + lifetime phase roadmap.
///
/// Route: `/train/roadmap` (registered in app_router.dart).
///
/// Vertical timeline. Sections (top to bottom):
///   1. Header: DEPLOYMENT NN · FOUNDATION  WK N/12  X% complete
///      (NN from the phase; earlier deployments listed as complete)
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
    // OI-447: the week WITHIN the phase (1-4, clamped), kept so the ladder
    // marker can place the user on the ABSOLUTE program week.
    final weekInPhase = ref
        .read(workoutScheduleReadServiceProvider)
        .getCurrentWeekNumber();
    // FOB-1 (OI-60): getProgramWeek is programWeekFor(phase,
    // getCurrentWeekNumber()), and that inner call clamps to [1,4] — so a
    // phase-1 holder read "WK 4 / 12" at every ordinal, forever. The PERCENT
    // and the bar stay derived from currentWeek (four of twelve program weeks
    // really are done); only the week COUNTER is dishonest for a holder, so
    // only it is suppressed. Null for a non-holder.
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
      body: RoadmapBody(
        phase: currentPhase,
        weekInPhase: weekInPhase,
        programWeek: currentWeek,
        phaseName: phaseName,
        holdOrdinal: holdOrdinal,
        isPro: isPro,
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
                    showsUpgradeAffordance()
                        ? 'UPGRADE TO PRO  →'
                        : PurchaseCopy.seeWhatProIncludesCta,
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

/// The roadmap's scrolling content, built from plain values so a test can pump
/// it without Hive or a provider scope (OI-447).
class RoadmapBody extends StatelessWidget {
  const RoadmapBody({
    super.key,
    required this.phase,
    required this.weekInPhase,
    required this.programWeek,
    required this.phaseName,
    required this.isPro,
    this.holdOrdinal,
  });

  /// `user_progress.current_phase` (1-12).
  final int phase;

  /// Week within the phase, 1-4 (clamped; a holder reads 4).
  final int weekInPhase;

  /// Week within the CURRENT 12-week deployment (`getProgramWeek`), 1-12.
  final int programWeek;
  final String phaseName;
  final bool isPro;

  /// 1-based hold number while holding, else null.
  final int? holdOrdinal;

  @override
  Widget build(BuildContext context) {
    final currentWeek = programWeek;
    final completePct = ((currentWeek / 12) * 100).clamp(0, 100).round();
    final absoluteWeek = roadmapAbsoluteWeek(phase, weekInPhase);
    final markerAt = roadmapLadderMarkerIndex(absoluteWeek);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        _DeploymentHeader(
          deploymentNumber: roadmapDeploymentNumber(phase),
          currentWeek: currentWeek,
          completePct: completePct,
          phaseName: phaseName,
          holdOrdinal: holdOrdinal,
        ),
        const SizedBox(height: 16),
        for (var d = 1; d < roadmapDeploymentNumber(phase); d++)
          _CompletedDeployment(number: d),

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

        // ── Rank ladder (Year 1 → Years 3-5) ──────────
        for (var i = 0; i <= _ladder.length; i++) ...[
          if (i == markerAt)
            _YouAreHere(
              label: roadmapYouAreHereLabel(
                absoluteWeek: absoluteWeek,
                holdOrdinal: holdOrdinal,
              ),
            ),
          if (i < _ladder.length) ...[
            if (_ladder[i].band != null) _YearBand(label: _ladder[i].band!),
            _PromotionMarker(
              rankCode: _ladder[i].rankCode,
              whenLabel: _ladder[i].whenLabel,
              emphasised: _ladder[i].emphasised,
              faint: _ladder[i].faint,
            ),
          ],
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────

class _DeploymentHeader extends StatelessWidget {
  const _DeploymentHeader({
    required this.deploymentNumber,
    required this.currentWeek,
    required this.completePct,
    required this.phaseName,
    this.holdOrdinal,
  });
  final int deploymentNumber;
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
          'DEPLOYMENT ${deploymentNumber.toString().padLeft(2, '0')}'
          ' · ${phaseName.toUpperCase()}',
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

// ── Earlier deployments + ladder position ─────────────────────────

class _CompletedDeployment extends StatelessWidget {
  const _CompletedDeployment({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: ValueKey('roadmap_deployment_complete_$number'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Text(
            'DEPLOYMENT ${number.toString().padLeft(2, '0')} · COMPLETE',
            style: AppTypography.mono.copyWith(
              fontSize: 10,
              letterSpacing: 1.6,
              color: AppColors.textDim,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _YouAreHere extends StatelessWidget {
  const _YouAreHere({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('roadmap_you_are_here'),
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const SizedBox(width: 32),
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: AppTypography.mono.copyWith(
                fontSize: 10,
                letterSpacing: 1.4,
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
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
