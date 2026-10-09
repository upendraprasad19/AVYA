/// Typed sync failure classification.
///
/// Every `SyncService` method returns `Result<void, SyncError>` (see
/// `result.dart`) so callers can react to specific failure modes instead
/// of swallowing opaque exceptions into `debugPrint`.
///
/// Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar A.
library;

/// Offline-network noise signature (B2a-2b, diagnose — see
/// docs/diagnoses/, coupling risk named by d2c9f4's impact_analysis).
/// Mirrors migration 147's `alert_client_errors_spike` exclusion signature
/// BYTE-FOR-BYTE (see
/// supabase/migrations/147_alert_client_errors_spike_breadth.sql) — the
/// server-side alert and this client-side classification must agree on
/// what counts as "offline noise" or the two sides of the same signal
/// classify differently. Pinned by
/// test/contracts/offline_signature_migration_147_parity_test.dart, which
/// re-derives both sides from the migration file so drift is caught rather
/// than silent (an applied migration is immutable, so if this ever needs
/// to change, it can only be via a NEW migration re-defining the job).
final RegExp _offlineNoiseSignature = RegExp(
  r'(failed host lookup|socketexception|connection (refused|reset|closed|abort)|network is unreachable|software caused connection abort|failed to fetch|load failed|xmlhttprequest error)',
  caseSensitive: false,
);

/// Never-offline override — a real HTTP status code. Case-insensitive in
/// the migration (`~*`), mirrored the same way here.
final RegExp _offlineNoiseStatusOverride = RegExp(
  r'status(Code)?: ?[1-9][0-9]{2}',
  caseSensitive: false,
);

/// Never-offline override — a server-answered Supabase exception type.
/// Case-SENSITIVE in the migration (`~`, not `~*`) — mirrored the same way
/// here; do not add `caseSensitive: false`.
final RegExp _offlineNoiseTypeOverride = RegExp(
  r'(PostgrestException|FunctionsHttpException|FunctionsRelayException|AuthApiException)',
);

/// True when [message] is shaped like offline-network connectivity loss
/// per migration 147's exact signature, with NO override (a real HTTP
/// status code, or one of the four server-answered exception types, which
/// mean a server DID answer and this is never network-loss noise).
///
/// Deliberately does NOT special-case a bare "timeout" — migration 147
/// does not exclude offline-caused client timeouts either (undercounting a
/// real incident is worse than occasionally counting a stalled request),
/// so this returns false for a timeout-only message, matching the SQL.
bool isOfflineNoiseSignature(String message) {
  if (!_offlineNoiseSignature.hasMatch(message)) return false;
  if (_offlineNoiseStatusOverride.hasMatch(message)) return false;
  if (_offlineNoiseTypeOverride.hasMatch(message)) return false;
  return true;
}

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

  /// True when this error's [message] matches migration 147's exact
  /// offline-noise signature (see [isOfflineNoiseSignature]) — i.e., the
  /// client and the alert_client_errors_spike alert classify this exact
  /// failure the SAME way. Null-safe: an error with no message is never
  /// offline-noise-shaped. This is broader-than-NetworkError-narrower: a
  /// NetworkError classified via a bare "timeout" is NOT offline-noise per
  /// this getter (matching the SQL), while it IS a NetworkError for retry
  /// purposes — the two classifications answer different questions.
  bool get isOfflineNoise => message != null && isOfflineNoiseSignature(message!);

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
