import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

/// Severity of the Home subscription-expiry banner (diagnose 2026-06-06).
/// `expiringSoon` = still PRO with < 7 days left; `lapsed` = PRO has expired and
/// not yet renewed. Decided by the pure [SubscriptionService.expiryBannerSeverity].
enum ExpiryBannerSeverity { none, expiringSoon, lapsed }

/// Manages PRO subscription state.
///
/// Reads/writes Hive configBox for instant local checks (offline-first).
/// Refreshes from Supabase on app launch when online.
class SubscriptionService {
  SubscriptionService._() {
    _registerLifecycle();
  }
  static final SubscriptionService _instance = SubscriptionService._();

  /// Tech-debt audit 2026-05-20 / A7 (B5 D9-D10) — prefer
  /// `ref.read(subscriptionServiceProvider)` over `.instance`. The
  /// singleton path is preserved for non-Riverpod contexts (main.dart
  /// bootstrap, static helpers); the Provider exposes the same
  /// instance with `ref.listen(authUserIdTokenProvider, …)` wiring so
  /// the SingletonLifecycleRegistry reset fires through Riverpod's
  /// lifecycle. Full removal lands in a follow-up batch (CLAUDE.md §4.11).
  @Deprecated(
      'Use ref.read(subscriptionServiceProvider) — singleton path will be removed after full migration')
  static SubscriptionService get instance => _instance;

  final HiveService _hive = HiveService.instance;

  /// Tech-debt audit 2026-05-20 / A7 — register cross-account reset
  /// hook. The instance carries no mutable in-memory cache (every read
  /// goes through Hive/MigratedKey), but the static [onStateChanged]
  /// callback fires the Riverpod invalidation chain. On a user swap we
  /// must re-fire it so widgets re-read the new user's PRO state from
  /// the now-flipped namespaced userBox — otherwise a previously-PRO
  /// account's pill can linger for one frame on the new account.
  void _registerLifecycle() {
    SingletonLifecycleRegistry.register('SubscriptionService', _onUserChanged);
  }

  /// A7 — invoked from [SingletonLifecycleRegistry.notifyUserChanged].
  /// All entitlement state lives in MigratedKey (per-user userBox), so
  /// there is no in-memory cache to drop. We only need to re-fire the
  /// state-changed hook so consumers re-render with the new user.
  void _onUserChanged() {
    try {
      onStateChanged?.call();
    } catch (_) {
      // Hook intentionally swallows — same pattern as _downgradeLocally.
    }
  }

  // ── Pricing (sourced from AppConstants) ─────────────────────
  static int get monthlyPriceInr => AppConstants.monthlyPriceInr;
  static int get yearlyPriceInr => AppConstants.yearlyPriceInr;

  // ── PRO Feature Keys (canonical list from AppConstants) ─────
  /// All feature keys that require a PRO subscription.
  /// Usage-gated features (scan_meal, cart_auditor, ai_text_log)
  /// are included here — the usage counter service handles limits.
  ///
  /// audit-2026-05-16 E.8 — `featureActiveWorkoutMode`, `featureVoiceNotes`,
  /// `featureDietPlanPdf` removed entirely. Active workout is free since
  /// Test #2 Q6, voice is free since Test #9 F13, diet-plan PDF is free per
  /// CLAUDE.md §14. The constants themselves are also deleted from
  /// AppConstants in this batch.
  /// `featurePhotoAnalysis` added — was a documented PRO feature per §14
  /// with no gate callsite anywhere (audit F8.1 sub-bug); now in the list.
  static const List<String> allProFeatures = [
    AppConstants.featurePhases2To12,
    AppConstants.featureAiCoachUnlimited,
    AppConstants.featureWeeklyAiReport,
    AppConstants.featureProgressPhotos,
    AppConstants.featureScanMealPro,
    AppConstants.featureCartAuditorPro,
    AppConstants.featureAiTextLogPro,
    AppConstants.featureMorningAlertPro,
    AppConstants.featurePredictionMonthly,
    AppConstants.featurePhotoAnalysis,
    AppConstants.featureAdaptiveWorkouts,
  ];

  // ── Hive Keys ───────────────────────────────────────────────

  static const String _isProKey = 'isPro';
  static const String _expiresAtKey = 'expiresAt';
  static const String _planKey = 'plan';
  static const String _lastVerifiedKey = 'lastVerifiedAt';

