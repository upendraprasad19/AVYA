import 'dart:async';
import 'dart:convert' show jsonEncode;
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FunctionResponse;
import 'package:uuid/uuid.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/health_sync_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/plan_integrity_reconciler.dart';
import 'package:icanbefitter/core/services/streak_progress_service.dart';
import 'package:icanbefitter/core/services/result.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/services/sync_coalescer.dart';
import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/coach_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/community_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/health_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/nutrition_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/profile_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/restore_completeness_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/streaks_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_domains/workouts_sync_domain.dart';
import 'package:icanbefitter/core/services/sync_error.dart';
import 'package:icanbefitter/core/services/sync_flags.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/sync_queue.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/utils/equipment_vocab.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/models/coach_memory.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/profile/services/profile_write_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

part 'sync/sync_coach.dart';
part 'sync/sync_community.dart';
part 'sync/sync_health.dart';
part 'sync/sync_nutrition.dart';
part 'sync/sync_profile.dart';
part 'sync/sync_realtime.dart';
part 'sync/sync_restore_completeness.dart';
part 'sync/sync_workout.dart';

/// Result of a [SyncService.restoreFromCloudForUser] call.
class RestoreResult {
  final bool succeeded;
  final bool cancelled;
  final Object? error;

  RestoreResult.success()
      : succeeded = true,
        cancelled = false,
        error = null;

  RestoreResult.cancelled()
      : succeeded = false,
        cancelled = true,
        error = null;

  RestoreResult.failed(this.error)
      : succeeded = false,
        cancelled = false;
}

/// Handles background data sync between Hive (local) and Supabase (cloud).
///
/// Schedule:
///   - Immediately: custom foods/exercises (community contribution)
///   - Daily 11 PM IST: user_daily_snapshot for AI context
///   - Weekly (app launch if >7 days): full sync of all logs
///   - On restore (new device): pull full history from Supabase
/// APK Test #15.1 / Bug A — defensive int coercion for Hive map fields
/// whose cloud-side representation may be int, num, or String.
///
/// `_restoreWorkoutTemplates` historically stringified `prescribed_sets`
/// into the local Hive shape; home_screen + day_detail_sheet read it as
/// `int?` and crashed. Coerce at the writer instead of patching every
/// reader. Accepts int, num, String (parseable), or null → fallback.
///
/// closes-diagnose: 2026-05-12-schedule-int-coercion-a2f9e1
int _coerceInt(dynamic value, {required int fallback}) {
  if (value == null) return fallback;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed != null) return parsed;
  }
  return fallback;
}

/// C3 single-call restore (`restore-user-snapshot` EF) — sentinel for the
/// optional `preFetched` param on every gated `_restoreX` helper. When the
/// caller leaves the param at this sentinel the helper runs its existing
/// network query verbatim (the legacy / fallback / kill-switch path). When the
/// single-call orchestrator injects a bundle value INSTEAD (even an injected
/// `null` or `[]` — a legitimately-empty table), the network query is skipped
/// and the existing apply/parse/merge loop runs against the injected rows.
///
/// Distinguishing "not injected" from "injected null" requires a sentinel
/// (a plain `null` default cannot tell `coach_memory: null` in the bundle from
/// "caller wants a network fetch"). See plan `restore-single-call-c3.md` §4.
const Object _kNoInject = Object();

class SyncService {
  SyncService._() {
    _registerLifecycle();
    // H1a (Unit H, 2026-06-27) — flush owed trailing sync passes when the app
    // backgrounds (best-effort; the next login's full sweep is the backstop).
    _hive.onAppPaused = flushPendingSyncs;
  }
  static final SyncService _instance = SyncService._();

  /// DEBUG/SIM ONLY — when true, the heavy fire-and-forget [pushSnapshot]
  /// short-circuits. The year-simulation harness sets this during a bulk
  /// historical backfill (where every WriteService write would otherwise
  /// queue a full snapshot rebuild + cloud write, saturating the single web
  /// isolate) and fires ONE [pushSnapshot] at the end. Always false in normal
  /// operation; never set from production code paths.
  static bool pausedForSimulation = false;

  /// Tech-debt audit 2026-05-20 / A7 (B5 D9-D10) — prefer
  /// `ref.read(syncServiceProvider)` over `.instance`. The singleton
  /// path is preserved for non-Riverpod contexts (main.dart bootstrap,
  /// migrators); the Provider exposes the same instance with
  /// `ref.listen(authUserIdTokenProvider, …)` wiring so the
  /// SingletonLifecycleRegistry reset fires through Riverpod's
  /// lifecycle. A6 (commit d230301) wired SyncDomain wrappers; the
  /// provider simply exposes this singleton — internals unchanged.
  @Deprecated(
      'Use ref.read(syncServiceProvider) — singleton path will be removed after full migration')
  static SyncService get instance => _instance;

  /// Tech-debt audit 2026-05-20 / A7 — register cross-account reset
  /// hook so the singleton's in-memory state (queue init flag,
  /// realtime sub, restore-cancelled flag, health-sync completer,
  /// restore-progress label) is dropped when [HiveUserSession] flips
  /// to a new user. Public API unchanged — callers do not move.
  void _registerLifecycle() {
    SingletonLifecycleRegistry.register('SyncService', _onUserChanged);
  }

  /// A7 — invoked from [SingletonLifecycleRegistry.notifyUserChanged].
  /// Resets in-memory state that would otherwise leak across a user
  /// swap. Hive-backed timestamps (`last_snapshot_sync` etc.) live in
  /// `syncBox` (shared) so they are intentionally NOT reset here —
  /// the namespacing already scopes them by ownership at read time.
  void _onUserChanged() {
    // Drop realtime subscription so the next user does not receive
    // the previous user's broadcast events.
    try {
      _realtimeSubscription?.cancel();
    } catch (_) {
      // Subscription may already be cancelled; ignore.
    }
    _realtimeSubscription = null;

    // Complete any in-flight health-sync waiter so callers awaiting
    // the previous user's pass do not hang on the new user's session.
    final completer = _healthSyncCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    _healthSyncCompleter = null;

    // Reset restore-progress label to the cold-start default so the
    // next RestoringScreen mount does not flash stale copy from the
    // previous user's restore.
    restoreProgressLabel.value = 'Pulling your dispatch.';

    // Clear the inflight-cancellation flag. The previous user's
    // restore loop has already short-circuited; a fresh restore for
    // the new user must start from `false`.
    _restoreCancelled = false;

    // H1a — drop any owed trailing sync pass for the previous user so a
    // coalesced burst never lands under the new owner's session.
    _workoutCoalescer = SyncCoalescer();
    _nutritionCoalescer = SyncCoalescer();
    // H1b Part B1 (B-fix-1, GATING) — reset the snapshot coalescer too. An owed
    // trailing pushSnapshot under the NEW owner would mirror the PREVIOUS user's
    // coach_memory into the new owner's coachBox (auth_hive_owner_agreement
    // cross-account leak — strictly worse than the cost problem).
    _snapshotCoalescer = SyncCoalescer();
  }

  final HiveService _hive = HiveService.instance;
  final SupabaseService _supabase = SupabaseService.instance;

  /// H1a (Unit H) — coalescers for the fire-and-forget log syncs. A burst of
  /// per-write `syncWorkoutData()` / `syncNutritionData()` calls collapses to
  /// 1–2 cloud passes (the signup-storm fix). Reassigned on a user swap (see
  /// [_onUserChanged]) so an owed trailing pass never lands under the wrong
  /// owner. Kill-switch `disable_sync_debounce` bypasses both.
  SyncCoalescer _workoutCoalescer = SyncCoalescer();
  SyncCoalescer _nutritionCoalescer = SyncCoalescer();

  /// H1b Part B1 — coalescer for the fire-and-forget `pushSnapshot()` (~50
  /// callers each fire it after a write). A burst collapses to 1–2 EF calls.
  /// MUST be reassigned on a user swap (see [_onUserChanged]) — an owed trailing
  /// pass under the new owner would mirror the previous user's coach_memory into
  /// the new owner's `coachBox` (cross-account leak). Kill-switch
  /// `disable_snapshot_debounce` bypasses it.
  SyncCoalescer _snapshotCoalescer = SyncCoalescer();

  /// Defensive reads: a test may exercise a sync path without
  /// `HiveService.init()`; a missing configBox defaults each kill-switch to
  /// fix-active (the production default, since configBox is always open before
  /// `runApp`).
  bool get _syncDebounceDisabled {
    try {
      return _hive.configBox.get('disable_sync_debounce') == true;
    } catch (_) {
      return false;
    }
  }

  /// H3 (Unit H) — kill-switch reverting [pushSnapshot] to the pre-Unit-H raw
  /// `functions.invoke` (no cold-start retry).
  bool get _pushSnapshotViaCallFunctionDisabled {
    try {
      return _hive.configBox
              .get('disable_pushsnapshot_via_callfunction') ==
          true;
    } catch (_) {
      return false;
    }
  }

  /// H1b Part B1 — kill-switch reverting [pushSnapshot] to the verbatim
  /// pre-H1b direct (un-coalesced) [pushSnapshotNow]. Defensive read (see
  /// [_syncDebounceDisabled]).
  bool get _snapshotDebounceDisabled {
    try {
      return _hive.configBox.get('disable_snapshot_debounce') == true;
    } catch (_) {
      return false;
    }
  }

  /// C3 single-call restore — kill-switch reverting [restoreFromCloudForUser]
  /// to the verbatim legacy Step A/B/C fan-out (no `restore-user-snapshot` EF
  /// call). Honest rollback (plan §5): a LOCAL Hive config flag (never
  /// server-populated — there is no RemoteConfig); real levers are this flag,
  /// the automatic in-pass fallback, and a revert APK + web redeploy. Defensive
  /// read (see [_syncDebounceDisabled]).
  bool get _singleCallKillSwitch {
    try {
      return _hive.configBox.get('disable_single_call_restore') == true;
    } catch (_) {
      return false;
    }
  }

  /// H1b Part A — reserved user-scoped `workoutBox` key holding the
  /// `{scheduled_date: fingerprint}` index that lets an unchanged planned
  /// `scheduled_workouts` row skip its idempotent re-upsert (a returning login
  /// re-pushed ~96 rows the cloud already held). Sole writer+reader is
  /// [_syncScheduledWorkouts] so writer/reader drift is structurally
  /// impossible; the per-user box file IS the namespace, so it auto-clears on
  /// user-swap / sign-out / DPDP — no extra wiring.
  static const String _schedHashIndexKey = 'sync_sched_payload_hash_index';

  /// H1b Part A — kill-switch reverting [_syncScheduledWorkouts] to the verbatim
  /// pre-H1b unconditional full-sweep upsert (no fingerprint skip). Defensive
  /// read (see [_syncDebounceDisabled]).
  bool get _schedHashSkipDisabled {
    try {
      return _hive.configBox.get('disable_sched_hash_skip') == true;
    } catch (_) {
      return false;
    }
  }

