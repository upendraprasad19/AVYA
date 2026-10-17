import 'dart:async';

import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/singleton_lifecycle_registry.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';

/// Tracks daily and monthly usage counters for gated features.
///
/// All counters are user-scoped and stored in the per-user `userBox`
/// via [MigratedKey] — sign-out → sign-up cannot reset another user's
/// counters. Call [checkAndResetCounters] on app launch to reset stale
/// counters by IST date.
class UsageCounterService {
  UsageCounterService._() {
    _registerLifecycle();
  }
  static final UsageCounterService _instance = UsageCounterService._();

  /// Tech-debt audit 2026-05-20 / A7 (B5 D9-D10) — prefer
  /// `ref.read(usageCounterServiceProvider)` over `.instance`. The
  /// singleton is preserved for non-Riverpod contexts (main.dart
  /// counter-reset boot).
  @Deprecated(
      'Use ref.read(usageCounterServiceProvider) — singleton path will be removed after full migration')
  static UsageCounterService get instance => _instance;

  /// Tech-debt audit 2026-05-20 / A7 — register cross-account reset
  /// hook. All counters live in per-user userBox via MigratedKey, so
  /// there is no in-memory cache. The callback is wired for symmetry +
  /// future-proofing (a memoised limit table or rate-limit clock would
  /// have a natural reset point here).
  void _registerLifecycle() {
    SingletonLifecycleRegistry.register(
        'UsageCounterService', _onUserChanged);
  }

  /// A7 — invoked from [SingletonLifecycleRegistry.notifyUserChanged].
  /// No-op today; all state is Hive-backed and already user-scoped.
  void _onUserChanged() {
    // Intentionally empty.
  }

  /// OI-45 (usage-counter-race batch, 2026-07-29) — per-key mutex around
  /// [increment]'s read-modify-write, mirroring `ProfileWriteService._withLock`
  /// (Completer-per-key, not a package dep).
  ///
  /// Verified honestly, not assumed: a same-device interleaved-read race on
  /// this exact read-then-await-write shape is currently STRUCTURALLY
  /// IMPOSSIBLE under Dart's single-threaded event loop + Hive's `Box.put()`
  /// (which mutates its in-memory keystore synchronously before its own
  /// first `await`) — `read()` is fully synchronous and is the only thing
  /// that runs before `increment()`'s one `await`, so nothing can interleave
  /// between a caller's read and its write landing in memory. A regression
  /// test attempting `Future.wait([increment(), increment()])` against the
  /// PRE-fix code (read; await write(current+1)) still counted both — see
  /// `usage_counter_service_race_behavioral_test.dart`'s header comment for
  /// the full investigation. This mirrors the identical structural-safety
  /// finding already documented in
  /// `streak_freeze_refill_race_behavioral_test.dart` for a different pair
  /// of methods. This mutex is kept anyway as defense-in-depth matching this
  /// codebase's established convention for shared Hive-backed state accessed
  /// from multiple call sites (`ProfileWriteService`, `WorkoutWriteService`)
  /// — NOT because a reproducible bug was found here.
  ///
  /// Separately: the actual daily caps this service gates (ai-text-log,
  /// scan_meal, cart_auditor) are ALL enforced authoritatively server-side by
  /// Postgres triggers on `ai_coach_interactions` (migrations 026/113
  /// pre-existing; 111/114 added 2026-07-29) — even a hypothetical lost local
  /// increment, or a genuine cross-device inconsistency (this counter is
  /// per-device, not synced in real time), can no longer let a request
  /// bypass the real cap; worst case is a stale "X remaining" display or a
  /// request the server correctly 429s.
  final Map<String, Completer<void>> _locks = {};

  Future<T> _withLock<T>(String key, Future<T> Function() op) async {
    while (_locks[key] != null) {
      try {
        await _locks[key]!.future;
      } catch (_) {/* swallowed; holder will release */}
    }
    final c = Completer<void>();
    _locks[key] = c;
    try {
      return await op();
    } finally {
      _locks.remove(key);
      if (!c.isCompleted) c.complete();
    }
  }

