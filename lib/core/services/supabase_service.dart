import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
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

  /// Obs 4 (2026-06-05): warm the PostgREST/edge connection during splash so
  /// RestoringScreen's first restore query doesn't eat the cold-start penalty
  /// (measured ~24s on the `user_profile` op — cold backend + the retry
  /// budget). Best-effort + non-blocking — fired unawaited; failures swallowed.
  Future<void> warmConnection() async {
    try {
      final uid = currentUser?.id;
      if (uid == null) return; // signed out → no restore coming → nothing to warm
      await client
          .from('user_profile')
          .select('user_id')
          .eq('user_id', uid)
          .limit(1);
    } catch (_) {
      // Warm-up is pure latency hygiene — never surface or block on failure.
    }
  }

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

  /// The in-flight refresh, so a second caller JOINS instead of racing.
  ///
  /// closes-diagnose d7b1f8. During the 2026-08-13 23:03–23:19 IST backend
  /// brown-out this method held NO in-flight future: every caller that found
  /// the token inside the [buffer] window independently called
  /// `refreshSession()`, so N concurrent callers produced N concurrent
  /// refreshes, each holding a connection for 10–36s against an already
  /// CPU-starved database.
  ///
  /// The tell is the recovery instant. `edge_logs` records roughly FIFTEEN
  /// `GET /auth/v1/user` requests all returning 200 inside one 400ms window
  /// (17:49:45.375 → 17:49:45.502). Fifteen requests do not complete
  /// simultaneously because fifteen things were needed — they complete
  /// simultaneously because fifteen INDEPENDENT in-flight requests had each
  /// been blocked on the same unavailable backend and were released at once.
  /// The client amplified an outage it was also a victim of.
  ///
  /// The codebase already solved this next door: `AuthNotifier.signOut` keeps
  /// `_inFlightSignOut` and returns the existing future so a second caller
  /// joins rather than races, and `SyncCoalescer` does the same for the write
  /// fan-out after the free-tier collapse (c4f8d2). Token freshness got
  /// neither. This is that same guard, applied to the same shape of problem.
  static Future<String?>? _inFlightRefresh;

  /// The session id [_inFlightRefresh] was armed FOR.
  ///
  /// B-pass finding 1 (2026-08-17), and it is the sharpest kind: the first
  /// version of this join had no identity affinity at all, so a caller acting
  /// for a DIFFERENT session joined the in-flight future and received the
  /// other identity's token without ever running its own refresher. The
  /// reviewer proved it by execution, not argument —
  /// `refresherARan=true refresherBRan=false resultB=token-for-USER-A`.
  ///
  /// That is precisely the bug class this same commit fixes for e5c2d1 ("an
  /// identity captured before an await is a SNAPSHOT, and every await is a
  /// chance for the session to change underneath it"), reproduced raw and
  /// unmirrored in the new auth-layer code shipped alongside it. The lesson is
  /// `feedback_mistake_guard_without_its_mirror`: a guard written for the
  /// failure you just hit does not generalise itself.
  static String? _inFlightRefreshOwner;

  /// Test hook — the join state is process-global (mirroring
  /// `AuthNotifier._inFlightSignOut`), so a test that leaves a future parked
  /// here would leak into the next one.
  @visibleForTesting
  static void resetRefreshJoinForTest() {
    _inFlightRefresh = null;
    _inFlightRefreshOwner = null;
  }

  /// The join, extracted behind an injectable so it is behaviorally testable
  /// without a live Supabase session — same seam as [retryColdStart].
  ///
  /// Returns the SAME future to callers that arrive while one is in flight
  /// **for the same [ownerId]**, so N concurrent callers of one identity
  /// produce exactly ONE [refresher] call — and a caller of a DIFFERENT
  /// identity never joins, because a shared token is a shared identity.
  ///
  /// [liveOwnerId] is injectable purely so the cross-account case is testable;
  /// production passes the real reader.
  @visibleForTesting
  static Future<String?> coalescedRefresh(
    Future<String?> Function() refresher, {
    required String? ownerId,
    String? Function()? liveOwnerId,
  }) {
    if (disableRefreshJoin) return refresher();
    final live = liveOwnerId ?? () => instance.currentUser?.id;

    // Sink-side re-check on RESOLVE, not just on arm: the refresh takes real
    // network time, and the session can swap while it is in flight. Handing a
    // token back to a caller whose identity has since changed is the same
    // defect one layer up. Null means "no fresh token" — every caller already
    // handles that.
    Future<String?> guarded(Future<String?> f) =>
        f.then((token) => live() == ownerId ? token : null);

    final existing = _inFlightRefresh;
    if (existing != null && _inFlightRefreshOwner == ownerId) {
      return guarded(existing); // join, never race — SAME identity only
    }

    final run = refresher();
    _inFlightRefresh = run;
    _inFlightRefreshOwner = ownerId;
    // Cleared on BOTH paths. `_refreshToken` never rethrows today, but
    // whenComplete still fires if that ever changes, so a throw can never
    // strand the field and wedge every later refresh.
    return guarded(run.whenComplete(() {
      _inFlightRefresh = null;
      _inFlightRefreshOwner = null;
    }));
  }

  /// Test override for [disableRefreshJoin]. `null` = read the real flag.
  @visibleForTesting
  static bool? disableRefreshJoinForTest;

  /// Kill-switch for the [_inFlightRefresh] join (root CLAUDE.md §4.6 — auth is
  /// on the risky-change list). Set `configBox['disable_token_refresh_join']`
  /// to restore the pre-fix racing behaviour verbatim.
  ///
  /// ⚠ B-pass finding 2 (2026-08-17): this was a `static bool` field whose doc
  /// claimed it was "flipped by the same boot code that reads the flag". No
  /// such boot code existed anywhere in the repo, and nothing but the tests
  /// ever assigned it — a kill-switch that is unreachable in production
  /// satisfies platform tier's `requires: feature_flag` in appearance only.
  /// The two switches shipped in one commit were asymmetric: `signInTimeout`'s
  /// read Hive and worked; this one was decorative. It now reads Hive lazily,
  /// exactly the way its sibling does.
  ///
  /// Fails CLOSED to the fix being ON: an unopened configBox leaves the join
  /// active, because a racing refresh is the defect being repaired.
  static bool get disableRefreshJoin {
    final override = disableRefreshJoinForTest;
    if (override != null) return override;
    try {
      return Hive.box(_configBoxName).get('disable_token_refresh_join') == true;
    } catch (_) {
      return false;
    }
  }

  /// Local copy of the config box name. `hive_service.dart` imports this file,
  /// so importing it back would be a cycle.
  static const String _configBoxName = 'configBox';

  /// Ceiling on a single token refresh.
  ///
  /// B-pass finding 5 (2026-08-17): the join made an unbounded refresh STRICTLY
  /// WORSE than before it existed. Pre-fix, a stalled refresh stranded only the
  /// N callers concurrent with it, and each held an independent connection that
  /// could resolve on its own. Post-fix, `_inFlightRefresh` is cleared only via
  /// `whenComplete`, so a refresh that never resolves is joined by every caller
  /// for the remaining life of the process and no independent attempt is ever
  /// made again. Bounding it restores retry: the timeout throws, `whenComplete`
  /// clears the field, and the next caller starts a genuinely new refresh.
  static const Duration refreshTimeout = Duration(seconds: 20);

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
        // Token is about to expire or already expired — refresh.
        // d7b1f8: join an in-flight refresh instead of starting a second one.
        // The guard is HERE, not at method entry, so the common fast path (a
        // still-fresh token) stays lock-free and is never serialised behind a
        // refresh — only the expensive network branch coalesces.
        return coalescedRefresh(
          () => _refreshToken(session, expiryTime),
          ownerId: session.user.id,
        );
      }
    }

    // Token is still fresh
    return session.accessToken;
  }

  /// The refresh itself. Single call site — see [ensureFreshToken].
  Future<String?> _refreshToken(Session session, DateTime expiryTime) async {
    try {
      // Bounded — see [refreshTimeout]. A TimeoutException lands in the catch
      // below like any other failure, and `whenComplete` in [coalescedRefresh]
      // then clears the in-flight field so a later caller can retry.
      final refreshed =
          await client.auth.refreshSession().timeout(refreshTimeout);
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
    bool retryOn500 = false,
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
      () => _invokeRaw(name, headers: headers, body: body),
      functionName: name,
      retryOn500: retryOn500,
    );
  }

  /// The ONE raw `functions.invoke` call site in the app.
  ///
  /// Both [callFunction] (authed, token-refreshed) and [callFunctionAnonymous]
  /// (pre-auth lane) funnel through here, so this file contains exactly one
  /// raw invoke call site. That count is pinned by
  /// `test/contracts/edge_function_503_retry_test.dart` — which greps the file
  /// WITHOUT stripping comments, so do not spell the literal out in prose here
  /// or the doc comment itself trips the gate. Its real concern is
  /// that nobody reintroduces a naive `try { invoke } catch { invoke }` — an
  /// unconditional retry would mask sustained outages and auth failures.
  Future<FunctionResponse> _invokeRaw(
    String name, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) =>
      client.functions.invoke(name, headers: headers, body: body);

  /// Invokes an Edge Function with NO user session — the pre-auth telemetry
  /// lane (diagnose b6e4f2).
  ///
  /// Deliberately does NOT call [ensureFreshToken]: there is no session to
  /// refresh, and [callFunction] would THROW 'No active session. Please sign in
  /// again.' before ever reaching the network — which is exactly the barrier
  /// that made every signed-out failure unloggable. supabase_flutter attaches
  /// the project's anon key as the Bearer when no session exists, which is what
  /// `log-client-error`'s allow-listed pre-auth lane expects.
  ///
  /// Lives HERE, not at the callsite, on purpose. `check_authed_invoke_fresh_token
  /// .dart` exempts exactly one file — this one — because it is the sanctioned
  /// home for a raw `functions.invoke`. That gate's rule is about AUTHED calls
  /// carrying a STALE token; this call carries no user token at all, so it is
  /// outside the rule's intent rather than an exception to it. Putting it at the
  /// callsite would mean grandfathering `error_telemetry.dart` into the
  /// baseline, which would then silently permit a REAL authed invoke there later.
  ///
  /// DOES get the cold-start retry, via the same [retryColdStart] as the authed
  /// path. An earlier version skipped it, reasoning that "telemetry must never
  /// add latency to a failing auth screen" — that reason is wrong on its own
  /// terms: every callsite is `unawaited(...)`, so the retry cannot delay any
  /// UI. Skipping it only meant the pre-auth lane silently lost its event
  /// whenever the function happened to be cold, which is precisely the
  /// observability-silent-drop class the lane exists to end. A cold start also
  /// costs no server budget, since the request never reaches the handler.
  Future<FunctionResponse> callFunctionAnonymous(
    String name, {
    Map<String, dynamic>? body,
  }) {
    return retryColdStart(
      () => _invokeRaw(name, body: body),
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
    List<int> storageRaceBackoffsMs = _storageRaceBackoffsMs,
    bool retryOn500 = false,
  }) async {
    int coldStartAttempt = 0;
    int storageRaceAttempt = 0;
    while (true) {
      try {
        return await invoke();
      } on FunctionException catch (e) {
        // Theme I (diagnose <id>) — ai-proxy returns 500 on transient
        // Gemini upstream timeouts. The default retry-trigger set is
        // 502/503/504 (gateway-side cold-start signals). 500 is opt-in
        // per-caller via [retryOn500] so we extend the retry budget for
        // ai-proxy without changing behavior for other Edge Functions
        // where a 500 IS a caller bug (validation, malformed body) that
        // shouldn't retry.
        final isColdStart =
            e.status == 502 || e.status == 503 || e.status == 504 ||
            (retryOn500 && e.status == 500);
        // audit-2026-05-16 / Obs 6 — Storage 404 upload-CDN race.
        // ai-media-proxy v17 maps Storage 404 to 400 with the typed
        // body `{"error_type": "storage", ...}`. CDN propagation
        // resolves in sub-second; brief retry budget absorbs it. Any
        // other 400 (validation, oversized, malformed body) is a
        // caller bug and must NOT retry.
        final isStorageRace =
            e.status == 400 && _functionDetailsIsStorageRace(e.details);

        if (isColdStart) {
          if (coldStartAttempt >= backoffsMs.length) rethrow;
          final backoffMs = backoffsMs[coldStartAttempt];
          unawaited(ErrorTelemetry.logEvent(
            'edge_function_cold_start_retry',
            message:
                'fn=$functionName attempt=${coldStartAttempt + 1} status=${e.status} backoff_ms=$backoffMs',
          ));
          await Future<void>.delayed(Duration(milliseconds: backoffMs));
          coldStartAttempt++;
          continue;
        }

        if (isStorageRace) {
          if (storageRaceAttempt >= storageRaceBackoffsMs.length) rethrow;
          final backoffMs = storageRaceBackoffsMs[storageRaceAttempt];
          unawaited(ErrorTelemetry.logEvent(
            'edge_function_storage_race_retry',
            message:
                'fn=$functionName attempt=${storageRaceAttempt + 1} status=400 error_type=storage backoff_ms=$backoffMs',
          ));
          await Future<void>.delayed(Duration(milliseconds: backoffMs));
          storageRaceAttempt++;
          continue;
        }

        rethrow;
      }
    }
  }

  /// Storage-race retry schedule. Sub-second-friendly because CDN
  /// propagation typically resolves in <1s; total budget ~5s.
  static const List<int> _storageRaceBackoffsMs = [500, 1500, 3000];

  /// True if the FunctionException body carries `error_type=="storage"`.
  /// Tolerant of varied shapes — `details` may be a Map, a JSON string,
  /// or null depending on supabase_flutter internals.
  static bool _functionDetailsIsStorageRace(dynamic details) {
    if (details == null) return false;
    if (details is Map) return details['error_type'] == 'storage';
    if (details is String) {
      try {
        final m = jsonDecode(details);
        if (m is Map) return m['error_type'] == 'storage';
      } catch (_) {
        return false;
      }
    }
    return false;
  }
}
