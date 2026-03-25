import 'dart:ui';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

/// Manages PRO subscription state.
///
/// Reads/writes Hive configBox for instant local checks (offline-first).
/// Refreshes from Supabase on app launch when online.
class SubscriptionService {
  SubscriptionService._();
  static final SubscriptionService _instance = SubscriptionService._();
  static SubscriptionService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  // ── Pricing (sourced from AppConstants) ─────────────────────
  static int get monthlyPriceInr => AppConstants.monthlyPriceInr;
  static int get yearlyPriceInr => AppConstants.yearlyPriceInr;

  // ── PRO Feature Keys (canonical list from AppConstants) ─────
  /// All feature keys that require a PRO subscription.
  /// Usage-gated features (scan_meal, cart_auditor, ai_text_log)
  /// are included here — the usage counter service handles limits.
  static const List<String> allProFeatures = [
    AppConstants.featurePhases2To12,
    AppConstants.featureActiveWorkoutMode,
    AppConstants.featureAiCoachUnlimited,
    AppConstants.featureReasoningTab,
    AppConstants.featureWeeklyAiReport,
    AppConstants.featureProgressPhotos,
    AppConstants.featureScanMealPro,
    AppConstants.featureCartAuditorPro,
    AppConstants.featureAiTextLogPro,
    AppConstants.featureVoiceNotes,
    AppConstants.featureMorningAlertPro,
    AppConstants.featurePredictionMonthly,
    AppConstants.featureAdaptiveWorkouts,
  ];

  // ── Hive Keys ───────────────────────────────────────────────

  static const String _isProKey = 'isPro';
  static const String _expiresAtKey = 'expiresAt';
  static const String _planKey = 'plan';

  // ── Core API ────────────────────────────────────────────────

  /// Returns `true` if the user has an active PRO subscription.
  ///
  /// Checks Hive configBox for the `isPro` flag and verifies the local
  /// expiry date has not passed. If expired, immediately downgrades.
  bool isPro() {
    final configBox = _hive.configBox;
    final pro = configBox.get(_isProKey, defaultValue: false) as bool;
    if (!pro) return false;

    final expiresAtRaw = configBox.get(_expiresAtKey);
    if (expiresAtRaw == null) {
      // isPro flag is set but no expiry — treat as PRO (test/dev mode).
      return true;
    }

    final expiresAt = DateTime.tryParse(expiresAtRaw.toString());
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      // Expired — downgrade immediately (no grace period).
      _downgradeLocally();
      return false;
    }

    return true;
  }

  /// The ONLY way to gate PRO features in the app.
  ///
  /// ```dart
  /// await subscriptionService.gate(
  ///   AppConstants.featureScanMealPro,
  ///   onPro: () => scanMeal(),
  ///   onFree: () => showPaywallSheet(context, feature: 'Scan Meal'),
  /// );
  /// ```
  ///
  /// Phase 1 is ALWAYS free — never gate it.
  void gate(
    String feature, {
    required VoidCallback onPro,
    required VoidCallback onFree,
  }) {
    if (isPro()) {
      onPro();
    } else {
      onFree();
    }
  }

  /// Polls Supabase `subscriptions` table for the current user and
  /// updates Hive configBox accordingly.
  ///
  /// Call on app launch (when online). Failures are silently ignored
  /// so the app continues to work offline with cached state.
  Future<void> refreshFromSupabase() async {
    try {
      final supabase = SupabaseService.instance;
      final userId = supabase.currentUser?.id;
      if (userId == null) return;

      final response = await supabase.client
          .from('subscriptions')
          .select()
          .eq('user_id', userId)
          .eq('status', 'active')
          .order('end_date', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) {
        _downgradeLocally();
        return;
      }

      final endDate = response['end_date'] as String?;
      final plan = response['plan'] as String?;

      if (endDate == null) {
        _downgradeLocally();
        return;
      }

      final expiresAt = DateTime.tryParse(endDate);
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
        _downgradeLocally();
        return;
      }

      // Active subscription — upgrade locally.
      final configBox = _hive.configBox;
      await configBox.put(_isProKey, true);
      await configBox.put(_expiresAtKey, expiresAt.toIso8601String());
      await configBox.put(_planKey, plan ?? 'monthly');
    } catch (_) {
      // Offline or error — keep cached state, do not throw.
    }
  }

  /// Returns the current plan name (e.g., "monthly", "yearly"), or null.
  String? get currentPlan {
    return _hive.configBox.get(_planKey) as String?;
  }

  /// Returns the subscription expiry date, or null.
  DateTime? get expiresAt {
    final raw = _hive.configBox.get(_expiresAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// Returns the number of days until subscription expires.
  /// Returns -1 if not a PRO user or no expiry date is set.
  int daysUntilExpiry() {
    final expiry = expiresAt;
    if (expiry == null) return -1;
    final diff = expiry.difference(DateTime.now()).inDays;
    return diff < 0 ? 0 : diff;
  }

  /// Returns true if the subscription expires within 7 days.
  /// Returns false if the user is not PRO or has no expiry date.
  bool get isExpiringSoon {
    if (!isPro()) return false;
    final days = daysUntilExpiry();
    return days >= 0 && days < 7;
  }

  // ── Private ─────────────────────────────────────────────────

  /// Soft-lock: set isPro = false. All data is kept; PRO features
  /// simply show a paywall.
  Future<void> _downgradeLocally() async {
    final configBox = _hive.configBox;
    await configBox.put(_isProKey, false);
  }
}