  // ── Hive Keys ───────────────────────────────────────────────────

  static const String _aiTextLogCountToday = 'ai_text_log_count_today';
  static const String _scanMealCountToday = 'scan_meal_count_today';
  static const String _cartAuditorCountToday = 'cart_auditor_count_today';
  static const String _lastDailyReset = 'last_daily_reset';

  /// Not a Hive key — a [_locks] map key reserved for [checkAndResetCounters]'s
  /// own outer double-checked-locking guard (B-pass finding, usage-counter-race
  /// batch). Distinct from every real counter/reset key above so it can never
  /// collide with a per-key increment lock.
  static const String _dailyResetLockKey = '__daily_reset__';

  // ── Feature → Counter Key Mapping ────────────────────────────────

  /// Returns the Hive key for a feature's counter.
  /// All counters are now daily (no monthly counters).
  String? _counterKey(String feature, bool isPro) {
    if (feature == AppConstants.featureAiTextLogPro) {
      return _aiTextLogCountToday;
    }
    if (feature == AppConstants.featureScanMealPro) {
      return _scanMealCountToday;
    }
    if (feature == AppConstants.featureCartAuditorPro) {
      return _cartAuditorCountToday;
    }
    return null;
  }

  /// Returns the maximum allowed uses for a feature.
  /// PRO AI text logs are unlimited (returns max int).
  int _limit(String feature, bool isPro) {
    if (feature == AppConstants.featureAiTextLogPro) {
      // PRO: unlimited AI text logs
      return isPro ? 999999 : AppConstants.freeAiTextLogsPerDay;
    }
    if (feature == AppConstants.featureScanMealPro) {
      return isPro
          ? AppConstants.proScanMealPerDay
          : AppConstants.freeScanMealPerDay;
    }
    if (feature == AppConstants.featureCartAuditorPro) {
      return isPro
          ? AppConstants.proCartAuditorPerDay
          : AppConstants.freeCartAuditorPerDay;
    }
    return 0;
  }

  // ── Public API ──────────────────────────────────────────────────

  /// Returns `true` if the user has remaining uses for [feature].
  bool canUse(String feature, bool isPro) {
    final key = _counterKey(feature, isPro);
    if (key == null) return false;

    final used = MigratedKey.readWithDefault<int>(key, 0);
    return used < _limit(feature, isPro);
  }

  /// Increments the usage counter for [feature].
  ///
  /// Call this AFTER the feature action succeeds. Serialized per-key (see
  /// [_withLock]) so two same-device concurrent callers on the SAME counter
  /// never lose an increment to a stale read.
  Future<void> increment(String feature, bool isPro) async {
    final key = _counterKey(feature, isPro);
    if (key == null) return;

    await _withLock(key, () async {
      final current = MigratedKey.readWithDefault<int>(key, 0);
      await MigratedKey.write(key, current + 1);
    });
  }

  /// Returns how many uses remain for [feature].
  int remaining(String feature, bool isPro) {
    final key = _counterKey(feature, isPro);
    if (key == null) return 0;

    final used = MigratedKey.readWithDefault<int>(key, 0);
    final max = _limit(feature, isPro);
    return (max - used).clamp(0, max);
  }

  /// Returns the current count for [feature].
  int used(String feature, bool isPro) {
    final key = _counterKey(feature, isPro);
    if (key == null) return 0;
    return MigratedKey.readWithDefault<int>(key, 0);
  }

  // ── Reset Logic ─────────────────────────────────────────────────

