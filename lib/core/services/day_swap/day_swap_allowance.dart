// lib/core/services/day_swap/day_swap_allowance.dart
//
// The weekly day-swap allowance (spec §5.3). A phone copy per IST week
// lives in the user-scoped Hive key `day_swap_allowance`; after each swap a
// background call to `consume-day-swap` (the ONE call site of quota key
// `day_swap`) corrects it. The phone enforces offline; the server count
// wins when online; no answer keeps the phone copy (fail open) and nothing
// retries — a retry after an ambiguous failure could double-count, and one
// uncounted swap is the accepted cost.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../error_telemetry.dart';
import '../hive_service.dart';
import '../supabase_service.dart';
import '../../utils/ist_date.dart';
import 'day_swap_result.dart';
import 'day_swap_rules.dart';

class DaySwapAllowance {
  DaySwapAllowance._();
  static final DaySwapAllowance instance = DaySwapAllowance._();

  /// userBox key: `{ '<IST Monday>': {used, limit?, pro?, server_seen_at_ms?} }`.
  /// `limit` / `pro` / `server_seen_at_ms` come ONLY from a server reply.
  static const String hiveKey = 'day_swap_allowance';
  static const int freeLimit = 1;
  static const int proLimit = 3;

  /// Bumped after every write, so `daySwapAllowanceProvider` refreshes when
  /// a server reply lands in the background.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Test seam: replaces the `consume-day-swap` call. Return the decoded
  /// reply, or null for "no answer".
  @visibleForTesting
  static Future<Map<String, dynamic>?> Function(String weekStart)?
      debugConsumeForTests;

  /// The last background consume, so a test can await it.
  @visibleForTesting
  Future<void>? lastConsumeForTests;

  DayAllowance current(String weekStart, {required bool isPro}) {
    final builtIn = isPro ? proLimit : freeLimit;
    final entry = _readAll(HiveService.instance.userBox)[weekStart];
    if (entry is! Map) {
      return DayAllowance(weekStart: weekStart, used: 0, limit: builtIn);
    }
    final used = (entry['used'] as num?)?.toInt() ?? 0;
    final stored = (entry['limit'] as num?)?.toInt();
    // A server limit applies only to the tier it was seen under: after an
    // upgrade or downgrade the built-in limit stands until the next reply.
    final limit = stored != null && stored > 0 && (entry['pro'] == true) == isPro
        ? stored
        : builtIn;
    return DayAllowance(
        weekStart: weekStart, used: used < 0 ? 0 : used, limit: limit);
  }

  /// Counts one SUCCESSFUL swap: +1 on the phone now, then the server call
  /// in the background (spec §5.3 "After a successful write").
  Future<DayAllowance> recordSwap(String weekStart,
      {required bool isPro}) async {
    final box = HiveService.instance.userBox;
    final before = current(weekStart, isPro: isPro);
    await _write(box, weekStart, used: before.used + 1);
    final consume = _consume(box, weekStart, isPro: isPro);
    lastConsumeForTests = consume;
    unawaited(consume);
    return DayAllowance(
        weekStart: weekStart, used: before.used + 1, limit: before.limit);
  }

  // Only the NEWEST in-flight consume per week may write its reply. Two
  // swaps' background calls can finish out of order; an older reply that
  // lands late is dropped. A later reply with a LOWER count still wins
  // (a server-side correction) — "server wins" holds. In memory only: a
  // restart leaves no call in flight, so nothing needs persisting.
  // Plan-review round 1 slice C F1; reworked by round 2 slice C F3.
  int _consumeSeq = 0;
  final Map<String, int> _latestConsumeSeq = <String, int>{};

  Future<void> _consume(Box<dynamic> box, String weekStart,
      {required bool isPro}) async {
    final seq = ++_consumeSeq;
    _latestConsumeSeq[weekStart] = seq;
    try {
      final hook = debugConsumeForTests;
      final reply =
          hook != null ? await hook(weekStart) : await _callServer(weekStart);
      if (reply == null) return; // no answer: keep the phone copy
      final used = (reply['used'] as num?)?.toInt();
      final limit = (reply['limit'] as num?)?.toInt();
      if (used == null || limit == null || limit < 1) return;
      // Signed out or switched account while the call was in flight: the
      // captured box is closed, and nobody's allowance is written.
      if (!box.isOpen) return;
      // A newer consume for this week was issued after this one: its reply
      // (or the phone copy it will keep) is the current truth.
      if (_latestConsumeSeq[weekStart] != seq) return;
      await _write(box, weekStart,
          used: used,
          serverLimit: limit,
          serverPro: isPro,
          serverSeenAtMs: nowWall().millisecondsSinceEpoch);
    } catch (e, st) {
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'day_swap_allowance_consume'));
    }
  }

  static Future<Map<String, dynamic>?> _callServer(String weekStart) async {
    final res = await SupabaseService.instance
        .callFunction('consume-day-swap', body: {'week_start': weekStart});
    if (res.status != 200) return null;
    final data = res.data;
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Map<String, dynamic> _readAll(Box<dynamic> box) {
    final raw = box.get(hiveKey);
    if (raw is! Map) return <String, dynamic>{};
    return {
      for (final e in raw.entries)
        e.key.toString():
            e.value is Map ? Map<String, dynamic>.from(e.value as Map) : e.value,
    };
  }

  Future<void> _write(
    Box<dynamic> box,
    String weekStart, {
    required int used,
    int? serverLimit,
    bool? serverPro,
    int? serverSeenAtMs,
  }) async {
    final all = _readAll(box);
    final entry = all[weekStart] is Map
        ? Map<String, dynamic>.from(all[weekStart] as Map)
        : <String, dynamic>{};
    entry['used'] = used;
    if (serverLimit != null) {
      entry['limit'] = serverLimit;
      entry['pro'] = serverPro == true;
      entry['server_seen_at_ms'] = serverSeenAtMs;
    }
    all[weekStart] = entry;
    // Prune by TODAY's week. If a reply for last week lands just after IST
    // Monday 00:00, its own entry is pruned in the same write — harmless:
    // that week is over and nothing reads it (round-2 review C F2).
    final currentMonday = DaySwapRules.mondayOf(istTodayStr());
    all.removeWhere((week, _) => week.compareTo(currentMonday) < 0);
    await box.put(hiveKey, all);
    revision.value++;
  }
}