  /// H1b Part A — stable fingerprint of the EXACT `scheduled_workouts` payload
  /// pushed to cloud. Serializes EVERY entry under a deterministic key sort
  /// (null → '') so any value change — and a present-vs-absent `template_id`
  /// (the key set differs) — flips the fingerprint and forces a re-push.
  /// Key-generic (not a fixed field list) so a future payload column is covered
  /// automatically — no forget-to-fingerprint drift. [_deterministicId] is UUID
  /// v5 (sha1-based) → STABLE across VMs/sessions (NOT `String.hashCode`, H-15).
  /// Pure; extracted for behavioral coverage.
  @visibleForTesting
  static String schedPayloadFingerprint(Map<String, dynamic> payload) {
    // Delimiter-SAFE canonical form: sorted keys → jsonEncode. JSON quotes +
    // escapes every value, so a literal `|`/`=`/`"` inside a value cannot alias
    // two distinct payloads (the prior `'$k=$v'.join('|')` form was
    // delimiter-ambiguous — review e7c1a9 P2 hardening).
    final sorted = <String, dynamic>{
      for (final k in payload.keys.toList()..sort()) k: payload[k],
    };
    return _deterministicId(jsonEncode(sorted));
  }

  /// H1b Part A — the skip decision for one `scheduled_workouts` row. True iff
  /// the idempotent re-upsert can be skipped because cloud already holds this
  /// exact payload. A `completed` row NEVER skips (A-fix-1: cloud can be
  /// silently stale per d9b2c5/B.1 and the resync migrator's one-shot flag makes
  /// a mis-skip PERMANENT). A null [storedFingerprint] (never pushed, or a prior
  /// push failed → store-on-200-only) never skips. Pure.
  @visibleForTesting
  static bool schedShouldSkipUpsert({
    required bool killSwitchDisabled,
    required String status,
    required String? storedFingerprint,
    required String currentFingerprint,
  }) {
    if (killSwitchDisabled) return false;
    if (status == 'completed') return false;
    return storedFingerprint != null &&
        storedFingerprint == currentFingerprint;
  }

  /// H1b Part A (A-fix-2) — the fingerprint index pruned to the schedule rows
  /// still present. A deleted date drops its entry so a later re-create
  /// re-pushes. Pure (returns a new map).
  @visibleForTesting
  static Map<String, String> schedPrunedHashIndex(
      Map<String, String> index, Set<String> liveDates) {
    return <String, String>{
      for (final e in index.entries)
        if (liveDates.contains(e.key)) e.key: e.value,
    };
  }

  /// H1a — best-effort flush fired on `AppLifecycleState.paused` (wired to
  /// [HiveService.onAppPaused] in the constructor). Runs the NON-coalesced
  /// variants so a burst that coalesced just before backgrounding still reaches
  /// cloud. Purely best-effort: Hive is the source of truth, so a missed flush
  /// is a delay (the next login's full sweep re-pushes), never data loss.
  void flushPendingSyncs() {
    if (pausedForSimulation) return;
    // Go THROUGH the coalescer (not the raw *Now()) so a flush that lands while
    // a pass is already draining sets _dirty for ONE trailing pass instead of
    // starting a concurrent second fan-out (B-pass P1, diagnose c4f8d2).
    unawaited(_workoutCoalescer.trigger(syncWorkoutDataNow));
    unawaited(_nutritionCoalescer.trigger(syncNutritionDataNow));
    // H1b Part B1 (B-fix-3) — best-effort snapshot flush on background. The real
    // durability guarantee is the eager `pushSnapshotNow()` carve-out (onboarding
    // + checkAndSync); web `paused` is unreliable, so this is necessary-not-
    // sufficient.
    unawaited(_snapshotCoalescer.trigger(pushSnapshotNow));
  }

  /// Tech-debt audit 2026-05-20 / A6 — registered [SyncDomain] wrappers
  /// for the 8 part-files. Each wrapper delegates to the existing
  /// `_syncX` / `_restoreX` private helpers via public forwarders on
  /// the corresponding `SyncServiceX` extension.
  ///
  /// THIS LIST IS NOT YET ACTIVE IN THE FAN-OUT. The legacy fan-out in
  /// `syncWorkoutData` / `weeklyFullSync` / `restoreFromCloudForUser`
  /// continues to call the private helpers directly. Each domain
  /// migrates to dispatch through this list on its own follow-up
  /// commit, gated behind `SyncFlags.useDomainFor(domain.name)`
  /// (default FALSE).
  ///
  /// Ordering matches the canonical fan-out so future dispatch loops
  /// preserve the documented ordering quirks (templates before
  /// schedules per APK Test #14 / Bug B.1; workout_plan before
  /// scheduled_workouts per Test #12.9).
  late final List<SyncDomain> _domains = [
    WorkoutsSyncDomain(syncService: this),
    StreaksSyncDomain(syncService: this),
    NutritionSyncDomain(syncService: this),
    HealthSyncDomain(syncService: this),
    CoachSyncDomain(syncService: this),
    ProfileSyncDomain(syncService: this),
    CommunitySyncDomain(syncService: this),
    RestoreCompletenessSyncDomain(syncService: this),
  ];

  /// A6 — exposed for the behavioural contract test
  /// (`test/contracts/sync_domain_full_migration_test.dart`). Returns
  /// the registered domain list; production callers do NOT iterate
  /// over this until per-domain [SyncFlags] are flipped.
  List<SyncDomain> get registeredDomainsForTests => _domains;

  /// A6 — internal dispatcher (NOT YET WIRED into the fan-out).
  ///
  /// Iterates `_domains` and calls `domain.push()` (or `restore()`)
  /// ONLY for domains whose [SyncFlags] gate has been flipped TRUE.
  /// Domains with the gate FALSE are skipped — the legacy `_syncX` /
  /// `_restoreX` calls in the existing fan-out cover them.
  ///
  /// This wrapper-landing batch (B5 D7-D8 of audit 2026-05-20) does
  /// NOT call these dispatchers from any fan-out site. The follow-up
  /// batch that flips the first flag is responsible for:
  ///   (a) inserting `await _dispatchDomainPushes()` /
  ///       `_dispatchDomainRestores()` at the appropriate fan-out
  ///       sites (after legacy parallel waits, before timestamp
  ///       update), AND
  ///   (b) deleting the legacy `_safeRestoreOp(...)` calls for the
  ///       domains being flipped — otherwise that domain double-syncs.
  ///
  /// Currently exercised by the contract test
  /// (`test/contracts/sync_domain_full_migration_test.dart`) under a
  /// transient flag flip with no signed-in user to assert short-circuit
  /// safety.
  @visibleForTesting
  Future<void> dispatchDomainPushesForTests() => _dispatchDomainPushes();

  @visibleForTesting
  Future<void> dispatchDomainRestoresForTests() => _dispatchDomainRestores();