  /// Stamped when PRO lapses due to EXPIRY (now past `expiresAt`), so the Home
  /// expiry banner can show "your PRO expired" even after [_downgradeLocally]
  /// wipes `expiresAt`. **User-scoped**: registered in
  /// `UserConfigMigrator.userScopedKeys` AND written only with an open session
  /// (see [isPro]) so it never seeds the shared `configBox` — without both, a
  /// configBox fall-through would leak User A's lapsed banner to User B
  /// (review P0, 2026-06-06). Cleared on renewal ([writeSubscriptionState]).
  /// NOT stamped on cross-account/sign-out wipes — only the genuine-expiry
  /// branch in [isPro] sets it.
  static const String _proLapsedAtKey = 'pro_lapsed_at';

  /// Debug-only (year-sim harness). When true, [refreshFromSupabase] skips its
  /// server query + downgrade so a dev-granted PRO state survives a simulation.
  /// The sim user has no real `subscriptions` row, so an un-paused refresh would
  /// `_downgradeLocally()` mid-run and silently gate off phase generation
  /// (stuck-at-Phase-1 → rank never climbs). Mirrors
  /// `SyncService.pausedForSimulation`. Set/cleared by `SimulationService.run`
  /// and the `/dev` autorun; always false in normal app flow + release.
  static bool pausedForSimulation = false;

  /// APK Test #12 / Task C-1 + H-41 (audit-2026-05-11) — payment
  /// grace window key. While a payment is in-flight,
  /// [verifyFromServer] will NOT downgrade the user even if the server
  /// reports `is_pro: false` (the webhook hasn't fired yet). Set by
  /// [RazorpayService] on payment success; cleared when the webhook
  /// lands OR `verify-payment` confirms a final verdict.
  ///
  /// H-41 — pre-fix this was a pure ISO-timestamp `until` value.
  /// Time-based windows have two pathologies: (a) a slow webhook past
  /// 10 min flips grace to false even though we're still legitimately
  /// awaiting verdict; (b) a fast confirmation in 5s leaves the
  /// window open for another 9:55, masking unrelated downgrade events
  /// during that window.
  ///
  /// Now stores `{order_id, started_at_iso}`. Event-based clear from
  /// [clearPaymentInFlight] (webhook landed / final verdict). The
  /// 10-min ceiling is preserved ONLY as a fallback safety cap, in
  /// case the clear path is missed.
  static const String _paymentInFlightOrderKey = 'paymentInFlightOrder';

  /// Legacy key — read for back-compat one cold start after upgrade,
  /// then never written again. Removed in a future cleanup batch.
  static const String _paymentInFlightUntilKey = 'paymentInFlightUntil';

  /// Hard ceiling — even with the event-based clear path, never honour
  /// a stale grace window past this duration. Protects against the
  /// clear path being missed (network drop after webhook, app killed
  /// mid-verify, etc.).
  static const Duration _paymentGraceWindow = Duration(minutes: 10);

  /// Server-side verification cache TTL (5 minutes).
  static const Duration _verifyCacheTtl = Duration(minutes: 5);

  /// Returns true if a payment is currently mid-confirmation. While
  /// true, downgrade decisions in [verifyFromServer] are suppressed.
  ///
  /// H-41 evaluation logic:
  ///   1. If a `paymentInFlightOrder` record exists AND `started_at`
  ///      is within the 10-min ceiling → in flight.
  ///   2. Else if the legacy `paymentInFlightUntil` timestamp exists
  ///      and is still in the future (cold-start upgrade) → in flight.
  ///   3. Otherwise → not in flight.
  bool get isPaymentInFlight {
    final rec = MigratedKey.read<dynamic>(_paymentInFlightOrderKey);
    if (rec is Map) {
      final startedAt =
          DateTime.tryParse((rec['started_at'] ?? '').toString());
      if (startedAt != null) {
        return DateTime.now().difference(startedAt) < _paymentGraceWindow;
      }
    }
    // Legacy fallback — read once per device until first event-based
    // write supersedes it.
    final legacy = MigratedKey.read<dynamic>(_paymentInFlightUntilKey);
    if (legacy != null) {
      final until = DateTime.tryParse(legacy.toString());
      if (until != null) return DateTime.now().isBefore(until);
    }
    return false;
  }

