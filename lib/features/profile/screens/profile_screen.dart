import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/shared/widgets/paywall_sheet.dart';
import 'package:icanbefitter/shared/widgets/screen_loading_skeleton.dart';
import 'package:icanbefitter/shared/widgets/error_state.dart';
import '../providers/profile_provider.dart';
import '../widgets/profile_banner.dart';
import '../widgets/profile_identity.dart';
import '../widgets/baseline_grid.dart';
import '../widgets/profile_row.dart';
import '../widgets/section_header.dart';
import '../widgets/biometric_sync_card.dart';
import '../widgets/subscription_card.dart';
import '../widgets/progress_photos_card.dart';
import '../widgets/weekly_report_card.dart';
import '../widgets/badges_grid.dart';

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

  String _getNotifTime(String key) {
    final pref = _notifPrefs[key];
    if (pref is Map && pref['time'] is String) return pref['time'] as String;
    return '07:00';
  }

  String _getNotifDay(String key) {
    final pref = _notifPrefs[key];
    if (pref is Map && pref['day'] is String) return pref['day'] as String;
    return 'sunday';
  }

  void _toggleNotif(String key, bool value) {
    setState(() {
      final pref = Map<String, dynamic>.from(
        (_notifPrefs[key] as Map?) ?? {},
      );
      pref['enabled'] = value;
      _notifPrefs[key] = pref;
    });
    _saveNotificationPreferences();
  }

  void _setNotifTime(String key, String time) {
    setState(() {
      final pref = Map<String, dynamic>.from(
        (_notifPrefs[key] as Map?) ?? {},
      );
      pref['time'] = time;
      _notifPrefs[key] = pref;
    });
    _saveNotificationPreferences();
  }

  void _setNotifDay(String key, String day) {
    setState(() {
      final pref = Map<String, dynamic>.from(
        (_notifPrefs[key] as Map?) ?? {},
      );
      pref['day'] = day;
      _notifPrefs[key] = pref;
    });
    _saveNotificationPreferences();
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
    final photos = ref.watch(progressPhotosProvider);
    final usageWeeks = ref.watch(usageWeeksProvider);
    final firstReportViewed = ref.watch(firstReportViewedProvider);

    final name = profile['full_name'] as String? ?? 'User';
    final gender = profile['gender'] as String? ?? '';
    final heightCm = (profile['height_cm'] as num?)?.toDouble();
    final weightKg = (profile['current_weight_kg'] as num?)?.toDouble();
    final activityLevel = profile['activity_level'] as String? ?? '';
    final dob = profile['date_of_birth'] as String?;

    // Calculate age
    String ageStr = '\u2014';
    if (dob != null) {
      final birthDate = DateTime.tryParse(dob);
      if (birthDate != null) {
        final age = DateTime.now().difference(birthDate).inDays ~/ 365;
        if (age > 0) ageStr = '$age';
      }
    }

    final genderStr = gender.isNotEmpty
        ? gender[0].toUpperCase() + gender.substring(1)
        : '\u2014';
    final heightStr =
        heightCm != null ? '${heightCm.toStringAsFixed(0)}cm' : '\u2014';
    final weightStr =
        weightKg != null ? '${weightKg.toStringAsFixed(0)}kg' : '\u2014';
    final activityStr = _formatActivityLevel(activityLevel);

    final subtitle =
        'Phase ${stats.currentPhase} \u00B7 Week ${stats.currentWeek} \u00B7 ${_formatGoal(stats.primaryGoal)}';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Status bar safe area
              SizedBox(height: MediaQuery.of(context).padding.top),

              // 1. Banner
              Opacity(
                opacity: 0.5,
                child: Stack(
                  children: [
                    ProfileBanner(
                      onTapBanner: () => _showTodoSnackbar('Banner photo'),
                      onTapEdit: () => _showTodoSnackbar('Banner photo'),
                    ),
                    Positioned(
                      top: 8,
                      right: 26,
                      child: _phase2Badge(),
                    ),
                  ],
                ),
              ),

              // 2. Profile identity (overlaps banner by 30px)
              Transform.translate(
                offset: const Offset(0, -30),
                child: ProfileIdentity(
                  name: name,
                  subtitle: subtitle,
                  onTapAvatar: () => _showTodoSnackbar('Avatar photo'),
                  onTapEdit: () => context.go('/profile/edit'),
                ),
              ),

              // Offset the negative margin
              const SizedBox(height: 0),

              // Move remaining content up to compensate for the transform
              Transform.translate(
                offset: const Offset(0, -22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 3. Baseline stats
                    const SectionHeader('YOUR BASELINE'),
                    BaselineGrid(
                      ageGender: '$ageStr / $genderStr',
                      heightWeight: '$heightStr / $weightStr',
                      activityLevel: activityStr,
                      bodyFat: '\u2014',
                    ),
                    const SizedBox(height: 8),

                    // 4. Achievements
                    const SectionHeader('ACHIEVEMENTS'),
                    const BadgesGrid(),
                    const SizedBox(height: 8),

                    // 5. Subscription Card
                    const SectionHeader('SUBSCRIPTION'),
                    SubscriptionCard(
                      isPro: subInfo.isPro,
                      plan: subInfo.plan,
                      expiresAt: subInfo.expiresAt,
                      onUpgradeTap: () =>
                          showPaywallSheet(context, feature: 'PRO'),
                      onManageTap: () {
                        if (subInfo.isPro) {
                          // Show subscription details dialog
                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: AppColors.card,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(AppRadius.cardM),
                              ),
                              title: Text(
                                'Your Subscription',
                                style: GoogleFonts.getFont('DM Sans', fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Plan: ${(subInfo.plan ?? 'free').toUpperCase()}', style: GoogleFonts.getFont('DM Sans', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.proGold)),
                                  const SizedBox(height: 8),
                                  Text('Expires: ${subInfo.expiresAt ?? 'N/A'}', style: GoogleFonts.getFont('DM Sans', fontSize: 13, color: AppColors.textSecondary)),
                                  const SizedBox(height: 12),
                                  Text('To cancel or modify, contact support@icanbefitter.com', style: GoogleFonts.getFont('DM Sans', fontSize: 12, color: AppColors.textSecondary)),
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
                        } else {
                          showPaywallSheet(context, feature: 'PRO');
                        }
                      },
                    ),
                    const SizedBox(height: 8),

                    // 5. Biometric Sync (FREE for all)
                    const SectionHeader('HEALTH SYNC'),
                    BiometricSyncCard(
                      stepsToday: biometric.stepsToday,
                      sleepHours: biometric.sleepHours,
                      isSyncEnabled: biometric.isSyncEnabled,
                      onToggleSync: () async {
                        final newValue = !biometric.isSyncEnabled;
                        ref.read(biometricProvider.notifier).toggleSync(newValue);
                        if (newValue) {
                          // Notify user that Health Connect integration is being set up
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Health Connect sync enabled. Steps and sleep will be synced automatically.',
                                  style: GoogleFonts.getFont('DM Sans', fontSize: 13),
                                ),
                                backgroundColor: AppColors.card,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        }
                      },
                    ),
                    const SizedBox(height: 8),

                    // 6. Progress & Tracking
                    const SectionHeader('PROGRESS & TRACKING'),
                    _buildCard([
                      ProfileRow(
                        icon: Icons.show_chart,
                        title: 'Metrics & Graphs',
                        subtitle: 'Weight, Body Fat, Lift PRs',
                        trailing: const ProfileRowChevron(),
                        onTap: () => context.go('/profile/reports'),
                      ),
                    ]),
                    const SizedBox(height: 8),

                    // 7. Progress Photos (PRO gated — gallery coming Phase 2)
                    Opacity(
                      opacity: 0.5,
                      child: Stack(
                        children: [
                          ProgressPhotosCard(
                            isPro: subInfo.isPro,
                            photoCount: photos.photoCount,
                            onTap: () {
                              _showTodoSnackbar('Progress Photos Gallery');
                            },
                            onUpgradeTap: () {
                              SubscriptionService.instance.gate(
                                AppConstants.featureProgressPhotos,
                                onPro: () {},
                                onFree: () => showPaywallSheet(context,
                                    feature: 'Progress Photos'),
                              );
                            },
                          ),
                          Positioned(
                            top: 8,
                            right: 26,
                            child: _phase2Badge(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 8. Weekly Report
                    const SectionHeader('REPORTS'),
                    WeeklyReportCard(
                      isPro: subInfo.isPro,
                      usageWeeks: usageWeeks,
                      hasFirstReport: firstReportViewed,
                      onViewReport: () {
                        if (!firstReportViewed) {
                          ref
                              .read(firstReportViewedProvider.notifier)
                              .markViewed();
                        }
                        context.go('/profile/reports');
                      },
                      onUpgradeTap: () {
                        SubscriptionService.instance.gate(
                          AppConstants.featureWeeklyAiReport,
                          onPro: () => context.go('/profile/reports'),
                          onFree: () => showPaywallSheet(context,
                              feature: 'Weekly AI Report'),
                        );
                      },
                    ),
                    const SizedBox(height: 8),

                    // 9. Morning Alert (PRO gated)
                    const SectionHeader('DAILY MOTIVATION'),
                    _buildCard([
                      ProfileRow(
                        icon: Icons.wb_sunny_outlined,
                        title: 'AI Morning Alert',
                        subtitle: subInfo.isPro
                            ? 'Settings coming in Phase 2'
                            : 'Generic reminders (PRO for AI)',
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!subInfo.isPro)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.proGold.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'PRO',
                                  style: GoogleFonts.getFont(
                                    'DM Sans',
                                    fontSize: 8,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.proGold,
                                  ),
                                ),
                              ),
                            const ProfileRowChevron(),
                          ],
                        ),
                        onTap: () {
                          SubscriptionService.instance.gate(
                            AppConstants.featureMorningAlertPro,
                            onPro: () =>
                                _showTodoSnackbar('AI Morning Alert Settings'),
                            onFree: () => showPaywallSheet(context,
                                feature: 'Morning Alert'),
                          );
                        },
                      ),
                    ]),
                    const SizedBox(height: 8),

                    // 10. Notifications
                    const SectionHeader('NOTIFICATIONS'),
                    _buildCard([
                      _NotificationRow(
                        icon: Icons.wb_sunny_outlined,
                        title: 'Morning check-in',
                        isPro: !subInfo.isPro,
                        enabled: _getNotifEnabled('morning_checkin'),
                        onToggle: (v) => _toggleNotif('morning_checkin', v),
                        timeValue: _getNotifTime('morning_checkin'),
                        timeOptions: const ['06:00', '06:30', '07:00', '07:30', '08:00', '08:30', '09:00'],
                        onTimeChanged: (t) => _setNotifTime('morning_checkin', t),
                      ),
                      _NotificationRow(
                        icon: Icons.fitness_center,
                        title: 'Workout reminder',
                        enabled: _getNotifEnabled('workout_reminder'),
                        onToggle: (v) => _toggleNotif('workout_reminder', v),
                        timeValue: _getNotifTime('workout_reminder'),
                        timeOptions: const ['17:00', '17:30', '18:00', '18:30', '19:00', '19:30', '20:00'],
                        onTimeChanged: (t) => _setNotifTime('workout_reminder', t),
                      ),
                      _NotificationRow(
                        icon: Icons.local_fire_department_outlined,
                        title: 'Streak alerts',
                        enabled: _getNotifEnabled('streak_alerts'),
                        onToggle: (v) => _toggleNotif('streak_alerts', v),
                      ),
                      _NotificationRow(
                        icon: Icons.bar_chart_rounded,
                        title: 'Weekly recap',
                        enabled: _getNotifEnabled('weekly_recap'),
                        onToggle: (v) => _toggleNotif('weekly_recap', v),
                        dayValue: _getNotifDay('weekly_recap'),
                        dayOptions: const ['sunday', 'monday', 'saturday'],
                        onDayChanged: (d) => _setNotifDay('weekly_recap', d),
                      ),
                      _NotificationRow(
                        icon: Icons.credit_card_outlined,
                        title: 'Subscription reminders',
                        enabled: _getNotifEnabled('subscription_reminders'),
                        onToggle: (v) => _toggleNotif('subscription_reminders', v),
                        showBorder: false,
                      ),
                    ]),
                    const SizedBox(height: 8),

                    // 11. Settings
                    const SectionHeader('SETTINGS'),
                    _buildCard([
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
                        showBorder: false,
                        trailing: const ProfileRowChevron(),
                        onTap: () {
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
                                  Text('Your data is stored locally on your device (Hive). Supabase is used only for backups, AI, and community features.', style: GoogleFonts.getFont('DM Sans', fontSize: 13, color: AppColors.textSecondary, height: 1.5)),
                                  const SizedBox(height: 12),
                                  Text('Permissions:', style: GoogleFonts.getFont('DM Sans', fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                  const SizedBox(height: 6),
                                  Text('\u2022 Camera: Meal scanning (optional)\n\u2022 Health Connect: Steps & sleep sync (optional)\n\u2022 Storage: Progress photos (optional)', style: GoogleFonts.getFont('DM Sans', fontSize: 12, color: AppColors.textSecondary, height: 1.5)),
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
                        },
                      ),
                    ]),
                    const SizedBox(height: 12),

                    // 12. Sign Out button
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
                      child: SizedBox(
                        width: double.infinity,
                        child: GestureDetector(
                          onTap: () => _showSignOutDialog(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            decoration: BoxDecoration(
                              color: AppColors.red.withValues(alpha: 0.08),
                              border: Border.all(
                                color: AppColors.red.withValues(alpha: 0.2),
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'Sign Out \u2192',
                                style: GoogleFonts.getFont(
                                  'DM Sans',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.red,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 13. Delete Account
                    Center(
                      child: GestureDetector(
                        onTap: () => _showDeleteAccountDialog(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.screenPadding, vertical: 4),
                          child: Text(
                            'Delete Account',
                            style: GoogleFonts.getFont(
                              'DM Sans',
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                              color: AppColors.red.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
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

  Widget _phase2Badge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.textSecondary.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        'PHASE 2',
        style: GoogleFonts.getFont(
          'DM Sans',
          fontSize: 8,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  void _showTodoSnackbar(String feature) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '$feature — Coming in Phase 2',
          style: GoogleFonts.getFont('DM Sans', fontSize: 13),
        ),
        backgroundColor: AppColors.card,
        duration: const Duration(seconds: 2),
      ),
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

  /// Clear Hive -> sign out Supabase -> route to auth screen.
  Future<void> _performSignOut() async {
    try {
      // Clear all user-specific Hive boxes via repository
      await UserRepository.instance.clearAllData();

      // Sign out from Supabase
      await SupabaseService.instance.client.auth.signOut();
    } catch (_) {
      // Supabase not initialized or error — still navigate to sign-in.
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
                // Clear all local Hive data
                await UserRepository.instance.clearAllData();
                // Attempt to delete from Supabase (soft delete — marks account inactive)
                try {
                  final supabase = SupabaseService.instance.client;
                  final userId = supabase.auth.currentUser?.id;
                  if (userId != null) {
                    await supabase.from('users').update({
                      'is_deleted': true,
                      'deleted_at': DateTime.now().toIso8601String(),
                    }).eq('id', userId);
                  }
                  await supabase.auth.signOut();
                } catch (_) {
                  // Offline — local data already cleared
                }
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

  String _formatActivityLevel(String level) {
    if (level.isEmpty) return '\u2014';
    switch (level) {
      case 'sedentary':
        return 'Sedentary';
      case 'lightly_active':
        return 'Lightly Active';
      case 'moderately_active':
        return 'Moderately Active';
      case 'very_active':
        return 'Very Active';
      case 'extra_active':
        return 'Extra Active';
      default:
        return level[0].toUpperCase() +
            level.substring(1).replaceAll('_', ' ');
    }
  }
}

/// A notification preference row with toggle, optional time/day picker, and PRO badge.
class _NotificationRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final bool isPro;
  final bool showBorder;

  // Time picker
  final String? timeValue;
  final List<String>? timeOptions;
  final ValueChanged<String>? onTimeChanged;

  // Day picker
  final String? dayValue;
  final List<String>? dayOptions;
  final ValueChanged<String>? onDayChanged;

  const _NotificationRow({
    required this.icon,
    required this.title,
    required this.enabled,
    required this.onToggle,
    this.isPro = false,
    this.showBorder = true,
    this.timeValue,
    this.timeOptions,
    this.onTimeChanged,
    this.dayValue,
    this.dayOptions,
    this.onDayChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: showBorder
            ? const Border(
                bottom: BorderSide(color: AppColors.border, width: 1),
              )
            : null,
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppColors.input,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(icon, size: 15, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 12),

          // Title + PRO badge
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: GoogleFonts.getFont(
                      'DM Sans',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isPro) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.proGold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'PRO',
                      style: GoogleFonts.getFont(
                        'DM Sans',
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: AppColors.proGold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Time or Day picker (if applicable)
          if (timeOptions != null && timeValue != null && enabled)
            _TimePicker(
              value: timeValue!,
              options: timeOptions!,
              onChanged: onTimeChanged!,
            ),
          if (dayOptions != null && dayValue != null && enabled)
            _DayPicker(
              value: dayValue!,
              options: dayOptions!,
              onChanged: onDayChanged!,
            ),

          const SizedBox(width: 8),

          // Toggle
          ProfileToggle(value: enabled, onChanged: onToggle),
        ],
      ),
    );
  }
}

/// Compact time picker dropdown.
class _TimePicker extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _TimePicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  String _formatTime(String time24) {
    final parts = time24.split(':');
    final hour = int.tryParse(parts[0]) ?? 0;
    final minute = parts.length > 1 ? parts[1] : '00';
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayHour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (ctx) => options
          .map((t) => PopupMenuItem(
                value: t,
                child: Text(
                  _formatTime(t),
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: t == value ? FontWeight.w700 : FontWeight.w400,
                    color: t == value ? AppColors.accent : AppColors.textPrimary,
                  ),
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatTime(value),
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

/// Compact day picker dropdown.
class _DayPicker extends StatelessWidget {
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  const _DayPicker({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  String _formatDay(String day) {
    if (day.isEmpty) return day;
    return day[0].toUpperCase() + day.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      onSelected: onChanged,
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (ctx) => options
          .map((d) => PopupMenuItem(
                value: d,
                child: Text(
                  _formatDay(d),
                  style: GoogleFonts.getFont(
                    'DM Sans',
                    fontSize: 12,
                    fontWeight: d == value ? FontWeight.w700 : FontWeight.w400,
                    color: d == value ? AppColors.accent : AppColors.textPrimary,
                  ),
                ),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.input,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _formatDay(value),
              style: GoogleFonts.getFont(
                'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 14, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}
