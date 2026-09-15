// lib/core/services/sync_domain.dart
//
// Sealed contract for one Sync domain. Introduced by tech-debt audit
// 2026-05-20 / finding A6 to make the recurring restore-vs-sync drift
// bug class structurally enforceable.
//
// Background
// ----------
// `lib/core/services/sync_service.dart` (1394 lines) plus 8 `part of`
// files (~5577 total lines) historically hosted every sync + restore
// helper as private methods on the singleton `SyncService` class. The
// pattern was "write a `_syncX` and remember to also write `_restoreX`"
// — purely a convention. Test #12.8 caught 16-of-16 `_restoreXxx`
// methods that wrote the wrong Hive shape because the symmetry was
// never compile-checked, only retroactively verified by
// `test/contracts/restore_round_trip_field_coverage_test.dart`.
//
// Scaffold intent
// ---------------
// This file is the foundation of the multi-batch SyncService
// extraction. The full migration replaces the 8 `part of` files with
// independent top-level classes that each implement [SyncDomain]; the
// SyncService singleton then holds a `List<SyncDomain>` and dispatches.
// That migration is staged across multiple batches because the
// part-files share intricate state via private members on SyncService.
//
// The first proof-of-pattern is
// `lib/core/services/sync_domains/streaks_sync_domain.dart` which
// wraps the existing `SyncService._syncStreaks` + `_restoreStreaks`
// pair as a [SyncDomain]. Existing call sites continue to invoke the
// private methods directly via `part of` until each domain is
// individually migrated.
//
// See diagnose-doc:
//   docs/diagnoses/2026-05-21-sync-domain-scaffold-A6-<hash>.md

/// One symmetric sync surface (workout / nutrition / health / custom /
/// coach / streak / community / profile / templates).
///
/// Implementations MUST honour:
///   * [push] performs the local → cloud direction (formerly the
///     `_syncXxx` helper on the SyncService class). May upsert one or
///     more Hive-side rows into the matching Supabase table(s).
///   * [restore] performs the cloud → local direction (formerly the
///     `_restoreXxx` helper). Idempotent — repeated calls must converge
///     on the same local state.
///   * [pushSnapshot] is an OPTIONAL secondary push of a subset of
///     fields for the AI snapshot path (defaults to no-op via the
///     [SyncDomainBase] mixin). Domains that participate in
///     `user_daily_snapshot.snapshot_json` override it.
///
/// The matched-pair contract — every [push] must have a matching
/// [restore] — is the explicit guard against the Test #12.8 drift
/// class. The behavioural test
/// `test/contracts/sync_domain_interface_test.dart` enforces that the
/// list of registered domain implementations is exhaustive over the
/// `_syncX` / `_restoreX` pairs actually present in
/// `sync_service.dart`.
///
/// Implementations should `extends SyncDomainBase` (mixes in the
/// [pushSnapshot] no-op default) and override [name], [push], and
/// [restore]. Direct `implements SyncDomain` is fine but then the
/// implementer is responsible for providing every method including
/// [pushSnapshot].
abstract interface class SyncDomain {
  /// Stable identifier — used by telemetry (`op_type`) and by the
  /// exhaustiveness test. Convention: lower_snake_case matching the
  /// `_safeRestoreOp(<name>, ...)` string in [SyncService] (e.g.
  /// `'streaks'`, `'workout_logs'`, `'nutrition_logs'`).
  String get name;

  /// Local → cloud push. Wraps the legacy `_syncXxx` private method.
  /// MUST be fire-and-forget safe — exceptions are caught and routed
  /// through `ErrorTelemetry.recordNonFatal` per H-42.
  Future<void> push();

  /// Cloud → local restore. Wraps the legacy `_restoreXxx` private
  /// method. MUST be idempotent — called from `restoreFromCloudForUser`
  /// on every cold start.
  Future<void> restore();

  /// Optional snapshot-tier push (subset of fields for AI context).
  /// Default no-op via [SyncDomainBase]; domains that emit into
  /// `user_daily_snapshot.snapshot_json` override.
  Future<void> pushSnapshot();
}

/// Convenience base class that supplies the no-op [pushSnapshot]
/// default. Most domains do not participate in the AI snapshot path
/// and can `extends SyncDomainBase` to satisfy the [SyncDomain]
/// interface with only [name] / [push] / [restore] overrides.
abstract class SyncDomainBase implements SyncDomain {
  const SyncDomainBase();

  @override
  Future<void> pushSnapshot() async {
    // No-op default. Domains that participate in
    // `user_daily_snapshot.snapshot_json` override.
  }
}
