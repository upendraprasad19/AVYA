import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/features/train/widgets/keep_training_phase1_action.dart';
import 'package:icanbefitter/features/train/widgets/phase2_preview_card.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';
import 'package:icanbefitter/shared/services/pro_phase_advance.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import '../providers/train_provider.dart';
import '../widgets/advance_choice_sheet.dart';

/// Phase 1 Graduation Ceremony — the #1 conversion moment.
///
/// Full-screen celebration with:
/// - Stats from Phase 1 (streak, workouts, PRs)
/// - Blurred Phase 2 structure preview
/// - "Continue Your Journey" CTA -> PaywallSheet for phases_2_to_12
class GraduationScreen extends ConsumerWidget {
  const GraduationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(graduationStatsProvider);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: ListView(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding),
              children: [
                const SizedBox(height: 32),

                // Trophy icon
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.proGold.withValues(alpha: 0.2),
                          AppColors.proGold.withValues(alpha: 0.05),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.proGold.withValues(alpha: 0.4),
                        width: 2,
                      ),
                    ),
                    child: const Icon(
                      Icons.emoji_events_rounded,
                      color: AppColors.proGold,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Congrats headline
                Center(
                  child: Text(
                    'PHASE 1 COMPLETE',
                    style: AppTypography.mono.copyWith(
                      fontSize: 13,
                      color: AppColors.proGold,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Week Four',
                    style: AppTypography.display.copyWith(height: 1.05),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'You built the foundation. Time to level up.',
                    style: AppTypography.body.copyWith(
                      color: AppColors.textDim,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 18),
                const WardRule(gold: true, margin: EdgeInsets.zero),
                const SizedBox(height: 22),

                // Stats grid
                _buildStatsGrid(stats),
                const SizedBox(height: 24),

                // Phase 2 Preview (blurred)
                const Phase2PreviewCard(),
                const SizedBox(height: 24),

                // What Phase 2 unlocks
                const Phase2BenefitsCard(),
                const SizedBox(height: 24),

                // CTA — Continue Your Journey
                _buildCta(context, ref),
                const SizedBox(height: 12),

                // Stay on Phase 1 link — runs redoWeek4() first so the
                // user actually HAS workouts to land on. Before the
                // 2026-04-18 fix (audit M22) this button routed to
                // /train on an exhausted Phase 1 schedule → empty page
                // → dead link.
                Center(
                  child: GestureDetector(
                    onTap: () => keepTrainingPhase1(context, ref),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'KEEP TRAINING PHASE 1',
                        style: AppTypography.monoXs.copyWith(
                          color: AppColors.textMute,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(GraduationStatsData stats) {
    return WardCard(
      variant: WardCardVariant.hero,
      child: Column(
        children: [
          Text(
            'YOUR PHASE 1 JOURNEY',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  value: '${stats.totalWorkouts}',
                  label: 'WORKOUTS',
                  icon: Icons.fitness_center,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${stats.streakWeeks}',
                  label: 'WEEK STREAK',
                  icon: Icons.local_fire_department,
                  color: AppColors.warn,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  value: '${stats.totalSets}',
                  label: 'TOTAL SETS',
                  icon: Icons.repeat,
                  color: AppColors.info,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${stats.personalRecords}',
                  label: 'PRS SET',
                  icon: Icons.emoji_events,
                  color: AppColors.proGold,
                ),
              ),
            ],
          ),

          // Top PRs
          if (stats.topPrs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const WardRule(margin: EdgeInsets.zero),
            const SizedBox(height: 12),
            Text(
              'TOP PERSONAL RECORDS',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 8),
            ...stats.topPrs.take(3).map((pr) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.star,
                          size: 14, color: AppColors.proGold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pr.exerciseName,
                          style: AppTypography.h3.copyWith(fontSize: 13),
                        ),
                      ),
                      Text(
                        pr.value,
                        style: AppTypography.h3.copyWith(
                          fontSize: 13,
                          color: AppColors.accent,
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _statTile({
    required String value,
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: AppTypography.h2.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCta(BuildContext context, WidgetRef ref) {
    return const _GenerateNextPhaseButton();
  }
}

/// Theme F (diagnose 2026-05-22 ec4d27) — extracted into a ConsumerStatefulWidget
/// so we can drive `_isGenerating` loading state, fire the 4 lifecycle
/// telemetry events, run the canonical provider-invalidation set after
/// successful generation, and show a success snackbar before navigation.
///
/// Pre-fix: the whole flow was a one-shot async lambda — button looked
/// dead during the multi-second generate; on success the user landed on
/// /train with stale providers (currentPlanProvider / todayWorkoutProvider
/// / calendarWeekProvider all cached the pre-unlock state) and saw the
/// "PHASE I COMPLETE" graduation card still in the UI.
class _GenerateNextPhaseButton extends ConsumerStatefulWidget {
  const _GenerateNextPhaseButton();

  @override
  ConsumerState<_GenerateNextPhaseButton> createState() =>
      _GenerateNextPhaseButtonState();
}

class _GenerateNextPhaseButtonState
    extends ConsumerState<_GenerateNextPhaseButton> {
  bool _isGenerating = false;

  @override
  Widget build(BuildContext context) {
    return WardButton(
      label: _isGenerating ? 'LOCKING IN YOUR PLAN…' : 'GENERATE NEXT PHASE',
      leading: _isGenerating
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppColors.bgDeep),
              ),
            )
          : const Icon(Icons.rocket_launch,
              size: 16, color: AppColors.bgDeep),
      onPressed: _isGenerating ? null : _onTap,
    );
  }

  void _onTap() {
    // Theme F telemetry — fire BEFORE the gate so we know the tap fired
    // even when the gate routes onFree (paywall) or onPro (continue).
    unawaited(ErrorTelemetry.logEvent('phase_unlock_initiated',
        message: 'tap=GENERATE_NEXT_PHASE'));
    SubscriptionService.instance.gateAndVerify(
      AppConstants.featurePhases2To12,
      onPro: _onPro,
      onFree: () {
        unawaited(ErrorTelemetry.logEvent('phase_unlock_gate_routed_free',
            message: 'feature=phases_2_to_12'));
        showPaywallSheet(context, feature: 'Phases 2-12');
      },
    );
  }

  Future<void> _onPro() async {
    unawaited(ErrorTelemetry.logEvent('phase_unlock_gate_routed_pro',
        message: 'feature=phases_2_to_12'));
    if (!mounted) return;
    final stopwatch = Stopwatch()..start();
    try {
      final profile = UserRepository.instance.getProfile() ?? {};
      final progress = UserRepository.instance.getProgress() ?? {};
      final currentPhase = (progress['current_phase'] as int?) ?? 1;
      // 2026-05-31 (post-12 deployment cycles): MONOTONIC phase number so
      // deployments_complete keeps counting toward PO/CPO/officer ranks. The
      // plan engine recycles phase-9-12 content internally; the number doesn't
      // cycle back (the old `9 + ((currentPhase-8) % 4)` froze the counter).
      final nextPhase = currentPhase + 1;

      final scheduleSvc = ref.read(workoutScheduleReadServiceProvider);

      // ⑧ 3-b (W2.5, ship-dark): on a LOW-adherence advance, OFFER a choice —
      // repeat the just-finished phase's drills (detrained) or take fresh
      // orders; the phase advances EITHER way (F3). The flag short-circuits so
      // the ~90-Hive-read currentPhaseCompletionRate() is NEVER evaluated when
      // OFF → then no sheet, no abort-check, VERBATIM generation.
      var choice = AdvanceChoice.advance;
      final offerChoice = PlanEngineFlags.adherenceGateEnabled &&
          shouldOfferAdvanceChoice(
            completionRate: scheduleSvc.currentPhaseCompletionRate(),
            threshold: AppConstants.phaseUnlockCompletionRate,
          );
      if (offerChoice) {
        choice = await showAdvanceChoiceSheet(context) ?? AdvanceChoice.advance;
        if (!mounted) return;
      }

      if (!mounted) return;
      // abort-if-changed: if a concurrent splash/card/coach advance bumped the
      // phase — while the choice sheet was open, or at any point before this
      // tap — DON'T recompute nextPhase (that would SKIP a phase), and don't
      // regenerate a plan for a phase the user is already on. Route to /train.
      //
      // Unit 3c (OI-45 finding 5): this check used to sit INSIDE the
      // `if (offerChoice)` block above, and `offerChoice` requires
      // PlanEngineFlags.adherenceGateEnabled — ship-dark, DEFAULT OFF
      // (plan_engine_flags.dart) — so on the production default path it never
      // executed at all. Hoisted out so it runs on every unlock.
      //
      // Precise about what that buys, because round-1 review caught the
      // over-claim: on the flag-OFF path there is NO await between the
      // `progress` read above and this line, so `live == currentPhase` always
      // and this early-out cannot fire. It is load-bearing only across the
      // choice-sheet await (flag ON) — and it becomes so the moment that flag
      // flips. The default path's real protection is the shared advance lock
      // below plus commitPhaseAdvance's re-read at write time.
      final live =
          (UserRepository.instance.getProgress()?['current_phase'] as int?) ?? 1;
      if (live >= nextPhase) {
        // The concurrent advancer bumped the phase — refresh the plan views
        // before routing so /train doesn't briefly show the pre-advance plan.
        ref.invalidate(currentPlanProvider);
        ref.invalidate(todayWorkoutProvider);
        context.go('/train');
        return;
      }

      setState(() => _isGenerating = true);

      // Unit B (OI-84): the locked generate + commitPhaseAdvance block that used
      // to live here inline is now `runGraduationPhaseAdvance` in
      // pro_phase_advance.dart, beside the other three advance paths. This
      // screen is UI only — choice sheet, snackbars, navigation, invalidation.
      //
      // The lock is still taken AFTER the choice sheet closes, never across it:
      // a modal waiting on human input must not block the splash's advance.
      // That ordering is enforced HERE, by where this call sits.
      final result = await runGraduationPhaseAdvance(
        ref: ref,
        profile: profile,
        nextPhase: nextPhase,
        repeat: choice == AdvanceChoice.repeat,
        stopwatch: stopwatch,
      );

      // ⑧ 3-b: surface the low-adherence "you repeated — step it up?" Home nudge
      // this session rather than only after a relaunch. The Hive write happens
      // inside the shared advance (which owns the cross-account belt); the
      // provider invalidation is UI work and stays here — `lib/shared/**` cannot
      // import this feature provider.
      if (result.repeatNudgeFlagged) {
        ref.invalidate(phaseRepeatNudgeProvider);
      }

      if (!mounted) return;
      if (result.outcome == GraduationAdvanceOutcome.busy) {
        // Another advance path holds the lock and is generating this same phase
        // right now. Same recourse the PhaseGeneratingCard already gives on its
        // own busy path — tell the user plainly and put them on /train, where
        // the plan appears the moment that pass lands.
        unawaited(ErrorTelemetry.logEvent('phase_unlock_advance_busy',
            message: 'phase=$nextPhase'));
        ref.invalidate(currentPlanProvider);
        ref.invalidate(todayWorkoutProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.card,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
            content: Text(
              'Still finishing up your next phase — opening your plan…',
              style: AppTypography.bodySm.copyWith(color: AppColors.accent),
            ),
          ),
        );
        context.go('/train');
        return;
      }

      // Theme F — provider invalidation set. Matches the canonical post-
      // workout-completion batch from train_provider.dart:1494-1500. The
      // train screen + home screen pull from these providers; without
      // invalidation they cache pre-unlock state and the founder lands
      // on /train still seeing "PHASE I COMPLETE".
      ref.invalidate(currentPlanProvider);
      ref.invalidate(todayWorkoutProvider);
      ref.invalidate(calendarWeekProvider);
      ref.invalidate(workoutStatsProvider);
      ref.invalidate(streakProvider);
      ref.invalidate(allExercisePRsProvider);
      ref.invalidate(aiInsightProvider);
      ref.invalidate(graduationStatsProvider);

      // Unit 3c: anything other than `committed` means the counter did NOT move
      // to nextPhase — either a concurrent advancer had already moved it past
      // us before we generated (preemptedBeforeGenerate) or commitPhaseAdvance
      // declined the write after we generated (generatedButDeclined). Firing
      // phase_unlock_completed for either would assert a write that never
      // happened — the false-signal class this whole batch exists to remove —
      // so the two outcomes get distinct events and distinct copy.
      //
      // Unit B (OI-84): the two non-busy failure modes are now DISTINCT enum
      // cases rather than one overloaded `false`, and each already fires its own
      // event inside the shared advance. They deliberately still share this
      // screen's copy and this summary event — that is the pre-hoist behaviour,
      // and this unit changes structure, not behaviour. The enum is what makes a
      // future divergence expressible; nothing here diverges yet.
      final committed = result.outcome == GraduationAdvanceOutcome.committed;
      unawaited(ErrorTelemetry.logEvent(
          committed
              ? 'phase_unlock_completed'
              : 'phase_unlock_counter_already_advanced',
          message: 'phase=$nextPhase ms=${stopwatch.elapsedMilliseconds}'));

      if (!mounted) return;
      // Success snackbar — pre-fix the user got no feedback on success;
      // the immediate navigate hid the "did anything happen?" question.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            side: BorderSide(
                color: AppColors.accent.withValues(alpha: 0.5)),
          ),
          content: Text(
            committed
                ? 'Phase $nextPhase unlocked — opening your new plan…'
                : 'Your new plan is ready — opening it now…',
            style: AppTypography.bodySm
                .copyWith(color: AppColors.accent),
          ),
        ),
      );
      context.go('/train');
    } catch (e) {
      final errStr = e.toString();
      final clipped =
          errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent(
          'train_graduation_generate_phase_2_failed',
          message:
              'ms=${stopwatch.elapsedMilliseconds} err=$clipped'));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.card,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sharp),
            side: BorderSide(color: AppColors.bad.withValues(alpha: 0.3)),
          ),
          content: Text(
            'Failed to generate next phase: $e',
            style: AppTypography.bodySm.copyWith(color: AppColors.bad),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }
}