  Future<void> _dispatchDomainPushes() async {
    for (final domain in _domains) {
      if (!SyncFlags.useDomainFor(domain.name)) continue;
      try {
        await domain.push();
      } catch (e, st) {
        debugPrint('[SyncService._dispatchDomainPushes] ${domain.name}: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_domain_push_${domain.name}'));
      }
    }
  }

  Future<void> _dispatchDomainRestores() async {
    for (final domain in _domains) {
      if (!SyncFlags.useDomainFor(domain.name)) continue;
      try {
        await domain.restore();
      } catch (e, st) {
        debugPrint('[SyncService._dispatchDomainRestores] ${domain.name}: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_domain_restore_${domain.name}'));
      }
    }
  }

  /// APK Test #12.7 — class fix for the "HiveUserSession not opened"
  /// silent-sync regression. Call this at the top of every public sync
  /// entry point that touches user-scoped boxes. Idempotent
  /// (`HiveUserSession.openForUser` returns immediately when the same
  /// id is already open). Returns the auth uid on success, or null when
  /// no Supabase session is live (caller should short-circuit).
  ///
  /// This closes the cold-start race where `pushSnapshot()` /
  /// `syncWorkoutData()` fire from `WorkoutWriteService` before
  /// `_ensureLocalUser` has run on the auth side — every box read used
  /// to throw `HiveUserSession not opened`, the `unawaited` swallowed
  /// the StateError, and the cloud silently received nothing.
  Future<String?> _ensureSessionOpen() =>
      HiveUserSession.ensureOpenedForCurrentSession();

  // ── Restore cancellation flag ───────────────────────────────

  /// Set to true by [cancelInflightRestore] to abort a running
  /// [restoreFromCloudForUser] call between restore steps.
  bool _restoreCancelled = false;

  /// Signals any in-flight [restoreFromCloudForUser] to abort between steps.
  /// Safe to call even if no restore is running.
  void cancelInflightRestore() {
    _restoreCancelled = true;
  }

  // ── Hive syncBox Keys ───────────────────────────────────────

  static const String _lastSnapshotKey = 'last_snapshot_sync';
  static const String _lastFullSyncKey = 'last_full_sync';
  static const String _lastCustomSyncKey = 'last_custom_sync';

  /// Duration between full syncs (1 day — safe because all upserts are idempotent).
  static const Duration _fullSyncInterval = Duration(days: 1); // daily full sync on app launch

  /// Deterministic UUID generator for sync IDs.
  /// Converts Hive keys (e.g. `wlog_1775500200000`) into stable UUIDs
  /// so repeated syncs don't create duplicate rows.
  static const _uuidGen = Uuid();
  static const _syncNamespace = '6ba7b810-9dad-11d1-80b4-00c04fd430c8';

  static String _deterministicId(String localKey) {
    return _uuidGen.v5(_syncNamespace, localKey);
  }

  /// APK Test #12.7 — true when [s] structurally looks like a v4/v5 UUID.
  /// 36 chars, hyphens at 8/13/18/23, hex elsewhere. Used by the coach
  /// sync path so server-already-UUID ids skip the v5 hashing detour.
  static bool _looksLikeUuid(String s) {
    if (s.length != 36) return false;
    if (s[8] != '-' || s[13] != '-' || s[18] != '-' || s[23] != '-') {
      return false;
    }
    for (var i = 0; i < s.length; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) continue;
      final c = s.codeUnitAt(i);
      final isDigit = c >= 0x30 && c <= 0x39;
      final isLowerHex = c >= 0x61 && c <= 0x66;
      final isUpperHex = c >= 0x41 && c <= 0x46;
      if (!isDigit && !isLowerHex && !isUpperHex) return false;
    }
    return true;
  }

  /// APK Test #12.8 / Bug #1 — mirror of
  /// [NutritionWriteService.computeLogKey] used by [_restoreNutritionLogs]
  /// so cloud→local round-trip collapses to the same Hive key as the
  /// original local write. Cannot reuse `computeLogKey` directly because
  /// it takes a typed `List<FoodItem>` and we restore from raw cloud
  /// maps.
  static String _nlogKeyForRestore({
    required String dateStr,
    required String mealType,
    required List<dynamic> items,
  }) {
    // Sort by name (case-insensitive trim) for stable hash regardless
    // of cloud row ordering.
    final pairs = <String>[];
    for (final raw in items) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final name = (m['name'] ?? m['food_name'] ?? '').toString();
      final qtyRaw = m['quantity_g'] ?? m['serving_g'];
      final qty = (qtyRaw is num) ? qtyRaw.toDouble() : 0.0;
      pairs.add('${name.toLowerCase().trim()}|${qty.toStringAsFixed(1)}');
    }
    pairs.sort();
    final joined = pairs.join(';');
    // H-15 (audit-2026-05-11) — `String.hashCode` is NOT guaranteed
    // stable across Dart VM versions / isolates / platforms. Two
    // devices running the same restore could compute different
    // 8-char tags for the same `(date, meal, items)` tuple → Hive
    // ends up with two rows for what should be one logical meal.
    // Switched to UUID v5 (deterministic, cross-platform stable);
    // take the first 8 hex chars to keep the Hive key compact and
    // visually similar to the previous shape.
    final hash = _uuidGen
        .v5(_syncNamespace, joined)
        .replaceAll('-', '')
        .substring(0, 8);
    return 'nlog_${dateStr}_${mealType}_$hash';
  }

  /// Namespace for custom-entity stable IDs (F8/F22).
  /// Must match the namespace used in `CreateCustomExerciseSheet` and
  /// `NutritionNotifier.addCustomFood`.
  static const _customEntityNamespace = '5a1f0b0c-9dad-11d1-80b4-00c04fd430c8';

  /// Deterministic id for a custom entity (exercise or food).
  /// Same (userId, type, lowercased name) → same id across devices.
  static String _customEntityId(String userId, String type, String name) {
    return _uuidGen.v5(
      _customEntityNamespace,
      '$userId|$type|${name.toLowerCase()}',
    );
  }

  // ── Sync Reliability (feature-flagged) ─────────────────────

  /// When true, failed Supabase writes are enqueued in `SyncQueue` and
  /// retried with exponential backoff. Dead-lettered failures are reported
  /// to the `log-client-error` Edge Function.
  ///
  /// When false (default): existing fire-and-forget behavior is preserved —
  /// failures are logged to `debugPrint` only. This is a safety flag for
  /// the sync-reliability rollout; flip to `true` after dark-launch
  /// validation.
  bool get _syncReliabilityEnabled =>
      _hive.configBox.get('sync_reliability_v1', defaultValue: false) as bool;

  /// One-time queue initialization — registers op executors and the
  /// dead-letter telemetry hook. Must be called AFTER Hive init and
  /// BEFORE any sync path runs. Safe to call multiple times (idempotent).
  bool _queueInitialized = false;
  void initQueue() {
    if (_queueInitialized) return;
    _queueInitialized = true;

    SyncQueue.instance.registerExecutor(
      'upsert_user_profile',
      _executeUserProfileUpsert,
    );

    SyncQueue.instance.onDeadLetter = _sendDeadLetterTelemetry;
  }

  /// Executor for `upsert_user_profile` ops. The payload is the full
  /// column map (keys already mirror `user_profile` column names).
  /// Returns a typed `Result` — success or classified `SyncError`.
  Future<Result<void, SyncError>> _executeUserProfileUpsert(
    Map<String, dynamic> payload,
  ) async {
    try {
      await _supabase.client
          .from('user_profile')
          .upsert(payload, onConflict: 'user_id')
          .select()
          .single();
      return Result.ok(null);
    } catch (e) {
      return Result.err(SyncError.classify(e));
    }
  }

  /// Posts a dead-letter record to `log-client-error` Edge Function.
  /// Non-fatal — telemetry failure is swallowed (queue has already
  /// removed the op).
  Future<void> _sendDeadLetterTelemetry(PendingSyncOp op) async {
    try {
      // BUG-C (d3a1c7): refresh the session before the authed EF invoke so a
      // stale access token doesn't 401 (telemetry was silently lost).
      await _supabase.ensureFreshToken();
      await _supabase.client.functions.invoke(
        'log-client-error',
        body: {
          'error_code': op.lastErrorCode ?? 'UnknownError',
          'error_message': op.lastErrorMessage,
          'op_type': op.opType,
          'retry_count': op.retryCount,
          'client_version': _currentClientVersion(),
          'platform': _currentPlatform(),
        },
      );
    } catch (e, st) {
      debugPrint('[SyncService] dead-letter telemetry failed: $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_send_dead_letter_telemetry'));
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

  /// Audit 2026-05-12 P2-A — was `0.0.0+release` hardcoded which prevented
  /// correlating client_errors rows to APK builds. Now reads from
  /// AppConstants.appVersion (kept in sync with pubspec.yaml version).
  /// kDebugMode override preserves the historical dev/release distinction.
  static String _currentClientVersion() {
    return kDebugMode ? '${AppConstants.appVersion}+dev' : AppConstants.appVersion;
  }

  // ── Public API ──────────────────────────────────────────────

  /// Active realtime subscription (PRO only, for Telegram cross-channel).
  StreamSubscription? _realtimeSubscription;

  /// Completes when health sync finishes (or immediately if disabled).
  /// The home screen awaits this to invalidate [todayStepsProvider] at
  /// exactly the right moment instead of guessing with a fixed delay.
  Completer<void>? _healthSyncCompleter;

  /// F5 · Broadcasts after `checkAndSync` completes a restore pass so
  /// screens can invalidate cached providers (PRs, plan, stats). Emits
  /// on every successful sync cycle, not just restore-from-empty.
  final StreamController<void> _restoreCompleteController =
      StreamController<void>.broadcast();
  Stream<void> get onRestoreComplete => _restoreCompleteController.stream;

  /// Bug 2026-05-19 (A4 progress text) — current label shown on
  /// RestoringScreen while `restoreFromCloudForUser` is running. Updated
  /// at the start of each step so the user gets a signal that progress
  /// is happening during long restores (>15s threshold for the existing
  /// CONTINUE escape CTA). RestoringScreen binds via ValueListenableBuilder.
  final ValueNotifier<String> restoreProgressLabel =
      ValueNotifier<String>('Pulling your dispatch.');

  /// Returns a Future that completes when the current health sync pass
  /// finishes writing to Hive. Returns an already-completed future when
  /// no sync is in progress or health sync is disabled.
  Future<void> get healthSyncDone =>
      _healthSyncCompleter?.future ?? Future.value();

  /// Called on every app launch. Determines what needs syncing and
  /// triggers the appropriate operations in the background.
  ///
  /// Never blocks the UI — failures are silently ignored.
  Future<void> checkAndSync() async {
    try {
      if (!_supabase.isAuthenticated) return;

      // APK Test #12.7 — defensive HiveUserSession bootstrap. Cold-start
      // path can land here before `_ensureLocalUser` ran (e.g. the
      // restoring screen kicks off other syncs in parallel). Without
      // this every user-scoped box read below throws
      // `HiveUserSession not opened` and the unawaited swallow nukes
      // the cloud upload silently.
      final userId = await _ensureSessionOpen();
      if (userId == null) return;

      // ── Health sync FIRST — steps/weight are fast local reads from
      // Health Connect and the user expects to see them immediately on
      // the home screen. All other sync tasks (restore, full sync,
      // snapshot push) are slower and can follow afterward.
      _healthSyncCompleter = Completer<void>();
      // Audit 2026-05-29 B2 — defensive web guard. The `health` plugin has
      // no web implementation; calling Health()/syncToHive on web throws
      // MissingPluginException. isEnabled() returns false on web today (no
      // permission ever granted), but guard explicitly so a future code
      // path that enables it can't crash the web build. Mirrors the
      // splash_screen `!kIsWeb && HealthSyncService.isEnabled()` guard.
      if (!kIsWeb && HealthSyncService.isEnabled()) {
        try {
          await HealthSyncService.instance.syncToHive();
          debugPrint('[SyncService.checkAndSync] Health sync completed '
              '(wroteData=${HealthSyncService.instance.lastSyncWroteData})');
        } catch (e, st) {
          debugPrint('[SyncService.checkAndSync] Health sync failed: $e');
          // audit-2026-05-11 H-42 — telemetry pair.
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'sync_service_check_and_sync'));
        }
      }
      // Null-safe: a concurrent user-switch (_resetForNewUser nulls
      // _healthSyncCompleter, line ~148) can land between the Completer
      // creation above and here, so the bare `!` threw
      // "_TypeError: Null check operator used on a null value" on the
      // check_and_sync path (diagnose c5e1b7). Read the local + guard.
      final hsc = _healthSyncCompleter;
      if (hsc != null && !hsc.isCompleted) {
        hsc.complete();
      }

      // Drain any telemetry failures that were queued during the previous
      // session because _reportSyncFailure itself hit a network error.
      unawaited(drainTelemetryQueue());

      // Backfill custom-entity ids for pre-F8/F22 entries. Runs at most
      // once — the scan is O(customBox.length) and quick.
      await _backfillCustomEntityIds();

      // On reinstall / new device: if Hive workout data is empty,
      // pull everything from Supabase first.
      await _restoreIfNeeded(userId);

      // Self-heal path for the silent onboarding-sync failures observed
      // 2026-04-17 on icanbefitter@gmail.com. If `completeOnboarding`
      // couldn't land the first two upserts (user_profile + user_progress),
      // it leaves `pending_onboarding_sync = true` in configBox. Replay
      // once per launch until it sticks.
      await _replayPendingOnboardingSync(userId);

      // Pull recent cross-channel logs (Telegram → Hive, last 24h).
      await pullRecentCrossChannelLogs();

      // Pull latest fitness_summary from Supabase → Hive (updated nightly by rolling-context).
      await _syncFitnessSummary(userId);

      // Check if a weekly full sync is needed.
      final lastFull = _getTimestamp(_lastFullSyncKey);
      if (lastFull == null ||
          DateTime.now().difference(lastFull) >= _fullSyncInterval) {
        await weeklyFullSync();
      }

      // Push any pending custom items immediately.
      await _syncCustomItems();

      // Push daily snapshot + trigger coaching notes extraction.
      // Idempotent: Edge Function upserts by (user_id, snapshot_date).
      // Includes: profile, progress, workouts, nutrition, water, steps,
      // weight, PRs, coaching notes — full AI context for reports/alerts.
      try {
        // H1b Part B1 (B-fix-2) — the next-login backstop MUST be durable; call
        // the non-coalesced *Now() so completion is awaited, not deferred to a
        // coalescer trailing pass.
        await pushSnapshotNow();
      } catch (e, st) {
        debugPrint('[SyncService.checkAndSync] Snapshot push failed: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch'));
        try {
          await _reportSyncFailure(opType: 'check_and_sync_snapshot', error: e);
        } catch (_) {}
      }

      // Pull approved community foods/exercises.
      await syncCommunityItems();

      // PRO users: subscribe to realtime for instant Telegram sync.
      if (SubscriptionService.instance.isPro()) {
        unawaited(subscribeToRealtimeSync());
      }

      // F5 · Broadcast restore-complete so screens can invalidate cached
      // providers (PRs recomputed from refreshed logs, plan from latest
      // templates, etc.).
      if (!_restoreCompleteController.isClosed) {
        _restoreCompleteController.add(null);
      }
    } catch (e, st) {
      // Offline or error — silently skip.
      // Ensure the health sync completer is resolved even on early failure
      // so the home screen doesn't hang.
      // Null-safe read-into-local (same race as the success path, diagnose
      // c5e1b7): a concurrent user-switch can null _healthSyncCompleter between
      // the check and the bare `!`.
      final hscErr = _healthSyncCompleter;
      if (hscErr != null && !hscErr.isCompleted) {
        hscErr.complete();
      }
      debugPrint('[SyncService.checkAndSync] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_2'));
      try {
        await _reportSyncFailure(opType: 'check_and_sync', error: e);
      } catch (_) {}
    }
  }

  /// Compiles a daily snapshot from Hive data for AI context injection.
  Map<String, dynamic> compileDailySnapshot() {
    final today = istDateStr(DateTime.now());
    final aiContext = AiCoachRepository.instance.buildAiContext();

    return {
      'snapshot_date': today,
      ...aiContext,
    };
  }

  /// H1b Part B1 — coalesced fire-and-forget snapshot entry. The ~50 per-write
  /// callers collapse to 1–2 `daily-snapshot` EF calls via [_snapshotCoalescer]
  /// instead of one invoke per write. Callers that need a DURABLE snapshot
  /// (onboarding first-context, the checkAndSync next-login backstop) MUST call
  /// [pushSnapshotNow] directly. Kill-switch `disable_snapshot_debounce` bypasses
  /// the coalescer (every call runs the full push — the pre-H1b behavior).
  Future<void> pushSnapshot() async {
    if (pausedForSimulation) return; // sim bulk-backfill (guard FIRST)
    if (_snapshotDebounceDisabled) {
      await pushSnapshotNow();
      return;
    }
    await _snapshotCoalescer.trigger(pushSnapshotNow);
  }

  /// Pushes the daily snapshot to Supabase via the `daily-snapshot` Edge
  /// Function. The function upserts `user_daily_snapshots`, runs coaching
  /// notes extraction, and returns the latest `coach_memory` row, which
  /// we mirror into Hive `coachBox['coach_memory']` for local readers.
  ///
  /// Non-coalesced — runs the full push NOW. Called by awaited/durable callers
  /// (onboarding first-context, the checkAndSync next-login backstop) and
  /// internally by [pushSnapshot]'s coalescer. Kept verbatim from the pre-H1b
  /// `pushSnapshot` (H3 callFunction routing + coach_memory mirror intact).
  Future<void> pushSnapshotNow() async {
    // Sim harness: suppress the per-write snapshot storm during a bulk
    // backfill; the harness fires one final pushSnapshot itself.
    if (pausedForSimulation) return;
    try {
      // APK Test #12.7 — open HiveUserSession before compiling the
      // snapshot. compileDailySnapshot() → AiCoachRepository.buildAiContext
      // touches every user-scoped box; without the bootstrap the call
      // throws StateError and the catch below swallows it.
      final userId = await _ensureSessionOpen();
      if (userId == null) return;

      final snapshot = compileDailySnapshot();

      // H3 (Unit H, 2026-06-27) — route through callFunction so a transient
      // cold-start 502/503/504 retries with backoff instead of failing on the
      // first attempt (was a raw `functions.invoke` with NO retry). callFunction
      // refreshes the token first — preserving the BUG-C (d3a1c7) fix where a
      // stale access token 401'd push_snapshot and dropped the plan_json /
      // coach_memory snapshot — so the explicit ensureFreshToken() here is now
      // redundant. Returns the full FunctionResponse; the coach_memory mirror
      // below still reads response.data. Kill-switch
      // `disable_pushsnapshot_via_callfunction` reverts to the raw invoke.
      final FunctionResponse response;
      if (_pushSnapshotViaCallFunctionDisabled) {
        await _supabase.ensureFreshToken();
        response = await _supabase.client.functions.invoke(
          'daily-snapshot',
          body: {'snapshot_json': snapshot},
        );
      } else {
        response = await _supabase.callFunction(
          'daily-snapshot',
          body: {'snapshot_json': snapshot},
        );
      }

      if (response.status != 200) {
        debugPrint(
          '[SyncService.pushSnapshot] non-200 from daily-snapshot: ${response.status}',
        );
      }

      // Mirror coach_memory from the response into Hive (Layer 4/5 identity).
      // Wrapped defensively — a malformed/changed schema must NEVER crash sync.
      if (response.status == 200 && response.data is Map) {
        // H1b review (e7c1a9, cross-account guard): if the session swapped to a
        // DIFFERENT user while this push was parked on its EF `await`, the
        // response carries the ORIGINAL user's coach_memory — mirroring it into
        // the now-current owner's coachBox is a cross-account leak. B-fix-1's
        // coalescer reset only drops an OWED trailing pass; it cannot cancel an
        // already-in-flight one. `currentUser?.id` is a SYNCHRONOUS getter and
        // there is no `await` between this check and the `_hive.coachBox`
        // resolution below, so the check + box resolution are atomic w.r.t. the
        // event loop (a swap can only land before the check → skip, or after the
        // box is resolved → writes the correct owner's box).
        if (_supabase.currentUser?.id != userId) {
          debugPrint(
            '[SyncService.pushSnapshotNow] session changed mid-push; '
            'skipping coach_memory mirror (cross-account guard)',
          );
        } else {
          try {
            final data = response.data as Map;
            final memJson = data['coach_memory'];
            if (memJson is Map) {
              final mem = CoachMemory.fromJson(memJson);
              await mem.writeToBox(_hive.coachBox);
              debugPrint(
                '[SyncService.pushSnapshot] coach_memory mirrored to Hive',
              );
            }
          } catch (memErr, st) {
            debugPrint(
              '[SyncService.pushSnapshot] coach_memory mirror failed: $memErr',
            );
            // audit-2026-05-11 H-42 — telemetry pair.
            unawaited(ErrorTelemetry.recordNonFatal(memErr, st,
                reason: 'sync_service_if_3'));
            try {
              await _reportSyncFailure(opType: 'mirror_coach_memory_from_snapshot', error: memErr);
            } catch (_) {}
          }
        }
      }

      await _setTimestamp(_lastSnapshotKey);
    } catch (e, st) {
      // Offline — will retry next scheduled run.
      debugPrint('[SyncService.pushSnapshot] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_catch_2'));
      try {
        await _reportSyncFailure(opType: 'push_snapshot', error: e);
      } catch (_) {}
    }
  }

  /// Pushes all workout logs, nutrition logs, weight logs, measurements,
  /// sleep logs, and streaks to Supabase.
  ///
  /// Triggered on app launch if >1 day since last full sync.
  Future<void> weeklyFullSync() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      // APK Test #14 / Bug B.1 — `_syncWorkoutTemplates` MUST complete
      // before `_syncScheduledWorkouts` starts, otherwise the schedule
      // upsert FK-references a parent row cloud doesn't have yet → 23503.
      // Pre-fix this was inside the parallel `Future.wait` and racy.
      // See docs/diagnoses/2026-05-10-fk-violation-saturday-c8e4a1.md.
      await _safeRestoreOp('sync_templates', _syncWorkoutTemplates(userId));

      await Future.wait(
        [
          _safeRestoreOp('sync_workouts', _syncWorkoutLogs(userId)),
          _safeRestoreOp('sync_exercises', _syncExerciseLogs(userId)),
          _safeRestoreOp('sync_schedule_completions', _syncScheduleCompletions(userId)),
          _safeRestoreOp('sync_nutrition', _syncNutritionLogs(userId)),
          _safeRestoreOp('sync_weight', _syncWeightLogs(userId)),
          _safeRestoreOp('sync_measurements', _syncMeasurements(userId)),
          _safeRestoreOp('sync_sleep', _syncSleepLogs(userId)),
          _safeRestoreOp('sync_steps', _syncStepsLogs(userId)), // F20
          _safeRestoreOp('sync_streaks', _syncStreaks(userId)),
          _safeRestoreOp('sync_user_profile', _syncUserProfile(userId)),
          _safeRestoreOp('sync_urine', _syncUrineColorLogs(userId)),
          _safeRestoreOp('sync_water', _syncWaterLogs(userId)),
          _safeRestoreOp('sync_workout_plan', _syncWorkoutPlan(userId)),
          _safeRestoreOp('sync_user_progress', _syncUserProgress(userId)),
          // ── New sync gap methods (templates run sequentially above) ──
          _safeRestoreOp('sync_scheduled_workouts', _syncScheduledWorkouts(userId)),
          _safeRestoreOp('sync_saved_meals', _syncSavedMeals(userId)),
          _safeRestoreOp('sync_preferences', _syncUserPreferences(userId)),
          _safeRestoreOp('sync_coach_interactions', _syncCoachInteractions(userId)),
          // ⑥ 6 B-pass P2-3 — periodic backstop: an offline-failed readiness
          // check-in push otherwise only retried on the NEXT check-in.
          _safeRestoreOp('sync_readiness', _syncReadiness(userId)),
        ],
        eagerError: false,
      );

      await _setTimestamp(_lastFullSyncKey);
    } catch (e, st) {
      // Partial sync failure — next launch will retry.
      debugPrint('[SyncService.weeklyFullSync] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_weekly_full_sync'));
      try {
        await _reportSyncFailure(opType: 'weekly_full_sync', error: e);
      } catch (_) {}
    }
  }

  // ── Workout-Specific Sync (callable after workout completion) ──

  // ── Restore from Cloud (reinstall / new device) ────────────────

  /// If `completeOnboarding` left `pending_onboarding_sync = true` in
  /// configBox, replay the Hive → Supabase push. Clears the flag on
  /// success; leaves it set for the next launch on failure.
  ///
  /// Safe no-op when:
  ///   - The flag is unset (normal healthy case).
  ///   - Hive has no profile row (logged out between attempts).
  ///
  /// This is the true safety net for the "user_profile stays all-NULL"
  /// failure mode that the inline 10 s retry misses when the user taps
  /// through to the Home screen before the retry fires.
  Future<void> _replayPendingOnboardingSync(String userId) async {
    try {
      final pending = MigratedKey.read<bool>('pending_onboarding_sync');
      if (pending != true) return;

      final profile = _hive.userBox.get('profile');
      final progress = _hive.userBox.get('progress');
      if (profile == null) {
        debugPrint('[SyncService._replayPendingOnboardingSync] '
            'flag set but Hive profile missing — clearing flag');
        await MigratedKey.delete('pending_onboarding_sync');
        return;
      }

      final p = Map<String, dynamic>.from(profile as Map);
      final pr = progress == null
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(progress as Map);

      await UserRepository.syncOnboardingToSupabase(
        userId: userId,
        userData: {
          'email': _supabase.currentUser?.email,
          'full_name': p['full_name'],
          'onboarding_completed': true,
          // UTC (Unit B, diagnose c4d8a2) — users.last_active_at is a timestamptz.
          'last_active_at': DateTime.now().toUtc().toIso8601String(),
        },
        profileData: {
          'date_of_birth': p['date_of_birth'],
          'gender': p['gender'],
          'height_cm': p['height_cm'],
          'current_weight_kg': p['current_weight_kg'],
          'target_weight_kg': p['target_weight_kg'],
          'primary_goal': p['primary_goal'],
          'fitness_experience': p['fitness_experience'],
          'days_per_week': p['days_per_week'],
          'equipment_access': p['equipment_access'],
          'activity_level': p['activity_level'],
          'lifestyle_activity': p['lifestyle_activity'],
          'pace_preference': p['pace_preference'],
          'diet_preference': p['diet_preference'],
          'injuries': p['injuries'] is List ? p['injuries'] : <String>[],
          'city': p['city'],
          'bmr': p['bmr'],
          'tdee': p['tdee'],
          'body_fat_percent': p['body_fat_percent'],
          'body_fat_assessed_at': p['body_fat_assessed_at'],
          'session_duration_minutes': p['session_duration_minutes'],
          'physique_focus': p['physique_focus'],
          'avatar_url': p['avatar_url'],
          'banner_url': p['banner_url'],
          'wake_up_time': p['wake_up_time'],
          'preferred_workout_time': p['preferred_workout_time'],
          'daily_calories': p['daily_calories'],
          'protein_grams': p['protein_grams'],
          'carbs_grams': p['carbs_grams'],
          'fat_grams': p['fat_grams'],
          'water_target_ml': p['water_target_ml'],
        },
        progressData: {
          'current_phase': pr['current_phase'] ?? 1,
          'current_week': pr['current_week'] ?? 1,
          'total_workouts_done': pr['total_workouts_done'] ?? 0,
          'current_streak_weeks': pr['current_streak_weeks'] ?? 0,
          'phase_started_at':
              pr['phase_started_at'] ?? DateTime.now().toIso8601String(),
          'plan_generated_at':
              pr['plan_generated_at'] ?? DateTime.now().toIso8601String(),
          'detected_experience_level': p['fitness_experience'],
        },
      );

      await MigratedKey.delete('pending_onboarding_sync');
      debugPrint('[SyncService._replayPendingOnboardingSync] success — flag cleared');
    } catch (e, st) {
      debugPrint('[SyncService._replayPendingOnboardingSync] failed: $e '
          '— flag left set; will retry next launch');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_4'));
      unawaited(_reportSyncFailure(
        opType: 'onboarding_sync_replay',
        error: e,
      ));
    }
  }

  /// Checks if local Hive is empty and restores from Supabase if so.
  /// Called automatically by checkAndSync() on app launch.
  Future<void> _restoreIfNeeded(String userId) async {
    // Check if there's any workout data locally. If workoutBox has
    // exercise logs or workout logs, the user hasn't reinstalled.
    bool hasLocalData = false;
    for (final key in _hive.workoutBox.keys) {
      if (key is String &&
          (key.startsWith('wlog_') || key.startsWith('exlog_'))) {
        hasLocalData = true;
        break;
      }
    }

    if (!hasLocalData) {
      await restoreFromCloud(userId);
    } else {
      // F6 · Even when Hive has workout data, pull lightweight pieces that
      // may have changed on another device or via an admin action —
      // custom items, templates, profile, progress. These are cheap
      // (small, indexed by user_id) and inexpensive to merge.
      await restoreLightweightAlways(userId);
    }
  }

  /// F6 · Lightweight restore that fires on every sign-in regardless of
  /// whether Hive has workout history. Pulls the small, frequently-drifting
  /// datasets: profile, progress, subscription-adjacent state, customs,
  /// templates. Bulk history (workout/nutrition logs) stays gated on
  /// empty-Hive so we don't re-download GBs every launch.
  Future<void> restoreLightweightAlways(String userId) async {
    try {
      await Future.wait(
        [
          _safeRestoreOp('user_profile', _restoreUserProfile(userId)),
          _safeRestoreOp('user_progress', _restoreUserProgress(userId)),
          _safeRestoreOp('custom_exercises', _restoreCustomExercises(userId)),
          _safeRestoreOp('custom_foods', _restoreCustomFoods(userId)),
          _safeRestoreOp('workout_templates', _restoreWorkoutTemplates(userId)),
          _safeRestoreOp('user_preferences', _restoreUserPreferences(userId)),
          // F38 (2026-06-07): re-anchor the workout plan on every returning-user
          // launch. A plan_start_date that advanced on another device was never
          // re-applied on a normal (non-empty-Hive) launch, leaving this device's
          // week number / day labels stale. _restoreWorkoutPlan is idempotent —
          // it applies the cloud plan_json via the completed-day-preserving
          // PlanIntegrityReconciler merge (diagnose a7d3f1).
          _safeRestoreOp('workout_plan', _restoreWorkoutPlan(userId)),
        ],
        eagerError: false,
      );
    } catch (e, st) {
      debugPrint('[SyncService.restoreLightweightAlways] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_lightweight_always'));
      try {
        await _reportSyncFailure(opType: 'restore_lightweight_always', error: e);
      } catch (_) {}
    }
  }

  /// Pulls all user data from Supabase into Hive.
  /// Used on reinstall/login when Hive is empty.
  ///
  /// Restores full history for ALL users (free + PRO).
  /// Storage per user is negligible (~1-2MB/year).
  Future<void> restoreFromCloud(String userId) async {
    try {
      // BUG-G (a7f2e9): refresh the session before a long multi-step restore so
      // its REST/EF calls don't 401 on a token that expires mid-restore (a heavy
      // account's restore can span the access token TTL). Cheap in-memory check
      // unless near expiry; never throws.
      await _supabase.ensureFreshToken();
      // Full restore for ALL users — no date limit. Data is already in Supabase
      // and storage per user is negligible (~1-2MB/year).
      const since = '2020-01-01T00:00:00Z';

      // APK Test #12.9 — _restoreWorkoutPlan must complete BEFORE
      // _restoreScheduledWorkouts so cloud-authoritative status='completed'
      // is the LAST writer to schedule_<date> keys. See
      // restoreFromCloudForUser for the full rationale.
      await _safeRestoreOp('workout_plan', _restoreWorkoutPlan(userId));

      await Future.wait(
        [
          _safeRestoreOp('workout_logs', _restoreWorkoutLogs(userId, since)),
          _safeRestoreOp('exercise_logs', _restoreExerciseLogs(userId, since)),
          _safeRestoreOp('schedule_completions', _restoreScheduleCompletions(userId, since)),
          _safeRestoreOp('custom_exercises', _restoreCustomExercises(userId)),
          _safeRestoreOp('custom_foods', _restoreCustomFoods(userId)),
          _safeRestoreOp('weight_logs', _restoreWeightLogs(userId, since)),
          _safeRestoreOp('steps_logs', _restoreStepsLogs(userId, since)), // F20
          _safeRestoreOp('nutrition_logs', _restoreNutritionLogs(userId, since)),
          _safeRestoreOp('measurements', _restoreMeasurements(userId, since)),
          _safeRestoreOp('user_profile', _restoreUserProfile(userId)),
          _safeRestoreOp('user_progress', _restoreUserProgress(userId)),
          _safeRestoreOp('water_logs', _restoreWaterLogs(userId, since)),
          _safeRestoreOp('sleep_logs', _restoreSleepLogs(userId, since)),
          _safeRestoreOp('readiness_daily', _restoreReadiness(userId, since)), // ⑥ 6-C
          _safeRestoreOp('streaks', _restoreStreaks(userId)),
          // ── New restore methods ──
          _safeRestoreOp('workout_templates', _restoreWorkoutTemplates(userId)),
          _safeRestoreOp('scheduled_workouts', _restoreScheduledWorkouts(userId, since)),
          _safeRestoreOp('saved_meals', _restoreSavedMeals(userId)),
          _safeRestoreOp('user_preferences', _restoreUserPreferences(userId)),
          _safeRestoreOp('coach_interactions', _restoreCoachInteractions(userId, since)),
          _safeRestoreOp('coach_memory', _restoreCoachMemory(userId)), // B7 — skip induction on returning device
        ],
        eagerError: false,
      );
    } catch (e, st) {
      // Partial restore is fine — app works offline with whatever we got.
      debugPrint('[SyncService.restoreFromCloud] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_restore_from_cloud'));
      try {
        await _reportSyncFailure(opType: 'restore_from_cloud', error: e);
      } catch (_) {}
    }
  }

  /// Cancellable restore used by [RestoringScreen].
  ///
  /// Returns [RestoreResult.success] when all steps complete,
  /// [RestoreResult.cancelled] if [cancelInflightRestore] was called between
  /// steps, or [RestoreResult.failed] on an unrecoverable error.
  ///
  /// The cancellation flag is reset at the start of each call so callers can
  /// safely call this multiple times.
  /// Obs 4 (2026-06-05): bumped after a background restore + post-restore heals
  /// settle, so a mounted home screen refreshes its cards from the now-updated
  /// Hive (offline-first background-restore — the user reached home before the
  /// cloud restore finished). Singleton-owned → survives RestoringScreen
  /// disposal. No-op for the default path (home mounts fresh after restore).
  final ValueNotifier<int> restoreCompletedTick = ValueNotifier<int>(0);

  /// Bump [restoreCompletedTick] — call after a background restore + heals.
  void bumpRestoreCompleted() => restoreCompletedTick.value++;

  Future<RestoreResult> restoreFromCloudForUser() async {
    _restoreCancelled = false;
    final userId = _supabase.currentUser?.id;
    if (userId == null) {
      return RestoreResult.failed('No authenticated user');
    }

    // Test #12.6 — defensive HiveUserSession bootstrap. Cold-start path
    // (splash → /restoring) does NOT call _ensureLocalUser, so the
    // user-scoped namespaced boxes (workoutBox / nutritionBox / etc.)
    // are not yet open when this method runs. Every restore op then
    // throws `HiveUserSession not opened — cannot wrap user-scoped box
    // "<name>"` from GuardedBox, surfacing as 30+ client_errors per cold
    // start.
    //
    // openForUser is documented as idempotent for the same id (line 67-94
    // of hive_user_session.dart returns immediately when
    // _currentOwnerFullId == userId), so it is safe to call here even if
    // _ensureLocalUser already ran. This closes the race regardless of
    // upstream caller ordering.
    try {
      await HiveUserSession.openForUser(userId);
    } catch (e, st) {
      debugPrint(
        '[SyncService.restoreFromCloudForUser] openForUser failed: $e',
      );
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_5'));
      return RestoreResult.failed(e);
    }

    // APK Test #12.8 — restore lifecycle event so we can correlate
    // post-restore symptoms (PRO pill stuck, profile blank) with
    // whether restore even ran. Pre-12.8 we had per-op
    // _reportSyncFailure but no "started/completed" bookend to detect
    // "restore never ran" cases.
    unawaited(ErrorTelemetry.logEvent('restore_started',
        message: 'userId=${userId.substring(0, 8)}'));

    // BUG-G (a7f2e9): proactively refresh before the long restore (see
    // restoreFromCloud). A heavy account's restore can span the access token's
    // TTL; refreshing up front avoids mid-restore 401s.
    await _supabase.ensureFreshToken();

    // Bug 2026-05-19 (A2 telemetry) — bracket every step with a Stopwatch
    // so the next post-mortem can pinpoint which step (and via A1 inside,
    // which op) is the actual long pole behind the >15s RestoringScreen.
    final swTotal = Stopwatch()..start();
    // A4 — reset progress label for this restore pass.
    restoreProgressLabel.value = 'Pulling your dispatch.';
    // C3 single-call restore — the path discriminator threaded into the final
    // `restore_completed` telemetry (plan §6): `singlecall` when the
    // `restore-user-snapshot` EF bundle was applied; `legacy_killswitch` when
    // the local kill-switch forced the legacy fan-out; `legacy_fallback` when a
    // single-call FAULT (EF error / non-200 / bad schema / a missing table key)
    // fell through to the legacy fan-out THIS pass. Set below.
    String restorePath = 'legacy_fallback';
    try {
      const since = '2020-01-01T00:00:00Z';

      // ── C3 single-call attempt (plan §2/§4/§5) ─────────────────────────
      // One `restore-user-snapshot` EF round-trip replaces the Step A/B/C
      // fan-out. FAIL-CLOSED (H-1/H-2): any fault falls through to the
      // verbatim legacy path below — a partial bundle is NEVER written as a
      // complete restore. Kill-switch bypasses the attempt entirely.
      if (_singleCallKillSwitch) {
        restorePath = 'legacy_killswitch';
      } else {
        final singleCallResult = await _attemptSingleCallRestore(userId, since);
        if (singleCallResult != null) {
          // Single-call applied the whole bundle (or was cancelled mid-apply):
          // its own `restore_completed` (success) was already emitted, or it
          // returns a cancellation. Either way this restore pass is DONE.
          swTotal.stop();
          return singleCallResult;
        }
        // null → single-call FAULT; restorePath stays 'legacy_fallback' and we
        // fall through to the legacy fan-out below (heals any clobber).
      }

      // Step A — profile + lightweight data
      if (_restoreCancelled) return RestoreResult.cancelled();
      restoreProgressLabel.value = 'Loading profile & plan';
      final swA = Stopwatch()..start();
      await Future.wait(
        [
          _safeRestoreOp('user_profile', _restoreUserProfile(userId)),
          _safeRestoreOp('user_progress', _restoreUserProgress(userId)),
          _safeRestoreOp('custom_exercises', _restoreCustomExercises(userId)),
          _safeRestoreOp('custom_foods', _restoreCustomFoods(userId)),
          _safeRestoreOp('workout_templates', _restoreWorkoutTemplates(userId)),
          _safeRestoreOp('user_preferences', _restoreUserPreferences(userId)),
          // APK Test #12.9 — moved from step B. _restoreWorkoutPlan
          // writes `schedule_*` keys from a frozen `plan_json.schedules`
          // snapshot (status='planned' for all days). _restoreScheduledWorkouts
          // (step B) overlays cloud-authoritative status='completed' from
          // the live `scheduled_workouts` table. Pre-12.9 both ran in
          // parallel via Future.wait; if `_restoreWorkoutPlan` won the
          // race it clobbered the completed status with stale 'planned'.
          // Sequential ordering (A before B) guarantees the live table
          // is the LAST writer and therefore wins.
          _safeRestoreOp('workout_plan', _restoreWorkoutPlan(userId)),
        ],
        eagerError: false,
      );
      swA.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=A ms=${swA.elapsedMilliseconds}'));

      // Step B — bulk history
      if (_restoreCancelled) return RestoreResult.cancelled();
      restoreProgressLabel.value = 'Catching up your history';
      final swB = Stopwatch()..start();
      await Future.wait(
        [
          _safeRestoreOp('workout_logs', _restoreWorkoutLogs(userId, since)),
          _safeRestoreOp('exercise_logs', _restoreExerciseLogs(userId, since)),
          _safeRestoreOp('schedule_completions', _restoreScheduleCompletions(userId, since)),
          _safeRestoreOp('weight_logs', _restoreWeightLogs(userId, since)),
          _safeRestoreOp('steps_logs', _restoreStepsLogs(userId, since)),
          _safeRestoreOp('nutrition_logs', _restoreNutritionLogs(userId, since)),
          _safeRestoreOp('measurements', _restoreMeasurements(userId, since)),
          _safeRestoreOp('water_logs', _restoreWaterLogs(userId, since)),
          _safeRestoreOp('sleep_logs', _restoreSleepLogs(userId, since)),
          _safeRestoreOp('readiness_daily', _restoreReadiness(userId, since)), // ⑥ 6-C
          _safeRestoreOp('streaks', _restoreStreaks(userId)),
          _safeRestoreOp('scheduled_workouts', _restoreScheduledWorkouts(userId, since)),
          _safeRestoreOp('saved_meals', _restoreSavedMeals(userId)),
          _safeRestoreOp('coach_interactions', _restoreCoachInteractions(userId, since)),
          _safeRestoreOp('coach_memory', _restoreCoachMemory(userId)), // B7 — skip induction on returning device; also pulls coaching_notes (A6)
        ],
        eagerError: false,
      );
      swB.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=B ms=${swB.elapsedMilliseconds}'));

      // Step C — restore-completeness surfaces (Theme A pull side).
      // These are smaller/faster operations run sequentially after bulk
      // history so a cancellation between steps doesn't leave Hive
      // in a partially-populated state.
      if (_restoreCancelled) return RestoreResult.cancelled();
      restoreProgressLabel.value = 'Finishing up';
      final swC = Stopwatch()..start();
      await _safeRestoreOp('freezes', _restoreFreezes(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('notifications_inbox', _restoreNotificationsInbox(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('saved_diet_plan', _restoreSavedDietPlan(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('rank_promotions', _restoreRankPromotions(userId));
      // E.10 (F4-S2 / audit 2026-05-16) — referral surfaces.
      // Codes survive reinstall + audit history visible cross-device.
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp('referral_codes', _restoreReferralCodes(userId));
      if (_restoreCancelled) return RestoreResult.cancelled();
      await _safeRestoreOp(
          'referral_redemptions', _restoreReferralRedemptions(userId));
      swC.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=C ms=${swC.elapsedMilliseconds}'));

      // A3 — Subscription refresh folded into restore as the atomic last
      // step so it's never skipped when the post-auth flow changes.
      // Fire-and-forget posture: failure keeps cached local PRO state
      // (consistent with existing refreshFromSupabase semantics).
      if (_restoreCancelled) return RestoreResult.cancelled();
      final swSub = Stopwatch()..start();
      try {
        await SubscriptionService.instance.refreshFromSupabase();
      } catch (e, st) {
        // Non-fatal — keep cached subscription state.
        debugPrint('[SyncService.restoreFromCloudForUser] subscription refresh error: $e');
        // audit-2026-05-11 H-42 — telemetry pair.
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_catch_3'));
        unawaited(_reportSyncFailure(
            opType: 'subscription_refresh_on_restore', error: e));
      }
      swSub.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=sub ms=${swSub.elapsedMilliseconds}'));

      if (_restoreCancelled) return RestoreResult.cancelled();
      swTotal.stop();
      // APK Test #12.8 — restore completion event. Counts every full
      // success path. If client_errors shows restore_started without a
      // matching restore_completed, the user had a silent abort
      // somewhere in steps A-C.
      unawaited(ErrorTelemetry.logEvent('restore_completed',
          message: 'userId=${userId.substring(0, 8)} status=success '
              'total_ms=${swTotal.elapsedMilliseconds} path=$restorePath'));
      return RestoreResult.success();
    } catch (e) {
      swTotal.stop();
      debugPrint('[SyncService.restoreFromCloudForUser] $e');
      try {
        await _reportSyncFailure(opType: 'restore_from_cloud_for_user', error: e);
      } catch (_) {}
      unawaited(ErrorTelemetry.logEvent('restore_completed',
          message: 'userId=${userId.substring(0, 8)} status=failed '
              'total_ms=${swTotal.elapsedMilliseconds} path=$restorePath'));
      return RestoreResult.failed(e);
    }
  }

  /// C3 single-call restore (plan `restore-single-call-c3.md` §2/§4/§5).
  ///
  /// Fetches the WHOLE gated-restore dataset in one `restore-user-snapshot` EF
  /// round-trip and applies it through the SAME `_restoreX` apply/merge loops
  /// the legacy fan-out uses (via the `preFetched` inject param) — preserving
  /// the per-row merge policy AND the shared-key write order (workout_plan →
  /// scheduled_workouts → schedule_completions on `schedule_<date>`;
  /// user_progress → freezes on `progress`) by running A→B→C SEQUENTIALLY.
  ///
  /// Returns:
  ///   • [RestoreResult.success] — bundle validated + fully applied (emits its
  ///     own `restore_completed status=success path=singlecall`).
  ///   • [RestoreResult.cancelled] — a cancel / owner-swap landed at an inter-step
  ///     checkpoint (H-7). The pre-write check (before Step A) discards the whole
  ///     snapshot with NO write; a cancel landing MID-batch lets the in-flight step
  ///     finish its writes (the next inter-step check then returns cancelled) — safe
  ///     because every restore write is additive/local-wins and the next login
  ///     re-restores. (B-pass P2 — accurate inter-step semantics.)
  ///   • `null` — a FAULT (H-1/H-2 fail-closed: callFunction throw / non-200 /
  ///     non-Map data / `schema_version != 1` / `tables` not a Map / ANY of the
  ///     29 expected keys ABSENT). The caller falls through to the verbatim
  ///     legacy fan-out THIS pass (a present key with a null/[] value is a
  ///     legitimately-empty table, NOT a fault).
  ///
  /// NEVER throws — a fault is signalled by returning `null`, so the caller's
  /// legacy path runs unharmed.
  Future<RestoreResult?> _attemptSingleCallRestore(
      String userId, String since) async {
    final sw = Stopwatch()..start();
    try {
      // ── Fetch (one round-trip; e8a1c3 auth via callFunction/fresh token) ──
      final FunctionResponse resp =
          await _supabase.callFunction('restore-user-snapshot');

      // ── FAIL-CLOSED validation (H-1/H-2) — extracted to the pure
      // `validatedSnapshotTables` helper so the partial-200 / missing-key /
      // bad-schema fault contract is BEHAVIORALLY pinned
      // (test/sync/restore_single_call_bundle_validation_test.dart). ─────────
      final Map? tables = validatedSnapshotTables(resp.status, resp.data);
      if (tables == null) {
        debugPrint('[SyncService._attemptSingleCallRestore] '
            'bundle validation failed (status=${resp.status}) → legacy fallback');
        return null;
      }

      // ── Cancellation + owner re-assert (H-7), BEFORE any Hive write ────
      // A StartMissionBrief/ResumeOnboarding cancel, or a fast account-switch
      // mid-call, must not write user A's bundle into user B's boxes.
      if (_restoreCancelled) return RestoreResult.cancelled();
      if (_supabase.currentUser?.id != userId) {
        debugPrint('[SyncService._attemptSingleCallRestore] '
            'owner changed mid-call → cancel (no write)');
        return RestoreResult.cancelled();
      }

      Object? row(String key) => tables[key];

      // ── Apply — SAME order as the legacy A→B→C fan-out ─────────────────
      // Step A (profile + lightweight; workout_plan LAST so the cloud-
      // authoritative scheduled_workouts overlay in Step B is the later
      // writer on schedule_<date> — APK Test #12.9).
      restoreProgressLabel.value = 'Loading profile & plan';
      final swA = Stopwatch()..start();
      await _safeRestoreOp(
          'user_profile',
          _restoreUserProfile(userId,
              preFetched: row('user_profile'),
              preFetchedUsers: row('users')));
      await _safeRestoreOp('user_progress',
          _restoreUserProgress(userId, preFetched: row('user_progress')));
      await _safeRestoreOp(
          'custom_exercises',
          _restoreCustomExercises(userId,
              preFetched: row('user_custom_exercises')));
      await _safeRestoreOp('custom_foods',
          _restoreCustomFoods(userId, preFetched: row('user_custom_foods')));
      await _safeRestoreOp(
          'workout_templates',
          _restoreWorkoutTemplates(userId,
              preFetched: row('workout_templates')));
      await _safeRestoreOp('user_preferences',
          _restoreUserPreferences(userId, preFetched: row('user_preferences')));
      await _safeRestoreOp('workout_plan',
          _restoreWorkoutPlan(userId, preFetched: row('workout_plan')));
      swA.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=A ms=${swA.elapsedMilliseconds} path=singlecall'));

      if (_restoreCancelled) return RestoreResult.cancelled();

      // Step B (bulk history; scheduled_workouts overlays the planned snapshot;
      // schedule_completions runs AFTER scheduled_workouts on schedule_<date>).
      restoreProgressLabel.value = 'Catching up your history';
      final swB = Stopwatch()..start();
      await _safeRestoreOp('workout_logs',
          _restoreWorkoutLogs(userId, since, preFetched: row('workout_logs')));
      await _safeRestoreOp(
          'exercise_logs',
          _restoreExerciseLogs(userId, since,
              preFetchedExercises: row('workout_log_exercises'),
              preFetchedSets: row('workout_log_sets')));
      await _safeRestoreOp('weight_logs',
          _restoreWeightLogs(userId, since, preFetched: row('weight_logs')));
      await _safeRestoreOp('steps_logs',
          _restoreStepsLogs(userId, since, preFetched: row('daily_steps')));
      await _safeRestoreOp(
          'nutrition_logs',
          _restoreNutritionLogs(userId, since,
              preFetched: row('nutrition_logs')));
      await _safeRestoreOp(
          'measurements',
          _restoreMeasurements(userId, since,
              preFetched: row('body_measurements')));
      await _safeRestoreOp('water_logs',
          _restoreWaterLogs(userId, since, preFetched: row('water_logs')));
      await _safeRestoreOp('sleep_logs',
          _restoreSleepLogs(userId, since, preFetched: row('sleep_logs')));
      // ⑥ 6-C (R2a P0-A) — readiness is deliberately NOT in the single-call
      // bundle (a missing bundle key would fail-closed the whole fast path
      // platform-wide). So it restores via a standalone network read HERE, on the
      // fast path, before the success return — else readiness is synced-but-never
      // -restored for most reinstalls. One extra read; the C3 speedup is intact.
      await _safeRestoreOp(
          'readiness_daily', _restoreReadiness(userId, since));
      await _safeRestoreOp(
          'streaks', _restoreStreaks(userId, preFetched: row('streaks')));
      await _safeRestoreOp(
          'scheduled_workouts',
          _restoreScheduledWorkouts(userId, since,
              preFetched: row('scheduled_workouts')));
      await _safeRestoreOp(
          'schedule_completions',
          _restoreScheduleCompletions(userId, since,
              preFetched: row('workout_schedule_completions')));
      await _safeRestoreOp('saved_meals',
          _restoreSavedMeals(userId, preFetched: row('user_saved_meals')));
      await _safeRestoreOp(
          'coach_interactions',
          _restoreCoachInteractions(userId, since,
              preFetched: row('ai_coach_interactions')));
      await _safeRestoreOp('coach_memory',
          _restoreCoachMemory(userId, preFetched: row('coach_memory')));
      swB.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=B ms=${swB.elapsedMilliseconds} path=singlecall'));

      if (_restoreCancelled) return RestoreResult.cancelled();

      // Step C (restore-completeness surfaces; freezes AFTER user_progress so
      // the refill-aware merge is the last writer on the `progress` key — H-6).
      restoreProgressLabel.value = 'Finishing up';
      final swC = Stopwatch()..start();
      await _safeRestoreOp(
          'freezes', _restoreFreezes(userId, preFetched: row('freezes')));
      await _safeRestoreOp(
          'notifications_inbox',
          _restoreNotificationsInbox(userId,
              preFetched: row('notifications_inbox')));
      await _safeRestoreOp('saved_diet_plan',
          _restoreSavedDietPlan(userId, preFetched: row('saved_diet_plan')));
      await _safeRestoreOp('rank_promotions',
          _restoreRankPromotions(userId, preFetched: row('rank_promotions')));
      await _safeRestoreOp('referral_codes',
          _restoreReferralCodes(userId, preFetched: row('referral_codes')));
      await _safeRestoreOp(
          'referral_redemptions',
          _restoreReferralRedemptions(userId,
              preFetched: row('referral_redemptions')));
      swC.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=C ms=${swC.elapsedMilliseconds} path=singlecall'));

      // ── Subscription refresh — SAME as the legacy path (H-3:
      // `subscriptions` is NOT in the bundle; refreshFromSupabase applies
      // grace-window / payment-in-progress / downgrade-suppression logic). ──
      if (_restoreCancelled) return RestoreResult.cancelled();
      final swSub = Stopwatch()..start();
      try {
        await SubscriptionService.instance.refreshFromSupabase();
      } catch (e, st) {
        // Non-fatal — keep cached subscription state (legacy posture).
        debugPrint('[SyncService._attemptSingleCallRestore] '
            'subscription refresh error: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_service_single_call_sub_refresh'));
        unawaited(_reportSyncFailure(
            opType: 'subscription_refresh_on_restore', error: e));
      }
      swSub.stop();
      unawaited(ErrorTelemetry.logEvent('restore_step_done',
          message: 'step=sub ms=${swSub.elapsedMilliseconds} path=singlecall'));

      if (_restoreCancelled) return RestoreResult.cancelled();
      sw.stop();
      unawaited(ErrorTelemetry.logEvent('restore_completed',
          message: 'userId=${userId.substring(0, 8)} status=success '
              'total_ms=${sw.elapsedMilliseconds} path=singlecall'));
      return RestoreResult.success();
    } catch (e, st) {
      // ANY throw → FAULT. Signal the caller to run the verbatim legacy path
      // THIS pass (H-2 fail-closed; the legacy ops are individually idempotent
      // and additive/local-wins, so they heal any partial single-call write).
      sw.stop();
      debugPrint('[SyncService._attemptSingleCallRestore] fault → '
          'legacy fallback: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_single_call_restore_fault'));
      return null;
    }
  }

  /// FAIL-CLOSED validation of the `restore-user-snapshot` bundle (plan §2/§5,
  /// H-1/H-2). Returns the `tables` map ONLY for a complete, well-formed bundle;
  /// returns `null` for ANY fault — a non-200 status, non-Map `data`, an
  /// unrecognised `schema_version`, a non-Map `tables`, or ANY of the 29 expected
  /// keys ABSENT. A partial bundle must NEVER be written as a complete restore;
  /// `null` makes the caller fall through to the verbatim legacy fan-out. A
  /// present key with a null/`[]` value is a legitimately-empty table, NOT a
  /// fault. Pure + `@visibleForTesting` so the fail-closed contract is pinned by
  /// a behavioral test rather than a source-grep (feedback_source_grep_false_confidence).
  @visibleForTesting
  static Map? validatedSnapshotTables(int status, Object? data) {
    if (status != 200) return null;
    if (data is! Map) return null;
    if (data['schema_version'] != 1) return null;
    final tables = data['tables'];
    if (tables is! Map) return null;
    for (final key in _kSingleCallBundleKeys) {
      if (!tables.containsKey(key)) return null; // ABSENT key = partial = fault
    }
    return tables;
  }

  /// The canonical single-call bundle keys, exposed so the fail-closed validation
  /// behavioral test asserts against the SAME source of truth the EF + validator
  /// use (no hard-coded copy that could drift).
  @visibleForTesting
  static List<String> get singleCallBundleKeys =>
      List<String>.unmodifiable(_kSingleCallBundleKeys);

  /// C3 single-call restore — the 29 table keys the `restore-user-snapshot`
  /// bundle MUST carry (H-2 fail-closed: an ABSENT key is a fault → legacy
  /// fallback; a present null/[] value is a legitimately-empty table). Keys are
  /// the cloud table names as emitted by the EF (NOT the Hive/`_restoreX`
  /// names). `subscriptions` is intentionally excluded (H-3).
  static const List<String> _kSingleCallBundleKeys = <String>[
    // LIST-valued (array of rows; limit-1 reads serialize as a 0/1-element array)
    'user_profile',
    'user_progress',
    'user_preferences',
    'workout_plan',
    'workout_templates',
    'user_custom_exercises',
    'user_custom_foods',
    'workout_logs',
    'workout_log_exercises',
    'workout_log_sets',
    'workout_schedule_completions',
    'weight_logs',
    'daily_steps',
    'nutrition_logs',
    'body_measurements',
    'water_logs',
    'sleep_logs',
    'streaks',
    'scheduled_workouts',
    'user_saved_meals',
    'ai_coach_interactions',
    'notifications_inbox',
    'rank_promotions',
    'referral_redemptions',
    // OBJECT-valued (single object or null from a maybeSingle/limit-1)
    'users',
    'coach_memory',
    'freezes',
    'saved_diet_plan',
    'referral_codes',
  ];

  // ── Fitness Summary Sync (rolling-context → Hive) ───────────

  /// Fetches the latest fitness_summary from user_daily_snapshots
  /// and writes it to coachBox. Updated nightly by rolling-context cron.
  Future<void> _syncFitnessSummary(String userId) async {
    try {
      final rows = await _supabase.client
          .from('user_daily_snapshots')
          .select('snapshot_json')
          .eq('user_id', userId)
          .not('snapshot_json->fitness_summary', 'is', null)
          .order('snapshot_date', ascending: false)
          .limit(1);

      if (rows.isNotEmpty) {
        final json = rows.first['snapshot_json'] as Map<String, dynamic>?;
        final summary = json?['fitness_summary'] as String?;
        if (summary != null && summary.isNotEmpty) {
          await _hive.coachBox.put('fitness_summary', summary);
        }
      }
    } catch (e, st) {
      debugPrint('[SyncService._syncFitnessSummary] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_if_6'));
      try {
        await _reportSyncFailure(opType: 'sync_fitness_summary', error: e);
      } catch (_) {}
    }
  }

  // ── Cross-Channel Sync (Telegram → Hive) ────────────────────

  /// Pulls logs from Supabase that were created in the last 24 hours
  /// from other channels (e.g. Telegram bot). Merges into local Hive
  /// without overwriting existing entries.
  Future<void> pullRecentCrossChannelLogs() async {
    try {
      final userId = _supabase.currentUser?.id;
      if (userId == null) return;

      final since =
          DateTime.now().subtract(const Duration(hours: 24)).toIso8601String();

      await Future.wait(
        [
          _safeRestoreOp('pull_weight', _pullWeightLogs(userId, since)),
          _safeRestoreOp('pull_nutrition', _pullNutritionLogs(userId, since)),
          _safeRestoreOp('pull_measurements', _pullMeasurements(userId, since)),
        ],
        eagerError: false,
      );
    } catch (e, st) {
      // Offline or error — silently skip.
      debugPrint('[SyncService.pullRecentCrossChannelLogs] $e');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_pull_recent_cross_channel_logs'));
      try {
        await _reportSyncFailure(opType: 'pull_cross_channel_logs', error: e);
      } catch (_) {}
    }
  }

  Future<void> _pullWeightLogs(String userId, String since) async {
    final res = await _supabase.client
        .from('weight_logs')
        .select()
        .eq('user_id', userId)
        .gte('created_at', since);

    final rows = res;
    final healthBox = _hive.healthBox;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final date = map['date'] as String? ?? '';
      final key = 'weight_$date';
      // Skip if already exists locally (Hive-first wins)
      if (healthBox.get(key) != null) continue;
      await healthBox.put(key, {
        'type': 'weight_log',
        'date': date,
        'weight_kg': map['weight_kg'],
        'created_at': map['created_at'],
        'source': 'telegram',
      });
    }
  }

  Future<void> _pullNutritionLogs(String userId, String since) async {
    final res = await _supabase.client
        .from('nutrition_logs')
        .select()
        .eq('user_id', userId)
        .gte('created_at', since);

    final rows = res;
    final nutritionBox = _hive.nutritionBox;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final id = map['id'] as String? ?? '';
      // Skip if already exists locally
      if (nutritionBox.get(id) != null) continue;
      await nutritionBox.put(id, {
        ...map,
        'source': map['source'] ?? 'telegram',
      });
    }
  }

  Future<void> _pullMeasurements(String userId, String since) async {
    final res = await _supabase.client
        .from('body_measurements')
        .select()
        .eq('user_id', userId)
        .gte('created_at', since);

    final rows = res;
    final healthBox = _hive.healthBox;
    for (final row in rows) {
      final map = Map<String, dynamic>.from(row as Map);
      final date = map['date'] as String? ?? '';
      final key = 'measurement_$date';
      // Merge — don't overwrite if exists (individual fields may differ)
      final existing = healthBox.get(key);
      if (existing is Map) {
        final merged = Map<String, dynamic>.from(existing);
        // Only fill in fields that are null locally
        for (final field in ['waist', 'chest', 'hips', 'arms']) {
          if (merged[field] == null && map[field] != null) {
            merged[field] = map[field];
          }
        }
        await healthBox.put(key, merged);
      } else {
        await healthBox.put(key, {
          ...map,
          'source': 'telegram',
        });
      }
    }
  }

  // ── Private Push Helpers ────────────────────────────────────

  /// Plan A A-5: normalize the per-set list across legacy `sets_detail`
  /// (had explicit `set_number`) and the new WorkoutWriteService `sets`
  /// shape (ordinal — set_number derived from index + 1).
  ///
  /// Returns a list of maps where each entry has at least `set_number`,
  /// `weight_kg`, `reps`. May also include `duration_seconds`,
  /// `duration_sec`, `distance_km`. Empty list → no per-set data
  /// available (fall back to summary-only).
  List<Map<String, dynamic>> _resolvePerSetList(Map<String, dynamic> log) {
    // Prefer legacy `sets_detail` (often has explicit set_number).
    // APK Test #12.2 / Task #7 — defensively stamp set_number from
    // index+1 if the entry lacks it. Cloud audit revealed users with
    // 33 workout_log_exercises rows but 0 workout_log_sets rows: the
    // per-set projection downstream filters entries with null
    // set_number, and pre-Test-#6 sets_detail entries may not carry
    // an explicit set_number. Stamping here unblocks per-set sync.
    final detail = log['sets_detail'];
    if (detail is List && detail.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      var idx = 0;
      for (final s in detail) {
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        if (m['set_number'] == null) {
          m['set_number'] = idx + 1;
        }
        out.add(m);
        idx += 1;
      }
      if (out.isNotEmpty) return out;
    }
    // Fallback to the new WorkoutWriteService shape: `sets` list of
    // {weight_kg, reps, duration_sec?, logged_at_ms} maps. Stamp
    // `set_number` from the array index (1-based).
    final newSets = log['sets'];
    if (newSets is List && newSets.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < newSets.length; i++) {
        final s = newSets[i];
        if (s is! Map) continue;
        final m = Map<String, dynamic>.from(s);
        m['set_number'] = i + 1;
        out.add(m);
      }
      return out;
    }
    return const [];
  }

  /// Public wrapper for [_reportSyncFailure] so other modules (e.g. the
  /// onboarding flow's custom catch block) can emit `client_errors`
  /// telemetry through the same code path.
  Future<void> reportSyncFailure({
    required String opType,
    required Object error,
    int retryCount = 0,
  }) => _reportSyncFailure(
        opType: opType,
        error: error,
        retryCount: retryCount,
      );

  /// Wraps a restore/sync future so one table failure cannot abort the others
  /// in a [Future.wait] call.
  ///
  /// On failure the error is logged locally and reported to `client_errors`
  /// via [_reportSyncFailure] with `opType = 'restore_<label>'`. The wrapper
  /// always completes normally so that `eagerError: false` propagation still
  /// works correctly (any remaining tasks in the wait list continue).
  Future<void> _safeRestoreOp(String label, Future<void> task) async {
    // Bug 2026-05-19 (A1 telemetry) — wrap with Stopwatch so client_errors
    // can answer "which restore op is the long pole." LOW-priority op_type
    // emitted on success; failure path keeps the pre-existing error report.
    final sw = Stopwatch()..start();
    try {
      await task;
      sw.stop();
      unawaited(ErrorTelemetry.logEvent(
        'restore_op_done',
        message: 'op=$label ms=${sw.elapsedMilliseconds}',
      ));
    } catch (e, st) {
      sw.stop();
      debugPrint('[sync/restore] $label failed: $e (${sw.elapsedMilliseconds}ms)');
      // audit-2026-05-11 H-42 — telemetry pair.
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sync_service_safe_restore_op'));
      try {
        await _reportSyncFailure(opType: 'restore_$label', error: e);
      } catch (_) {}
    }
  }

  // ── Telemetry failure queue ─────────────────────────────────
  // When _reportSyncFailure itself fails (network error, 5xx, etc.) the failure
  // was previously silently dropped. The queue below persists up to 50 entries
  // in syncBox and drains them on the next checkAndSync call (app launch).

  static const String _telemetryQueueKey = 'pending_telemetry_failures';
  static const int _telemetryQueueMax = 50;

  /// Enqueues a failed telemetry report so it can be retried on next launch.
  /// Last-resort — all exceptions are swallowed to prevent infinite recursion.
  Future<void> _enqueueTelemetryFailure(String opType, Object error) async {
    try {
      final queue =
          (_hive.syncBox.get(_telemetryQueueKey) as List?)?.cast<Map>().toList() ??
              [];
      final msg = error.toString();
      queue.insert(0, {
        'op_type': opType,
        'error': msg.substring(0, msg.length.clamp(0, 500)),
        'queued_at': DateTime.now().toIso8601String(),
      });
      // Cap at max to prevent unbounded Hive growth on persistent failures.
      while (queue.length > _telemetryQueueMax) {
        queue.removeLast();
      }
      await _hive.syncBox.put(_telemetryQueueKey, queue);
    } catch (_) {
      // Last-resort — truly silent.
    }
  }

  /// Drains the telemetry failure queue, retrying each entry via
  /// [_reportSyncFailure]. Entries that succeed are removed; those that still
  /// fail are re-enqueued for the following launch.
  ///
  /// Called fire-and-forget from [checkAndSync] on every app launch.
  Future<void> drainTelemetryQueue() async {
    final queue =
        (_hive.syncBox.get(_telemetryQueueKey) as List?)?.cast<Map>().toList() ??
            [];
    if (queue.isEmpty) return;

    final remaining = <Map>[];
    for (final entry in queue) {
      try {
        await _reportSyncFailure(
          opType: (entry['op_type'] as String?) ?? 'unknown',
          error: (entry['error'] as String?) ?? 'unknown',
        );
        // Success — don't re-add to remaining.
      } catch (_) {
        remaining.add(entry); // Still failing — keep for next attempt.
      }
    }
    await _hive.syncBox.put(_telemetryQueueKey, remaining);
  }

  /// Fire-and-forget telemetry for a sync failure. Sends one row to
  /// `client_errors` via the `log-client-error` Edge Function so we stop
  /// being blind to payload-rejection failures in prod.
  ///
  /// APK Test #12.7 — also forwards to ErrorTelemetry.recordNonFatal so
  /// every sync failure gets a Crashlytics non-fatal record in addition
  /// to the `client_errors` row. This is the single funnel — every
  /// `catch (e) { _reportSyncFailure(...) }` in this file inherits the
  /// Crashlytics leg without per-callsite edits.
  Future<void> _reportSyncFailure({
    required String opType,
    required Object error,
    int retryCount = 0,
  }) async {
    // Crashlytics + secondary log-client-error path (idempotent dual
    // posting; the legacy path below stays as the canonical
    // client_errors writer for retry-queue continuity).
    // Stack is unavailable here (this function takes Object only); pass
    // null and let Crashlytics auto-capture.
    unawaited(ErrorTelemetry.recordNonFatal(error, null, reason: opType));

    try {
      final code = error.runtimeType.toString();
      // Truncate to keep the Edge Function request body reasonable — some
      // PostgrestException messages include the full echoed row which can
      // be several KB on user_profile.
      var message = error.toString();
      if (message.length > 2000) {
        message = '${message.substring(0, 2000)}…(truncated)';
      }
      // BUG-C (d3a1c7): refresh before the authed EF invoke (stale-token 401
      // was dropping failure telemetry into the void).
      await _supabase.ensureFreshToken();
      await _supabase.client.functions.invoke(
        'log-client-error',
        body: {
          'error_code': code,
          'error_message': message,
          'op_type': opType,
          'retry_count': retryCount,
          'client_version': _currentClientVersion(),
          'platform': _currentPlatform(),
        },
      );
    } catch (_) {
      // Telemetry call itself failed — enqueue for next-launch retry so no
      // failure is silently dropped. _enqueueTelemetryFailure is truly silent.
      await _enqueueTelemetryFailure(opType, error);
    }
  }

  /// Immediately pushes all saved meals to Supabase `user_saved_meals`, including
  /// the updated `times_used` counter.
  ///

  /// True if `v` is a non-null, non-empty-string value.
  /// PostgREST rejects `""` for strict-typed columns (date, time, timestamptz,
  /// numeric) with "invalid input syntax" — callers must omit the field
  /// entirely rather than send the empty string.
  static bool _hasValue(dynamic v) {
    if (v == null) return false;
    if (v is String && v.trim().isEmpty) return false;
    return true;
  }

  /// True if `v` is a finite number. Excludes empty strings, NaN, and
  /// infinities that would otherwise corrupt an integer/numeric column.
  static bool _hasNumber(dynamic v) {
    if (v == null) return false;
    if (v is! num) return false;
    if (v is double && (v.isNaN || v.isInfinite)) return false;
    return true;
  }

  // ── Paginated Fetch Helper ──────────────────────────────────

  /// Fetches all rows from a Supabase table using offset-based pagination.
  /// Replaces hardcoded `.limit(5000)` to support full-history restore.
  /// Safety ceiling: 50,000 rows per table to prevent runaway fetches.
  Future<List<Map<String, dynamic>>> _fetchAllRows(
    String table,
    String userId, {
    String? dateColumn,
    String? since,
    String orderBy = 'created_at',
    int pageSize = 1000,
    String? selectColumns,
  }) async {
    const maxRows = 50000;
    final results = <Map<String, dynamic>>[];
    int offset = 0;
    while (true) {
      var query = _supabase.client
          .from(table)
          .select(selectColumns ?? '*')
          .eq('user_id', userId);
      if (dateColumn != null && since != null) {
        query = query.gte(dateColumn, since);
      }
      final rows = await query
          .order(orderBy)
          .range(offset, offset + pageSize - 1);
      for (final row in rows) {
        results.add(Map<String, dynamic>.from(row as Map));
      }
      if (rows.length < pageSize) break; // last page
      offset += pageSize;
      if (results.length >= maxRows) {
        debugPrint('[SyncService._fetchAllRows] Hit $maxRows ceiling for $table');
        break;
      }
    }
    return results;
  }

  // ── Private Restore Helpers (Cloud → Hive) ──────────────────

  // ── Restore: Water, Sleep, Streaks ──────────────────────────

  // ── Sync: Workout Plan + User Progress ─────────────────────

  // ── Gap 1+2: Workout Templates + Template Exercises ─────────

  // ── Gap 3: Scheduled Workouts ──────────────────────────────

  // ── Timestamp helpers ───────────────────────────────────────

  DateTime? _getTimestamp(String key) {
    final raw = _hive.syncBox.get(key);
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }

  Future<void> _setTimestamp(String key) async {
    await _hive.syncBox.put(key, DateTime.now().toIso8601String());
  }
}
