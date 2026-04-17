import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:icanbefitter/core/services/prediction_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import 'package:icanbefitter/shared/widgets/sync_banner.dart';
import 'package:icanbefitter/core/services/usage_counter_service.dart';
import 'package:icanbefitter/core/utils/bmr_calculator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:icanbefitter/features/nutrition/providers/nutrition_provider.dart';
import 'package:icanbefitter/features/home/providers/home_provider.dart';
import 'package:icanbefitter/features/ai_coach/providers/ai_coach_provider.dart';
import 'package:icanbefitter/features/ai_coach/widgets/prediction_card.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_identity.dart';
import '../widgets/profile_row.dart';
import '../widgets/section_header.dart';
import '../widgets/slim_achievements_card.dart';
import '../widgets/profile_completeness_card.dart';
import '../widgets/biometric_sync_card.dart';
import '../widgets/weekly_report_card.dart';
import 'notification_settings_screen.dart';
import 'package:icanbefitter/shared/widgets/community_review_sheet.dart';

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

  // Bug #14 — Prediction polling moved from home_screen.dart. The Future
  // Prediction card now lives in profile, so the fire-and-forget post-
  // onboarding generation needs a poller here to render the result once
  // it lands in Hive.
  Timer? _predictionPollTimer;
  int _predictionPollCount = 0;
  static const int _maxPredictionPollAttempts = 10; // 3s × 10 = 30s

  @override
  void initState() {
    super.initState();
    _isMetric = UserRepository.instance.getUnitsMetric();
    _notifPrefs = _loadNotificationPreferences();
    Future.microtask(() {
      if (mounted) setState(() => _isLoading = false);
      _startPredictionPollIfNeeded();
    });
  }

  @override
  void dispose() {
    _predictionPollTimer?.cancel();
    super.dispose();
  }

  /// Polls Hive every 3 seconds (up to 30s) until a prediction is found.
  /// Once found, invalidates [predictionProvider] so the card renders.
  void _startPredictionPollIfNeeded() {
    final existing = HiveService.instance.configBox.get('prediction_text');
    if (existing != null) return;
    _predictionPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _predictionPollCount++;
      final found = HiveService.instance.configBox.get('prediction_text');
      if (found != null) {
        if (mounted) ref.invalidate(predictionProvider);
        timer.cancel();
        _predictionPollTimer = null;
      } else if (_predictionPollCount >= _maxPredictionPollAttempts) {
        timer.cancel();
        _predictionPollTimer = null;
      }
    });
  }

  /// PRO monthly prediction refresh — calls AI via the prediction route
  /// (bypasses daily limits + interaction logging). Moved from home_screen.dart.
  /// Now delegates to PredictionService for shared logic.
  Future<void> _refreshPrediction() async {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Generating fresh prediction...',
        style: GoogleFonts.getFont('DM Sans', fontSize: 13),
      ),
      backgroundColor: AppColors.card,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 10),
    ));

    final success =
        await PredictionService.instance.regeneratePrediction();

    if (mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (success) {
        ref.invalidate(predictionProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Prediction updated!',
            style: GoogleFonts.getFont('DM Sans',
                fontSize: 13, fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Could not refresh prediction. Please try again later.',
            style: GoogleFonts.getFont('DM Sans', fontSize: 13),
          ),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
    }
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

  static String _monthName(int m) => const ['', 'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][m];

  String? _addCacheBuster(String? url) {
    if (url == null || url.isEmpty) return null;
    final ts = DateTime.now().millisecondsSinceEpoch;
    return url.contains('?') ? '$url&t=$ts' : '$url?t=$ts';
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
    final bodyFatPct = (profile['body_fat_percent'] as num?)?.toDouble();
    final dob = profile['date_of_birth'] as String?;

    final experience = profile['fitness_experience'] as String? ?? '';
    final expLabel = experience.isNotEmpty
        ? ' \u00B7 ${experience[0].toUpperCase()}${experience.substring(1)}'
        : '';
    final subtitle =
        'Phase ${stats.currentPhase} \u00B7 Week ${stats.currentWeek} \u00B7 ${_formatGoal(stats.primaryGoal)}$expLabel';

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
      final bodyFat = (profile['body_fat_percent'] as num?)?.toDouble();
      final t = BmrCalculator.calculateTargets(
        weightKg: weightKg,
        heightCm: heightCm,
        age: age,
        gender: gender,
        activityLevel: profile['activity_level'] as String? ?? 'moderate',
        goal: stats.primaryGoal,
        pacePreference: (profile['pace_preference'] as String?) ?? 'balanced',
        bodyFatPercent: bodyFat,
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
      body: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          const SyncBanner(),
          Expanded(
            child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Safe area
              const SizedBox(height: 10),

              // 1. Profile identity with banner + avatar
              ProfileIdentity(
                name: name,
                subtitle: subtitle,
                avatarUrl: _addCacheBuster(profile['avatar_url'] as String?),
                bannerUrl: _addCacheBuster(profile['banner_url'] as String?),
                onReplaceAvatar: () async {
                  final outcome = await ref.read(userProfileProvider.notifier).uploadAvatar();
                  if (!context.mounted) return;
                  ref.invalidate(userProfileProvider);
                  if (outcome.result == UploadResult.cancelled) {
                    debugPrint('[ProfileScreen] Avatar upload cancelled: ${outcome.errorMessage}');
                    if (outcome.errorMessage != null && outcome.errorMessage!.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(outcome.errorMessage!, style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
                        backgroundColor: AppColors.card,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 3),
                      ));
                    }
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      outcome.result == UploadResult.success
                          ? 'Profile photo updated'
                          : 'Upload failed: ${outcome.errorMessage ?? "Unknown error"}',
                      style: GoogleFonts.getFont('DM Sans', fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: outcome.result == UploadResult.success
                        ? const Color(0xFF1a2a1a)
                        : const Color(0xFF2a1a1a),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                onReplaceBanner: () async {
                  final outcome = await ref.read(userProfileProvider.notifier).uploadBanner();
                  if (!context.mounted) return;
                  ref.invalidate(userProfileProvider);
                  if (outcome.result == UploadResult.cancelled) {
                    debugPrint('[ProfileScreen] Banner upload cancelled: ${outcome.errorMessage}');
                    if (outcome.errorMessage != null && outcome.errorMessage!.isNotEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(outcome.errorMessage!, style: GoogleFonts.getFont('DM Sans', fontSize: 13)),
                        backgroundColor: AppColors.card,
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 3),
                      ));
                    }
                    return;
                  }
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(
                      outcome.result == UploadResult.success
                          ? 'Banner updated'
                          : 'Upload failed: ${outcome.errorMessage ?? "Unknown error"}',
                      style: GoogleFonts.getFont('DM Sans', fontSize: 13, fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: outcome.result == UploadResult.success
                        ? const Color(0xFF1a2a1a)
                        : const Color(0xFF2a1a1a),
                    behavior: SnackBarBehavior.floating,
                  ));
                },
                onTapEdit: () => context.go('/profile/edit'),
                isPro: isPro,
                onTapPremium: () {
                  // Bug #14 — PRO users see subscription detail; free users
                  // get the paywall sheet. Subscription detail reuses the
                  // existing _buildSubscriptionSection inside a bottom sheet
                  // so we don't have to maintain two upgrade surfaces.
                  if (isPro) {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: AppColors.card,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(22)),
                      ),
                      builder: (_) => SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: AppColors.border,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSubscriptionSection(
                                  subInfo, isPro, usageService),
                            ],
                          ),
                        ),
                      ),
                    );
                  } else {
                    showPaywallSheet(context, feature: 'PRO Upgrade');
                  }
                },
              ),
              const SizedBox(height: 8),

              // Profile completeness (shows until 100%)
              const ProfileCompletenessCard(),
              const SizedBox(height: 8),

              // #2 Daily Completion summary
              _buildDailyCompletion(stats),
              const SizedBox(height: 8),

              // Slim single-row achievements card (after Daily Completion)
              const SlimAchievementsCard(),
              const SizedBox(height: 8),

              // #3 Body Stats card
              _buildBodyStats(weightKg, targetKg, bmi, bodyFatPct),
              const SizedBox(height: 8),

              // #4 Journey timeline — pass profile data to avoid
              // duplicate UserRepository reads (single source of truth).
              _buildJourneyTimeline(
                stats,
                currentWeightKg: weightKg,
                targetWeightKg: targetKg,
                goal: stats.primaryGoal,
              ),
              const SizedBox(height: 8),

              // #8 Nutrition Targets
              if (nutritionTargets != null) ...[
                _buildNutritionTargets(
                  nutritionTargets,
                  currentKg: weightKg,
                  targetKg: targetKg,
                  goal: stats.primaryGoal,
                  pacePreference: profile['pace_preference'] is String
                      ? profile['pace_preference'] as String
                      : 'balanced',
                ),
                const SizedBox(height: 8),
              ],

              // Bug #14 — Future Prediction (moved from home dashboard).
              const SectionHeader('YOUR PREDICTION'),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding),
                child: _buildPredictionCard(),
              ),
              const SizedBox(height: 8),

              // Bug #14 — Reports now sit directly after prediction (plan order:
              // prediction → reports → health sync → share & grow → settings).
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
                    // Invalidate home screen step provider so it re-reads
                    // the freshly synced Hive data immediately.
                    ref.invalidate(todayStepsProvider);
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

              // #4b Invite Friends (referral)
              const SectionHeader('SHARE & GROW'),
              _buildCard([
                ProfileRow(
                  icon: Icons.card_giftcard,
                  title: 'Invite Friends',
                  subtitle: 'Both get 7 days PRO free',
                  trailing: const ProfileRowChevron(),
                  onTap: () => _showInviteFriends(),
                ),
                ProfileRow(
                  icon: Icons.rate_review_outlined,
                  title: 'Review Community Items',
                  subtitle: 'Approve foods & exercises from users',
                  trailing: const ProfileRowChevron(),
                  onTap: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => const CommunityReviewSheet(),
                  ),
                ),
                // F9 — user-visible status of their own submissions
                ProfileRow(
                  icon: Icons.workspace_premium_outlined,
                  title: 'My Submissions',
                  subtitle: 'Track approval status of foods & exercises you shared',
                  trailing: const ProfileRowChevron(),
                  // F19 — progress photos entry (PRO-gated at tap time)
                  showBorder: true,
                  onTap: () => context.go('/profile/my-submissions'),
                ),
                ProfileRow(
                  icon: Icons.photo_library_outlined,
                  title: 'Progress Photos',
                  subtitle: subInfo.isPro
                      ? 'Track your transformation visually'
                      : 'PRO \u2014 visual progress timeline',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => SubscriptionService.instance.gate(
                    AppConstants.featureProgressPhotos,
                    onPro: () => context.go('/profile/progress-photos'),
                    onFree: () =>
                        showPaywallSheet(context, feature: 'Progress Photos'),
                  ),
                ),
              ]),
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

              // Bug #14 — Subscription moved to the bottom (full upsell banner
              // in the closing-pitch position). Premium pill at the top is the
              // primary discoverability surface; this card is the closer.
              const SectionHeader('SUBSCRIPTION'),
              _buildSubscriptionSection(subInfo, isPro, usageService),
              const SizedBox(height: 8),

              // Bug #21 — Achievements are now rendered as the compact inline
              // row inside ProfileIdentity. Full grid opens via its chevron.

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
          ),
        ],
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

  Widget _buildJourneyTimeline(
    UserStatsData stats, {
    required double? currentWeightKg,
    required double? targetWeightKg,
    required String goal,
  }) {
    // Phase data
    const phaseNames = [
      'Foundation', 'Building', 'Progression', 'Strength',
      'Endurance', 'Power', 'Conditioning', 'Peak',
      'Mastery', 'Elite', 'Champion', 'Legend',
    ];
    final phaseName = stats.currentPhase <= phaseNames.length
        ? phaseNames[stats.currentPhase - 1]
        : 'Phase ${stats.currentPhase}';

    // Goal insights — sourced from userProfileProvider (single source of truth)
    final currentWeight = currentWeightKg ?? 0;
    final targetWeight = targetWeightKg ?? 0;

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

  // ── Bug #14 Prediction Card (moved from home_screen) ────────────

  Widget _buildPredictionCard() {
    final prediction = ref.watch(predictionProvider);
    final isPro = SubscriptionService.instance.isPro();
    return PredictionCard(
      predictionText: prediction.predictionText,
      generatedAt: prediction.generatedAt,
      isPro: isPro,
      canRefresh: prediction.canRefresh,
      isStale: prediction.isStale,
      onRefreshTap: isPro
          ? _refreshPrediction
          : () {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                  'Prediction refresh is a PRO feature. Upgrade in Profile \u2192 Subscription',
                  style: GoogleFonts.getFont('DM Sans', fontSize: 13),
                ),
                backgroundColor: AppColors.proGold,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ));
            },
    );
  }

  // ── #7 Subscription Section ─────────────────────────────────────

  Widget _buildSubscriptionSection(SubscriptionInfoData subInfo, bool isPro, UsageCounterService usage) {
    if (isPro) {
      // Simple PRO card with expiry
      final expiryStr = subInfo.expiresAt != null
          ? '${subInfo.expiresAt!.day} ${_monthName(subInfo.expiresAt!.month)} ${subInfo.expiresAt!.year}'
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
    final scanLimit = AppConstants.freeScanMealPerDay;
    final cartUsed = usage.used(AppConstants.featureCartAuditorPro, false);
    final cartLimit = AppConstants.freeCartAuditorPerDay;

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
          _usageRow('Meal Scans', scanUsed, scanLimit, '/day'),
          const SizedBox(height: 6),
          _usageRow('Cart Auditor', cartUsed, cartLimit, '/day'),
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

  // ── #8 Nutrition Targets (Bug #24: + projection subtitle) ──────

  Widget _buildNutritionTargets(
    Map<String, double> targets, {
    double? currentKg,
    double? targetKg,
    required String goal,
    required String pacePreference,
  }) {
    // Bug #24 — compute projection only when we have a real target delta
    // and a non-maintenance goal. Otherwise hide the subtitle entirely.
    String? projectionLine;
    if ((goal == 'lose_fat' || goal == 'build_muscle') &&
        currentKg != null &&
        targetKg != null &&
        (currentKg - targetKg).abs() > 0.1) {
      final p = BmrCalculator.projectGoalDate(
        currentKg: currentKg,
        targetKg: targetKg,
        pacePreference: pacePreference,
      );
      if (p.weeks > 104) {
        projectionLine =
            "At this pace, you'll reach ${targetKg.toStringAsFixed(0)} kg in >2 years";
      } else if (p.weeks > 0) {
        final dateStr = '${_monthAbbr(p.date.month)} ${p.date.day}';
        projectionLine =
            "At this pace, you'll reach ${targetKg.toStringAsFixed(0)} kg on $dateStr (~${p.weeks.round()} weeks)";
      }
    }

    return GestureDetector(
      onTap: projectionLine == null
          ? null
          : () => _showPaceDetailSheet(
                currentKg: currentKg!,
                targetKg: targetKg!,
                pacePreference: pacePreference,
                goal: goal,
              ),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
            if (projectionLine != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      projectionLine,
                      style: GoogleFonts.getFont('DM Sans',
                          fontSize: 11, fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right,
                      size: 14,
                      color: AppColors.textSecondary.withValues(alpha: 0.7)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _monthAbbr(int m) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return months[(m - 1).clamp(0, 11)];
  }

  Future<void> _showPaceDetailSheet({
    required double currentKg,
    required double targetKg,
    required String pacePreference,
    required String goal,
  }) async {
    final p = BmrCalculator.projectGoalDate(
      currentKg: currentKg,
      targetKg: targetKg,
      pacePreference: pacePreference,
    );
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('GOAL PROJECTION',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 1.0, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              Text(
                  'Current: ${currentKg.toStringAsFixed(1)} kg → Target: ${targetKg.toStringAsFixed(1)} kg',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Pace: ${pacePreference.toUpperCase()}',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accent)),
              const SizedBox(height: 12),
              Text('At this pace, projected ~${p.weeks.round()} weeks to goal.',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textSecondary)),
              const SizedBox(height: 4),
              Text(
                  'Based on ${_paceRateLabel(pacePreference)} body-weight change per week and 7700 kcal ≈ 1 kg.',
                  style: GoogleFonts.getFont('DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w400,
                      color: AppColors.textDisabled)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.go('/profile/edit');
                  },
                  child: Text('Change pace →',
                      style: GoogleFonts.getFont('DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.accent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _paceRateLabel(String pace) {
    switch (pace) {
      case 'slow':
        return '0.25%';
      case 'aggressive':
        return '0.75%';
      case 'balanced':
      default:
        return '0.5%';
    }
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
    // Write to a temp file to avoid OOM on large exports
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/avya_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(jsonStr);
    await Share.shareXFiles([XFile(file.path)], subject: 'AVYA Fit Data Export');
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
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _launchUrl('https://icanbefitter.vercel.app/privacy'),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new, size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text('Read our Privacy Policy', style: GoogleFonts.getFont('DM Sans', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _launchUrl('https://icanbefitter.vercel.app/terms'),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new, size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text('Terms of Service', style: GoogleFonts.getFont('DM Sans', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent)),
                ],
              ),
            ),
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

  void _launchUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Future<void> _showInviteFriends() async {
    String? referralCode;
    try {
      referralCode = await SupabaseService.instance.getOrCreateReferralCode();
    } catch (e) {
      debugPrint('[ProfileScreen._showInviteFriends] $e');
    }

    if (referralCode == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate referral code', style: GoogleFonts.getFont('DM Sans', fontSize: 13)), backgroundColor: AppColors.red),
        );
      }
      return;
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Invite Friends',
                style: GoogleFonts.getFont('DM Sans', fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 8),
              Text(
                'Share your code with friends. When they sign up, both of you get 7 days of PRO free!',
                textAlign: TextAlign.center,
                style: GoogleFonts.getFont('DM Sans', fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 20),
              // Code display
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      referralCode!,
                      style: GoogleFonts.getFont('DM Sans', fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.accent, letterSpacing: 1.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Share button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Share.share(
                      'Join me on AVYA Fit! Use my referral code $referralCode to get 7 days of PRO free. Download: https://icanbefitter.vercel.app',
                      subject: 'AVYA Fit Referral',
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
                  ),
                  child: Text(
                    'Share My Code',
                    style: GoogleFonts.getFont('DM Sans', fontSize: 15, fontWeight: FontWeight.w900, color: Colors.black),
                  ),
                ),
              ),
            ],
          ),
        ),
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
    } catch (e) {
      debugPrint('[ProfileScreen._performSignOut] global signOut: $e');
      try {
        await SupabaseService.instance.client.auth
            .signOut(scope: SignOutScope.local);
      } catch (e) {
        debugPrint('[ProfileScreen._performSignOut] local signOut: $e');
      }
    }

    // 2. Wipe all user-specific Hive boxes after session is gone.
    try {
      await UserRepository.instance.clearAllData();
    } catch (e) {
      debugPrint('[ProfileScreen._performSignOut] clearAllData: $e');
    }

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
                } catch (e) {
                  // Offline or server error — force a local-only sign-out so
                  // the router never sees authenticated + !onboarded → /onboarding.
                  debugPrint('[ProfileScreen._deleteAccount] global signOut: $e');
                  try {
                    await SupabaseService.instance.client.auth
                        .signOut(scope: SignOutScope.local);
                  } catch (e) {
                    debugPrint('[ProfileScreen._deleteAccount] local signOut: $e');
                  }
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

