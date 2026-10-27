import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:icanbefitter/core/services/app_events_service.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'keep_training_phase1_action.dart';

/// Day-29+ free-tier UI shown on Home + Train when Phase 1 has
/// elapsed. Three doors:
///
///   1. Primary · Upgrade to PRO   → opens paywall sheet ('Phases 2-12')
///   2. Secondary · Build your own → navigates to template builder
///   3. Tertiary · Re-do Week 4   → copies last week's schedule forward
///
/// Analytics:
///   - `phase_1_day_29_expired_seen` fires once per day the card renders.
///   - CTA taps fire `phase_1_day_29_{upgrade,template_builder,redo_week_4}_tapped`.
///   - `phase_1_cycle_repeat_started` after redoWeek4() writes the new schedule.
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

  Future<void> _handleRedoWeek4() async {
    if (_redoing) return;
    setState(() => _redoing = true);
    AppEventsService.instance.log('phase_1_day_29_redo_week_4_tapped');
    try {
      // Ship-dark: enable_hold_weeks flips the free-tier mechanic from the
      // verbatim redoWeek4 (trailing-week copy) to the correct holdWeek
      // (Peak/deload-by-date, Monday-aligned, plan_json-durable). Default OFF.
      // The branch itself lives in ONE place — see runFreeTierRepeatWrite.
      await runFreeTierRepeatWrite(ref);
      AppEventsService.instance.log('phase_1_cycle_repeat_started');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            // A hold is NOT "week 4 again" — it materializes the phase's Peak
            // week (or a deload every 4th) dated to THIS week.
            PlanEngineFlags.holdWeeksEnabled
                ? 'Line held. Another week on the board.'
                : 'Week 4 back on the board. Carry on.',
            style: AppTypography.body.copyWith(fontSize: 13),
          ),
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      widget.onRedoComplete?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Couldn't schedule again. Please try again.",
            style: AppTypography.body.copyWith(fontSize: 13),
          ),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _redoing = false);
    }
  }

  void _handleUpgrade() {
    AppEventsService.instance.log('phase_1_day_29_upgrade_tapped');
    // Pass the DISPLAY token (matches phase_unlock_card.dart) so
    // PaywallSheet._featureSubtitle resolves the "You crushed Phase 1"
    // subtitle instead of falling back to the generic copy. Passing the
    // gate-KEY ('phases_2_to_12') misses the switch.
    showPaywallSheet(context, feature: 'Phases 2-12');
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

          // Ship-dark: with `enable_hold_weeks` ON, holding is a REAL second
          // door (an indefinite, correctly-periodized free path) rather than a
          // one-shot "run it again", so it is promoted from a tertiary link to
          // an accented pill beside the upgrade CTA — the locked mockup's
          // two-door wall. Flag OFF renders the original three-link layout
          // verbatim.
          if (PlanEngineFlags.holdWeeksEnabled) ...[
            _holdTheLineCta(),
            const SizedBox(height: 14),
            const Divider(height: 1, color: AppColors.border),
            const SizedBox(height: 12),
            _templateHint(),
          ] else ...[
            // Secondary / tertiary section header
            Text(
              'OR HOLD THE LINE — FREE',
              style: AppTypography.monoXs.copyWith(fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 1.2),
            ),
            const SizedBox(height: 10),

            // Secondary — Build your own plan
            _secondaryLink(
              icon: Icons.build_outlined,
              label: 'Draw up your own drills',
              onTap: _handleTemplateBuilder,
            ),
            const SizedBox(height: 8),

            // Tertiary — Re-do Week 4
            _secondaryLink(
              icon: Icons.replay_outlined,
              label: 'Run Week 4 again',
              onTap: _redoing ? null : _handleRedoWeek4,
              trailing: _redoing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.textSecondary,
                      ),
                    )
                  : null,
            ),
          ],
        ],
      ),
    );
  }

  /// Outlined gold pill — the free door, weighted to read as a genuine choice
  /// next to the gold-filled upgrade CTA rather than a consolation link.
  Widget _holdTheLineCta() {
    return GestureDetector(
      onTap: _redoing ? null : _handleRedoWeek4,
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
            'Deploy to Phase $nextPhase — go PRO →',
            style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
          ),
        ),
      ),
    );
  }

  Widget _secondaryLink({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    Widget? trailing,
  }) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.row),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: enabled
                  ? AppColors.textPrimary
                  : AppColors.textSecondary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: enabled
                      ? AppColors.textPrimary
                      : AppColors.textDim),
              ),
            ),
            trailing ??
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColors.textSecondary.withValues(alpha: 0.7),
                ),
          ],
        ),
      ),
    );
  }
}
