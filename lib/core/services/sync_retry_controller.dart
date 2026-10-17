/// Re-runs the changed-rows-only push sweep after an OUTAGE-SHAPED push failure.
///
/// closes-diagnose e5b2a9. Every domain push already goes through
/// `SyncSkipIndex.pushIfChanged`, which records a row as sent only after a
/// CONFIRMED push — so re-running the sweep sends exactly what is still unsent.
/// What was missing is the TRIGGER: a failed push only retried on the next write
/// or the next app launch, and the connectivity trigger in `SyncStateNotifier`
/// cannot fire when only the backend is down (the device is online).
///
/// Gate: a retry first PROBES that the backend answers (one tiny request), so a
/// still-down server costs one probe per backoff step, not a full sweep. A cap
/// of [kSyncRetryMaxAttempts] failed runs ends the cycle (the next failure
/// starts a fresh one), so a permanently-broken path cannot loop.
///
/// This controller's own state (timer, `paused`, attempt count) is memory-only.
/// What survives an app kill / web reload is the DURABLE "sweep owed" flag
/// `SyncService` writes to the sync box when it accepts a failure and clears on a
/// clean sweep; [shouldRunFullSweep] makes the launch-time sweep honour it.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'hive_service.dart';

/// Wait before retry attempt N (0-indexed). Capped at the last entry.
const List<Duration> kSyncRetrySchedule = [
  Duration(seconds: 30),
  Duration(minutes: 2),
  Duration(minutes: 10),
];

/// Failed runs before the cycle ends: 30 s, 2 m, 10 m, 10 m, 10 m, 10 m.
const int kSyncRetryMaxAttempts = 6;

/// A banner "Retry" tapped repeatedly is ONE probe+sweep, not N.
const Duration kSyncRetryManualCooldown = Duration(seconds: 10);

/// A sweep that has not returned by now is abandoned as a FAILED run, so a
/// hung request can never wedge the controller in `_running` forever.
const Duration kSyncRetrySweepCeiling = Duration(minutes: 5);

Duration syncRetryDelay(int attempt,
        {List<Duration> schedule = kSyncRetrySchedule}) =>
    schedule[attempt.clamp(0, schedule.length - 1)];

// A 3-digit HTTP status as it appears in the real error text:
//   `PostgrestException(message: error code: 521\n, code: 521, ...)`
//   `FunctionException(status: 503, ...)`.
// `(?!\d)` keeps 5-digit Postgres codes (23505, 57014) and UUID fragments from
// matching; the leading `code`/`status` word keeps a UUID's "401" from matching.
final RegExp _httpStatusRe = RegExp(
    r'\b(?:status(?:code)?|code)\W{0,4}(\d{3})(?!\d)',
    caseSensitive: false);

/// The part of [error]'s text that is the SERVER'S verdict. Postgres echoes the
/// rejected row into `details` (and `hint`) — text the USER typed ("my workout
/// timed out yesterday") — so scanning it would call a deterministic rejection an
/// outage. `PostgrestException.toString()` is
/// `PostgrestException(message: …, code: …, details: …, hint: …)`: cut at
/// `, details:`.
String _classifiableText(Object error) {
  final t = error.toString();
  final i = t.indexOf(', details:');
  return i < 0 ? t : t.substring(0, i);
}

/// The HTTP status carried in [error]'s text, if any.
int? httpStatusOfError(Object error) {
  final m = _httpStatusRe.firstMatch(_classifiableText(error));
  return m == null ? null : int.tryParse(m.group(1)!);
}

// Outage shapes that carry NO HTTP status in the text: socket/DNS/fetch failures
// (all platforms), PostgREST's JSON-bodied 503s (PGRST000-003 — "Could not query
// the database for the schema cache"), and PG overload codes.
final RegExp _outageTextRe = RegExp(
  r'(socketexception|failed host lookup|connection (refused|reset|closed|abort|terminated)|network is unreachable|software caused connection abort|failed to fetch|load failed|xmlhttprequest error|timeoutexception|tlsexception|handshakeexception|net::err_|timed out|pgrst00[0-3]|code: ?(?:57014|57p0[123]|53\d{3}|08\w{3}|40001|40p01)\b)',
  caseSensitive: false,
);