  /// Check if counters need resetting and reset them.
  ///
  /// Must be called on app launch (in main.dart after Hive init) AND fires
  /// again on every app-resume (`DayRolloverService._doRollover`, not just
  /// cold boot). Resets daily counters if the IST date has changed.
  ///
  /// Round-1 review raised a theoretical concern (usage-counter-race batch,
  /// 2026-07-29): this is a SECOND writer of the 3 counter keys, previously
  /// unlocked, and unlike [increment]'s single-await-after-mutation shape,
  /// this method's 4 SEQUENTIAL `await MigratedKey.write(...)` calls each
  /// genuinely yield to the event loop — a plausible mechanism for an
  /// in-flight [increment] to interleave with a reset on the same key right
  /// at an IST-midnight app-resume. Investigated with the SAME rigor as
  /// [increment]'s own claim (test the pre-fix/unlocked code directly, don't
  /// assume from the mechanism alone): a concurrent-dispatch test
  /// (`checkAndResetCounters` vs `increment` on the same key via
  /// `Future.wait`) did NOT reproduce a corrupted outcome even against the
  /// UNLOCKED code — round-2 review sharpened this further: the outcome is
  /// provably DETERMINISTIC (not merely unobserved), since a list literal
  /// invokes its elements in fixed order and each write's in-memory landing
  /// is synchronous, so whichever call is listed first always lands before
  /// the second is even invoked (Hive's `Box.put()` synchronous in-memory
  /// mutation + Dart's synchronous list-evaluation front-loading both
  /// operations' prefixes before either can genuinely interleave). See
  /// `usage_counter_service_race_behavioral_test.dart`'s "deterministic-order
  /// contract" group for the full investigation, incl. both list orders
  /// verified.
  ///
  /// B-pass review found a THIRD, genuinely-reachable shape the above
  /// doesn't cover: two INDEPENDENTLY-dispatched calls to this method
  /// itself (not co-scheduled via one `Future.wait` list). `DayRolloverObserver`
  /// (`day_rollover_service.dart`) has no re-entrancy guard, and its staleness
  /// gate (`last_known_date`) is only written well after this method returns
  /// — a duplicate `AppLifecycleState.resumed` firing before the first
  /// rollover completes (a real, documented Flutter/Android lifecycle class,
  /// not hypothetical) dispatches a SECOND, independent
  /// `checkAndResetCounters()` call. Since the two calls are NOT co-scheduled
  /// synchronously, the deterministic list-evaluation guarantee above does
  /// not apply — there can be a genuine async gap (real Hive disk-flush
  /// latency) between the two calls' progress, during which a legitimate
  /// `increment()` could land between one call's per-key reset and the
  /// OTHER call's now-redundant reset of that same key, silently losing the
  /// increment. Closed by double-checked locking: the whole staleness-check
  /// + reset body is now wrapped in one outer per-run lock, and the
  /// staleness condition is RE-CHECKED after acquiring it — a second
  /// concurrent call blocks on the outer lock and, once it acquires it,
  /// observes the first call already updated [_lastDailyReset] and no-ops
  /// instead of redundantly re-zeroing keys a fresh increment may have
  /// already touched. Each individual key's reset keeps its own per-key
  /// [_withLock] too (now redundant against a SECOND resetter, since the
  /// outer lock already serializes that — but still required to serialize
  /// against a concurrent [increment] on the same key, which does not
  /// touch the outer lock at all).
  Future<void> checkAndResetCounters() async {
    final todayStr = istDateStr(DateTime.now());

    await _withLock(_dailyResetLockKey, () async {
      // Re-check staleness AFTER acquiring the outer lock — a second,
      // independently-dispatched call that queued behind this one will see
      // the first call's already-updated _lastDailyReset here and no-op.
      final lastDaily = MigratedKey.read<String>(_lastDailyReset);
      if (lastDaily == todayStr) return;

      // ── Daily reset (all counters are now daily) ─────────────────
      await _withLock(_aiTextLogCountToday,
          () => MigratedKey.write(_aiTextLogCountToday, 0));
      await _withLock(
          _scanMealCountToday, () => MigratedKey.write(_scanMealCountToday, 0));
      await _withLock(_cartAuditorCountToday,
          () => MigratedKey.write(_cartAuditorCountToday, 0));
      await MigratedKey.write(_lastDailyReset, todayStr);
    });
  }
}