  /// Order id of the in-flight payment (event-based handle for the
  /// webhook + verify-payment confirmation paths to clear by). Returns
  /// null when no payment is in flight.
  String? get paymentInFlightOrderId {
    final rec = MigratedKey.read<dynamic>(_paymentInFlightOrderKey);
    if (rec is Map) {
      final id = rec['order_id'];
      return id is String && id.isNotEmpty ? id : null;
    }
    return null;
  }

  /// Marks a payment as in-flight by recording its Razorpay order_id +
  /// the start timestamp. Public so [RazorpayService] can call it on
  /// payment success. The 10-min ceiling enforced by [isPaymentInFlight]
  /// is a fallback only — the canonical clear path is event-based.
  Future<void> markPaymentInFlight({String? orderId}) async {
    final startedAt = DateTime.now().toIso8601String();
    await MigratedKey.write(_paymentInFlightOrderKey, <String, dynamic>{
      'order_id': orderId ?? '',
      'started_at': startedAt,
    });
    // Clear the legacy time-based key in the same write — if it
    // happens to be present from a pre-upgrade install, the event-
    // based path now owns the grace window.
    try {
      await MigratedKey.delete(_paymentInFlightUntilKey);
    } catch (_) {}
  }

  /// Clears the payment grace window. Called from:
  ///   - [RazorpayService] webhook-confirmed path (preferred clear)
  ///   - [RazorpayService.verifyPayment] final-verdict path (success
  ///     OR explicit final failure)
  ///   - Defensive on subscription-state writes after server confirms.
  ///
  /// Idempotent — safe to call when no payment is in flight.
  Future<void> clearPaymentInFlight() async {
    await MigratedKey.delete(_paymentInFlightOrderKey);
    await MigratedKey.delete(_paymentInFlightUntilKey);
  }

  /// APK Test #12.2 / cold-start reactivity hook.
  ///
  /// Wired from `app.dart` initState — invokes a Riverpod invalidation
  /// of `subscriptionInfoProvider` (+ `trialInfoProvider`,
  /// `messageLimitProvider`) so widgets watching these providers
  /// rebuild after `writeSubscriptionState` / `_downgradeLocally`
  /// changes Hive.
  ///
  /// Pre-fix: `refreshFromSupabase` is unawaited on splash. It
  /// successfully wrote `isPro=true` to local Hive, but no provider
  /// invalidation fired. The UI kept showing the stale `isPro=false`
  /// from when subscriptionInfoProvider was first built. Founder
  /// observation 2026-05-06: "I don't see PRO pill on profile, may be
  /// reading from local phone data." Yes — local phone data was
  /// correct (post-refresh) but Riverpod cached the stale snapshot.
  static void Function()? onStateChanged;

  /// Atomically writes all subscription keys in a single Hive batch.
  ///
  /// Hive's [Box.putAll] writes all entries in one I/O operation,
  /// preventing inconsistent state if the app crashes mid-write.
  ///
  /// Public so [RazorpayService] can use the same atomic pattern.
  Future<void> writeSubscriptionState({
    required bool isPro,
    required String expiresAt,
    required String plan,
  }) async {
    // Test #10.1 — write via MigratedKey (per-user userBox post-migration).
    try {
      await MigratedKey.write(_isProKey, isPro);
      await MigratedKey.write(_expiresAtKey, expiresAt);
      await MigratedKey.write(_planKey, plan);
      // Renewal/activation clears the lapsed marker so the Home expiry banner
      // disappears once PRO is active again (diagnose 2026-06-06).
      await MigratedKey.delete(_proLapsedAtKey);
      // APK Test #12.8 — fire success event so we can correlate UI
      // mismatch reports with the actual write timestamp.
      unawaited(ErrorTelemetry.logEvent(
        'subscription_state_written',
        message: 'isPro=$isPro plan=$plan',
      ));
    } catch (e, st) {
      // APK Test #12.8 — surface MigratedKey write failures. These were
      // previously invisible: a failed write left the UI/UI-state desync
      // and produced "PRO pill stuck on GO PRO after payment" symptoms.
      unawaited(ErrorTelemetry.recordNonFatal(
        e,
        st,
        reason: 'subscription_write_failure',
        extra: {'isPro': isPro.toString(), 'plan': plan},
      ));
      rethrow;
    }
    // APK Test #12.2 — fire reactivity hook so any widgets watching
    // subscriptionInfoProvider rebuild with the new state.
    try {
      onStateChanged?.call();
    } catch (_) {}
  }

