import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/train/repositories/workout_repository.dart';
import 'package:icanbefitter/features/nutrition/repositories/nutrition_repository.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/pro_badge.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/empty_state.dart';
import 'package:icanbefitter/shared/widgets/video_share_button.dart';
import 'package:icanbefitter/features/train/providers/video_render_provider.dart';
import 'package:icanbefitter/features/train/providers/train_provider.dart';
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
  String _weightFilter = '3M'; // All, 1Y, 6M, 3M, 1M, 1W

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
    // Fix 2026-06-02 (stale-report zeros) — the report is cloud-sourced and the
    // cache was treated as valid for 7 DAYS, so the founder saw a multi-day-old
    // report (0 workouts + a protein target computed at an old weight). Refresh
    // on every open so it reflects current data. SILENT: the cached report (if
    // any) stays on screen until the fresh one lands; a transient failure keeps
    // the cache rather than blanking it. Cheap — the PRO report is opened
    // infrequently, and the cloud now has correct data (sync-ID fixes 082).
    Future.microtask(() {
      if (mounted) _generateReport(silent: true);
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
          } catch (e) {
            // Corrupted cache, ignore
            debugPrint('[ReportsScreen._loadCachedReport] $e');
          }
        }
      }
    }
  }

  /// Call the weekly-report Edge Function, parse the result, and cache it.
  ///
  /// [silent] = a background refresh-on-open: keep the cached report visible
  /// (no full-screen loader) and swallow errors (no banner) so a transient
  /// network blip doesn't blank a usable cached report. The fresh result still
  /// replaces `_aiReport` + the cache on success. Fix 2026-06-02.
  Future<void> _generateReport({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isGeneratingReport = true;
        _reportError = null;
      });
    }

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
      // Silent (refresh-on-open): keep the cached report visible; don't surface
      // an error banner just because a background refresh failed.
      if (silent) {
        debugPrint('[ReportsScreen._generateReport] silent refresh failed: $e');
        return;
      }
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
      // Handoff dispatch-style header (`utility.jsx` ReportScreen lines
      // 568-608): back / Seal badge / share + dispatch range + Fraunces
      // title. Double gold rule bottom.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(140),
        child: Container(
          decoration: const BoxDecoration(color: AppColors.bg),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(18, 14, 18, 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.go('/profile'),
                        behavior: HitTestBehavior.opaque,
                        child: Text(
                          '\u2190 BACK',
                          style: AppTypography.mono.copyWith(
                            fontSize: 11,
                            color: AppColors.textDim,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                      const Spacer(),
                      const WardSealBadge(
                        label: 'REPORT',
                        subline: 'W\u00B72026',
                        variant: WardSealVariant.report,
                      ),
                      const Spacer(),
                      // F41 \u2014 the gold "SHARE" header label was a dead
                      // affordance (styled like a button but had no onTap;
                      // the real share is the weekly-video row below). Removed
                      // the tappable-looking text. An invisible mirror of the
                      // BACK label keeps the seal optically centred between
                      // the two Spacers.
                      Visibility(
                        visible: false,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Text(
                          '\u2190 BACK',
                          style: AppTypography.mono.copyWith(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    'WEEKLY DISPATCH',
                    style: AppTypography.monoXs.copyWith(
                      fontSize: 9,
                      color: AppColors.accent,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(22, 2, 22, 10),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: RichText(
                      text: TextSpan(
                        style: AppTypography.h1.copyWith(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                        children: const [
                          TextSpan(text: 'A '),
                          TextSpan(
                            text: 'clean',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              color: AppColors.accent,
                            ),
                          ),
                          TextSpan(text: ' week.'),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  height: 1,
                  color: AppColors.accent.withValues(alpha: 0.6),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 1,
                  color: AppColors.accent.withValues(alpha: 0.3),
                ),
              ],
            ),
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
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('profile_reports_build_failed',
          message: clipped));
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

        // ⑥ Batch 6 (W3.7) readiness trend (PRO). Hidden until there is data.
        _buildReadinessTrend(),

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
    // APK +34 obs 2: this card showed lifetime total_workouts_done under a
    // "This Week" label. Use the real current-week count — index 0 of the
    // 4-week rolling window, the same source _buildWorkoutFrequency's
    // "This Week" bar uses. closes-diagnose: c2e8b4.
    final weekCounts = WorkoutRepository.instance.getWeeklyWorkoutCounts();
    final thisWeekWorkouts = weekCounts.isNotEmpty ? weekCounts.first : 0;
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
                  'Workouts', '$thisWeekWorkouts', AppColors.accent),
              _summaryItem(
                  // currentStreak is the live DAY walk-back (same as Home's
                  // "N DAYS"); was mislabeled 'w' (weeks). APK +34 obs 5.2.
                  'Streak', '${stats.currentStreak}d', AppColors.orange),
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
          style: AppTypography.body.copyWith(fontSize: 28, fontWeight: FontWeight.w900, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 1.2),
        ),
      ],
    );
  }

  Widget _buildWorkoutFrequency() {
    final weekCounts = WorkoutRepository.instance.getWeeklyWorkoutCounts();

    final maxCount = weekCounts.isEmpty ? 0 : weekCounts.reduce((a, b) => a > b ? a : b);
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
          style: AppTypography.body.copyWith(fontWeight: FontWeight.w800, color: AppColors.textPrimary),
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
          style: AppTypography.monoXs.copyWith(fontSize: 8, fontWeight: FontWeight.w700, color: AppColors.textDim),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ⑥ Batch 6 (W3.7) — readiness trend. A parallel colored-day strip (NOT
  // _buildLineChart, which hardcodes weight_kg). Hidden entirely until there is
  // ≥1 check-in. FREE for all since 2026-09-01 — the PRO gate and its paywall
  // teaser were removed when readiness went live (founder decision).
  Widget _buildReadinessTrend() {
    final history = HealthReadService.instance.readinessHistory();
    if (history.isEmpty) return const SizedBox.shrink();
    // Readiness trends are FREE for all (founder decision 2026-08-31) --
    // flipping an engine flag must not introduce a monetization surface.
    // history is newest-first; show the last 14 oldest→newest for the strip.
    final strip = history.take(14).toList().reversed.toList();
    final last30 = history.take(30).toList();
    final green =
        last30.where((c) => c.level == ReadinessLevel.green).length;
    final red = last30.where((c) => c.level == ReadinessLevel.red).length;

    final card = Container(
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
              Text('Readiness', style: AppTypography.titleS),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              for (final c in strip)
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: _readinessColor(c.level),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${last30.length} check-ins · $green green · $red red (last 30 days)',
            style: AppTypography.bodyS.copyWith(color: AppColors.textDim),
          ),
        ],
      ),
    );

    return Column(children: [
      card,
      const SizedBox(height: AppSpacing.sectionGap),
    ]);
  }

  Color _readinessColor(ReadinessLevel level) {
    switch (level) {
      case ReadinessLevel.green:
        return AppColors.ok;
      case ReadinessLevel.yellow:
        return AppColors.warn;
      case ReadinessLevel.red:
        return AppColors.bad;
    }
  }

  Widget _buildWeightTrend() {
    // Load ALL weight entries (no limit)
    final allEntries = NutritionRepository.instance.getWeightEntries(limit: 9999);

    // Filter by selected time window
    final now = DateTime.now();
    final cutoff = _weightFilterCutoff(now);
    final filtered = cutoff == null
        ? allEntries
        : allEntries.where((e) {
            final d = DateTime.tryParse(e['date'] as String? ?? '');
            return d != null && d.isAfter(cutoff);
          }).toList();

    // Target weight for projection
    final profile = UserRepository.instance.getProfile() ?? {};
    final targetWeight = (profile['target_weight_kg'] as num?)?.toDouble() ?? 0;

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
          const SizedBox(height: 10),

          // Time filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', '1Y', '6M', '3M', '1M', '1W'].map((label) {
                final isActive = _weightFilter == label;
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _weightFilter = label),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.accent : AppColors.input,
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(
                          color: isActive
                              ? AppColors.accent
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        label,
                        style: AppTypography.bodySm.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: isActive ? Colors.black : AppColors.textDim),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          if (filtered.length < 2)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Column(
                  children: [
                    Icon(Icons.show_chart, size: 32, color: AppColors.textSecondary.withValues(alpha: 0.4)),
                    const SizedBox(height: 8),
                    Text(
                      'Log your weight daily to see your trend',
                      style: AppTypography.bodyM.copyWith(color: AppColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            // Chart
            SizedBox(
              height: 180,
              child: _buildLineChart(filtered, targetWeight),
            ),

            // Projection callout
            if (targetWeight > 0 && filtered.length >= 2) ...[
              const SizedBox(height: 10),
              _buildProjectionCallout(filtered, targetWeight),
            ],
          ],
        ],
      ),
    );
  }

  DateTime? _weightFilterCutoff(DateTime now) {
    switch (_weightFilter) {
      case '1W':  return now.subtract(const Duration(days: 7));
      case '1M':  return now.subtract(const Duration(days: 30));
      case '3M':  return now.subtract(const Duration(days: 90));
      case '6M':  return now.subtract(const Duration(days: 180));
      case '1Y':  return now.subtract(const Duration(days: 365));
      default:    return null; // 'All'
    }
  }

  Widget _buildLineChart(List<Map<String, dynamic>> entries, double targetWeight) {
    final spots = <FlSpot>[];
    final dates = <int, String>{};

    for (int i = 0; i < entries.length; i++) {
      final w = (entries[i]['weight_kg'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), w));

      // Store date labels for tooltip and axis
      final dateStr = entries[i]['date'] as String? ?? '';
      dates[i] = dateStr;
    }

    // Calculate Y axis range (guard against empty spots list)
    if (spots.isEmpty) return const SizedBox.shrink();
    final weights = spots.map((s) => s.y);
    double minY = weights.reduce((a, b) => a < b ? a : b) - 1;
    double maxY = weights.reduce((a, b) => a > b ? a : b) + 1;
    if (targetWeight > 0) {
      minY = minY < targetWeight ? minY : targetWeight - 1;
      maxY = maxY > targetWeight ? maxY : targetWeight + 1;
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: ((maxY - minY) / 4).clamp(0.5, 10.0),
          getDrawingHorizontalLine: (value) => FlLine(
            color: AppColors.border.withValues(alpha: 0.5),
            strokeWidth: 0.5,
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toStringAsFixed(0),
                  style: AppTypography.monoXs.copyWith(color: AppColors.textDim),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: (entries.length / 5).clamp(1, 100).roundToDouble(),
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= entries.length) return const SizedBox();
                final d = dates[idx] ?? '';
                // Show abbreviated date: "3/12" or "12 Mar"
                final parts = d.split('-');
                if (parts.length == 3) {
                  return Text(
                    '${int.tryParse(parts[2]) ?? ""}/${int.tryParse(parts[1]) ?? ""}',
                    style: AppTypography.monoXs.copyWith(fontSize: 8, color: AppColors.textDim),
                  );
                }
                return const SizedBox();
              },
            ),
          ),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        minY: minY,
        maxY: maxY,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final dateStr = dates[spot.x.toInt()] ?? '';
                return LineTooltipItem(
                  '${spot.y.toStringAsFixed(1)} kg\n$dateStr',
                  AppTypography.bodySm.copyWith(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
        extraLinesData: targetWeight > 0
            ? ExtraLinesData(horizontalLines: [
                HorizontalLine(
                  y: targetWeight,
                  color: AppColors.green.withValues(alpha: 0.4),
                  strokeWidth: 1,
                  dashArray: [4, 4],
                  label: HorizontalLineLabel(
                    show: true,
                    labelResolver: (_) => 'Goal: ${targetWeight.toStringAsFixed(0)}kg',
                    style: AppTypography.monoXs.copyWith(color: AppColors.ok),
                  ),
                ),
              ])
            : ExtraLinesData(),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.2,
            color: AppColors.accent,
            barWidth: 2.5,
            dotData: FlDotData(
              show: entries.length <= 30,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 3,
                  color: AppColors.accent,
                  strokeWidth: 1,
                  strokeColor: AppColors.bg,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.accent.withValues(alpha: 0.06),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectionCallout(List<Map<String, dynamic>> entries, double targetWeight) {
    final first = entries.first;
    final last = entries.last;
    final firstDate = DateTime.tryParse(first['date'] as String? ?? '');
    final lastDate = DateTime.tryParse(last['date'] as String? ?? '');
    final firstW = (first['weight_kg'] as num).toDouble();
    final lastW = (last['weight_kg'] as num).toDouble();

    if (firstDate == null || lastDate == null) return const SizedBox();
    final weeksDiff = lastDate.difference(firstDate).inDays / 7.0;
    if (weeksDiff < 0.5) return const SizedBox();

    final weeklyRate = (lastW - firstW) / weeksDiff;
    final remaining = targetWeight - lastW;

    // Check if moving in right direction
    final goal = UserRepository.instance.getProfile()?['primary_goal'] as String? ?? '';
    final wantsLose = goal.contains('lose');
    final movingRight = (wantsLose && weeklyRate < 0) || (!wantsLose && weeklyRate > 0);

    if (!movingRight && remaining.abs() > 0.5) {
      return Row(
        children: [
          Icon(Icons.warning_amber, size: 14, color: AppColors.orange),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Adjust your ${wantsLose ? "diet" : "nutrition"} to stay on track',
              style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.warn),
            ),
          ),
        ],
      );
    }

    if (remaining.abs() < 0.5) {
      return Row(
        children: [
          Icon(Icons.check_circle, size: 14, color: AppColors.green),
          const SizedBox(width: 6),
          Text(
            'You\'ve reached your goal weight!',
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w600, color: AppColors.ok),
          ),
        ],
      );
    }

    final weeksToGo = (remaining / weeklyRate).abs().ceil();
    final targetDate = DateTime.now().add(Duration(days: weeksToGo * 7));
    const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final dateLabel = '${monthNames[targetDate.month - 1]} ${targetDate.year}';

    return Row(
      children: [
        Icon(Icons.trending_down, size: 14, color: AppColors.green),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'At current rate, you\'ll reach ${targetWeight.toStringAsFixed(0)}kg in ~$weeksToGo weeks (around $dateLabel)',
            style: AppTypography.bodySm.copyWith(fontWeight: FontWeight.w500, color: AppColors.ok),
          ),
        ),
      ],
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
                style: AppTypography.body.copyWith(fontSize: 28, fontWeight: FontWeight.w900, color: AppColors.warn),
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
                      style: AppTypography.bodySm.copyWith(color: AppColors.bad),
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
                      SubscriptionService.instance.gateAndVerify(
                        AppConstants.featureWeeklyAiReport,
                        onPro: () => _generateReport(),
                        onFree: () {
                          // First report is free; subsequent ones require PRO.
                          final alreadyGenerated =
                              HiveService.instance.configBox.get(
                                    'first_report_generated',
                                    defaultValue: false,
                                  ) as bool;
                          if (alreadyGenerated) {
                            showPaywallSheet(context,
                                feature: 'AI Weekly Report');
                          } else {
                            _generateReport();
                          }
                        },
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
                          style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: Colors.black54),
                        ),
                      ],
                    )
                  : Text(
                      'Generate Report',
                      style: AppTypography.body.copyWith(fontWeight: FontWeight.w900, color: Colors.black),
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

    // C4 follow-up: the new Sunday Strategic Brief returns plain text (8-12
    // lines, Captain voice) which the server stores in `summary` via the
    // JSON-parse fallback path. Detect this by checking whether the legacy
    // bullet lists are all empty — if so, it's the new brief format and the
    // full prose lives in summary. Legacy reports carry non-empty bullet lists.
    final isFullBrief =
        summary.isNotEmpty && topWins.isEmpty && areasToImprove.isEmpty && recommendations.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header card — renders the full brief or the legacy short summary
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
                style: AppTypography.monoXs.copyWith(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.textDim, letterSpacing: 1.2),
              ),
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 12),
                if (isFullBrief)
                  // New format: full multi-line Captain's brief.
                  // softWrap: true is the Flutter default, but stated explicitly
                  // for clarity. height: 1.6 gives readable line spacing for the
                  // 8-12 line plain-text brief (mono voice, dense content).
                  Text(
                    summary,
                    softWrap: true,
                    style: AppTypography.bodyL.copyWith(
                      height: 1.6,
                      color: AppColors.textPrimary,
                    ),
                  )
                else
                  // Legacy format: 2-3 sentence summary string.
                  Text(summary, style: AppTypography.bodyL),
              ],
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
                    style: AppTypography.body.copyWith(fontSize: 32, fontWeight: FontWeight.w900, color: compliancePercent >= 70
                          ? AppColors.ok
                          : compliancePercent >= 40
                              ? AppColors.warn
                              : AppColors.bad),
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

        // Share as Video — Remotion weekly recap render
        _buildWeeklyVideoShareRow(report),
        const SizedBox(height: AppSpacing.inlineGap),

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
              style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.accent),
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

  Widget _buildWeeklyVideoShareRow(Map<String, dynamic> report) {
    final renderState = ref.watch(videoRenderNotifierProvider);

    if (renderState.isLoading ||
        renderState.status == VideoRenderStatus.ready ||
        renderState.status == VideoRenderStatus.failed) {
      return SizedBox(
          width: double.infinity,
          child: Center(child: VideoShareButton()));
    }

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () {
          final userName =
              UserRepository.instance.getProfile()?['full_name'] as String? ??
                  'Athlete';
          final workoutSummary =
              report['workout_summary'] as Map<String, dynamic>? ?? {};
          ref.read(videoRenderNotifierProvider.notifier).triggerWorkoutVideo(
            compositionId: 'WeeklyRecap',
            inputProps: {
              'userName': userName,
              // FOB-1 (OI-60): getCurrentWeekNumber() clamps to [1,4] and a
              // hold starts at plan_start+28, so the recap card stamped
              // "WEEK 4 RECAP" for every hold at every ordinal. `holdOrdinal`
              // supersedes the counter in the composition when present; it is
              // null for every user while `enable_hold_weeks` is OFF, so the
              // rendered video is byte-identical until the flip.
              'weekNumber': WorkoutRepository.instance.getCurrentWeekNumber(),
              'holdOrdinal': ref.read(weekIdentityProvider).holdOrdinal,
              'totalVolume': workoutSummary['total_volume_kg'] ?? 0,
              'totalWorkouts': workoutSummary['workouts_completed'] ?? 0,
              'totalPrs': workoutSummary['prs_hit'] ?? 0,
              'aiTagline': report['summary'] ?? '',
            },
          );
        },
        icon: const Icon(Icons.video_library_rounded, size: 16),
        label: Text(
          'Share as Video',
          style: AppTypography.body.copyWith(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textDim),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          side: const BorderSide(color: AppColors.border),
          padding: const EdgeInsets.symmetric(vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
        ),
      ),
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
