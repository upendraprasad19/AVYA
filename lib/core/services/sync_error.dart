/// Typed sync failure classification.
///
/// Every `SyncService` method returns `Result<void, SyncError>` (see
/// `result.dart`) so callers can react to specific failure modes instead
/// of swallowing opaque exceptions into `debugPrint`.
///
/// Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar A.
library;

/// Base class for all sync failures. Use the `SyncError.classify()`
/// factory to convert caught exceptions into one of the concrete subtypes.
sealed class SyncError {
  /// Stable string identifier sent to the server telemetry sink
  /// (`log-client-error` Edge Function). Must match the Edge Function's
  /// `VALID_ERROR_CODES` allowlist.
  String get code;

  /// Human-readable detail. Safe to log locally; sent to server only on
  /// dead-letter. Never surfaced verbatim to the user — map to actionable
  /// copy in `sync_state_provider.dart`.
  final String? message;

  /// When the error was observed. Used for backoff math and for the
  /// pending-sync-queue retry schedule.
  final DateTime at;

  const SyncError({this.message, required this.at});

  /// True if retrying (with backoff) could plausibly succeed later.
  /// - Network / rate-limit / auth / unknown → retry
  /// - Validation / schema → pointless to retry; dead-letter immediately
  bool get isTransient;

  /// Build a `SyncError` from a caught exception. Inspects the error type
  /// and message to choose the most specific subtype. Falls back to
  /// `UnknownError` preserving the raw string.
  static SyncError classify(Object err) {
    final now = DateTime.now();
    final s = err.toString();
    final lower = s.toLowerCase();

    // Auth / JWT errors
    if (lower.contains('jwt') ||
        lower.contains('unauthorized') ||
        lower.contains('invalid token') ||
        lower.contains('expired') && lower.contains('token') ||
        lower.contains('403') ||
        lower.contains('401')) {
      return AuthError(message: s, at: now);
    }

    // Network / connectivity
    if (lower.contains('socketexception') ||
        lower.contains('connection') ||
        lower.contains('network') ||
        lower.contains('timeout') ||
        lower.contains('dns') ||
        lower.contains('unreachable')) {
      return NetworkError(message: s, at: now);
    }

    // Rate limit
    if (lower.contains('429') || lower.contains('rate limit')) {
      return RateLimitError(message: s, at: now);
    }

    // Schema issues (pg error codes 42703 unknown column, 42P01 table missing,
    // or Supabase REST reporting the same)
    if (lower.contains('42703') ||
        lower.contains('42p01') ||
        lower.contains('column') && lower.contains('does not exist') ||
        lower.contains('relation') && lower.contains('does not exist')) {
      return SchemaError(message: s, at: now);
    }

    // PostgREST 400 validation (check constraints, not-null violations).
    // Use 23xxx PG error codes and 400 status strings as hints.
    if (lower.contains('23502') ||
        lower.contains('23503') ||
        lower.contains('23505') ||
        lower.contains('23514') ||
        lower.contains('400') && lower.contains('bad request')) {
      return ValidationError(message: s, at: now);
    }

    return UnknownError(message: s, at: now);
  }

  @override
  String toString() => '$code${message == null ? '' : ': $message'}';
}

/// No route to host, DNS failure, socket timeout, offline. Retryable.
class NetworkError extends SyncError {
  const NetworkError({super.message, required super.at});
  @override
  String get code => 'NetworkError';
  @override
  bool get isTransient => true;
}

/// 401/403 — JWT expired or RLS policy denied. Retryable after auth refresh.
class AuthError extends SyncError {
  const AuthError({super.message, required super.at});
  @override
  String get code => 'AuthError';
  @override
  bool get isTransient => true;
}

/// 400 — payload rejected by Postgres (constraint violation, type mismatch).
/// Retrying with the same payload will always fail — dead-letter immediately.
class ValidationError extends SyncError {
  const ValidationError({super.message, required super.at});
  @override
  String get code => 'ValidationError';
  @override
  bool get isTransient => false;
}

/// Schema mismatch — column or table missing (e.g. migration didn't run,
/// client ahead of server). Not retryable from the client side.
class SchemaError extends SyncError {
  const SchemaError({super.message, required super.at});
  @override
  String get code => 'SchemaError';
  @override
  bool get isTransient => false;
}

/// 429 — too many requests. Retryable with longer backoff.
class RateLimitError extends SyncError {
  const RateLimitError({super.message, required super.at});
  @override
  String get code => 'RateLimitError';
  @override
  bool get isTransient => true;
}

/// Any other failure. Preserves the raw error body for server triage.
/// Retryable by default since we don't know what it is.
class UnknownError extends SyncError {
  const UnknownError({super.message, required super.at});
  @override
  String get code => 'UnknownError';
  @override
  bool get isTransient => true;
}
