import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/service_providers.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import '../providers/train_provider.dart';

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
                _buildPhase2Preview(),
                const SizedBox(height: 24),

                // What Phase 2 unlocks
                _buildPhase2Benefits(),
                const SizedBox(height: 24),

                // CTA — Continue Your Journey
                _buildCta(context, ref),
                const SizedBox(height: 12),

                // Theme H-followup (diagnose 2026-05-22 5cb912) —
                // founder's "scroll back to see completed phases" wish.
                // Surfaces only when at least one phase is complete
                // (phase >= 2 or phase 1 with status=completed days).
                // PhaseHistoryScreen handles the empty case if tapped
                // before completion.
                Center(
                  child: GestureDetector(
                    onTap: () => context.push('/train/history'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'VIEW PAST PHASES',
                        style: AppTypography.mono.copyWith(
                          color: AppColors.textDim,
                          fontSize: 11,
                          letterSpacing: 1.4,
                          decoration: TextDecoration.underline,
                          decorationColor: AppColors.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Stay on Phase 1 link — runs redoWeek4() first so the
                // user actually HAS workouts to land on. Before the
                // 2026-04-18 fix (audit M22) this button routed to
                // /train on an exhausted Phase 1 schedule → empty page
                // → dead link.
                Center(
                  child: GestureDetector(
                    onTap: () async {
                      try {
                        await ref
                            .read(workoutScheduleWriteServiceProvider)
                            .redoWeek4();
                      } catch (_) {}
                      if (context.mounted) context.go('/train');
                    },
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

  Widget _buildPhase2Preview() {
    // Blurred Phase 2 preview — show day names, blur exercise names
    final phase2Days = [
      'Day 1: Upper Power',
      'Day 2: Lower Power',
      'Day 3: Rest & Mobility',
      'Day 4: Upper Hypertrophy',
      'Day 5: Lower Hypertrophy',
    ];

    return WardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const WardChip(label: 'PHASE 2', tone: WardChipTone.gold),
              const SizedBox(width: 8),
              Text(
                'Progressive Overload',
                style: AppTypography.h3,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '5 DAYS/WEEK · WEEKS 5-8 · POWER + HYPERTROPHY',
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textDim,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 14),

          // Day names visible, exercise names blurred
          ...phase2Days.map((day) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      day,
                      style: AppTypography.h3.copyWith(fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    // Blurred exercise placeholder
                    Expanded(
                      child: ImageFiltered(
                        imageFilter:
                            ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Text(
                          'Bench Press, Rows, OHP...',
                          style: AppTypography.bodySm.copyWith(
                            color: AppColors.textDim,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPhase2Benefits() {
    const benefits = [
      'New exercises with progressive overload',
      'Power + hypertrophy split for faster gains',
      'AI-personalised workout adjustments',
      'Advanced coaching cues and PRO tips',
      'Phases 2-12 unlock full 48-week journey',
    ];

    return WardCard(
      variant: WardCardVariant.inset,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT PHASE 2 UNLOCKS',
            style: AppTypography.mono.copyWith(
              color: AppColors.textMute,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 10),
          ...benefits.map((benefit) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.accent,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        benefit,
                        style: AppTypography.body,
                      ),
                    ),
                  ],
                ),
              )),
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
    SubscriptionService.instance.gate(
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
    setState(() => _isGenerating = true);
    final stopwatch = Stopwatch()..start();
    try {
      final profile = UserRepository.instance.getProfile() ?? {};
      final progress = UserRepository.instance.getProgress() ?? {};
      final currentPhase = (progress['current_phase'] as int?) ?? 1;
      // Cycle phases 9→10→11→12→9→10... for users who've completed all 12.
      final nextPhase = currentPhase >= 12
          ? 9 + ((currentPhase - 8) % 4)
          : currentPhase + 1;

      final savedDays = MigratedKey.read<List>('preferred_training_days');
      final preferredDays =
          savedDays is List ? savedDays.cast<int>() : null;

      // Theme H fix — was `DateTime.now()` which normalizeToMonday-ed to
      // THIS WEEK's Monday, overwriting the current Phase 1 W4 entries.
      // nextPhaseStartDate computes max(today, currentPhaseEnd + 1 day)
      // Monday-normalized.
      final scheduleSvc = ref.read(workoutScheduleReadServiceProvider);
      final startDate = scheduleSvc.nextPhaseStartDate();
      await scheduleSvc.generateAndSchedule(
        goal: profile['primary_goal'] as String? ?? 'general_fitness',
        equipment:
            profile['equipment_access'] as String? ?? 'basic_gym',
        daysPerWeek: (profile['days_per_week'] as num?)?.toInt() ?? 4,
        startDate: startDate,
        phase: nextPhase,
        experienceLevel:
            profile['fitness_experience'] as String? ?? 'beginner',
        preferredDays: preferredDays,
      );
      unawaited(ErrorTelemetry.logEvent('phase_unlock_plan_generated',
          message: 'phase=$nextPhase ms=${stopwatch.elapsedMilliseconds}'));

      // Theme F — stamp plan_generated_at (cloud user_progress column
      // already accepts it via sync_profile.dart:165). UserRepository
      // .updateProgress now fires syncProgressNow (F-NEW root cause fix
      // in user_repository.dart) — so this push lands on cloud.
      await UserRepository.instance.updateProgress({
        'current_phase': nextPhase,
        'current_week': 1,
        'phase_started_at': DateTime.now().toIso8601String(),
        'plan_generated_at': DateTime.now().toIso8601String(),
      });

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

      unawaited(ErrorTelemetry.logEvent('phase_unlock_completed',
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
            'Phase $nextPhase unlocked — opening your new plan…',
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
