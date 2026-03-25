import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
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
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: AppColors.proGold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'You built the foundation. Time to level up.',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),

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
                _buildCta(context),
                const SizedBox(height: 12),

                // Stay on Phase 1 link
                Center(
                  child: GestureDetector(
                    onTap: () => context.go('/train'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'Keep training Phase 1',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textSecondary,
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
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.proGold.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Text(
            'YOUR PHASE 1 JOURNEY',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _statTile(
                  value: '${stats.totalWorkouts}',
                  label: 'Workouts',
                  icon: Icons.fitness_center,
                  color: AppColors.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${stats.streakWeeks}',
                  label: 'Week Streak',
                  icon: Icons.local_fire_department,
                  color: AppColors.orange,
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
                  label: 'Total Sets',
                  icon: Icons.repeat,
                  color: AppColors.blue,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  value: '${stats.personalRecords}',
                  label: 'PRs Set',
                  icon: Icons.emoji_events,
                  color: AppColors.proGold,
                ),
              ),
            ],
          ),

          // Top PRs
          if (stats.topPrs.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(color: AppColors.border, height: 1),
            const SizedBox(height: 12),
            Text(
              'TOP PERSONAL RECORDS',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...stats.topPrs.take(3).map((pr) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: AppColors.proGold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pr.exerciseName,
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        pr.value,
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
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
        borderRadius: BorderRadius.circular(AppRadius.cardS),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w400,
              color: AppColors.textSecondary,
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'PHASE 2',
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.accent,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Progressive Overload',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '5 days/week \u00B7 Weeks 5-8 \u00B7 Power + Hypertrophy',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 11,
              color: AppColors.textSecondary,
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
                      decoration: BoxDecoration(
                        color: AppColors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      day,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Blurred exercise placeholder
                    Expanded(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Text(
                          'Bench Press, Rows, OHP...',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 11,
                            color: AppColors.textSecondary,
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

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.input,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'WHAT PHASE 2 UNLOCKS',
            style: GoogleFonts.getFont(
              'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: AppColors.textSecondary,
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
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: AppColors.textPrimary,
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

  Widget _buildCta(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          SubscriptionService.instance.gate(
            AppConstants.featurePhases2To12,
            onPro: () async {
              // PRO user — generate next phase plan
              try {
                final profile = UserRepository.instance.getProfile() ?? {};
                final progress = UserRepository.instance.getProgress() ?? {};
                final currentPhase = (progress['current_phase'] as int?) ?? 1;
                final nextPhase = currentPhase + 1;

                // Generate next phase plan and write schedule to Hive
                await WorkoutScheduleService.instance.generateAndSchedule(
                  goal: profile['primary_goal'] as String? ?? 'general_fitness',
                  equipment: profile['equipment_access'] as String? ?? 'basic_gym',
                  daysPerWeek: (profile['days_per_week'] as int?) ?? 4,
                  startDate: DateTime.now(),
                  phase: nextPhase,
                  experienceLevel: profile['fitness_experience'] as String? ?? 'beginner',
                );

                // Update user progress
                await UserRepository.instance.updateProgress({
                  'current_phase': nextPhase,
                  'current_week': 1,
                  'phase_started_at': DateTime.now().toIso8601String(),
                });

                if (context.mounted) context.go('/train');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: AppColors.card,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                            color: AppColors.red.withValues(alpha: 0.3)),
                      ),
                      content: Text(
                        'Failed to generate Phase 2: $e',
                        style: GoogleFonts.getFont(
                          'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.red,
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
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.proGold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          elevation: 6,
          shadowColor: AppColors.proGold.withValues(alpha: 0.3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.rocket_launch, size: 18, color: Colors.black),
            const SizedBox(width: 8),
            Text(
              'Continue Your Journey',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