/// A failure that means "the backend or the network did not answer", i.e. one a
/// later retry can plausibly fix. 4xx (400/401/403/404/409/422) and PG `23xxx` /
/// `42703` are the server ANSWERING "no" — retrying the same payload cannot
/// succeed. Unknown shapes are NOT retried (an unclassified error must not be
/// able to loop).
bool isOutageShapedFailure(Object error) {
  if (error is TimeoutException) return true;
  final status = httpStatusOfError(error);
  if (status != null) return status >= 500 || status == 408 || status == 429;
  return _outageTextRe.hasMatch(_classifiableText(error));
}

/// Push-looking op types the retry SWEEP (`weeklyFullSync`) does NOT re-send, plus
/// the READS that merely share the `sync_` prefix. Arming on these would show
/// "Sync paused", spend a probe and a full sweep, then report recovery while the
/// failed item stays unsent until its own trigger (B-pass F4). They keep exactly the
/// behaviour they had before e5b2a9 (next write / next launch).
const Set<String> kNotSweptOpTypes = {
  'sync_fitness_summary', // READ
  'sync_community_items', // READ (pulls approved community rows)
  'sync_custom_items', // pushed by checkAndSync / writers, not the sweep
  'upsert_custom_exercise',
  'upsert_custom_food',
  'sync_freezes',
  'sync_saved_diet_plan',
  'sync_notifications_inbox_entry',
  'upsert_coach_memory_induction',
};

/// `_reportSyncFailure` also receives restore, realtime, onboarding and
/// bookkeeping failures. Only a PUSH failure that the sweep re-sends can be fixed
/// by re-running it. `restore_sync_*` is a push op wrapped by `_safeRestoreOp` in
/// `weeklyFullSync` that hit its 45 s ceiling; [kNotSweptOpTypes] are excluded.
bool isPushFailureOpType(String opType) {
  if (kNotSweptOpTypes.contains(opType)) return false;
  return opType == 'weekly_full_sync' ||
      opType.startsWith('upsert_') ||
      opType.startsWith('restore_sync_') ||
      opType.startsWith('sync_');
}

/// Whether the launch-time sweep (`checkAndSync`) should run: the daily interval
/// elapsed, there is no stamp, OR a previous failure left the sweep OWED (the
/// durable flag survives the memory-only retry cycle — B-pass F1: a reload or the
/// 6-run cap otherwise left a row unsent until tomorrow's launch).
bool shouldRunFullSweep({
  required DateTime? lastFullSync,
  required DateTime now,
  required Duration interval,
  required bool owed,
}) =>
    owed || lastFullSync == null || now.difference(lastFullSync) >= interval;

/// §4.6 kill-switch predicate: only a literal `true` disables.
bool isSyncRetryDisabled(Object? raw) => raw == true;

class SyncRetryController {
  SyncRetryController({
    required Future<bool> Function() probe,
    required Future<void> Function() sweep,
    this.schedule = kSyncRetrySchedule,
    this.maxAttempts = kSyncRetryMaxAttempts,
    Duration Function(Duration)? jitter,
    bool Function()? isDisabled,
  })  : _probe = probe,
        _sweep = sweep,
        _jitter = jitter ?? _defaultJitter,
        _isDisabled = isDisabled ?? _configDisabled;

  /// The app-wide instance. Callbacks are bound by `SyncService`
  /// (`bind`) so this file never imports the service (no cycle).
  static final SyncRetryController instance = SyncRetryController(
    probe: () async => false,
    sweep: () async {},
  );

  static final Random _rng = Random();

  /// ±20% so every device that failed in the same outage does not re-probe in
  /// the same second when the backend returns (d7b1f8 saw ~15 requests released
  /// within 400 ms).
  static Duration _defaultJitter(Duration d) => Duration(
      milliseconds:
          (d.inMilliseconds * (0.8 + _rng.nextDouble() * 0.4)).round());

  static bool _configDisabled() {
    try {
      return isSyncRetryDisabled(
          HiveService.instance.configBox.get('disable_sync_retry_sweep'));
    } catch (_) {
      return false;
    }
  }

  Future<bool> Function() _probe;
  Future<void> Function() _sweep;
  final List<Duration> schedule;
  final int maxAttempts;
  final Duration Function(Duration) _jitter;
  final bool Function() _isDisabled;

