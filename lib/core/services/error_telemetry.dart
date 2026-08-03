import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

import '../constants/app_constants.dart';
import 'supabase_service.dart';

/// APK Test #12.6 — unified non-fatal error + event telemetry.
///
/// `recordNonFatal`: post to Crashlytics (fatal: false) AND `log-client-error`.
/// `logEvent`: structured event with `op_type` for `client_errors` table.
///
/// All methods are fire-and-forget. Never throws. Never blocks caller.
/// In `kDebugMode`, Crashlytics calls are skipped to avoid spamming the
/// dashboard during local development; the `log-client-error` post still
/// runs so server-side telemetry can be exercised end-to-end during QA.
///
/// APK Test #16.1 / Theme D (2026-05-16) — rate-limit cooldown.
///
/// When the `log-client-error` Edge Function returns
/// `{rate_limited: true, next_window_at: <iso>, priority_lane: "low"}`,
/// the client sets [_rateLimitedUntil] to `next_window_at` (falling back
/// to `now + 1h` when the timestamp is missing). Subsequent LOW-priority
/// `logEvent` calls within the cooldown window short-circuit before the
/// network round-trip — saves bandwidth + tracker noise.
///
/// HIGH-priority op_types (per [isHighPriorityOpType]) bypass the
/// cooldown and always POST: the server-side priority lane will insert
/// regardless of budget, so dropping them client-side would defeat the
/// purpose.
///
/// Pre-Test-#16.1 the client ignored `rate_limited: true` entirely and
/// kept hammering the endpoint — every call paid a JWT refresh + cold-
/// start retry budget for a row that was discarded server-side.
class ErrorTelemetry {
  ErrorTelemetry._();

  /// Until-time of the current rate-limit cooldown (UTC).
  ///
  /// Null when no cooldown is active. Set when the server replies with
  /// `rate_limited: true`. LOW-priority `logEvent` calls before this
  /// instant are dropped without a network round-trip; HIGH-priority
  /// op_types always post.
  ///
  /// `@visibleForTesting` so behavioral tests can clear/seed it.
  @visibleForTesting
  static DateTime? rateLimitedUntil;

  /// Fallback cooldown duration when the server reply omits
  /// `next_window_at`. Mirrors the 1h floor used by the Edge Function
  /// docstring.
  static const Duration _fallbackCooldown = Duration(hours: 1);

  /// Test seam — set to true in unit tests to disable the static-mode
  /// HIGH op_type allowlist (so the cooldown can be exercised on any
  /// op_type without seeding a real "crash_*" prefix). Production code
  /// MUST leave this false.
  @visibleForTesting
  static bool forceTreatAllAsLowPriorityForTest = false;

  /// Test seam — when non-null, `logEvent` invokes this instead of making
  /// a real network call, so a behavioral test can assert an event fired
  /// (op_type + message) without a Supabase client. Production code MUST
  /// leave this null. Reset to null in `setUp`/`tearDown`.
  @visibleForTesting
  static void Function(String opType, {String? message})?
      debugOnLogEventForTests;