  // ── Core API ────────────────────────────────────────────────

  /// Returns `true` if the user has an active PRO subscription.
  ///
  /// Checks Hive configBox for the `isPro` flag and verifies the local
  /// expiry date has not passed. If expired, immediately downgrades.
  ///
  /// Also runs a "who does this Hive state belong to?" check: if the
  /// profile stored in Hive has an `id` that doesn't match the current
  /// Supabase session's user id, the Hive cache is from another
  /// account (Android Auto Backup restore, dev-build Hive copy, manual
  /// tamper). Force-downgrade and return free. This is the defensive
  /// layer that catches leaks the startup id-mismatch guard misses.
  bool isPro() {
    final pro = MigratedKey.readWithDefault<bool>(_isProKey, false);
    if (!pro) return false;

    // Defense-in-depth: PRO + Hive-profile.id ≠ session.id means the
    // Hive cache is from a different account. Don't trust any of it.
    try {
      final profile = _hive.userBox.get('profile');
      final localId = (profile is Map) ? profile['id'] as String? : null;
      final sessionId = SupabaseService.instance.currentUser?.id;
      if (localId != null && sessionId != null && localId != sessionId) {
        // APK Test #12.8 — surface cross-account guard fires. These
        // indicate Hive state from a different account (Auto Backup
        // restore, dev-build Hive copy, manual tamper) and force-
        // downgrade. Previously invisible.
        // ignore: discarded_futures
        ErrorTelemetry.logEvent(
          'pro_state_force_downgrade_cross_account',
          message:
              'localId=${localId.length >= 8 ? localId.substring(0, 8) : localId} '
              'sessionId=${sessionId.length >= 8 ? sessionId.substring(0, 8) : sessionId}',
        );
        _downgradeLocally();
        return false;
      }
    } catch (_) {
      // Box not open / Supabase not initialized — fall through to the
      // existing expiry check. The startup guard in splash_screen covers
      // the not-yet-initialized case.
    }

    final expiresAtRaw = MigratedKey.read<dynamic>(_expiresAtKey);
    if (expiresAtRaw == null) {
      // isPro flag is set but no expiry — only treat as PRO in debug builds.
      // In release builds, this is a tampered state (rooted device attack).
      return kDebugMode;
    }

    final expiresAt = DateTime.tryParse(expiresAtRaw.toString());
    if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
      // Expired — downgrade immediately (no grace period). Stamp pro_lapsed_at
      // (once) BEFORE the wipe so the Home expiry banner can surface "your PRO
      // expired" even though _downgradeLocally clears expiresAt. Only this
      // genuine-expiry path stamps it — the cross-account wipe above does not
      // (diagnose 2026-06-06).
      // Session-gated so the marker is written to the per-user userBox, NEVER
      // the shared configBox (cross-account leak vector — review P0 2026-06-06).
      if (expiresAt != null &&
          HiveUserSession.currentOwnerFullId != null &&
          MigratedKey.read<dynamic>(_proLapsedAtKey) == null) {
        unawaited(
            MigratedKey.write(_proLapsedAtKey, expiresAt.toIso8601String()));
      }
      _downgradeLocally();
      return false;
    }

