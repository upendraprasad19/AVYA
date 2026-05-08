import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

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
class ErrorTelemetry {
  ErrorTelemetry._();

  /// Record a non-fatal error. Fire-and-forget — never throws.
  ///
  /// Posts to Firebase Crashlytics with `fatal: false` and to the
  /// `log-client-error` Edge Function. Both legs are independently
  /// best-effort; either failing does not affect the other.
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
    try {
      final raw = error.toString();
      final message = raw.length > 500 ? raw.substring(0, 500) : raw;
      final code = error.runtimeType.toString();
      await SupabaseService.instance.callFunction(
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
    } catch (_) {
      // log-client-error swallow — telemetry must never throw.
    }
  }

  /// Log a structured product event keyed by [opType]. Fire-and-forget.
  ///
  /// Posts only to the `log-client-error` Edge Function (which doubles as
  /// the `client_errors` event sink). Use `recordNonFatal` instead when
  /// you have an actual `Object error` + stack trace.
  static Future<void> logEvent(
    String opType, {
    String? message,
  }) async {
    try {
      final raw = message ?? '';
      final cap = raw.length > math.min(500, raw.length) ? 500 : raw.length;
      final capped = raw.substring(0, cap);
      await SupabaseService.instance.callFunction(
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

  static String _currentClientVersion() {
    return kDebugMode ? '0.0.0+dev' : '0.0.0+release';
  }
}