  /// HIGH-priority op_type matcher — must stay in lock-step with the
  /// server-side `HIGH_PRIORITY_OP_TYPES` set in
  /// `supabase/functions/log-client-error/index.ts`. Drift between
  /// these two lists is a silent observability bug: a HIGH op_type the
  /// server inserts but the client drops (or vice versa).
  ///
  /// Matching rules (must match server `isHighPriority`):
  ///   - Trailing `_` means prefix match (e.g. `crash_` matches
  ///     `crash_native_oom`).
  ///   - No trailing `_` means exact equality.
  ///   - Case-sensitive.
  ///
  /// Pinned by `test/safety/error_telemetry_rate_limit_test.dart`.
  @visibleForTesting
  static const List<String> highPriorityOpTypes = [
    // Crash classes.
    'crash_',
    'app_crash_',
    'isolate_unhandled_',

    // Auth failures.
    'auth_failure_',
    'auth_signed_out_unexpected',
    'guarded_box_disagreement',
    'hive_session_owner_mismatch',

    // Known-bad SQL state codes.
    '42P10',
    '23502',
    '23505',
    '23503',
    'permission_denied',
    'unique_violation',

    // /build-apk discipline-gate violations.
    'gate16_violation',
    'discipline_gate_violation',

    // Bug-class triggers.
    'bug_class_new_',
    'writer_reader_drift_',
    'sync_failure_dead_letter',

    // Streak-freeze lifecycle — money-relevant + once-per-lifecycle, so an event
    // dropped in a cooldown window is UNRECOVERABLE (Hermes L37, f9d2e7). MUST
    // stay in sync with the server HIGH_PRIORITY_OP_TYPES (twin test).
    'streak_freeze_first_pro_grant',
    'streak_freeze_lapse_reset',

    // Cross-device optimistic-lock drop events (Hermes C8, 2026-07-30, same
    // reasoning as the streak-freeze pair above: a dropped write is only
    // discoverable via this exact event, and a cooldown is most likely to
    // be active precisely when the backend is degraded — exactly when a
    // drop is most likely and most needs to be seen, not hidden
    // (feedback_backend_collapse_blinds_telemetry.md, c4f8d2). MUST stay in
    // sync with the server HIGH_PRIORITY_OP_TYPES (twin test).
    'sync_freezes_retry_dropped',
    'sync_user_progress_retry_dropped',
    'sync_freezes_row_absent_after_conflict',
    'sync_user_progress_row_absent_after_conflict',

    // Restore-side monotonic guard (OI-83 / d1f6b3, 2026-08-03, round-1 review
    // P2). Same reasoning as the two blocks above: a refused demotion is only
    // discoverable via this exact event, and the condition that produces it in
    // bulk — a degraded backend serving stale user_progress rows to a wave of
    // restores — is precisely when a cooldown is most likely to be active
    // (feedback_backend_collapse_blinds_telemetry.md, c4f8d2). MUST stay in
    // sync with the server HIGH_PRIORITY_OP_TYPES (twin test).
    'progress_restore_demotion_declined',
    'progress_restore_field_malformed',

    // The declined-advance stale-rows signal (OI-85). B-pass finding 4: OI-85's
    // whole plan is "measure the frequency before building a repair", and a
    // LOW-priority event is dropped by the client cooldown — so the measurement
    // would be biased exactly when the condition is most likely. MUST stay in
    // sync with the server HIGH_PRIORITY_OP_TYPES (twin test).
    'phase_advance_declined_rows_stale',
  ];

  /// Returns true when [opType] should bypass client-side rate-limit
  /// cooldown and always POST to the server.
  @visibleForTesting
  static bool isHighPriorityOpType(String? opType) {
    if (forceTreatAllAsLowPriorityForTest) return false;
    if (opType == null || opType.isEmpty) return false;
    for (final marker in highPriorityOpTypes) {
      if (marker.endsWith('_')) {
        if (opType.startsWith(marker)) return true;
      } else {
        if (opType == marker) return true;
      }
    }
    return false;
  }

  /// Returns true when we are currently inside a server-signalled
  /// cooldown window. LOW-priority `logEvent` calls drop on true.
  static bool _isCooldownActive() {
    final until = rateLimitedUntil;
    if (until == null) return false;
    if (DateTime.now().toUtc().isAfter(until)) {
      // Window expired — clear so the next call resumes normal posting.
      rateLimitedUntil = null;
      return false;
    }
    return true;
  }

  /// Honor `{rate_limited: true}` from the server.
  ///
  /// Called from both `recordNonFatal` and `logEvent` after a successful
  /// `callFunction` return. The `data` argument is the JSON body of the
  /// 200 response. We parse `next_window_at` (ISO 8601) and set the
  /// cooldown; on parse failure we use a 1h fallback so we still get
  /// SOME relief from the spam.
  static void _maybeHonorRateLimit(dynamic data) {
    if (data is! Map) return;
    if (data['rate_limited'] != true) return;
    final raw = data['next_window_at'];
    DateTime? until;
    if (raw is String && raw.isNotEmpty) {
      until = DateTime.tryParse(raw)?.toUtc();
    }
    rateLimitedUntil =
        until ?? DateTime.now().toUtc().add(_fallbackCooldown);
  }

