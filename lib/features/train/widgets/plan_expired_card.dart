import 'package:icanbefitter/core/copy/purchase_copy.dart';
import 'package:icanbefitter/core/constants/purchase_mode.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/services/app_events_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'keep_training_phase1_action.dart';

/// Day-29+ free-tier UI shown on Home + Train when Phase 1 has
/// elapsed. Two doors and a hint:
///
///   1. Primary · Upgrade to PRO        → opens paywall sheet (PaywallSheet.phaseProgressionFeature)
///   2. Hold the line — another week    → `holdWeek()` (Unit 3D-b, d57)
///   3. Hint · MY TEMPLATES             → navigates to template builder
///
/// Analytics:
///   - `phase_1_day_29_expired_seen` fires once per day the card renders.
///   - CTA taps fire `phase_1_day_29_{upgrade,template_builder,redo_week_4}_tapped`
///     (the hold tap keeps the `redo_week_4` name: a stored telemetry key,
///     renaming it would split its history).
///   - `phase_1_cycle_repeat_started` only when `holdWeek()` returns `written`.
///
/// Used by:
///   - `home_screen.dart` when today has no scheduled workout AND phase expired.
///   - `train_screen.dart` (today tab) same condition.
///
/// Part of audit H9 (day-29 dead-end fix, 2026-04-18).
class PlanExpiredCard extends ConsumerStatefulWidget {
  final VoidCallback? onRedoComplete;

  const PlanExpiredCard({super.key, this.onRedoComplete});

  @override
  ConsumerState<PlanExpiredCard> createState() => _PlanExpiredCardState();
}

class _PlanExpiredCardState extends ConsumerState<PlanExpiredCard> {
  bool _seenLogged = false;
  bool _redoing = false;

  @override
  void initState() {
    super.initState();
    // Log the impression once per mount. Good enough for beta —
    // daily-unique counting can be a post-beta refinement.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_seenLogged) {
        _seenLogged = true;
        AppEventsService.instance.log('phase_1_day_29_expired_seen');
      }
    });
  }

  Future<void> _handleHoldWeek() async {
    if (_redoing) return;
    setState(() => _redoing = true);
    AppEventsService.instance.log('phase_1_day_29_redo_week_4_tapped');
    try {
      final outcome = await runFreeTierRepeatWrite(ref);
      if (outcome == HoldWeekOutcome.written) {
        AppEventsService.instance.log('phase_1_cycle_repeat_started');
      }
      if (!mounted) return;
      switch (outcome) {
        case HoldWeekOutcome.written:
          // A hold is NOT "week 4 again" — it materializes the phase's Peak
          // week (or a deload every 4th) dated to THIS week.
          _snack('Line held. Another week on the board.', AppColors.card);
          widget.onRedoComplete?.call();
        case HoldWeekOutcome.alreadyHolding:
          // The double tap (defect A): nothing was written, nothing to refresh.
          _snack('Already holding this week.', AppColors.card);
        case HoldWeekOutcome.inFlight:
          break; // the first tap is still writing; it reports its own outcome
        case HoldWeekOutcome.noPlan:
        case HoldWeekOutcome.failed:
          _snack("Couldn't schedule again. Please try again.", AppColors.red);
      }
    } catch (e) {
      if (!mounted) return;
      _snack("Couldn't schedule again. Please try again.", AppColors.red);
    } finally {
      if (mounted) setState(() => _redoing = false);
    }
  }

  void _snack(String text, Color background) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: AppTypography.body.copyWith(fontSize: 13),
        ),
        backgroundColor: background,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleUpgrade() {
    AppEventsService.instance.log('phase_1_day_29_upgrade_tapped');
    // Pass the DISPLAY token (matches phase_unlock_card.dart) so
    // PaywallSheet._featureSubtitle resolves the "You crushed Phase 1"
    // subtitle instead of falling back to the generic copy. Passing the
    // gate-KEY ('phases_2_to_12') misses the switch.
    showPaywallSheet(context, feature: PaywallSheet.phaseProgressionFeature);
  }

  void _handleTemplateBuilder() {
    AppEventsService.instance.log('phase_1_day_29_template_builder_tapped');
    context.go('/train/template-builder');
  }

  @override
  Widget build(BuildContext context) {
    // The card names the phase you BANKED and the one you'd deploy to. Both were
    // hardcoded "1"/"2", so a phase-2+ user whose plan expired was told they had
    // secured Phase 1 and offered a Phase 2 they already own. Same repository
    // read `phase2_preview_card.dart:64-65` uses; current_phase cannot change
    // while this card is mounted (an advance removes the card).
    final currentPhase =
        (UserRepository.instance.getProgress()?['current_phase'] as int?) ?? 1;
    final nextPhase = currentPhase + 1;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — endowed-progress lead (Phase 1 already banked)
          Text(
            'Phase $currentPhase — secured, Recruit.',
            style: AppTypography.body.copyWith(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            'Phase $nextPhase: new drills, supersets, progressive overload — your orders are ready.',
            style: AppTypography.body.copyWith(fontSize: 13, color: AppColors.textDim, height: 1.4),
          ),
          const SizedBox(height: 18),

          // Primary — Upgrade to PRO
          _primaryCta(nextPhase),
          const SizedBox(height: 12),

          // Holding is a REAL second door (an indefinite, correctly-periodized
          // free path), an accented pill beside the upgrade CTA: the locked
          // mockup's two-door wall. Unit 3D-b deleted the old three-link
          // "Run Week 4 again" layout with the `enable_hold_weeks` flag.
          _holdTheLineCta(),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppColors.border),
          const SizedBox(height: 12),
          _templateHint(),
        ],
      ),
    );
  }

  /// Outlined gold pill — the free door, weighted to read as a genuine choice
  /// next to the gold-filled upgrade CTA rather than a consolation link.
  Widget _holdTheLineCta() {
    return GestureDetector(
      onTap: _redoing ? null : _handleHoldWeek,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.accent, width: 1.5),
        ),
        child: Center(
          child: _redoing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                )
              : Text(
                  'Hold the line — another week',
                  style: AppTypography.body.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.accent,
                  ),
                ),
        ),
      ),
    );
  }

  /// The template door, kept reachable as a hint line so the two primary doors
  /// stay visually uncontested (locked mockup).
  Widget _templateHint() {
    return GestureDetector(
      onTap: _handleTemplateBuilder,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.build_outlined, size: 15, color: AppColors.textMute),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                text: 'Want different drills? Draw up your own from ',
                children: [
                  TextSpan(
                    text: 'MY TEMPLATES',
                    style: AppTypography.body.copyWith(
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textDim,
                    ),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: AppTypography.body.copyWith(
                fontSize: 11.5,
                height: 1.4,
                color: AppColors.textMute,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryCta(int nextPhase) {
    return GestureDetector(
      onTap: _handleUpgrade,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
              color: AppColors.accent.withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            PurchaseCopy.deployToPhase(nextPhase,
                purchaseUi: showsUpgradeAffordance()),
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
          ),
        ),
      ),
    );
  }
}
