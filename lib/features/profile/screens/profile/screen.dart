import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:icanbefitter/core/theme/colors.dart';
import 'package:icanbefitter/core/theme/spacing.dart';
import 'package:icanbefitter/core/theme/typography.dart';
import 'package:icanbefitter/shared/mixins/hive_tab_scaffold.dart';
import 'package:icanbefitter/shared/widgets/wardroom/wardroom.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SignOutScope;
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/features/profile/services/notification_prefs_repository.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/prediction_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
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
import '../../providers/profile_provider.dart';
import '../../providers/referral_eligibility_provider.dart';
import '../../utils/profile_image_url.dart';
import '../apply_referral_sheet.dart';
import '../../widgets/profile_identity.dart';
import '../../widgets/profile_row.dart';
import '../../widgets/section_header.dart';
import '../../widgets/slim_achievements_card.dart';
import '../../widgets/profile_completeness_card.dart';
import '../../widgets/biometric_sync_card.dart';
import '../../widgets/weekly_report_card.dart';
import '../../widgets/rank_service_record_sheet.dart';
import '../invite_friends_sheet.dart';


part 'profile_content.dart';
part 'flush_card.dart';
part 'daily_completion.dart';
part 'body_stats.dart';
part 'journey_timeline.dart';
part 'prediction_sheet.dart';
part 'prediction_card.dart';
part 'subscription_section.dart';
part 'nutrition_targets.dart';
part 'pace_detail_sheet.dart';
part 'danger_zone.dart';
part 'health_sync_subtitle.dart';
part 'health_sync_sheet.dart';
part 'export_data.dart';
part 'privacy_dialog.dart';
part 'launch_url.dart';
part 'open_instagram.dart';
part 'build_card.dart';
part 'sign_out_dialog.dart';
part 'perform_sign_out.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with HiveTabScaffoldMixin<ProfileScreen> {
  // Synchronous Hive reads — initialized lazily on first access via the
  // `late` keyword. Both keys are guaranteed-present (`isMetric` defaults
  // to true; `notification_preferences` defaults to {}); UserRepository
  // and `_loadNotificationPreferences()` handle missing-key fallbacks.
  // These can't go into a regular field initializer because they depend
  // on Hive being open, which is guaranteed by `main.dart` before
  // `runApp()`.
  late bool _isMetric = UserRepository.instance.getUnitsMetric();
  late Map<String, dynamic> _notifPrefs = _loadNotificationPreferences();

  // Bug #14 — Prediction polling moved from home_screen.dart. The Future
  // Prediction card now lives in profile, so the fire-and-forget post-
  // onboarding generation needs a poller here to render the result once
  // it lands in Hive.
  Timer? _predictionPollTimer;
  int _predictionPollCount = 0;
  static const int _maxPredictionPollAttempts = 10; // 3s × 10 = 30s

  // initState is owned by HiveTabScaffoldMixin (microtask + isLoading flip).
  // First-mount-only side effects move to `initTab()` below.
  @override
  Future<void> initTab() async {
    _startPredictionPollIfNeeded();
  }

  @override
  void invalidateOnRetry(WidgetRef ref) {
    ref.invalidate(userProfileProvider);
    ref.invalidate(userStatsProvider);
    ref.invalidate(subscriptionInfoProvider);
    ref.invalidate(biometricProvider);
    ref.invalidate(progressPhotosProvider);
    ref.invalidate(usageWeeksProvider);
    ref.invalidate(firstReportViewedProvider);
  }

  @override
  void dispose() {
    _predictionPollTimer?.cancel();
    super.dispose();
  }

  /// Polls Hive every 3 seconds (up to 30s) until a prediction is found.
  /// Once found, invalidates [predictionProvider] so the card renders.
  void _startPredictionPollIfNeeded() {
    final existing = MigratedKey.read<String>('prediction_text');
    if (existing != null) return;
    _predictionPollTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _predictionPollCount++;
      final found = MigratedKey.read<String>('prediction_text');
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
        style: AppTypography.bodyM,
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
            style: AppTypography.bodyM.copyWith(fontWeight: FontWeight.w600),
          ),
          backgroundColor: AppColors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Could not refresh prediction. Please try again later.',
            style: AppTypography.bodyM,
          ),
          backgroundColor: AppColors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  Map<String, dynamic> _loadNotificationPreferences() {
    // Unit C (bug c): reads the USER-scoped box via the repository, which
    // normalises the Hive `Map<dynamic, dynamic>` shape and returns {} rather
    // than throwing. Deliberately NOT MigratedKey — its configBox fallback
    // would serve the previous user's value (migrated_key.dart:46-48).
    final stored = NotificationPrefsRepository.read();
    if (stored.isNotEmpty) {
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

  // _addCacheBuster removed (APK +34 / obs 4): it re-fetched the avatar/banner
  // on every build. Versioning now happens at upload time; the read path passes
  // the stored URL through verbatim via ProfileImageUrl.forDisplay. See
  // lib/features/profile/utils/profile_image_url.dart.

  Future<void> _saveNotificationPreferences() async {
    // Unit C (bug c): routed through the repository, which writes the
    // USER-scoped box. This used to `put` straight into the SHARED configBox,
    // so on a shared device the last saver set preferences for whoever signed
    // in next. Returns false without a session — silently doing nothing is
    // correct here, since absent ⇒ the server SENDS (decision N2).
    await NotificationPrefsRepository.write(_notifPrefs);
  }

  bool _getNotifEnabled(String key) {
    final pref = _notifPrefs[key];
    if (pref is Map) return pref['enabled'] == true;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading || isSessionTearingDown) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: const ScreenLoadingSkeleton(cardCount: 5),
      );
    }

    try {
      return _buildProfileContent(context);
    } catch (e) {
      final errStr = e.toString();
      final clipped = errStr.length > 500 ? errStr.substring(0, 500) : errStr;
      unawaited(ErrorTelemetry.logEvent('profile_screen_build_failed',
          message: clipped));
      return Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            child: ErrorState(
              title: 'Failed to load profile',
              subtitle: 'Tap to retry',
              onRetry: retry,
            ),
          ),
        ),
      );
    }
  }
}


/// Theme C · Test #8 — Position of a card inside the flush stack.
/// Drives the corner-radius + top-border decisions in `_buildFlushCard`.
enum _FlushPos { first, middle, last, only }


