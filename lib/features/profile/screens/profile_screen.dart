import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
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
import '../providers/referral_eligibility_provider.dart';
import '../screens/apply_referral_sheet.dart';
import '../widgets/profile_identity.dart';
import '../widgets/profile_row.dart';
import '../widgets/section_header.dart';
import '../widgets/slim_achievements_card.dart';
import '../widgets/profile_completeness_card.dart';
import '../widgets/biometric_sync_card.dart';
import '../widgets/weekly_report_card.dart';
import '../screens/invite_friends_sheet.dart';

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

  /// "EST" seal date for the PRO subscription card corner — shows when
  /// the user became a member. SubscriptionInfoData carries `expiresAt`
  /// but no dedicated `startedAt`, so we back-compute from plan duration
  /// (annual = 365d, monthly = 30d). DD/MM/YY format matches the
  /// Wardroom handoff brand motif (see welcome.jsx `EST · 2026`).
  static String _estSealDate(SubscriptionInfoData subInfo) {
    if (subInfo.expiresAt == null) {
      final now = DateTime.now();
      return _ddMmYy(now);
    }
    final planDays = (subInfo.plan?.toLowerCase() == 'yearly' ||
            subInfo.plan?.toLowerCase() == 'annual')
        ? 365
        : 30;
    final startedAt =
        subInfo.expiresAt!.subtract(Duration(days: planDays));
    return _ddMmYy(startedAt);
  }

  static String _ddMmYy(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yy = (d.year % 100).toString().padLeft(2, '0');
    return '$dd/$mm/$yy';
  }

  /// PRO-card "MANAGE SUBSCRIPTION →" tap target. No self-service
  /// cancel/upgrade flow exists in-app yet (Razorpay subscriptions are
  /// managed out-of-band via support), so show a bottom sheet with the
  /// support contact. Wire a richer flow later via a dedicated PR if
  /// self-service becomes a priority.
  void _onManageSubscription() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MANAGE SUBSCRIPTION',
                style: AppTypography.mono.copyWith(
                  fontSize: 10,
                  color: AppColors.accent,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Your PRO subscription is handled by Razorpay and '
                'auto-renews by default. To cancel, change plans, or '
                'request a refund, reach out to us and we\'ll sort it '
                'within 24 hours.',
                style: AppTypography.body.copyWith(
                  color: AppColors.textDim,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgDeep,
                  border: Border.all(color: AppColors.line2),
                  borderRadius: BorderRadius.circular(AppRadius.sharp),
                ),
                child: Row(
                  children: [
                    Icon(Icons.mail_outline,
                        size: 16, color: AppColors.accent),
                    const SizedBox(width: 10),
                    Text(
                      'support@avya.app',
                      style: AppTypography.body.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Text(
                    'GOT IT',
                    style: AppTypography.mono.copyWith(
                      fontSize: 11,
                      color: AppColors.bgDeep,
                      letterSpacing: 2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

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
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final targetKg = (profile['target_weight_kg'] as num?)?.toDouble();
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final bodyFatPct = (profile['body_fat_percent'] as num?)?.toDouble();

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
    //
    // Source of truth (CLAUDE.md §15): `macroTargetsProvider` is the ONE
    // reader for BMR / TDEE / calories / P / C / F across Home, Nutrition,
    // and Profile. It prefers the stored targets in the Hive profile map
    // (written at onboarding and on every Edit Profile save) and falls
    // back to `BmrCalculator.calculateTargets` only when they're missing.
    //
    // Profile used to call BmrCalculator directly here, which diverged
    // from Home/Nutrition whenever `activity_level` was stale or defaulted
    // to 'moderate' — observed 2026-04-17 with icanbefitter@gmail.com.
    final macros = ref.watch(macroTargetsProvider);
    final Map<String, double>? nutritionTargets = (macros['calories'] ?? 0) > 0
        ? {
            'tdee': macros['tdee'] ?? 0,
            'calories': macros['calories'] ?? 0,
            'protein': macros['protein'] ?? 0,
          }
        : null;

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
              // Wardroom letterhead — mono eyebrow + Fraunces title above identity card
              const WardLetterhead(
                eyebrow: 'OFFICER \u00B7 DOSSIER',
                title: 'Profile',
                padding: EdgeInsets.fromLTRB(22, 14, 22, 12),
                divider: true,
              ),
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

              // AT A GLANCE — combined Journey + Body Stats + My Targets.
              //
              // Previously rendered as three separate cards with
              // `SizedBox(height: 8)` gaps between them. User feedback
              // 2026-04-18 asked to collapse them into a single visual
              // group (less vertical space). Order: Journey → Body Stats
              // → My Targets. Each card keeps its own styling; the gaps
              // between them collapse to zero so the trio reads as one
              // block in the scroll.
              _buildJourneyTimeline(
                stats,
                currentWeightKg: weightKg,
                targetWeightKg: targetKg,
                goal: stats.primaryGoal,
              ),
              _buildBodyStats(weightKg, targetKg, bmi, bodyFatPct),
              if (nutritionTargets != null)
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

              // Bug #14 — Future Prediction (moved from home dashboard).
              const SectionHeader('YOUR PREDICTION'),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.screenPadding),
                child: _buildPredictionCard(),
              ),
              const SizedBox(height: 8),

              // Reports now hosts BOTH the weekly AI report AND progress
              // photos (moved here from SHARE & GROW per 2026-04-18 user
              // feedback). Progress Photos is still PRO-gated at tap.
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
              const SizedBox(height: 6),
              _buildCard([
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

              // #4b Invite Friends (referral)
              //
              // Progress Photos moved up to REPORTS. Health Sync row added
              // into SETTINGS (see below) — its standalone section was
              // removed.
              const SectionHeader('SHARE & GROW'),
              _buildCard([
                // Q4: Apply Referral Code — visible only within 7-day signup
                // window AND when the user hasn't redeemed a referral yet.
                // Tap opens ApplyReferralSheet; on success the provider is
                // invalidated so the tile disappears automatically.
                ...ref.watch(referralEligibilityProvider).when(
                  data: (state) {
                    if (!state.isEligible) return const <Widget>[];
                    return <Widget>[
                      ProfileRow(
                        icon: Icons.card_giftcard_outlined,
                        iconBgColor: AppColors.accentSoft,
                        iconColor: AppColors.accent,
                        title: 'Apply Referral Code',
                        subtitle: '7 days of PRO when you apply a code',
                        titleSuffix: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.accentSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${state.daysRemaining}D LEFT',
                            style: AppTypography.monoXs.copyWith(
                              letterSpacing: 0.8,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        trailing: const ProfileRowChevron(),
                        onTap: () async {
                          final ok = await ApplyReferralSheet.show(context);
                          if (ok == true && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '7 days of PRO unlocked!',
                                  style: AppTypography.body.copyWith(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                backgroundColor: AppColors.card,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                            ref.invalidate(referralEligibilityProvider);
                          }
                        },
                      ),
                    ];
                  },
                  loading: () => const <Widget>[],
                  error: (e, st) => const <Widget>[],
                ),
                ProfileRow(
                  icon: Icons.card_giftcard,
                  title: 'Invite Friends',
                  subtitle: 'Both get 7 days PRO free',
                  trailing: const ProfileRowChevron(),
                  onTap: () => InviteFriendsSheet.show(context),
                ),
                // S1 (2026-04-24) — the pre-APK-1-batch split of
                // "Review Community Items" (bottom sheet) and
                // "My Submissions" (screen) confused testers who kept
                // tapping one expecting the other. Collapsed into a
                // single Submissions row that opens a tabbed screen
                // with both views.
                ProfileRow(
                  icon: Icons.workspace_premium_outlined,
                  title: 'Submissions',
                  subtitle: 'Your submissions + vote on community items',
                  trailing: const ProfileRowChevron(),
                  onTap: () => context.go('/profile/submissions'),
                ),
                // AH.7 — Rate App tile completes the SHARE & GROW block
                // (JSX spec lines 331–338 + user ask for explicit Rate App
                // row). Launches the Play Store listing via externalApplication
                // so the Play Store app intercepts on-device; users without
                // it land on the web listing.
                ProfileRow(
                  icon: Icons.star_outline,
                  title: 'Rate App',
                  subtitle: 'Tell the Play Store what you think',
                  trailing: const ProfileRowChevron(),
                  showBorder: false,
                  onTap: () => _launchUrl(
                    'https://play.google.com/store/apps/details?id=com.icanbefitter.icanbefitter',
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
                  onTap: () => context.push(
                    '/profile/notification-settings',
                    extra: {
                      'notifPrefs': _notifPrefs,
                      'isPro': subInfo.isPro,
                      'onSave': (Map<String, dynamic> prefs) {
                        setState(() => _notifPrefs = prefs);
                        _saveNotificationPreferences();
                      },
                    },
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
                // Health Sync moved here from its own top-level section
                // (2026-04-18 user feedback). Tap opens a sheet with the
                // full BiometricSyncCard (steps / sleep / toggle / manual
                // sleep log). Keeping the rich widget live instead of
                // re-implementing it as individual rows.
                ProfileRow(
                  icon: Icons.favorite_outline,
                  title: 'Health Sync',
                  subtitle: _buildHealthSyncSubtitle(biometric),
                  trailing: const ProfileRowChevron(),
                  onTap: () => _showHealthSyncSheet(biometric),
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

              // Sign Out — sharp 2-px bad-tinted slab
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                child: WardButton(
                  label: 'Sign Out',
                  variant: WardButtonVariant.danger,
                  onPressed: () => _showSignOutDialog(),
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

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Progress ring
          SizedBox(
            width: 40,
            height: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: done / 4,
                  strokeWidth: 4,
                  backgroundColor: AppColors.bgRaise,
                  valueColor: AlwaysStoppedAnimation(
                      done == 4 ? AppColors.ok : AppColors.accent),
                ),
                Text(
                  '$done/4',
                  style: AppTypography.monoXs.copyWith(
                    color: done == 4 ? AppColors.ok : AppColors.accent,
                    letterSpacing: 0.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DAILY GOALS',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 6),
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
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: done ? AppColors.ok : AppColors.bgRaise,
            shape: BoxShape.circle,
            border: Border.all(
              color: done ? AppColors.ok : AppColors.line2,
              width: 1,
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label.toUpperCase(),
          style: AppTypography.monoXs.copyWith(
            color: done ? AppColors.ok : AppColors.textMute,
            letterSpacing: 1.5,
          ),
        ),
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

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'BODY STATS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => context.go('/profile/edit'),
                child: Text(
                  'EDIT',
                  style: AppTypography.monoXs.copyWith(
                    color: AppColors.accent,
                    letterSpacing: 2.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statCell('Weight', fmtWeight(weight), AppColors.accent),
              _statCell('Target', fmtWeight(target), AppColors.ok),
              _statCell('BMI', bmi != null ? bmi.toStringAsFixed(1) : '\u2014', AppColors.info),
              _statCell('Body Fat', bodyFat != null ? '${bodyFat.toStringAsFixed(0)}%' : '\u2014', AppColors.warn),
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
          Text(
            value,
            style: AppTypography.h3.copyWith(
              color: color,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label.toUpperCase(),
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.5,
            ),
          ),
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

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'YOUR JOURNEY',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const Spacer(),
              Text(
                'WEEK ${stats.currentWeek} OF 4',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Phase name — Fraunces
          Text(
            'Phase ${stats.currentPhase} \u2014 $phaseName',
            style: AppTypography.h3.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          // Week progress bar within phase
          WardBar(pct: stats.currentWeek / 4.0, color: AppColors.accent, height: 4),
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
                        ? AppColors.ok
                        : isCurrent
                            ? AppColors.accent
                            : stats.isPro || phase == 0
                                ? AppColors.bgRaise
                                : AppColors.bgRaise.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
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
              color: AppColors.ok,
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
              color: AppColors.textDim,
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
              style: AppTypography.bodySm.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
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
      // PRO dossier — matches the Wardroom handoff spec
      // (`design_handoff_wardroom/src/screens/profile.jsx` block 13,
      // lines 360–391): gradient accentSoft→bgDeep card with a Seal
      // badge in the top-right corner, PRO chip + plan tag on top,
      // "Everything unlocked" Fraunces hero line, renewal mono line,
      // and a dashed-divider + MANAGE SUBSCRIPTION → CTA below.
      final expiryStr = subInfo.expiresAt != null
          ? '${subInfo.expiresAt!.day} ${_monthName(subInfo.expiresAt!.month)} ${subInfo.expiresAt!.year}'
          : '\u2014';
      final planLabel = (subInfo.plan ?? 'monthly').toUpperCase();
      // "EST" seal carries the member-since date — the Wardroom brand
      // motif mirrors the welcome screen's "EST · 2026" + the founder
      // seal. Compute from expiresAt minus plan duration (best-effort;
      // no dedicated startedAt field exists on SubscriptionInfoData).
      final sealDate = _estSealDate(subInfo);
      return Container(
        margin: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.accentSoft,
              AppColors.bgDeep,
            ],
          ),
          border: Border.all(
            color: AppColors.accent.withValues(alpha: 0.40),
          ),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Reserve space on the right so content doesn't
                    // slide under the corner seal.
                    Padding(
                      padding: const EdgeInsets.only(right: 56),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const WardChip(
                                label: 'PRO',
                                tone: WardChipTone.gold,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                planLabel,
                                style: AppTypography.monoXs.copyWith(
                                  fontSize: 9,
                                  color: AppColors.accent,
                                  letterSpacing: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Everything unlocked',
                            style: AppTypography.h3.copyWith(
                              fontSize: 18,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'RENEWS $expiryStr'.toUpperCase(),
                            style: AppTypography.mono.copyWith(
                              fontSize: 10,
                              color: AppColors.textDim,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Dashed divider + MANAGE CTA (full width — past the
                    // reserved padding so it stretches across).
                    const SizedBox(height: 12),
                    WardDashedBorder(
                      color: AppColors.line2,
                      strokeWidth: 1,
                      dashLength: 3,
                      gapLength: 3,
                      radius: 0,
                      child: const SizedBox(
                        width: double.infinity,
                        height: 0.5,
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: _onManageSubscription,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Text(
                            'MANAGE SUBSCRIPTION \u2192',
                            style: AppTypography.mono.copyWith(
                              fontSize: 9,
                              color: AppColors.accent,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Corner seal — JSX spec uses size 48; the Wardroom
              // WardSealBadge.subscription variant defaults to 54 for
              // consistency with the report + phase placements.
              Positioned(
                top: 10,
                right: 10,
                child: WardSealBadge(
                  label: 'EST',
                  subline: sealDate,
                  variant: WardSealVariant.subscription,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Free user — rate-limit meters with trial pill.
    final aiTextUsed = usage.used(AppConstants.featureAiTextLogPro, false);
    final aiTextLimit = AppConstants.freeAiTextLogsPerDay;
    final scanUsed = usage.used(AppConstants.featureScanMealPro, false);
    final scanLimit = AppConstants.freeScanMealPerDay;
    final cartUsed = usage.used(AppConstants.featureCartAuditorPro, false);
    final cartLimit = AppConstants.freeCartAuditorPerDay;

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

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('FREE PLAN',
                  style: AppTypography.mono.copyWith(
                    color: AppColors.textMute,
                    letterSpacing: 2.0,
                  )),
              const Spacer(),
              GestureDetector(
                onTap: () => showPaywallSheet(context, feature: 'PRO'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.circular(AppRadius.sharp),
                  ),
                  child: Text('UPGRADE',
                      style: AppTypography.monoXs.copyWith(
                        color: Colors.black,
                        letterSpacing: 2.0,
                        fontWeight: FontWeight.w700,
                      )),
                ),
              ),
            ],
          ),
          if (trialDaysLeft != null) ...[
            const SizedBox(height: 10),
            WardChip(
              label: trialDaysLeft > 0
                  ? '${trialDaysLeft}d AI trial remaining'
                  : 'AI trial expired',
              tone: trialDaysLeft > 7 ? WardChipTone.gold : WardChipTone.warn,
              leading: Icon(
                Icons.timer_outlined,
                size: 11,
                color: trialDaysLeft > 7 ? AppColors.accent : AppColors.warn,
              ),
            ),
          ],
          const SizedBox(height: 12),
          _usageRow('AI Text Logs', aiTextUsed, aiTextLimit, '/day'),
          const SizedBox(height: 8),
          _usageRow('Meal Scans', scanUsed, scanLimit, '/day'),
          const SizedBox(height: 8),
          _usageRow('Cart Auditor', cartUsed, cartLimit, '/day'),
        ],
      ),
    );
  }

  Widget _usageRow(String label, int used, int limit, String period) {
    final pct = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final isExhausted = used >= limit;
    final meterColor = isExhausted ? AppColors.bad : AppColors.accent;
    final readoutColor = isExhausted ? AppColors.bad : AppColors.textDim;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 92,
          child: Text(label.toUpperCase(),
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 1.6,
              )),
        ),
        Expanded(child: WardBar(pct: pct, color: meterColor, height: 4)),
        const SizedBox(width: 10),
        Text('$used/$limit$period',
            style: AppTypography.monoXs.copyWith(color: readoutColor)),
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

    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      onTap: projectionLine == null
          ? null
          : () => _showPaceDetailSheet(
                currentKg: currentKg!,
                targetKg: targetKg!,
                pacePreference: pacePreference,
                goal: goal,
              ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'MY TARGETS',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
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
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.textDim,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right,
                    size: 14, color: AppColors.textMute),
              ],
            ),
          ],
        ],
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'GOAL PROJECTION',
                style: AppTypography.mono.copyWith(
                  color: AppColors.textMute,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Current: ${currentKg.toStringAsFixed(1)} kg → Target: ${targetKg.toStringAsFixed(1)} kg',
                style: AppTypography.h3
                    .copyWith(fontSize: 14, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 4),
              Text(
                'Pace: ${pacePreference.toUpperCase()}',
                style: AppTypography.monoXs.copyWith(
                  color: AppColors.accent,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'At this pace, projected ~${p.weeks.round()} weeks to goal.',
                style: AppTypography.body.copyWith(color: AppColors.textDim),
              ),
              const SizedBox(height: 4),
              Text(
                'Based on ${_paceRateLabel(pacePreference)} body-weight change per week and 7700 kcal ≈ 1 kg.',
                style: AppTypography.bodySm.copyWith(color: AppColors.textGhost),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    context.go('/profile/edit');
                  },
                  child: Text(
                    'CHANGE PACE →',
                    style: AppTypography.monoXs.copyWith(
                      color: AppColors.accent,
                      letterSpacing: 2.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
          Text(
            value,
            style: AppTypography.h3.copyWith(
              fontSize: 13,
              color: AppColors.accent,
              height: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: AppTypography.monoXs.copyWith(
              color: AppColors.textMute,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── #9 Danger Zone ──────────────────────────────────────────────

  Widget _buildDangerZone() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          'DANGER ZONE',
          style: AppTypography.mono.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
          ),
        ),
        iconColor: AppColors.textMute,
        collapsedIconColor: AppColors.textMute,
        children: [
          GestureDetector(
            onTap: () => _showDeleteAccountDialog(),
            child: Text(
              'Delete Account',
              style: AppTypography.bodySm.copyWith(
                color: AppColors.bad,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Health Sync (moved into SETTINGS row, 2026-04-18) ───────────

  /// Concise subtitle rendered next to the Health Sync row in settings.
  /// Collapses the live BiometricSyncCard metrics into one line so the
  /// list stays dense.
  String _buildHealthSyncSubtitle(BiometricData b) {
    if (!b.isSyncEnabled) return 'Connect Google Fit / Health Connect';
    final parts = <String>[];
    if (b.stepsToday != null) parts.add('${b.stepsToday} steps');
    if (b.sleepHours != null) parts.add('${b.sleepHours!.toStringAsFixed(1)}h sleep');
    return parts.isEmpty ? 'Connected' : parts.join(' \u00B7 ');
  }

  /// Opens the full BiometricSyncCard inside a bottom sheet so the rich
  /// widget (toggle, sleep-log button, live steps/sleep readouts) stays
  /// intact after the reorg.
  void _showHealthSyncSheet(BiometricData b) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom,
        ),
        child: Container(
          margin: const EdgeInsets.all(AppSpacing.screenPadding),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(6),
          child: BiometricSyncCard(
            stepsToday: b.stepsToday,
            sleepHours: b.sleepHours,
            isSyncEnabled: b.isSyncEnabled,
            onToggleSync: () async {
              final newValue = !b.isSyncEnabled;
              ref.read(biometricProvider.notifier).toggleSync(newValue);
              if (newValue && mounted) {
                ref.invalidate(todayStepsProvider);
              }
            },
            onLogSleep: (hours, quality) {
              ref.read(biometricProvider.notifier).logSleep(
                    hours: hours,
                    quality: quality,
                  );
            },
          ),
        ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'Privacy & Permissions',
          style: AppTypography.h3.copyWith(color: AppColors.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your data is stored locally on your device. Supabase is used only for backups, AI, and community features.',
              style: AppTypography.body
                  .copyWith(color: AppColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'PERMISSIONS',
              style: AppTypography.mono.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '\u2022 Camera: Meal scanning\n\u2022 Health Connect: Steps & sleep\n\u2022 Storage: Progress photos',
              style: AppTypography.bodySm
                  .copyWith(color: AppColors.textDim, height: 1.5),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _launchUrl('https://icanbefitter.vercel.app/privacy'),
              child: Row(
                children: [
                  const Icon(Icons.open_in_new, size: 14, color: AppColors.accent),
                  const SizedBox(width: 6),
                  Text(
                    'Read our Privacy Policy',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
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
                  Text(
                    'Terms of Service',
                    style: AppTypography.bodySm.copyWith(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CLOSE',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.accent,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _launchUrl(String url) {
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  /// Wraps children in a Wardroom card.
  Widget _buildCard(List<Widget> children) {
    return WardCard(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: EdgeInsets.zero,
      child: Column(children: children),
    );
  }

  void _showSignOutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: const BorderSide(color: AppColors.line2),
        ),
        title: Text(
          'CONFIRM SIGN OUT',
          style: AppTypography.mono.copyWith(
            color: AppColors.textMute,
            letterSpacing: 2,
          ),
        ),
        content: Text(
          'Are you sure you want to sign out? Your data is safe locally.',
          style: AppTypography.body.copyWith(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCEL',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          WardButton(
            label: 'Sign Out',
            variant: WardButtonVariant.danger,
            fullWidth: false,
            size: WardButtonSize.small,
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _performSignOut();
            },
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
          borderRadius: BorderRadius.circular(AppRadius.card),
          side: BorderSide(color: AppColors.bad.withValues(alpha: 0.3)),
        ),
        title: Text(
          'DELETE ACCOUNT',
          style: AppTypography.mono.copyWith(
            color: AppColors.bad,
            letterSpacing: 2,
          ),
        ),
        content: Text(
          'This will permanently delete your account and all data. This action cannot be undone.',
          style: AppTypography.body.copyWith(color: AppColors.textDim),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'CANCEL',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textMute,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
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
              backgroundColor: AppColors.bad,
              foregroundColor: AppColors.textPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sharp),
              ),
            ),
            child: Text(
              'DELETE',
              style: AppTypography.monoXs.copyWith(
                color: AppColors.textPrimary,
                letterSpacing: 2.5,
                fontWeight: FontWeight.w700,
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

