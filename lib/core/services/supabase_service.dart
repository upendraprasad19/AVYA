import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'error_telemetry.dart';

/// Singleton wrapper around the Supabase client.
///
/// Supabase is used for:
///   - Auth (Email + Google OAuth + Phone OTP)
///   - Backup & cross-device restore
///   - AI training corpus (snapshots, conversations)
///   - Community DB growth (custom foods/exercises)
///   - Subscription verification
///
/// It is NOT the primary database — Hive handles all reads/writes locally.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService _instance = SupabaseService._();
  static SupabaseService get instance => _instance;

  bool _initialized = false;
  // Stored so concurrent callers await the same Future and never double-init.
  Future<void>? _initFuture;

  /// Initialize the Supabase client. Call once in main() before runApp().
  /// Safe to call concurrently — only one actual init will run.
  Future<void> initialize() async {
    if (_initialized) return;
    _initFuture ??= _doInitialize();
    await _initFuture;
  }

  Future<void> _doInitialize() async {
    // Runtime guard — works in both debug AND release builds.
    // (assert() is stripped in release, so this is the real safety net.)
    if (AppConstants.supabaseUrl.isEmpty ||
        AppConstants.supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL or SUPABASE_ANON_KEY is empty. '
        'Build with: flutter run --dart-define-from-file=.env --flavor dev',
      );
    }

    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
    );
    _initialized = true;
  }

  /// The global Supabase client instance.
  /// Throws if Supabase has not been initialized.
  SupabaseClient get client => Supabase.instance.client;

  /// Current authenticated user, or null if not signed in.
  /// Returns null if Supabase is not initialized.
  User? get currentUser {
    if (!_initialized) return null;
    return client.auth.currentUser;
  }

  /// Current auth session, or null.
  Session? get currentSession {
    if (!_initialized) return null;
    return client.auth.currentSession;
  }

  /// Whether Supabase has been successfully initialized.
  bool get isInitialized => _initialized;

  /// Whether a user is currently authenticated.
  /// Returns false if Supabase is not initialized.
  bool get isAuthenticated {
    if (!_initialized) return false;
    return currentUser != null;
  }

  /// Returns the user's current non-expired referral code, or generates a
  /// new one. Returns null if not authenticated or on failure.
  Future<({String code, DateTime expiresAt})?> getOrCreateReferralCode() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    // Try to find an existing non-expired code
    try {
      final existing = await client
          .from('referral_codes')
          .select('code, expires_at')
          .eq('user_id', userId)
          .gt('expires_at', DateTime.now().toIso8601String())
          .maybeSingle();

      if (existing != null) {
        return (
          code: existing['code'] as String,
          expiresAt: DateTime.parse(existing['expires_at'] as String),
        );
      }
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[SupabaseService.getOrCreateReferralCode] read: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'supabase_service_get_or_create_referral_code_read'));
    }

    return _generateNewCode(userId);
  }

  /// Forces generation of a fresh 7-day code (used by REGENERATE button
  /// after the previous code expired). Returns null if not authenticated.
  Future<({String code, DateTime expiresAt})?> regenerateReferralCode() async {
    final userId = currentUser?.id;
    if (userId == null) return null;
    return _generateNewCode(userId);
  }

  Future<({String code, DateTime expiresAt})?> _generateNewCode(
      String userId) async {
    for (var i = 0; i < 5; i++) {
      final code = _buildReferralCode();
      final expiresAt = DateTime.now().add(const Duration(days: 7));
      try {
        await client.from('referral_codes').upsert({
          'user_id': userId,
          'code': code,
          'expires_at': expiresAt.toIso8601String(),
        }, onConflict: 'user_id');
        return (code: code, expiresAt: expiresAt);
      } catch (e, st) {
        if (i == 4) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[SupabaseService._generateNewCode] $e');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'supabase_service_generate_new_referral_code'));
          return null;
        }
      }
    }
    return null;
  }

  String _buildReferralCode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rand = Random.secure();
    final body =
        List.generate(8, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'AVYA-$body';
  }

  /// Returns a fresh access token, refreshing proactively if the current
  /// JWT expires within [buffer]. Returns null if no session exists or
  /// refresh fails and the token is already expired.
  Future<String?> ensureFreshToken({
    Duration buffer = const Duration(minutes: 5),
  }) async {
    final session = client.auth.currentSession;
    if (session == null) return null;

    // Check if token expires within the buffer window
    final expiresAt = session.expiresAt;
    if (expiresAt != null) {
      final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      if (DateTime.now().isAfter(expiryTime.subtract(buffer))) {
        // Token is about to expire or already expired — refresh
        try {
          final refreshed = await client.auth.refreshSession();
          return refreshed.session?.accessToken;
        } catch (e, st) {
          // audit-2026-05-11 H-42 — telemetry pair.
          debugPrint('[SupabaseService.ensureFreshToken] refresh failed: $e');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'supabase_service_ensure_fresh_token_refresh'));
          // If token is already past expiry, return null (caller should handle)
          if (DateTime.now().isAfter(expiryTime)) return null;
          // Token hasn't expired yet, return existing
          return session.accessToken;
        }
      }
    }

    // Token is still fresh
    return session.accessToken;
  }

  /// Cold-start backoff schedule for 502/503/504 retries on Edge Function calls.
  ///
  /// Length defines the retry count (here: 3 retries → up to 4 total
  /// invocations). Values are millisecond delays before each retry.
  ///
  /// Pinned by `test/contracts/retry_loop_guard_test.dart` — bump
  /// deliberately and update the test in the same commit.
  ///
  /// History:
  /// - 2026-05-11 (Bug G+H, commit 24d6d54): single retry @ 1500 ms.
  /// - 2026-05-12 (Bug 7c4e1a): bumped to [1500, 4000] after ai-proxy
  ///   logs showed 20+ s cold-start; 1500 ms wasn't enough wait time.
  /// - 2026-05-15 (Bug c01d57): bumped to [2000, 6000, 12000] after
  ///   09:33 IST logs showed 3 consecutive 502s in a row (6.1s / 6.6s /
  ///   7.2s exec_times) — [1500, 4000] (~5.5s) still didn't span the
  ///   20.2 s worst-case warm-start. 504 added to the retry-trigger set
  ///   since cold-start gateway timeouts can present as either status.
  static const List<int> _coldStartBackoffsMs = [2000, 6000, 12000];

  /// Shortcut to invoke a Supabase Edge Function by [name].
  ///
  /// Proactively refreshes the JWT if it expires within 60 seconds.
  /// Returns the response directly — callers handle non-200 status codes.
  Future<FunctionResponse> callFunction(
    String name, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    // Proactive token refresh — avoids sending an expired JWT
    final token = await ensureFreshToken();
    if (token == null) {
      // Token is expired and soft refresh failed. Force a hard refresh.
      // This handles the case where the session object exists in memory
      // but the access token is expired (e.g. after Razorpay checkout).
      try {
        final refreshed = await client.auth.refreshSession();
        if (refreshed.session == null) {
          throw Exception('No active session. Please sign in again.');
        }
      } catch (e) {
        // Refresh token itself has expired — user must re-authenticate.
        throw Exception('No active session. Please sign in again.');
      }
    }

    // APK Test #15.5 / Bug c01d57 — bounded retry loop on transient
    // cold-start 502/503/504. Edge Function logs (2026-05-15 09:33 IST)
    // showed 3 consecutive 502s — [1500, 4000] (~5.5 s) from Test #15.3
    // didn't span the 20.2 s worst-case warm-start. Now [2000, 6000,
    // 12000] (~20 s) covers it. 504 added to retry set since cold-start
    // gateway timeouts can surface as either 502 or 504; 500 stays
    // excluded (server error, not boot delay).
    //
    // Auth-class errors (401/403) and other 4xx are NOT retried — they
    // rethrow immediately so the caller (e.g. AiCoachProvider) handles
    // them. The 2026-04-07 401-recursion guard is preserved.
    //
    // Retry control flow is factored into [retryColdStart] so it can
    // be exercised by behavioral tests with a mock invoker (source-grep
    // alone can't catch a future refactor that breaks the break/rethrow
    // condition while keeping the const list + telemetry string intact).
    //
    // closes-diagnose: 2026-05-15-ai-proxy-cold-start-budget-c01d57
    return retryColdStart(
      () => client.functions.invoke(name, headers: headers, body: body),
      functionName: name,
    );
  }

  /// Bounded retry loop for transient 502/503/504 cold-start failures.
  ///
  /// Invokes [invoke] and retries on `FunctionException` with status 502,
  /// 503, or 504, using the supplied [backoffsMs] schedule. Other
  /// exceptions rethrow immediately (auth-class 401/403, other 4xx, and
  /// non-cold-start 5xx like 500 do NOT retry).
  ///
  /// Exposed `@visibleForTesting` so behavioral tests can inject a mock
  /// invoker and assert runtime semantics — see
  /// `test/contracts/edge_function_cold_start_retry_behavioral_test.dart`.
  @visibleForTesting
  static Future<FunctionResponse> retryColdStart(
    Future<FunctionResponse> Function() invoke, {
    required String functionName,
    List<int> backoffsMs = _coldStartBackoffsMs,
  }) async {
    int attempt = 0;
    while (true) {
      try {
        return await invoke();
      } on FunctionException catch (e) {
        final isColdStart =
            e.status == 502 || e.status == 503 || e.status == 504;
        if (!isColdStart || attempt >= backoffsMs.length) {
          rethrow;
        }
        final backoffMs = backoffsMs[attempt];
        // Fire-and-forget telemetry — keeps the retry latency from
        // being doubled by the log-client-error network round-trip.
        unawaited(ErrorTelemetry.logEvent(
          'edge_function_cold_start_retry',
          message:
              'fn=$functionName attempt=${attempt + 1} status=${e.status} backoff_ms=$backoffMs',
        ));
        await Future<void>.delayed(Duration(milliseconds: backoffMs));
        attempt++;
      }
    }
  }
}
