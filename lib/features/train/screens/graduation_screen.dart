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
    return WardButton(
      label: 'GENERATE NEXT PHASE',
      leading: const Icon(Icons.rocket_launch,
          size: 16, color: AppColors.bgDeep),
      onPressed: () {
        SubscriptionService.instance.gate(
          AppConstants.featurePhases2To12,
          onPro: () async {
            // PRO user — generate next phase plan
            try {
              final profile = UserRepository.instance.getProfile() ?? {};
              final progress = UserRepository.instance.getProgress() ?? {};
              final currentPhase = (progress['current_phase'] as int?) ?? 1;
              // Cycle phases 9→10→11→12→9→10... for users who've completed all 12
              final nextPhase = currentPhase >= 12
                  ? 9 + ((currentPhase - 8) % 4) // Cycles: 9→10→11→12→9→10...
                  : currentPhase + 1;

              // Generate next phase plan and write schedule to Hive
              final savedDays =
                  MigratedKey.read<List>('preferred_training_days');
              final preferredDays =
                  savedDays is List ? savedDays.cast<int>() : null;

              await ref
                  .read(workoutScheduleReadServiceProvider)
                  .generateAndSchedule(
                goal: profile['primary_goal'] as String? ?? 'general_fitness',
                equipment:
                    profile['equipment_access'] as String? ?? 'basic_gym',
                daysPerWeek:
                    (profile['days_per_week'] as num?)?.toInt() ?? 4,
                startDate: DateTime.now(),
                phase: nextPhase,
                experienceLevel:
                    profile['fitness_experience'] as String? ?? 'beginner',
                preferredDays: preferredDays,
              );

              // Update user progress
              await UserRepository.instance.updateProgress({
                'current_phase': nextPhase,
                'current_week': 1,
                'phase_started_at': DateTime.now().toIso8601String(),
              });

              if (context.mounted) context.go('/train');
            } catch (e) {
              final errStr = e.toString();
              final clipped =
                  errStr.length > 500 ? errStr.substring(0, 500) : errStr;
              unawaited(ErrorTelemetry.logEvent(
                  'train_graduation_generate_phase_2_failed',
                  message: clipped));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.card,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(AppRadius.sharp),
                      side: BorderSide(
                          color: AppColors.bad.withValues(alpha: 0.3)),
                    ),
                    content: Text(
                      'Failed to generate Phase 2: $e',
                      style: AppTypography.bodySm.copyWith(
                        color: AppColors.bad,
                      ),
                    ),
                  ),
                );
              }
            }
          },
          onFree: () => showPaywallSheet(context, feature: 'Phases 2-12'),
        );
      },
    );
  }
}
