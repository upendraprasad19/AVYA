/// Persistent retry queue for failed Supabase writes.
///
/// Wraps any `Future<Result<void, SyncError>>` operation. On first failure
/// the operation is persisted to Hive with a backoff schedule; on drain
/// it's retried until it either succeeds (removed from queue) or exhausts
/// all retries (dead-lettered + sent to server telemetry).
///
/// Drains run on:
///   * App launch (in `main.dart` after Hive opens, before `runApp`)
///   * Connectivity restore (via `connectivity_plus`)
///   * Periodic timer (every 5 min while app foregrounded)
///   * Explicit user "Retry now" tap in `SyncBanner`
///
/// Reference: docs/superpowers/specs/2026-04-17-sync-reliability.md Pillar B.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'result.dart';
import 'sync_error.dart';

/// One pending operation in the queue. Serialised as JSON under a
/// `pending_sync_<id>` key in `syncBox`.
class PendingSyncOp {
  final String id;
  final String opType;
  final Map<String, dynamic> payload;
  final int retryCount;
  final DateTime firstAttemptAt;
  final DateTime? lastAttemptAt;
  final String? lastErrorCode;
  final String? lastErrorMessage;

  const PendingSyncOp({
    required this.id,
    required this.opType,
    required this.payload,
    required this.retryCount,
    required this.firstAttemptAt,
    this.lastAttemptAt,
    this.lastErrorCode,
    this.lastErrorMessage,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'op_type': opType,
        'payload': payload,
        'retry_count': retryCount,
        'first_attempt_at': firstAttemptAt.toIso8601String(),
        if (lastAttemptAt != null)
          'last_attempt_at': lastAttemptAt!.toIso8601String(),
        if (lastErrorCode != null) 'last_error_code': lastErrorCode,
        if (lastErrorMessage != null) 'last_error_message': lastErrorMessage,
      };

  static PendingSyncOp fromJson(Map<String, dynamic> json) => PendingSyncOp(
        id: json['id'] as String,
        opType: json['op_type'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        retryCount: json['retry_count'] as int,
        firstAttemptAt: DateTime.parse(json['first_attempt_at'] as String),
        lastAttemptAt: json['last_attempt_at'] == null
            ? null
            : DateTime.parse(json['last_attempt_at'] as String),
        lastErrorCode: json['last_error_code'] as String?,
        lastErrorMessage: json['last_error_message'] as String?,
      );

  PendingSyncOp withRetry(SyncError err) => PendingSyncOp(
        id: id,
        opType: opType,
        payload: payload,
        retryCount: retryCount + 1,
        firstAttemptAt: firstAttemptAt,
        lastAttemptAt: err.at,
        lastErrorCode: err.code,
        lastErrorMessage: err.message,
      );
}

/// One day in seconds — named so the 86400 magic constant in the backoff
/// schedule is greppable.
const int _oneDaySeconds = 86400;

/// Exponential backoff schedule (seconds): 1s, 5s, 30s, 5min, 30min, 2h, 24h.
/// Attempt N (0-indexed) returns the delay before that attempt.
/// After the last entry we dead-letter.
///
/// Audit 2026-05-20 / C7: previously had a parallel `maxRetries = 7`
/// constant with a "keep in sync" comment. Now derived from list length.
const List<int> _backoffSeconds = [1, 5, 30, 300, 1800, 7200, _oneDaySeconds];

/// Maximum retry count before dead-letter. Hardcoded to match
/// `_backoffSeconds.length` (Dart const eval can't access `.length` on a
/// const list in a const context). Test
/// `test/contracts/sync_queue_retry_budget_consistency_test.dart` (lands
/// in B2 continuation) pins them together at runtime.
const int maxRetries = 7;

/// Returns true if the op should be dead-lettered given its retry count and
/// last-error classification. A non-transient error (Validation / Schema)
/// dead-letters immediately regardless of retry count.
bool _shouldDeadLetter(PendingSyncOp op, SyncError? err) {
  if (err != null && !err.isTransient) return true;
  return op.retryCount >= maxRetries;
}

/// Returns true if enough time has elapsed since the last attempt that the
/// op is due for another retry.
bool _isDue(PendingSyncOp op, DateTime now) {
  if (op.lastAttemptAt == null) return true;
  final backoffIdx = (op.retryCount - 1).clamp(0, _backoffSeconds.length - 1);
  final delay = Duration(seconds: _backoffSeconds[backoffIdx]);
  return now.isAfter(op.lastAttemptAt!.add(delay));
}

/// Typedef for the executor that actually performs the Supabase call.
///
/// The queue looks up the executor by `opType` — each op type registers
/// one at startup. This lets `SyncService` stay untouched (still writes to
/// Supabase directly) while the queue handles persistence + retry.
typedef SyncOpExecutor = Future<Result<void, SyncError>> Function(
  Map<String, dynamic> payload,
);

class SyncQueue {
  SyncQueue._();
  static final SyncQueue instance = SyncQueue._();

  final HiveService _hive = HiveService.instance;
  final Map<String, SyncOpExecutor> _executors = {};
  final StreamController<int> _pendingCountController =
      StreamController<int>.broadcast();

  /// Callback invoked when an op is dead-lettered. `SyncService` wires this
  /// up in `init()` to call the `log-client-error` Edge Function.
  Future<void> Function(PendingSyncOp op)? onDeadLetter;

  /// Stream of pending op counts — used by `SyncBanner` to show "N waiting".
  Stream<int> get pendingCount => _pendingCountController.stream;

  /// Register how to execute a given op type. Must be called at startup
  /// BEFORE `drain()` runs. Unregistered op types are dead-lettered
  /// immediately on drain (shouldn't happen in practice — shipping bug).
  void registerExecutor(String opType, SyncOpExecutor executor) {
    _executors[opType] = executor;
  }

  /// Enqueue an operation for retry. Use when an initial attempt has
  /// already failed with a transient error. The op is persisted to Hive
  /// immediately so it survives app restart.
  Future<void> enqueue({
    required String opType,
    required Map<String, dynamic> payload,
    required SyncError initialError,
  }) async {
    // If the first error is non-transient, don't bother queueing — just
    // dead-letter right away.
    if (!initialError.isTransient) {
      final op = PendingSyncOp(
        id: _generateId(),
        opType: opType,
        payload: payload,
        retryCount: 1,
        firstAttemptAt: initialError.at,
        lastAttemptAt: initialError.at,
        lastErrorCode: initialError.code,
        lastErrorMessage: initialError.message,
      );
      await _deadLetter(op);
      return;
    }

    final op = PendingSyncOp(
      id: _generateId(),
      opType: opType,
      payload: payload,
      retryCount: 1,
      firstAttemptAt: initialError.at,
      lastAttemptAt: initialError.at,
      lastErrorCode: initialError.code,
      lastErrorMessage: initialError.message,
    );
    await _persist(op);
    _notifyPending();
  }

  /// Enqueue + retry immediately (no initial error — the caller just wants
  /// the queue to own delivery). Used for push-snapshot where we want
  /// the guarantee but don't want to block the UI.
  Future<void> enqueueFresh({
    required String opType,
    required Map<String, dynamic> payload,
  }) async {
    final op = PendingSyncOp(
      id: _generateId(),
      opType: opType,
      payload: payload,
      retryCount: 0,
      firstAttemptAt: DateTime.now(),
    );
    await _persist(op);
    _notifyPending();
    // Fire immediately — if it succeeds we remove the op; if it fails
    // we leave it in the queue for the next drain.
    await _runOne(op);
  }

  /// Drain due ops. Idempotent — safe to call from multiple triggers.
  Future<void> drain() async {
    final ops = _loadAll();
    final now = DateTime.now();
    for (final op in ops) {
      if (!_isDue(op, now)) continue;
      await _runOne(op);
    }
    _notifyPending();
  }

  /// Count of currently-queued ops. Used on app launch to populate the
  /// initial banner state without having to subscribe.
  int get pendingCountSync => _loadAll().length;

  Future<void> _runOne(PendingSyncOp op) async {
    final executor = _executors[op.opType];
    if (executor == null) {
      debugPrint('[SyncQueue] no executor for ${op.opType} — dead-lettering');
      await _deadLetter(op);
      return;
    }

    final result = await executor(op.payload);
    if (result.isOk) {
      await _remove(op.id);
      return;
    }

    final err = (result as Err<void, SyncError>).error;
    final updated = op.withRetry(err);
    if (_shouldDeadLetter(updated, err)) {
      await _deadLetter(updated);
      return;
    }
    await _persist(updated);
  }

  Future<void> _deadLetter(PendingSyncOp op) async {
    debugPrint(
      '[SyncQueue] dead-letter ${op.opType} '
      '(retries=${op.retryCount}, last=${op.lastErrorCode}): '
      '${op.lastErrorMessage}',
    );
    await _remove(op.id);
    final cb = onDeadLetter;
    if (cb != null) {
      try {
        await cb(op);
      } catch (e, st) {
        // Telemetry failure is non-fatal — we already logged to debug.
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[SyncQueue] onDeadLetter callback failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_queue_dead_letter_callback'));
      }
    }
    _notifyPending();
  }

  Future<void> _persist(PendingSyncOp op) async {
    await _hive.syncBox.put('pending_sync_${op.id}', jsonEncode(op.toJson()));
  }

  Future<void> _remove(String id) async {
    await _hive.syncBox.delete('pending_sync_$id');
  }

  List<PendingSyncOp> _loadAll() {
    final out = <PendingSyncOp>[];
    for (final key in _hive.syncBox.keys) {
      if (key is! String || !key.startsWith('pending_sync_')) continue;
      final raw = _hive.syncBox.get(key);
      if (raw is! String) continue;
      try {
        final json = jsonDecode(raw) as Map<String, dynamic>;
        out.add(PendingSyncOp.fromJson(json));
      } catch (e, st) {
        // Corrupt entry — drop it. Better than looping on a broken payload.
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[SyncQueue] corrupt entry $key: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'sync_queue_load_all_corrupt_entry'));
        _hive.syncBox.delete(key);
      }
    }
    return out;
  }

  void _notifyPending() {
    if (_pendingCountController.isClosed) return;
    _pendingCountController.add(pendingCountSync);
  }

  String _generateId() {
    // Good enough — millisecond timestamp + random suffix.
    final ts = DateTime.now().microsecondsSinceEpoch;
    final r = (ts * 7) % 0xFFFFFF;
    return '${ts.toRadixString(36)}_${r.toRadixString(36)}';
  }

  @visibleForTesting
  Future<void> clearAll() async {
    final keys = _hive.syncBox.keys
        .where((k) => k is String && k.startsWith('pending_sync_'))
        .toList();
    for (final k in keys) {
      await _hive.syncBox.delete(k);
    }
    _notifyPending();
  }
}
