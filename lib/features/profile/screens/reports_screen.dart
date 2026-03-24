import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/pro_badge.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import '../providers/profile_provider.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  void _retry() {
    setState(() => _isLoading = true);
    ref.invalidate(userStatsProvider);
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.header,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => context.go('/profile'),
        ),
        title: Text(
          'Reports',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const ScreenLoadingSkeleton(cardCount: 4);
    }

    try {
      return _buildContent();
    } catch (e) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: ErrorState(
          title: 'Failed to load reports',
          subtitle: 'Tap to retry',
          onRetry: _retry,
        ),
      );
    }
  }

  Widget _buildContent() {
    final stats = ref.watch(userStatsProvider);

    // Check if we have any meaningful data
    final hasAnyData = stats.totalWorkouts > 0 ||
        stats.currentWeight > 0 ||
        stats.currentStreak > 0;

    if (!hasAnyData) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.screenPadding),
        child: const EmptyState(
          icon: Icons.bar_chart,
          title: 'No report data yet',
          subtitle: 'Start logging workouts and meals to see your progress here.',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      children: [
        // Weekly summary
        _buildWeeklySummary(stats),
        const SizedBox(height: AppSpacing.sectionGap),

        // Workout frequency chart
        _buildWorkoutFrequency(),
        const SizedBox(height: AppSpacing.sectionGap),

        // Weight trend
        _buildWeightTrend(),
        const SizedBox(height: AppSpacing.sectionGap),

        // Nutrition compliance
        _buildNutritionCompliance(),
        const SizedBox(height: AppSpacing.sectionGap),

        // AI report (PRO gated)
        _buildAiReport(context),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildWeeklySummary(UserStatsData stats) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border:
            Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This Week', style: AppTypography.titleS),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _summaryItem(
                  'Workouts', '${stats.totalWorkouts}', AppColors.accent),
              _summaryItem(
                  'Streak', '${stats.currentStreak}w', AppColors.orange),
              _summaryItem(
                'Weight',
                stats.currentWeight > 0
                    ? stats.currentWeight.toStringAsFixed(1)
                    : '--',
                AppColors.green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildWorkoutFrequency() {
    final weekCounts = WorkoutRepository.instance.getWeeklyWorkoutCounts();

    final maxCount = weekCounts.reduce((a, b) => a > b ? a : b);
    final maxBar = maxCount > 0 ? maxCount.toDouble() : 1.0;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Workout Frequency', style: AppTypography.titleS),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(4, (i) {
              final label = i == 0
                  ? 'This Week'
                  : i == 1
                      ? 'Last Week'
                      : '${i + 1}w ago';
              return _barColumn(
                label: label,
                value: weekCounts[i],
                maxValue: maxBar,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _barColumn(
      {required String label, required int value, required double maxValue}) {
    return Column(
      children: [
        Text(
          '$value',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 40,
          height: 80 * (value / maxValue).clamp(0.05, 1.0),
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildWeightTrend() {
    final last10 = NutritionRepository.instance.getWeightEntries(limit: 10);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Weight Trend', style: AppTypography.titleS),
          const SizedBox(height: 14),
          if (last10.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No weight entries yet',
                  style: AppTypography.bodyM
                      .copyWith(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ...last10.map((entry) {
              final weight = (entry['weight_kg'] as num).toDouble();
              final date = entry['date'] as String? ?? '';

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      date,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      '${weight.toStringAsFixed(1)} kg',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildNutritionCompliance() {
    final daysLogged = NutritionRepository.instance.getNutritionDaysLoggedThisWeek();

    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nutrition Compliance', style: AppTypography.titleS),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                '$daysLogged/7',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: AppColors.orange,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'days logged this week',
                style: AppTypography.bodyM
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 6,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(3),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (daysLogged / 7).clamp(0.0, 1.0),
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.orange,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAiReport(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(
            color: AppColors.proGold.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  color: AppColors.proGold, size: 18),
              const SizedBox(width: 8),
              Text('AI Weekly Report', style: AppTypography.titleS),
              const SizedBox(width: 8),
              const ProBadge(scale: 0.8),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Get a personalised AI-generated weekly report with insights and recommendations.',
            style:
                AppTypography.bodyM.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                SubscriptionService.instance.gate(
                  AppConstants.featureWeeklyAiReport,
                  onPro: () {
                    // TODO: Generate AI report
                  },
                  onFree: () => showPaywallSheet(context,
                      feature: 'AI Weekly Report'),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              child: Text(
                'Generate Report',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Colors.black,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
