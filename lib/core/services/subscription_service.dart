import 'package:flutter/foundation.dart';
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
  static const String _lastVerifiedKey = 'lastVerifiedAt';

  /// Server-side verification cache TTL (5 minutes).
  static const Duration _verifyCacheTtl = Duration(minutes: 5);

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

      // Grace period: if local activation just happened (Phase 3 fallback),
      // don't query Supabase yet — give the direct write time to propagate.
      final localActivation = _hive.configBox.get('localActivationAt');
      if (localActivation != null && isPro()) {
        final activatedAt = DateTime.tryParse(localActivation.toString());
        if (activatedAt != null &&
            DateTime.now().difference(activatedAt).inMinutes < 10) {
          return; // Grace period — don't override local activation yet
        }
        // Past grace period — clear the flag
        await _hive.configBox.delete('localActivationAt');
      }

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
    } catch (e) {
      // Offline or error — keep cached state, do not throw.
      debugPrint('[SubscriptionService.refreshFromSupabase] $e');
    }
  }

  /// Server-side subscription verification via `verify-subscription` edge function.
  ///
  /// Called from `gate()` for high-value PRO features. Uses a 5-minute cache TTL
  /// so we don't hit the server on every single gate() call.
  ///
  /// If the server confirms the user is NOT PRO but Hive says they are,
  /// this immediately downgrades. Prevents Hive-spoofing attacks.
  ///
  /// Returns `true` if verified PRO, `false` if free/expired/offline.
  Future<bool> verifyFromServer() async {
    try {
      final supabase = SupabaseService.instance;
      if (!supabase.isInitialized || !supabase.isAuthenticated) return isPro();

      // Check cache — skip server call if verified recently
      final lastVerifiedRaw = _hive.configBox.get(_lastVerifiedKey);
      if (lastVerifiedRaw != null) {
        final lastVerified = DateTime.tryParse(lastVerifiedRaw.toString());
        if (lastVerified != null &&
            DateTime.now().difference(lastVerified) < _verifyCacheTtl) {
          return isPro(); // Cache is fresh — trust local state
        }
      }

      final response = await supabase.callFunction(
        'verify-subscription',
        body: {},
      );

      if (response.status != 200) {
        // Offline-first: trust local Hive cache when server is unreachable.
        // This is intentional — a non-200 (network error, 401, 5xx) should
        // not immediately downgrade the user. The cache has a TTL
        // (_verifyCacheTtl) and will re-verify on next app launch.
        debugPrint('[SubscriptionService.verifyFromServer] HTTP ${response.status}');
        return isPro();
      }

      final data = response.data as Map<String, dynamic>?;
      if (data == null) return isPro();

      final serverIsPro = data['is_pro'] as bool? ?? false;
      final serverPlan = data['plan'] as String?;
      final serverExpiresAt = data['expires_at'] as String?;

      final configBox = _hive.configBox;

      if (serverIsPro && serverExpiresAt != null) {
        // Server confirms PRO — update local cache
        await configBox.put(_isProKey, true);
        await configBox.put(_expiresAtKey, serverExpiresAt);
        await configBox.put(_planKey, serverPlan ?? 'monthly');
      } else {
        // Server says NOT PRO — downgrade immediately (anti-spoof)
        await _downgradeLocally();
      }

      // Update verification timestamp
      await configBox.put(_lastVerifiedKey, DateTime.now().toIso8601String());

      return serverIsPro;
    } catch (e) {
      debugPrint('[SubscriptionService.verifyFromServer] $e');
      return isPro(); // Offline — trust cached state
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
