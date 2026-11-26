// lib/core/services/sync/sched_unpushed_swaps.dart
//
// OI-532 (diagnose f5a2c8): which schedule dates carry a LOCAL day swap the
// cloud has not confirmed yet. Written by the swap, cleared by the schedule
// push once the cloud holds that date's row, read by the schedule restore so a
// stale cloud row cannot undo the swap. Plan
// docs/plans/oi532-sched-restore-unpushed-swap.md section 5.
//
// A positive marker, never an absence: a fresh device, a cleared skip index or
// a kill-switched one has no fingerprints, and must NOT read every swapped row
// as unpushed (plan section 4).
//
// Two parts:
// - PERSISTED `{date: token}` in the user-scoped workoutBox, plus the reserved
//   `_seq` entry (the last token issued, so a token is never reused).
// - PROCESS-LOCAL: the dates of a swap still being written (in flight), and a
//   counter bumped by every mark and clear, so a restore can ask "did anything
//   happen to this date since I fetched?" (`fetchMark` / `touchedSince`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';

/// Hive key in the user-scoped workoutBox.
const String kSchedSwapUnpushedKey = 'sched_swap_unpushed';

/// Reserved entry inside the map: the last token ever issued.
const String _kSeqEntry = '_seq';

class SchedUnpushedSwaps {
  SchedUnpushedSwaps._();

  static bool _malformedReported = false;

  @visibleForTesting
  static int Function() nowMs = _realNowMs;
  static int _realNowMs() => DateTime.now().millisecondsSinceEpoch;

  // ── process-local ──
  static final Set<String> _inFlight = <String>{};
  static int _touchSeq = 0;
  static final Map<String, int> _touched = <String, int>{};

  /// Forgets the process-local dates. Called on every user change (they
  /// belong to the previous user's box) and by tests. The counter is NEVER
  /// reset: a restore that took its [fetchMark] before the change must still
  /// compare against a counter that only grows (round-3 finding 5).
  static void resetForUser() {
    _inFlight.clear();
    _touched.clear();
  }

  static void _touch(String date) => _touched[date] = ++_touchSeq;

  /// A restore takes this BEFORE it fetches cloud rows.
  static int fetchMark() => _touchSeq;

  /// True when a mark or a clear of [date] happened after [mark].
  static bool touchedSince(String date, int mark) =>
      (_touched[date] ?? 0) > mark;

  @visibleForTesting
  static Set<String> get inFlightForTests => Set.unmodifiable(_inFlight);

  // ── persisted ──

  /// PURE read (no telemetry outside the catch: `isPending` is a query,
  /// CLAUDE.md CQRS gate). A malformed value is reported by the writer
  /// ([markAll]), which is about to replace it.
  static Map<String, int> _readRaw(Box<dynamic> box) {
    try {
      final raw = box.get(kSchedSwapUnpushedKey);
      if (raw is Map) {
        return <String, int>{
          for (final e in raw.entries)
            if (e.key is String && e.value is int)
              e.key as String: e.value as int,
        };
      }
    } catch (e, st) {
      debugPrint('[SchedUnpushedSwaps] read: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'sched_swap_unpushed_read'));
    }
    return <String, int>{};
  }

  /// The stored `{date: token}` marks, without the reserved `_seq` entry.
  /// Empty on any unexpected shape (fail OPEN: no guard, the pre-OI-532
  /// behaviour).
  static Map<String, int> read(Box<dynamic> box) =>
      _readRaw(box)..remove(_kSeqEntry);

  static void _reportMalformed(String what) {
    if (_malformedReported) return;
    _malformedReported = true;
    unawaited(ErrorTelemetry.logEvent('sched_swap_unpushed_malformed',
        message: what));
  }

  static Future<void> _write(Box<dynamic> box, Map<String, int> m) async {
    final dates = m.keys.where((k) => k != _kSeqEntry);
    if (dates.isEmpty && !m.containsKey(_kSeqEntry)) {
      await box.delete(kSchedSwapUnpushedKey);
    } else {
      await box.put(kSchedSwapUnpushedKey, m);
    }
  }

  /// Marks [dates]. Every token is greater than any token issued before on
  /// this box, so a push holding an older token can never clear this mark.
  static Future<void> markAll(Box<dynamic> box, Iterable<String> dates) async {
    final stored = box.get(kSchedSwapUnpushedKey);
    if (stored != null &&
        (stored is! Map ||
            stored.entries.any((e) => e.key is! String || e.value is! int))) {
      _reportMalformed(stored.runtimeType.toString());
    }
    final m = _readRaw(box);
    var seq = m[_kSeqEntry] ?? 0;
    for (final d in dates) {
      final now = nowMs();
      seq = now > seq ? now : seq + 1;
      m[d] = seq;
      _touch(d);
    }
    m[_kSeqEntry] = seq;
    await box.put(kSchedSwapUnpushedKey, m);
  }

  /// A swap of [dates] starts: in flight, then marked (plan 5.2, T1).
  static Future<void> beginSwap(Box<dynamic> box, Set<String> dates) async {
    _inFlight.addAll(dates);
    await markAll(box, dates);
  }

  /// A swap of [dates] ended (success or not); call from a `finally`.
  static void endSwap(Set<String> dates) => _inFlight.removeAll(dates);

  static int? tokenOf(Box<dynamic> box, String date) => read(box)[date];

  /// Stored mark OR a swap of [date] still being written.
  static bool isPending(Box<dynamic> box, String date) =>
      _inFlight.contains(date) || read(box).containsKey(date);

  /// Drops [date] only while it still holds [token] and no swap of it is in
  /// flight. No await between the read and the put.
  static Future<void> clearIfUnchanged(
      Box<dynamic> box, String date, int token) async {
    if (_inFlight.contains(date)) return;
    final m = _readRaw(box);
    if (m[date] != token) return;
    m.remove(date);
    _touch(date);
    await _write(box, m);
  }

  /// Drops marks of dates with no `schedule_<date>` row NOW (not a list a
  /// pass collected earlier: a swap during the pass may have created one).
  static Future<void> prune(Box<dynamic> box) async {
    final m = _readRaw(box);
    final drop = m.keys
        .where((d) =>
            d != _kSeqEntry &&
            !_inFlight.contains(d) &&
            !box.containsKey('schedule_$d'))
        .toList();
    if (drop.isEmpty) return;
    for (final d in drop) {
      m.remove(d);
      _touch(d);
    }
    await _write(box, m);
  }
}
