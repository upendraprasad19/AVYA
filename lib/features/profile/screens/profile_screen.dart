import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_identity.dart';
import '../widgets/profile_row.dart';
import '../widgets/section_header.dart';
import '../widgets/biometric_sync_card.dart';
import '../widgets/weekly_report_card.dart';
import '../widgets/badges_grid.dart';
import 'notification_settings_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late bool _isMetric;
  bool _isLoading = true;

  // Notification preferences (loaded from Hive configBox)
  late Map<String, dynamic> _notifPrefs;

  @override
  void initState() {
    super.initState();
    _isMetric = UserRepository.instance.getUnitsMetric();
    _notifPrefs = _loadNotificationPreferences();
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Map<String, dynamic> _loadNotificationPreferences() {
    final configBox = HiveService.instance.configBox;
    final stored = configBox.get('notification_preferences');
    if (stored != null && stored is Map) {
      return Map<String, dynamic>.from(stored);
    }
    // Default preferences
    return {
      'morning_checkin': {'enabled': true, 'time': '07:00'},
      'workout_reminder': {'enabled': true, 'time': '18:30'},
      'streak_alerts': {'enabled': true},
      'weekly_recap': {'enabled': true, 'day': 'sunday'},
      'subscription_reminders': {'enabled': true},
    };
  }

  Future<void> _saveNotificationPreferences() async {
    await HiveService.instance.configBox.put('notification_preferences', _notifPrefs);
  }

  bool _getNotifEnabled(String key) {
    final pref = _notifPrefs[key];
    if (pref is Map) return pref['enabled'] == true;
    return true;
  }

  void _retry() {
    setState(() => _isLoading = true);
    ref.invalidate(userProfileProvider);
    ref.invalidate(userStatsProvider);
    ref.invalidate(subscriptionInfoProvider);
    ref.invalidate(biometricProvider);
    ref.invalidate(progressPhotosProvider);
    ref.invalidate(usageWeeksProvider);
    ref.invalidate(firstReportViewedProvider);
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const ScreenLoadingSkeleton(cardCount: 5),
      );
    }

    try {
      return _buildProfileContent(context);
    } catch (e) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: ErrorState(
              title: 'Failed to load profile',
              subtitle: 'Tap to retry',
              onRetry: _retry,
            ),
          ),
        ),
      );
    }
  }

  Widget _buildProfileContent(BuildContext context) {
    final profile = ref.watch(userProfileProvider);
    final stats = ref.watch(userStatsProvider);
    final subInfo = ref.watch(subscriptionInfoProvider);
    final biometric = ref.watch(biometricProvider);
    final usageWeeks = ref.watch(usageWeeksProvider);
    final firstReportViewed = ref.watch(firstReportViewedProvider);

    final name = profile['full_name'] as String? ?? 'User';
    final gender = profile['gender'] as String? ?? '';
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final targetKg = (profile['target_weight_kg'] as num?)?.toDouble();
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final bodyFatPct = (profile['body_fat_pct'] as num?)?.toDouble();
    final dob = profile['date_of_birth'] as String?;

    final subtitle =
        'Phase ${stats.currentPhase} \u00B7 Week ${stats.currentWeek} \u00B7 ${_formatGoal(stats.primaryGoal)}';

    // BMI calculation
    double? bmi;
    if (weightKg != null && heightCm != null && heightCm > 0) {
      bmi = weightKg / ((heightCm / 100) * (heightCm / 100));
    }

    // Nutrition targets
    Map<String, double>? nutritionTargets;
    if (weightKg != null && heightCm != null && gender.isNotEmpty) {
      int age = 25;
      if (dob != null) {
        final bd = DateTime.tryParse(dob);
        if (bd != null) age = DateTime.now().difference(bd).inDays ~/ 365;
      }
      final t = BmrCalculator.calculateTargets(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        gender: gender,
        activityLevel: profile['activity_level'] as String? ?? 'moderate',
        goal: stats.primaryGoal,
      );
      nutritionTargets = {
        'tdee': t.tdee.toDouble(),
        'calories': t.dailyCalories.toDouble(),
        'protein': t.proteinGrams.toDouble(),
      };
    }

    // Usage counts for free users
    final usageService = UsageCounterService.instance;
    final isPro = subInfo.isPro;

    // Enabled notifications count
    int enabledNotifCount = 0;
    for (final key in ['morning_checkin', 'workout_reminder', 'streak_alerts', 'weekly_recap', 'subscription_reminders']) {
      if (_getNotifEnabled(key)) enabledNotifCount++;
    }

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Safe area
              SizedBox(height: MediaQuery.of(context).padding.top + 10),

              // 1. Profile identity (no banner — #1 remove Phase 2 dead-ends)
              ProfileIdentity(
                name: name,
                subtitle: subtitle,
                onTapAvatar: () => context.go('/profile/edit'),
                onTapEdit: () => context.go('/profile/edit'),
              ),
              const SizedBox(height: 8),

              // #2 Daily Completion summary
              _buildDailyCompletion(stats),
              const SizedBox(height: 8),

              // #3 Body Stats card
              _buildBodyStats(weightKg, targetKg, bmi, bodyFatPct),
              const SizedBox(height: 8),

              // #4 Journey timeline
              _buildJourneyTimeline(stats),
              const SizedBox(height: 8),

              // #8 Nutrition Targets
              if (nutritionTargets != null) ...[
                _buildNutritionTargets(nutritionTargets),
                const SizedBox(height: 8),
              ],

              // Achievements (#6 — badge detail already has tap, kept as-is)
              const SectionHeader('ACHIEVEMENTS'),
              const BadgesGrid(),
              const SizedBox(height: 8),

              // #7 Subscription Card (PRO=expiry, Free=rate limits)
              const SectionHeader('SUBSCRIPTION'),
              _buildSubscriptionSection(subInfo, isPro, usageService),
              const SizedBox(height: 8),

              // Health Sync
              const SectionHeader('HEALTH SYNC'),
              BiometricSyncCard(
                stepsToday: biometric.stepsToday,
                sleepHours: biometric.sleepHours,
                isSyncEnabled: biometric.isSyncEnabled,
                onToggleSync: () async {
                  final newValue = !biometric.isSyncEnabled;
                  ref.read(biometricProvider.notifier).toggleSync(newValue);
                  if (newValue && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Health Connect sync enabled.',
                          style: GoogleFonts.getFont('DM Sans', fontSize: 13),
                        ),
                        backgroundColor: AppColors.card,
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                },
                onLogSleep: (hours, quality) {
                  ref.read(biometricProvider.notifier).logSleep(
                    hours: hours,
                    quality: quality,
                  );
                },
              ),
              const SizedBox(height: 8),

              // Reports
              const SectionHeader('REPORTS'),
              WeeklyReportCard(
                isPro: subInfo.isPro,
                usageWeeks: usageWeeks,
                hasFirstReport: firstReportViewed,
                onViewReport: () {
                  if (!firstReportViewed) {
                    ref.read(firstReportViewedProvider.notifier).markViewed();
                  }
                  context.go('/profile/reports');
                },
                onUpgradeTap: () {
                  SubscriptionService.instance.gate(
                    AppConstants.featureWeeklyAiReport,
                    onPro: () => context.go('/profile/reports'),
                    onFree: () => showPaywallSheet(context, feature: 'Weekly AI Report'),
                  );
                },
              ),
              const SizedBox(height: 8),

              // #5 Notifications (consolidated — just a row linking to settings screen)
              const SectionHeader('SETTINGS'),
              _buildCard([
                ProfileRow(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: '$enabledNotifCount/5 enabled',
                  trailing: const ProfileRowChevron(),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => NotificationSettingsScreen(
                      notifPrefs: _notifPrefs,
                      isPro: subInfo.isPro,
                      onSave: (prefs) {
                        setState(() => _notifPrefs = prefs);
                        _saveNotificationPreferences();
                      },
                    )),
                  ),
                ),
                ProfileRow(
                  icon: Icons.tune,
                  title: 'Units',
                  trailing: UnitsSegmentedControl(
                    isMetric: _isMetric,
                    onChanged: (metric) {
                      setState(() => _isMetric = metric);
                      UserRepository.instance.setUnitsMetric(metric);
                    },
                  ),
                ),
                ProfileRow(
                  icon: Icons.shield_outlined,
                  title: 'Privacy & Permissions',
                  trailing: const ProfileRowChevron(),
                  onTap: () => _showPrivacyDialog(),
                ),
                // #10 Export Data
                ProfileRow(
                  icon: Icons.download_outlined,
                  title: 'Export My Data',
                  subtitle: 'Download all your data as JSON',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => _exportData(),
                ),
              ]),
              const SizedBox(height: 12),

              // Sign Out
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                child: GestureDetector(
                  onTap: () => _showSignOutDialog(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.red.withValues(alpha: 0.08),
                      border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        'Sign Out \u2192',
                        style: GoogleFonts.getFont('DM Sans', fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.red),
                      ),
                    ),
                  ),
                ),
              ),

              // #9 Delete Account — hidden behind expandable danger zone
              const SizedBox(height: 8),
              _buildDangerZone(),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  // ── #2 Daily Completion ──────────────────────────────────────────

  Widget _buildDailyCompletion(UserStatsData stats) {
    // Read completion states from Hive
    final hive = HiveService.instance;
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    final workoutSchedule = hive.workoutBox.values.where((raw) {
      if (raw is! Map) return false;
      return raw['date'] == todayStr && raw['status'] == 'completed';
    });
    final workoutDone = workoutSchedule.isNotEmpty;

    final nutritionToday = ref.watch(nutritionSummaryProvider);
    final hasMeals = nutritionToday.calories >= nutritionToday.calorieTarget &&
        nutritionToday.protein >= nutritionToday.proteinTarget;

    final waterMl = ref.watch(waterIntakeProvider);
    final waterDone = waterMl >= 3000;

    final weightDone = hive.healthBox.get('weight_$todayStr') != null;

    final done = [workoutDone, hasMeals, waterDone, weightDone].where((b) => b).length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: done == 4
            ? AppColors.emerald.withValues(alpha: 0.3)
            : AppColors.border),
      ),
      child: Row(
        children: [
          // Progress ring
          SizedBox(
            width: 40, height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: done / 4,
                  strokeWidth: 4,
                  backgroundColor: AppColors.input,
                  valueColor: AlwaysStoppedAnimation(
                      done == 4 ? AppColors.emerald : AppColors.accent),
                ),
                Text('$done/4', style: GoogleFonts.getFont('DM Sans',
                    fontSize: 11, fontWeight: FontWeight.w900,
                    color: done == 4 ? AppColors.emerald : AppColors.accent)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('DAILY GOALS', style: GoogleFonts.getFont('DM Sans',
                    fontSize: 10, fontWeight: FontWeight.w700,
                    letterSpacing: 1.0, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _completionDot('Workout', workoutDone),
                    const SizedBox(width: 8),
                    _completionDot('Meals', hasMeals),
                    const SizedBox(width: 8),
                    _completionDot('Water', waterDone),
                    const SizedBox(width: 8),
                    _completionDot('Weight', weightDone),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _completionDot(String label, bool done) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: done ? AppColors.emerald : AppColors.input,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? AppColors.emerald : AppColors.border,
              width: 1,
            ),
          ),
        ),
        const SizedBox(width: 3),
        Text(label, style: GoogleFonts.getFont('DM Sans',
            fontSize: 9, color: done ? AppColors.emerald : AppColors.textSecondary)),
      ],
    );
  }

  // ── #3 Body Stats Card ──────────────────────────────────────────

  Widget _buildBodyStats(double? weight, double? target, double? bmi, double? bodyFat) {
    // Format weight/target according to the user's units preference.
    String fmtWeight(double? kg) {
      if (kg == null) return '\u2014';
      if (_isMetric) return '${kg.toStringAsFixed(1)} kg';
      final lbs = kg * 2.20462;
      return '${lbs.toStringAsFixed(0)} lbs';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('BODY STATS', style: GoogleFonts.getFont('DM Sans',
                  fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.0, color: AppColors.textSecondary)),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/profile/edit'),
                child: Text('EDIT', style: GoogleFonts.getFont('DM Sans',
                    fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.accent)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCell('Weight', fmtWeight(weight), AppColors.accent),
              _statCell('Target', fmtWeight(target), AppColors.emerald),
              _statCell('BMI', bmi != null ? bmi.toStringAsFixed(1) : '\u2014', AppColors.blue),
              _statCell('Body Fat', bodyFat != null ? '${bodyFat.toStringAsFixed(0)}%' : '\u2014', AppColors.orange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCell(String label, String value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: GoogleFonts.getFont('DM Sans',
              fontSize: 16, fontWeight: FontWeight.w900, color: color, height: 1)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.getFont('DM Sans',
              fontSize: 9, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── #4 Journey Timeline ─────────────────────────────────────────

  Widget _buildJourneyTimeline(UserStatsData stats) {
    // Phase data
    const phaseNames = [
      'Foundation', 'Building', 'Progression', 'Strength',
      'Endurance', 'Power', 'Conditioning', 'Peak',
      'Mastery', 'Elite', 'Champion', 'Legend',
    ];
    final phaseName = stats.currentPhase <= phaseNames.length
        ? phaseNames[stats.currentPhase - 1]
        : 'Phase ${stats.currentPhase}';

    // Goal insights from profile
    final profile = UserRepository.instance.getProfile() ?? {};
    final currentWeight = (profile['current_weight_kg'] as num?)?.toDouble() ?? 0;
    final targetWeight = (profile['target_weight_kg'] as num?)?.toDouble() ?? 0;
    final goal = profile['primary_goal'] as String? ?? '';

    // Weight trajectory (from weight logs in healthBox)
    final hive = HiveService.instance;
    final weightEntries = <MapEntry<DateTime, double>>[];
    for (final key in hive.healthBox.keys) {
      if (key is! String || !key.startsWith('weight_')) continue;
      final raw = hive.healthBox.get(key);
      if (raw is! Map) continue;
      final w = (raw['weight_kg'] as num?)?.toDouble();
      final d = DateTime.tryParse(raw['date'] as String? ?? '');
      if (w != null && d != null) weightEntries.add(MapEntry(d, w));
    }
    weightEntries.sort((a, b) => a.key.compareTo(b.key));

    // Compute weekly rate and ETA
    String? trajectoryText;
    String? etaText;
    if (weightEntries.length >= 2 && targetWeight > 0) {
      final first = weightEntries.first;
      final last = weightEntries.last;
      final weeksDiff = last.key.difference(first.key).inDays / 7.0;
      if (weeksDiff > 0.5) {
        final totalChange = last.value - first.value;
        final weeklyRate = totalChange / weeksDiff;
        final remaining = targetWeight - last.value;

        if (weeklyRate.abs() > 0.05 && !weeklyRate.isNaN && !weeklyRate.isInfinite) {
          final changeStr = totalChange.abs().toStringAsFixed(1);
          final verb = totalChange < 0 ? 'Lost' : 'Gained';
          trajectoryText = '$verb ${changeStr}kg in ${weeksDiff.toStringAsFixed(0)} weeks';

          // ETA: if moving in the right direction
          final movingRight = (goal.contains('lose') && weeklyRate < 0) ||
              (goal.contains('build') && weeklyRate > 0) ||
              (remaining.abs() < 0.5);
          if (movingRight && remaining.abs() > 0.5 && weeklyRate != 0) {
            final weeksToGo = (remaining / weeklyRate).abs().ceil();
            etaText = 'At this rate: ~$weeksToGo weeks to goal';
          }
        }
      }
    }

    // (Workout consistency data could be added here in future phases)

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text('YOUR JOURNEY', style: GoogleFonts.getFont('DM Sans',
                  fontSize: 10, fontWeight: FontWeight.w700,
                  letterSpacing: 1.0, color: AppColors.textSecondary)),
              const Spacer(),
              Text('Week ${stats.currentWeek} of 4', style: GoogleFonts.getFont('DM Sans',
                  fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.accent)),
            ],
          ),
          const SizedBox(height: 6),

          // Phase name + focus
          Text(
            'Phase ${stats.currentPhase} \u2014 $phaseName',
            style: GoogleFonts.getFont('DM Sans',
                fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 8),

          // Week progress bar within phase
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: stats.currentWeek / 4.0,
              minHeight: 6,
              backgroundColor: AppColors.input,
              valueColor: AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 10),

          // Phase dots
          Row(
            children: List.generate(12, (phase) {
              final isCompleted = phase + 1 < stats.currentPhase;
              final isCurrent = phase + 1 == stats.currentPhase;
              return Expanded(
                child: Container(
                  margin: EdgeInsets.only(right: phase < 11 ? 3 : 0),
                  height: 4,
                  decoration: BoxDecoration(
                    color: isCompleted
                        ? AppColors.green
                        : isCurrent
                            ? AppColors.accent
                            : stats.isPro || phase == 0
                                ? AppColors.input
                                : AppColors.input.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 10),

          // Motivating insights
          if (targetWeight > 0 && currentWeight > 0) ...[
            _journeyInsight(
              icon: Icons.flag_outlined,
              text: 'Goal: ${goal.contains("lose") ? "Lose" : goal.contains("build") ? "Build to" : "Reach"} ${targetWeight.toStringAsFixed(0)}kg',
              color: AppColors.accent,
            ),
          ],
          if (trajectoryText != null)
            _journeyInsight(
              icon: Icons.trending_down,
              text: trajectoryText,
              color: AppColors.green,
            ),
          if (etaText != null)
            _journeyInsight(
              icon: Icons.timer_outlined,
              text: etaText,
              color: AppColors.accent,
            ),
          if (trajectoryText == null && targetWeight > 0)
            _journeyInsight(
              icon: Icons.scale_outlined,
              text: 'Log your weight daily to see your trajectory',
              color: AppColors.textSecondary,
            ),

          // Next milestone
          if (stats.currentPhase == 1) ...[
            const SizedBox(height: 2),
            _journeyInsight(
              icon: Icons.emoji_events_outlined,
              text: '${(4 - stats.currentWeek).clamp(0, 4)} weeks to complete Phase 1',
              color: AppColors.proGold,
            ),
          ],
        ],
      ),
    );
  }

  Widget _journeyInsight({required IconData icon, required String text, required Color color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.getFont('DM Sans',
                  fontSize: 12, fontWeight: FontWeight.w500, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // ── #7 Subscription Section ─────────────────────────────────────

  Widget _buildSubscriptionSection(SubscriptionInfoData subInfo, bool isPro, UsageCounterService usage) {
    if (isPro) {
      // Simple PRO card with expiry
      final expiryStr = subInfo.expiresAt != null
          ? '${subInfo.expiresAt!.day}/${subInfo.expiresAt!.month}/${subInfo.expiresAt!.year}'
          : '\u2014';
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.cardM),
          border: Border.all(color: AppColors.proGold.withValues(alpha: 0.3)),
          gradient: const LinearGradient(
            colors: [Color(0xFF1a1408), Color(0xFF0e1219)],
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.proGold,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text('PRO', style: GoogleFonts.getFont('DM Sans',
                  fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: Colors.black)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${(subInfo.plan ?? "monthly").toUpperCase()} \u00B7 Renews $expiryStr',
                style: GoogleFonts.getFont('DM Sans', fontSize: 12,
                    fontWeight: FontWeight.w600, color: AppColors.proGold),
              ),
            ),
          ],
        ),
      );
    }

    // Free user — show trial pill + rate limits
    final aiTextUsed = usage.used(AppConstants.featureAiTextLogPro, false);
    final aiTextLimit = AppConstants.freeAiTextLogsPerDay;
    final scanUsed = usage.used(AppConstants.featureScanMealPro, false);
    final scanLimit = AppConstants.freeScanMealPerMonth;
    final cartUsed = usage.used(AppConstants.featureCartAuditorPro, false);
    final cartLimit = AppConstants.freeCartAuditorPerMonth;

    // Compute trial days remaining from Hive directly
    final configBox = HiveService.instance.configBox;
    final trialStartRaw = configBox.get('ai_trial_start') as String?;
    int? trialDaysLeft;
    if (trialStartRaw != null) {
      final trialStart = DateTime.tryParse(trialStartRaw);
      if (trialStart != null) {
        final elapsed = DateTime.now().difference(trialStart).inDays;
        final left = AppConstants.freeAiTrialDays - elapsed;
        trialDaysLeft = left.clamp(0, AppConstants.freeAiTrialDays);
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.cardM),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FREE PLAN', style: GoogleFonts.getFont('DM Sans',
                  fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: AppColors.textSecondary)),
              const Spacer(),
              GestureDetector(
                onTap: () => showPaywallSheet(context, feature: 'PRO'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text('Upgrade', style: GoogleFonts.getFont('DM Sans',
                      fontSize: 10, fontWeight: FontWeight.w900, color: Colors.black)),
                ),
              ),
            ],
          ),
          // Trial days pill
          if (trialDaysLeft != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: trialDaysLeft > 7
                    ? AppColors.accentTint
                    : AppColors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: trialDaysLeft > 7
                      ? AppColors.accent.withValues(alpha: 0.2)
                      : AppColors.red.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timer_outlined,
                    size: 11,
                    color: trialDaysLeft > 7 ? AppColors.accent : AppColors.red,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    trialDaysLeft > 0
                        ? '30-day AI trial · $trialDaysLeft day${trialDaysLeft == 1 ? '' : 's'} remaining'
                        : 'AI trial expired · Upgrade to continue',
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: trialDaysLeft > 7 ? AppColors.accent : AppColors.red,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          _usageRow('AI Text Logs', aiTextUsed, aiTextLimit, '/day'),
          const SizedBox(height: 6),
          _usageRow('Meal Scans', scanUsed, scanLimit, '/month'),
          const SizedBox(height: 6),
          _usageRow('Cart Auditor', cartUsed, cartLimit, '/month'),
        ],
      ),
    );
  }

  Widget _usageRow(String label, int used, int limit, String period) {
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isExhausted = used >= limit;
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(label, style: GoogleFonts.getFont('DM Sans',
              fontSize: 11, color: AppColors.textSecondary)),
        ),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: pct,
              child: Container(
                decoration: BoxDecoration(
                  color: isExhausted ? AppColors.red : AppColors.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$used/$limit$period', style: GoogleFonts.getFont('DM Sans',
            fontSize: 10, fontWeight: FontWeight.w700,
            color: isExhausted ? AppColors.red : AppColors.textSecondary)),
      ],
    );
  }

  // ── #8 Nutrition Targets ────────────────────────────────────────

  Widget _buildNutritionTargets(Map<String, double> targets) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Text('MY TARGETS', style: GoogleFonts.getFont('DM Sans',
              fontSize: 10, fontWeight: FontWeight.w700,
              letterSpacing: 1.0, color: AppColors.textSecondary)),
          const SizedBox(width: 12),
          _targetChip('${targets['tdee']?.round()} kcal', 'TDEE'),
          const SizedBox(width: 8),
          _targetChip('${targets['calories']?.round()} kcal', 'TARGET'),
          const SizedBox(width: 8),
          _targetChip('${targets['protein']?.round()}g', 'PROTEIN'),
        ],
      ),
    );
  }

  Widget _targetChip(String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: GoogleFonts.getFont('DM Sans',
              fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.accent)),
          Text(label, style: GoogleFonts.getFont('DM Sans',
              fontSize: 8, fontWeight: FontWeight.w700,
              letterSpacing: 0.5, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ── #9 Danger Zone ──────────────────────────────────────────────

  Widget _buildDangerZone() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text('Danger Zone', style: GoogleFonts.getFont('DM Sans',
            fontSize: 11, color: AppColors.textSecondary)),
        iconColor: AppColors.textSecondary,
        collapsedIconColor: AppColors.textSecondary,
        children: [
          GestureDetector(
            onTap: () => _showDeleteAccountDialog(),
            child: Text('Delete Account', style: GoogleFonts.getFont('DM Sans',
                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.red)),
          ),
        ],
      ),
    );
  }

  // ── #10 Export Data ─────────────────────────────────────────────

  Future<void> _exportData() async {
    final hive = HiveService.instance;
    final data = <String, dynamic>{
      'exported_at': DateTime.now().toIso8601String(),
      'profile': Map<String, dynamic>.from(hive.userBox.get('profile') as Map? ?? {}),
      'workout_logs_count': hive.workoutBox.length,
      'nutrition_logs_count': hive.nutritionBox.length,
      'health_logs_count': hive.healthBox.length,
    };

    // Collect workout logs
    final workouts = <Map<String, dynamic>>[];
    for (final raw in hive.workoutBox.values) {
      if (raw is Map) workouts.add(Map<String, dynamic>.from(raw));
    }
    data['workout_logs'] = workouts;

    // Collect nutrition logs
    final nutrition = <Map<String, dynamic>>[];
    for (final raw in hive.nutritionBox.values) {
      if (raw is Map) nutrition.add(Map<String, dynamic>.from(raw));
    }
    data['nutrition_logs'] = nutrition;

    // Collect health logs
    final health = <Map<String, dynamic>>[];
    for (final raw in hive.healthBox.values) {
      if (raw is Map) health.add(Map<String, dynamic>.from(raw));
    }
    data['health_logs'] = health;

    final jsonStr = const JsonEncoder.withIndent('  ').convert(data);
    await Share.share(jsonStr, subject: 'ICANBEFITTER Data Export');
  }

  // ── Privacy Dialog ──────────────────────────────────────────────

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.cardM)),
        title: Text('Privacy & Permissions', style: GoogleFonts.getFont('DM Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your data is stored locally on your device. Supabase is used only for backups, AI, and community features.', style: GoogleFonts.getFont('DM Sans', fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
            const SizedBox(height: 12),
            Text('Permissions:', style: GoogleFonts.getFont('DM Sans', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            Text('\u2022 Camera: Meal scanning\n\u2022 Health Connect: Steps & sleep\n\u2022 Storage: Progress photos', style: GoogleFonts.getFont('DM Sans', fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Close', style: GoogleFonts.getFont('DM Sans', fontWeight: FontWeight.w700, color: AppColors.accent)),
          ),
        ],
      ),
    );
  }

  /// Wraps children in a card container matching `.card` style.
  Widget _buildCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.cardM),
        ),
        title: Text(
          'Sign Out',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out? Your data is safe locally.',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _performSignOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text(
              'Sign Out',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Sign out Supabase -> clear Hive -> route to auth screen.
  ///
  /// Order matters: sign out FIRST so the router never sees
  /// authenticated + !onboarded which would redirect to /onboarding.
  Future<void> _performSignOut() async {
    // 1. Terminate the Supabase session (local scope always works offline).
    try {
      await SupabaseService.instance.client.auth
          .signOut(scope: SignOutScope.global);
    } catch (_) {
      try {
        await SupabaseService.instance.client.auth
            .signOut(scope: SignOutScope.local);
      } catch (_) {}
    }

    // 2. Wipe all user-specific Hive boxes after session is gone.
    try {
      await UserRepository.instance.clearAllData();
    } catch (_) {}

    if (mounted) {
      context.go('/sign-in');
    }
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.cardM),
        ),
        title: Text(
          'Delete Account',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: AppColors.red,
          ),
        ),
        content: Text(
          'This will permanently delete your account and all data. This action cannot be undone.',
          style: GoogleFonts.getFont(
            'DM Sans',
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: AppColors.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w700,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                // Sign out and soft-delete BEFORE clearing local data,
                // otherwise the router sees authenticated + !onboarded → /onboarding.
                try {
                  final supabase = SupabaseService.instance.client;
                  final userId = supabase.auth.currentUser?.id;
                  if (userId != null) {
                    await supabase.from('users').update({
                      'is_deleted': true,
                      'deleted_at': DateTime.now().toIso8601String(),
                    }).eq('id', userId);
                  }
                  // Use global scope to sign out on server too.
                  await supabase.auth.signOut(scope: SignOutScope.global);
                } catch (_) {
                  // Offline or server error — force a local-only sign-out so
                  // the router never sees authenticated + !onboarded → /onboarding.
                  try {
                    await SupabaseService.instance.client.auth
                        .signOut(scope: SignOutScope.local);
                  } catch (_) {}
                }
                // Clear all local Hive data after sign-out
                await UserRepository.instance.clearAllData();
                if (mounted) context.go('/sign-in');
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Failed to delete account. Please try again.',
                        style: GoogleFonts.getFont('DM Sans', fontSize: 13),
                      ),
                      backgroundColor: AppColors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
            ),
            child: Text(
              'Delete',
              style: GoogleFonts.getFont(
                'DM Sans',
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatGoal(String goal) {
    switch (goal) {
      case 'build_muscle':
        return 'Building Muscle';
      case 'lose_fat':
        return 'Losing Fat';
      case 'general_fitness':
        return 'General Fitness';
      case 'strength':
        return 'Building Strength';
      default:
        return goal.isNotEmpty
            ? goal[0].toUpperCase() +
                goal.substring(1).replaceAll('_', ' ')
            : 'Building Foundation';
    }
  }

}