  /// True from the first accepted failure until a sweep completes cleanly (or
  /// the cap ends the cycle). Drives the "sync paused" banner.
  final ValueNotifier<bool> paused = ValueNotifier<bool>(false);

  int _retryableFailureSeq = 0;

  /// Whether the §4.6 kill-switch is on (read through the same defensive getter).
  bool get disabled => _isDisabled();

  /// False while a recent banner tap's cooldown is running — callers that fan a tap
  /// out to other work (the queue drain) consult it so the cooldown is global.
  bool get manualRetryAllowed => !_manualCooling;

  /// Monotonic count of ACCEPTED failures. `weeklyFullSync` compares it before
  /// and after a sweep to decide whether the sweep was clean enough to stamp
  /// `last_full_sync`.
  int get retryableFailureSeq => _retryableFailureSeq;

  Timer? _timer;
  bool _running = false;
  bool _manualCooling = false;
  int _attempt = 0;
  int _failuresThisRun = 0;

  /// Bumped by `_fire` and by `reset`. A run whose captured value no longer
  /// matches is stale (account switch) and must touch nothing.
  int _gen = 0;

  void bind({
    required Future<bool> Function() probe,
    required Future<void> Function() sweep,
  }) {
    _probe = probe;
    _sweep = sweep;
  }

  /// Called from the single failure funnel (`SyncService._reportSyncFailure`).
  void noteFailure(Object error, {required String opType}) {
    if (_isDisabled()) return;
    // A String is a telemetry-queue REPLAY of an OLD failure, not a live one.
    if (error is String) return;
    if (!isPushFailureOpType(opType)) return;
    if (!isOutageShapedFailure(error)) return;
    _retryableFailureSeq++;
    if (_running) {
      _failuresThisRun++;
      return;
    }
    if (!paused.value) paused.value = true;
    _scheduleNext();
  }

  void _scheduleNext() {
    if (_timer != null) return;
    _timer = Timer(
      _jitter(syncRetryDelay(_attempt, schedule: schedule)),
      () => unawaited(_fire()),
    );
  }

  /// "Retry" tap on the banner: run now instead of waiting for the timer.
  /// Taps inside [kSyncRetryManualCooldown] of the previous one are ignored,
  /// so a frustrated user cannot turn the banner into a request cannon.
  Future<void> retryNow() async {
    if (_manualCooling) return;
    _manualCooling = true;
    Timer(kSyncRetryManualCooldown, () => _manualCooling = false);
    _timer?.cancel();
    _timer = null;
    await _fire(manual: true);
  }

  void _afterFailedRun() {
    if (_attempt >= maxAttempts) {
      // End of the cycle: stop claiming "retrying". The data is still unsent;
      // the durable "sweep owed" flag makes the next launch's sweep run it, and
      // the next failure or write's fan-out also picks it up.
      _attempt = 0;
      paused.value = false;
      return;
    }
    _scheduleNext();
  }

  Future<void> _fire({bool manual = false}) async {
    _timer = null;
    if (_running) return;
    _running = true;
    _failuresThisRun = 0;
    final gen = ++_gen;
    try {
      final reachable = await _probe();
      if (gen != _gen) return;
      if (!reachable) {
        if (!manual) _attempt++; // a manual tap must not escalate the backoff
        _afterFailedRun();
        return;
      }
      await _sweep().timeout(kSyncRetrySweepCeiling);
      if (gen != _gen) return;
      if (_failuresThisRun == 0) {
        _attempt = 0;
        paused.value = false;
      } else {
        _attempt++;
        _afterFailedRun();
      }
    } catch (_) {
      if (gen == _gen) {
        _attempt++;
        _afterFailedRun();
      }
    } finally {
      if (gen == _gen) _running = false;
    }
  }

  /// Account switch: drop everything. Bumping [_gen] makes an in-flight run's
  /// tail a no-op, and clearing [_running] here lets the NEW owner's first
  /// failure schedule normally instead of being swallowed as "a run is active".
  void reset() {
    _gen++;
    _running = false;
    _timer?.cancel();
    _timer = null;
    _attempt = 0;
    _failuresThisRun = 0;
    _manualCooling = false;
    paused.value = false;
  }
}