  /// Record a non-fatal error. Fire-and-forget — never throws.
  ///
  /// Posts to Firebase Crashlytics with `fatal: false` and to the
  /// `log-client-error` Edge Function. Both legs are independently
  /// best-effort; either failing does not affect the other.
  ///
  /// Crashlytics ALWAYS runs (even when the server is rate-limited) —
  /// it's a separate sink with its own budget. Only the server POST is
  /// gated by the cooldown.
  static Future<void> recordNonFatal(
    Object error,
    StackTrace? stack, {
    required String reason,
    Map<String, String>? extra,
  }) async {
    // Crashlytics leg.
    if (!kDebugMode) {
      try {
        if (extra != null) {
          for (final entry in extra.entries) {
            try {
              await FirebaseCrashlytics.instance
                  .setCustomKey(entry.key, entry.value);
            } catch (_) {
              // Per-key failure must not block recordError.
            }
          }
        }
        await FirebaseCrashlytics.instance.recordError(
          error,
          stack,
          reason: reason,
          fatal: false,
        );
      } catch (_) {
        // Crashlytics swallow — telemetry must never throw.
      }
    }

    // log-client-error leg.
    //
    // `reason` here doubles as `op_type` server-side. recordNonFatal is
    // reserved for actual exceptions, so we treat them as HIGH-priority
    // by default — but still defer to `isHighPriorityOpType` so the
    // allowlist is a single source of truth.
    if (!isHighPriorityOpType(reason) && _isCooldownActive()) {
      // LOW-priority + cooldown active → drop. Crashlytics already
      // captured the fatal:false event above, so this is purely a
      // server-side row save we're skipping.
      return;
    }
    try {
      final raw = error.toString();
      final message = raw.length > 500 ? raw.substring(0, 500) : raw;
      final code = error.runtimeType.toString();
      final resp = await SupabaseService.instance.callFunction(
        'log-client-error',
        body: {
          'error_code': code.isEmpty ? 'UnknownError' : code,
          'error_message': message,
          'op_type': reason,
          'retry_count': 0,
          'client_version': _currentClientVersion(),
          'platform': _currentPlatform(),
        },
      );
      _maybeHonorRateLimit(resp.data);
    } catch (_) {
      // log-client-error swallow — telemetry must never throw.
    }
  }

  /// Log a structured product event keyed by [opType]. Fire-and-forget.
  ///
  /// Posts only to the `log-client-error` Edge Function (which doubles as
  /// the `client_errors` event sink). Use `recordNonFatal` instead when
  /// you have an actual `Object error` + stack trace.
  ///
  /// LOW-priority op_types are dropped client-side when a cooldown is
  /// active. HIGH-priority op_types (per [isHighPriorityOpType]) always
  /// post — the server's priority lane inserts them past the budget.
  static Future<void> logEvent(
    String opType, {
    String? message,
  }) async {
    if (debugOnLogEventForTests != null) {
      debugOnLogEventForTests!(opType, message: message);
      return;
    }
    // Cooldown gate — drop LOW-priority events without the network
    // round-trip. HIGH-priority events fall through and post normally.
    if (!isHighPriorityOpType(opType) && _isCooldownActive()) {
      return;
    }
    try {
      final raw = message ?? '';
      final cap = raw.length > math.min(500, raw.length) ? 500 : raw.length;
      final capped = raw.substring(0, cap);
      final resp = await SupabaseService.instance.callFunction(
        'log-client-error',
        body: {
          'error_code': 'event',
          'error_message': capped,
          'op_type': opType,
          'retry_count': 0,
          'client_version': _currentClientVersion(),
          'platform': _currentPlatform(),
        },
      );
      _maybeHonorRateLimit(resp.data);
    } catch (_) {
      // Swallow — events must never break the host flow.
    }
  }

  static String _currentPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {/* Platform unavailable on web */}
    return 'web';
  }

  /// Audit 2026-05-12 P2-A — was hardcoded '0.0.0+release' which prevented
  /// correlating client_errors rows to APK builds. Now reads AppConstants
  /// .appVersion (kept in sync with pubspec.yaml `version:` field).
  static String _currentClientVersion() {
    return kDebugMode ? '${AppConstants.appVersion}+dev' : AppConstants.appVersion;
  }
}
