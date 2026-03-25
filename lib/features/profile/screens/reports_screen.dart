import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
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
  bool _isGeneratingReport = false;
  Map<String, dynamic>? _aiReport;
  String? _reportError;

  // Hive cache keys
  static const String _reportCacheKey = 'weekly_report_cache';
  static const String _reportCacheDateKey = 'weekly_report_cache_date';

  @override
  void initState() {
    super.initState();
    _loadCachedReport();
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  /// Load cached report from Hive configBox if it exists and is from this week.
  void _loadCachedReport() {
    final configBox = HiveService.instance.configBox;
    final cachedJson = configBox.get(_reportCacheKey) as String?;
    final cachedDate = configBox.get(_reportCacheDateKey) as String?;

    if (cachedJson != null && cachedDate != null) {
      final cacheDateTime = DateTime.tryParse(cachedDate);
      if (cacheDateTime != null) {
        // Cache is valid if generated within the last 7 days
        final daysSinceCache =
            DateTime.now().difference(cacheDateTime).inDays;
        if (daysSinceCache < 7) {
          try {
            _aiReport = jsonDecode(cachedJson) as Map<String, dynamic>;
          } catch (_) {
            // Corrupted cache, ignore
          }
        }
      }
    }
  }

  /// Call the weekly-report Edge Function, parse the result, and cache it.
  Future<void> _generateReport() async {
    setState(() {
      _isGeneratingReport = true;
      _reportError = null;
    });

    try {
      final userId = SupabaseService.instance.currentUser?.id;
      if (userId == null) {
        throw Exception('Not authenticated. Please sign in and try again.');
      }

      final response = await SupabaseService.instance.callFunction(
        AppConstants.weeklyReportFunction,
        body: {'user_id': userId},
      );

      final data = response.data;
      if (data == null) {
        throw Exception('Empty response from server.');
      }

      // response.data is already decoded by Supabase client
      final Map<String, dynamic> report;
      if (data is Map<String, dynamic>) {
        report = data;
      } else if (data is String) {
        report = jsonDecode(data) as Map<String, dynamic>;
      } else {
        throw Exception('Unexpected response format.');
      }

      if (report.containsKey('error')) {
        final code = report['code'] as String?;
        if (code == 'NOT_PRO') {
          throw Exception(
              'PRO subscription required for ongoing weekly reports.');
        }
        throw Exception(report['error'] as String? ?? 'Unknown error');
      }

      // Cache in Hive
      final configBox = HiveService.instance.configBox;
      await configBox.put(_reportCacheKey, jsonEncode(report));
      await configBox.put(
          _reportCacheDateKey, DateTime.now().toIso8601String());

      // Mark first report as generated (for free user gating).
      await configBox.put('first_report_generated', true);

      if (mounted) {
        setState(() {
          _aiReport = report;
          _isGeneratingReport = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _reportError = e.toString().replaceFirst('Exception: ', '');
          _isGeneratingReport = false;
        });
      }
    }
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
    // If we already have a report (cached or freshly generated), show it
    if (_aiReport != null) {
      return _buildAiReportResult(_aiReport!);
    }

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
          if (_reportError != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.cardS),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _reportError!,
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 12,
                        color: AppColors.red,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isGeneratingReport
                  ? null
                  : () {
                      final isPro = SubscriptionService.instance.isPro();
                      if (!isPro) {
                        // Free users: first report is free, subsequent ones are gated.
                        final alreadyGenerated = HiveService.instance.configBox
                            .get('first_report_generated', defaultValue: false) as bool;
                        if (alreadyGenerated) {
                          showPaywallSheet(context,
                              feature: 'AI Weekly Report');
                          return;
                        }
                      }
                      SubscriptionService.instance.gate(
                        AppConstants.featureWeeklyAiReport,
                        onPro: () => _generateReport(),
                        onFree: () => _generateReport(),
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.black,
                disabledBackgroundColor:
                    AppColors.accent.withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              child: _isGeneratingReport
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Generating...',
                          style: GoogleFonts.getFont(
                            'DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    )
                  : Text(
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

  Widget _buildAiReportResult(Map<String, dynamic> report) {
    final summary = report['summary'] as String? ?? '';
    final compliancePercent = (report['compliance_percent'] as num?)?.toInt() ?? 0;
    final topWins = (report['top_wins'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final areasToImprove = (report['areas_to_improve'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final recommendations = (report['recommendations'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];
    final periodStart = report['period_start'] as String? ?? '';
    final periodEnd = report['period_end'] as String? ?? '';
    final nutritionSummary =
        report['nutrition_summary'] as Map<String, dynamic>?;
    final workoutSummary =
        report['workout_summary'] as Map<String, dynamic>?;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header card
        Container(
          padding: const EdgeInsets.all(AppSpacing.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.cardM),
            border: Border.all(
                color: AppColors.proGold.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      color: AppColors.proGold, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                        Text('AI Weekly Report', style: AppTypography.titleS),
                  ),
                  const ProBadge(scale: 0.8),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$periodStart to $periodEnd',
                style: GoogleFonts.getFont(
                  'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(summary, style: AppTypography.bodyL),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),

        // Compliance gauge
        Container(
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '$compliancePercent%',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 32,
                      fontWeight: FontWeight.w900,
                      color: compliancePercent >= 70
                          ? AppColors.green
                          : compliancePercent >= 40
                              ? AppColors.orange
                              : AppColors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (nutritionSummary != null) ...[
                          Text(
                            '${nutritionSummary['avg_calories']} / ${nutritionSummary['calorie_target']} kcal avg',
                            style: AppTypography.bodyS
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          Text(
                            '${nutritionSummary['avg_protein']}g / ${nutritionSummary['protein_target']}g protein avg',
                            style: AppTypography.bodyS
                                .copyWith(color: AppColors.textSecondary),
                          ),
                          Text(
                            '${nutritionSummary['days_logged']}/7 days logged',
                            style: AppTypography.bodyS
                                .copyWith(color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.input,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (compliancePercent / 100).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: compliancePercent >= 70
                          ? AppColors.green
                          : compliancePercent >= 40
                              ? AppColors.orange
                              : AppColors.red,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sectionGap),

        // Workout summary
        if (workoutSummary != null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(AppRadius.cardM),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Workout Summary', style: AppTypography.titleS),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryItem(
                      'Days',
                      '${workoutSummary['days_trained']}',
                      AppColors.accent,
                    ),
                    _summaryItem(
                      'Sets',
                      '${workoutSummary['total_sets']}',
                      AppColors.blue,
                    ),
                    _summaryItem(
                      'PRs',
                      '${workoutSummary['prs_hit']}',
                      AppColors.proGold,
                    ),
                    _summaryItem(
                      'RPE',
                      '${workoutSummary['avg_rpe']}',
                      AppColors.orange,
                    ),
                  ],
                ),
              ],
            ),
          ),
        if (workoutSummary != null)
          const SizedBox(height: AppSpacing.sectionGap),

        // Top wins
        if (topWins.isNotEmpty)
          _buildBulletList(
            title: 'Top Wins',
            items: topWins,
            icon: Icons.emoji_events,
            iconColor: AppColors.proGold,
            bulletColor: AppColors.green,
          ),
        if (topWins.isNotEmpty)
          const SizedBox(height: AppSpacing.sectionGap),

        // Areas to improve
        if (areasToImprove.isNotEmpty)
          _buildBulletList(
            title: 'Areas to Improve',
            items: areasToImprove,
            icon: Icons.trending_up,
            iconColor: AppColors.orange,
            bulletColor: AppColors.orange,
          ),
        if (areasToImprove.isNotEmpty)
          const SizedBox(height: AppSpacing.sectionGap),

        // Recommendations
        if (recommendations.isNotEmpty)
          _buildBulletList(
            title: 'Recommendations',
            items: recommendations,
            icon: Icons.lightbulb_outline,
            iconColor: AppColors.accent,
            bulletColor: AppColors.accent,
          ),
        const SizedBox(height: AppSpacing.sectionGap),

        // Regenerate button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _isGeneratingReport ? null : () => _generateReport(),
            icon: _isGeneratingReport
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: AppColors.accent),
                  )
                : const Icon(Icons.refresh, size: 16),
            label: Text(
              _isGeneratingReport ? 'Regenerating...' : 'Regenerate Report',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.accent,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.accent,
              side: BorderSide(
                  color: AppColors.accent.withValues(alpha: 0.3),
                  width: 1.5),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBulletList({
    required String title,
    required List<String> items,
    required IconData icon,
    required Color iconColor,
    required Color bulletColor,
  }) {
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
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 8),
              Text(title, style: AppTypography.titleS),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(top: 6, right: 10),
                    decoration: BoxDecoration(
                      color: bulletColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item,
                      style: AppTypography.bodyM
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