    return true;
  }

  /// High-value features that trigger server-side verification.
  /// Prevents Hive-spoofing on rooted devices for premium features.
  ///
  /// Progress photos are included because they involve Supabase Storage
  /// writes to a user-scoped bucket — granting access via a spoofed
  /// local flag would let a free user persist private photos onto
  /// infrastructure we pay for.
  static const Set<String> _highValueFeatures = {
    AppConstants.featurePhases2To12,
    AppConstants.featureAiCoachUnlimited,
    AppConstants.featureProgressPhotos,
  };

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
  /// High-value features trigger server-side verification (cached 5 min).
  void gate(
    String feature, {
    required VoidCallback onPro,
    required VoidCallback onFree,
  }) {
    if (!isPro()) {
      // APK Test #12.6 telemetry — paywall fires after isPro() returned
      // false BUT a recent localActivationAt or in-flight payment grace
      // suggests the user might actually be PRO. Catches "free user
      // saw paywall after paying" cases that the new grace window was
      // designed to prevent. Fire-and-forget.
      try {
        final localAct = MigratedKey.read<dynamic>('localActivationAt');
        final mightBePro = isPaymentInFlight ||
            (localAct != null &&
                DateTime.tryParse(localAct.toString()) != null &&
                DateTime.now()
                        .difference(DateTime.parse(localAct.toString()))
                        .inMinutes <
                    15);
        if (mightBePro) {
          // ignore: discarded_futures
          ErrorTelemetry.logEvent(
            'paywall_hit_when_pro',
            message: 'feature=$feature paymentInFlight=$isPaymentInFlight '
                'localActivationAt=$localAct',
          );
        }
      } catch (_) {
        // Never let telemetry break the gate path.
      }
      // ignore: discarded_futures
      ErrorTelemetry.logEvent('subscription_gate_routed',
          message: 'feature=$feature exit=onFree reason=not_pro_local');
      onFree();
      return;
    }

    // High-value features: verify server-side (async, cached 5 min).
    //
    // Bug 2026-05-22 / diagnose 7b3eaf — pre-fix had no .catchError on
    // verifyFromServer().then(...) and no timeout. If verify threw
    // (network blip, JWT expired, Edge function down) NEITHER onPro NOR
    // onFree fired — button taps vanished silently. Founder hit this on
    // GENERATE NEXT PHASE (2026-05-21). Telemetry showed zero
    // train_graduation_generate_phase_2_failed events, zero cloud
    // writes. Fix: 10s timeout + .catchError, both fall back to onPro
    // since local isPro() already returned true (we trust local over
    // server when server fails). Telemetry on every exit so future
    // silent-disappear bugs are one-query debuggable.
    if (_highValueFeatures.contains(feature)) {
      verifyFromServer()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        // ignore: discarded_futures
        ErrorTelemetry.logEvent('subscription_gate_routed',
            message: 'feature=$feature exit=onPro reason=verify_timeout');
        return true;
      }).then((verified) {
        // ignore: discarded_futures
        ErrorTelemetry.logEvent('subscription_gate_routed',
            message: verified
                ? 'feature=$feature exit=onPro reason=verify_pro'
                : 'feature=$feature exit=onFree reason=verify_failed');
        if (verified) {
          onPro();
        } else {
          onFree();
        }
      }).catchError((Object e, StackTrace st) {
        // ignore: discarded_futures
        ErrorTelemetry.logEvent('subscription_gate_routed',
            message: 'feature=$feature exit=onPro reason=verify_threw '
                'error=${e.runtimeType}');
        // ignore: discarded_futures
        ErrorTelemetry.recordNonFatal(e, st,
            reason: 'subscription_gate_verify_failed');
        onPro();
      });
      return;
    }

    // ignore: discarded_futures
    ErrorTelemetry.logEvent('subscription_gate_routed',
        message: 'feature=$feature exit=onPro reason=local_pro');
    onPro();
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

      // Year-sim harness: the simulated user has no real `subscriptions` row,
      // so an un-paused refresh would `_downgradeLocally()` and wipe the
      // dev-granted PRO mid-run — gating off phase generation. Skip entirely
      // while a sim is in flight (debug-only; always false in normal flow).
      if (pausedForSimulation) {
        debugPrint('[SubscriptionService.refreshFromSupabase] paused for '
            'simulation — trusting local state');
        return;
      }

      // C-7 (audit-2026-05-11) — defensive HiveUserSession bootstrap.
      // Splash fires `refreshFromSupabase` fire-and-forget BEFORE
      // `_ensureLocalUser` has opened the per-user namespaced boxes.
      // Without this, the configBox/userBox reads / writes below race
      // with the session and the upgrade pill stays grey even after the
      // server confirms PRO.
      await HiveUserSession.ensureOpenedForCurrentSession();

      // APK Test #12.1 / hotfix — check payment grace window FIRST,
      // before any state evaluation. This is the second downgrade path
      // (alongside `verifyFromServer`); without this gate, a cold start
      // within minutes of payment success would query Supabase, find no
      // row (test mode webhook lag, or production webhook delay), and
      // call `_downgradeLocally()` even though the user just paid.
      //
      // The pre-existing `localActivationAt` grace check below was
      // conditional on `isPro()` being true — fragile during a cold
      // start session-restore race where MigratedKey reads can fall
      // back to an empty configBox. The new `isPaymentInFlight` check
      // is unconditional and time-based.
      if (isPaymentInFlight) {
        debugPrint('[SubscriptionService.refreshFromSupabase] payment in '
            'flight — skipping server query, trusting local state');
        // APK Test #12.8 — explicit grace-skip event so we can tell apart
        // "skipped because grace" from "skipped because no session".
        unawaited(ErrorTelemetry.logEvent('subscription_refresh_grace_skip',
            message: 'reason=payment_in_flight'));
        return;
      }

      // Grace period: if local activation just happened (Phase 3 fallback),
      // don't query Supabase yet — give the direct write time to propagate.
      // APK Test #12.1 — dropped the `&& isPro()` conditional. localActivationAt
      // alone is enough; the cold-start session race could make isPro() return
      // false transiently and skip the grace window.
      final localActivation = MigratedKey.read<dynamic>('localActivationAt');
      if (localActivation != null) {
        final activatedAt = DateTime.tryParse(localActivation.toString());
        if (activatedAt == null) {
          // Malformed timestamp — clear and continue with server check.
          await MigratedKey.delete('localActivationAt');
        } else if (DateTime.now().difference(activatedAt).inMinutes < 10) {
          debugPrint('[SubscriptionService.refreshFromSupabase] within '
              'localActivationAt grace — skipping server query');
          unawaited(ErrorTelemetry.logEvent('subscription_refresh_grace_skip',
              message: 'reason=local_activation'));
          return; // Grace period — don't override local activation yet
        } else {
          // Past grace period — clear the flag
          await MigratedKey.delete('localActivationAt');
        }
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
        debugPrint('[SubscriptionService.refreshFromSupabase] no active '
            'subscription row — downgrading locally');
        // APK Test #12.8 — distinct event so we can tell apart
        // "downgraded because no row" from "downgraded because expired".
        unawaited(ErrorTelemetry.logEvent(
            'subscription_refresh_query_returned_null'));
        unawaited(_downgradeLocally());
        return;
      }

      final endDate = response['end_date'] as String?;
      final plan = response['plan'] as String?;

      if (endDate == null) {
        unawaited(ErrorTelemetry.logEvent('subscription_refresh_expired_state',
            message: 'reason=null_end_date'));
        unawaited(_downgradeLocally());
        return;
      }

      final expiresAt = DateTime.tryParse(endDate);
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) {
        unawaited(ErrorTelemetry.logEvent('subscription_refresh_expired_state',
            message: 'reason=past_end_date end_date=$endDate'));
        unawaited(_downgradeLocally());
        return;
      }

      // Active subscription — upgrade locally (atomic write).
      await writeSubscriptionState(
        isPro: true,
        expiresAt: expiresAt.toIso8601String(),
        plan: plan ?? 'monthly',
      );
      // APK Test #12.8 — success ping so dashboard can correlate "I paid
      // but pill is stuck" reports against actual server-confirmed state.
      unawaited(ErrorTelemetry.logEvent('subscription_refresh_success',
          message: 'plan=${plan ?? 'monthly'}'));
    } catch (e, st) {
      // Offline or error — keep cached state, do not throw.
      debugPrint('[SubscriptionService.refreshFromSupabase] $e');

      // APK Test #12.5 / Class 3 — surface silent failures to
      // server-side telemetry so we can see when sync breaks for a
      // user (was previously ONLY a debugPrint — invisible in prod).
      // Fire-and-forget; never let logging fail block recovery.
      unawaited(_logRefreshFailure(e));

      // audit-2026-05-11 H-42 — direct Crashlytics path alongside the
      // log-client-error funnel above (defense-in-depth — if Edge
      // Functions are down, Crashlytics still gets the signal).
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'subscription_refresh_from_supabase'));

      // Don't let network errors perpetuate phantom PRO indefinitely.
      // If local activation grace period (10 min) has passed, clear the flag
      // so the NEXT launch will do a proper server check.
      final localAct = MigratedKey.read<dynamic>('localActivationAt');
      if (localAct != null) {
        final actAt = DateTime.tryParse(localAct.toString());
        if (actAt != null && DateTime.now().difference(actAt).inMinutes >= 10) {
          await MigratedKey.delete('localActivationAt');
        }
      }
    }
  }

  /// APK Test #12.5 / Class 3 — fire-and-forget telemetry hook for
  /// `refreshFromSupabase` failures. Posts to `log-client-error`
  /// Edge Function with a short type tag so we can audit sync gaps
  /// without needing the user's debug log.
  Future<void> _logRefreshFailure(Object err) async {
    try {
      final supabase = SupabaseService.instance;
      // Skip if we don't even have a session — the failure is
      // probably "user logged out", not interesting.
      if (supabase.currentUser == null) return;
      await supabase.callFunction(
        'log-client-error',
        body: {
          'type': 'subscription_refresh_failure',
          'message': err.toString(),
        },
      );
    } catch (_) {
      // Swallow — don't escalate logging-of-logging-failures.
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
  Future<bool> verifyFromServer({bool force = false}) async {
    try {
      final supabase = SupabaseService.instance;
      if (!supabase.isInitialized || !supabase.isAuthenticated) {
        debugPrint('[SubscriptionService.verifyFromServer] supabase not ready '
            '— returning local isPro=${isPro()}');
        return isPro();
      }

      // Check cache — skip server call if verified recently (unless forced)
      if (!force) {
        final lastVerifiedRaw = MigratedKey.read<dynamic>(_lastVerifiedKey);
        if (lastVerifiedRaw != null) {
          final lastVerified = DateTime.tryParse(lastVerifiedRaw.toString());
          if (lastVerified != null &&
              DateTime.now().difference(lastVerified) < _verifyCacheTtl) {
            debugPrint('[SubscriptionService.verifyFromServer] cache fresh '
                '(last=${lastVerified.toIso8601String()}) — local isPro=${isPro()}');
            return isPro(); // Cache is fresh — trust local state
          }
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
        debugPrint('[SubscriptionService.verifyFromServer] HTTP ${response.status} '
            '— trust local isPro=${isPro()}');
        // APK Test #12.8 — surface non-200 from verify-subscription so
        // we can correlate "PRO pill stuck" with server-side verify
        // failures (auth gateway, edge function down, etc.).
        unawaited(ErrorTelemetry.logEvent('subscription_verify_non_200',
            message: 'status=${response.status} localIsPro=${isPro()}'));
        return isPro();
      }

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        debugPrint('[SubscriptionService.verifyFromServer] empty body '
            '— trust local isPro=${isPro()}');
        return isPro();
      }

      final serverIsPro = data['is_pro'] as bool? ?? false;
      final serverPlan = data['plan'] as String?;
      final serverExpiresAt = data['expires_at'] as String?;
      debugPrint('[SubscriptionService.verifyFromServer] server returned '
          'is_pro=$serverIsPro plan=$serverPlan expires_at=$serverExpiresAt');

      if (serverIsPro && serverExpiresAt != null) {
        // Server confirms PRO — update local cache (atomic write)
        await writeSubscriptionState(
          isPro: true,
          expiresAt: serverExpiresAt,
          plan: serverPlan ?? 'monthly',
        );
        // Webhook has fired — clear the grace window so subsequent
        // verifies behave normally (no false-positive grace).
        await clearPaymentInFlight();
        debugPrint('[SubscriptionService.verifyFromServer] confirmed PRO '
            '— local cache updated, payment_in_flight cleared');
      } else {
        // APK Test #12 / Task C-1 — payment grace window. If a payment
        // is mid-confirmation (toast fired, webhook hasn't yet), DO NOT
        // downgrade. The optimistic local state must survive until the
        // grace window expires or the webhook arrives.
        if (isPaymentInFlight) {
          debugPrint('[SubscriptionService.verifyFromServer] server says '
              'NOT pro BUT payment in flight — suppressing downgrade, '
              'returning local isPro=${isPro()}');
          // Don't update _lastVerifiedKey — we want the next verify to
          // re-check after a short interval, not trust this stale "no" for 5min.
          return isPro();
        }
        // Server says NOT PRO + no grace window — downgrade (anti-spoof).
        debugPrint('[SubscriptionService.verifyFromServer] server says '
            'NOT pro, no grace window — downgrading locally');
        await _downgradeLocally();
      }

      // Update verification timestamp
      await MigratedKey.write(_lastVerifiedKey, DateTime.now().toIso8601String());

      return serverIsPro;
    } on Exception catch (e) {
      // Network errors, timeouts, platform exceptions — trust cached state.
      debugPrint('[SubscriptionService.verifyFromServer] threw: $e '
          '— trust local isPro=${isPro()}');
      return isPro();
    }
  }

  /// Returns the current plan name (e.g., "monthly", "yearly"), or null.
  String? get currentPlan {
    return MigratedKey.read<String>(_planKey);
  }

  /// Returns the subscription expiry date, or null.
  DateTime? get expiresAt {
    final raw = MigratedKey.read<dynamic>(_expiresAtKey);
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

  /// The date PRO lapsed due to expiry, or null. Set by [isPro] on the
  /// genuine-expiry path; cleared on renewal (diagnose 2026-06-06).
  DateTime? get proLapsedAt {
    final raw = MigratedKey.read<dynamic>(_proLapsedAtKey);
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  /// True when PRO has expired and has NOT yet been renewed — drives the red
  /// "your PRO expired" Home banner. (`expiresAt` is wiped on downgrade, so we
  /// rely on the [proLapsedAt] marker instead.)
  bool get isLapsed => !isPro() && proLapsedAt != null;

  /// PURE production helper (shared by the Home banner provider + tested
  /// directly): which expiry banner to show. `lapsed` wins over `expiringSoon`;
  /// `expiringSoon` requires an active PRO with < 7 days left.
  static ExpiryBannerSeverity expiryBannerSeverity({
    required bool isPro,
    required int daysUntilExpiry,
    required bool isLapsed,
  }) {
    if (isLapsed) return ExpiryBannerSeverity.lapsed;
    if (isPro && daysUntilExpiry >= 0 && daysUntilExpiry < 7) {
      return ExpiryBannerSeverity.expiringSoon;
    }
    return ExpiryBannerSeverity.none;
  }

  // ── Private ─────────────────────────────────────────────────

  /// Soft-lock: clear ALL PRO-state keys from Hive. User-visible data
  /// (workout history, logs, templates) is untouched — only the PRO
  /// entitlement cache is wiped so the next `isPro()` returns false and
  /// `expiresAt`-dependent UI (subscription card renewal date, "days
  /// until expiry" banner, etc.) stops showing stale dates.
  ///
  /// Why not just flip `_isProKey` to false: leaving `_expiresAtKey`
  /// and `_planKey` around means a subscription card that reads those
  /// directly (not via `isPro()`) can still show the old account's
  /// renewal date — exactly the bug observed 2026-04-24 with the
  /// Auto-Backup-leaked icanbefitter@gmail.com PRO state showing up on
  /// a fresh upendra.prasad@thinkingcode.com account as "renews 18 May".
  Future<void> _downgradeLocally() async {
    // Debug-only year-sim guard (always false in release/normal flow).
    // The single sink for every downgrade path — refreshFromSupabase
    // (response==null / no-active-row), verifyFromServer, AND the in-line
    // expiry/cross-account checks in isPro() all funnel here. Guarding at
    // the top-of-refreshFromSupabase entry alone is insufficient: an
    // un-paused refresh kicked off during the ~100s boot restore can still
    // be IN FLIGHT when the sim sets the flag, then resolve AFTER the
    // dev-PRO grant and wipe it — silently gating off phase generation
    // (stuck-at-Phase-1 → rank never climbs). Skipping the wipe here keeps
    // the dev-granted PRO durable for the whole simulated span.
    if (pausedForSimulation) {
      debugPrint('[SubscriptionService._downgradeLocally] paused for '
          'simulation — preserving dev-granted PRO');
      return;
    }
    await MigratedKey.write(_isProKey, false);
    await MigratedKey.delete(_expiresAtKey);
    await MigratedKey.delete(_planKey);
    await MigratedKey.delete('localActivationAt');
    await MigratedKey.delete(_lastVerifiedKey);
    // APK Test #12.2 — fire reactivity hook so widgets re-render
    // with the downgraded state.
    try {
      onStateChanged?.call();
    } catch (_) {}
  }
}
