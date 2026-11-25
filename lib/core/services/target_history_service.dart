// Target history: which nutrition targets were in force from which day
// (plan docs/plans/nutrition-history.md 5.2 / U1-U10), so the Nutrition
// History screen judges a past day against the target of THAT day.
//
// Stored at `userBox['target_history']`: a list, oldest first, of
//   {from: 'yyyy-MM-dd' (IST), calories, protein, carbs, fat, strategy, at_ms}
// holding the EFFECTIVE numbers (the diet strategy already applied). Water
// is not recorded (its target follows body weight and would churn the list).
//
// ONE writer: [TargetHistoryService.reconcile]. It reads the profile from and
// writes the list to the SAME per-owner userBox, so an entry can only ever
// describe the profile sitting beside it. Callers: ProfileWriteService (after
// each profile put), the day rollover, the post-restore heal, and the History
// screen on open. Every call is idempotent; a missed one is healed by the
// next. Local only until Landing B adds the cloud column.
//
// Stated limit: PRO state is read at call time (`proStateSnapshot`). A profile
// write that lands before PRO is known (the restore on a fresh install)
// records a Keto / Low carb user's Balanced carbs and fat; the next trigger
// the same day replaces the entry. Calories and protein never depend on the
// strategy, so day statuses and hit-rates are unaffected either way.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/nutrition_targets_resolver.dart';
import 'package:icanbefitter/features/nutrition/services/diet_strategy_flags.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';

/// One period of constant targets.
class TargetEntry {
  /// First IST day these targets applied to.
  final String from;
  final int calories, protein, carbs, fat;

  /// `DietStrategy.storageKey` the numbers were made for.
  final String strategy;
  final int atMs;

  const TargetEntry({
    required this.from,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.strategy,
    required this.atMs,
  });

  /// The five compared value fields are equal.
  bool sameTargets(TargetEntry o) =>
      calories == o.calories &&
      protein == o.protein &&
      carbs == o.carbs &&
      fat == o.fat &&
      strategy == o.strategy;

  Map<String, dynamic> toMap() => {
        'from': from,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'strategy': strategy,
        'at_ms': atMs,
      };

  /// Null for a malformed entry (skipped by the reader).
  static TargetEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final from = raw['from'];
    final cal = raw['calories'], pro = raw['protein'];
    final carbs = raw['carbs'], fat = raw['fat'];
    if (from is! String || from.length != 10) return null;
    if (cal is! num || pro is! num || carbs is! num || fat is! num) return null;
    final strategy = raw['strategy'];
    final at = raw['at_ms'];
    return TargetEntry(
      from: from,
      calories: cal.round(),
      protein: pro.round(),
      carbs: carbs.round(),
      fat: fat.round(),
      strategy: strategy is String ? strategy : 'balanced',
      atMs: at is num ? at.toInt() : 0,
    );
  }
}

class TargetHistoryService {
  TargetHistoryService._();

  static const String boxKey = 'target_history';

  /// `configBox` kill switch: true = [reconcile] writes nothing; readers then
  /// see whatever is stored (an empty history on a fresh install).
  static const String killSwitch = 'disable_target_history';

  /// Oldest entries are dropped past this; the new first entry then stands in
  /// for every earlier day.
  static const int maxEntries = 400;

  /// Test seam: thrown inside the next [reconcile] (proves it never rethrows).
  @visibleForTesting
  static Object? debugFailNext;

  /// Entries oldest first; malformed ones skipped. Empty with no session.
  static List<TargetEntry> read() {
    try {
      if (HiveUserSession.currentOwnerFullId == null) return const [];
      return parse(HiveService.instance.userBox.get(boxKey));
    } catch (_) {
      return const [];
    }
  }

  static List<TargetEntry> parse(Object? raw) {
    if (raw is! List) return const [];
    final out = <TargetEntry>[];
    for (final e in raw) {
      final entry = TargetEntry.tryParse(e);
      if (entry != null) out.add(entry);
    }
    out.sort((a, b) => a.from.compareTo(b.from));
    return out;
  }

  /// The entry in force on [day]: the last one with `from <= day`. For a day
  /// before the first entry, the FIRST entry with `assumed: true` (the day is
  /// judged against the earliest known target). Null with no entries.
  static ({TargetEntry entry, bool assumed})? targetFor(
    String day,
    List<TargetEntry> entries,
  ) {
    if (entries.isEmpty) return null;
    TargetEntry? hit;
    for (final e in entries) {
      if (e.from.compareTo(day) <= 0) {
        hit = e;
      } else {
        break;
      }
    }
    if (hit != null) return (entry: hit, assumed: false);
    return (entry: entries.first, assumed: true);
  }

  /// The pure step: [entries] after recording [today]'s targets. Returns the
  /// SAME list instance when nothing changes.
  ///
  /// A same-day entry is replaced (the last change of a day wins); when the
  /// replacement equals the entry before it, the same-day entry is removed.
  static List<TargetEntry> reconciled(
    List<TargetEntry> entries,
    TargetEntry today,
  ) {
    // Entries dated AFTER today describe days that have not happened (the
    // device clock was ahead when they were written, then corrected). They
    // are dropped, never obeyed: keeping one would block every recording
    // until the real date caught up with it.
    if (entries.isNotEmpty && entries.last.from.compareTo(today.from) > 0) {
      final past = [
        for (final e in entries)
          if (e.from.compareTo(today.from) <= 0) e,
      ];
      final next = reconciled(past, today);
      // `next` may be `past` itself (nothing to add): still a change, the
      // future entries are gone.
      return next;
    }
    final hasSameDay = entries.isNotEmpty && entries.last.from == today.from;
    final before = hasSameDay
        ? (entries.length >= 2 ? entries[entries.length - 2] : null)
        : (entries.isEmpty ? null : entries.last);
    if (!hasSameDay) {
      if (before != null && before.sameTargets(today)) return entries;
      return _capped([...entries, today]);
    }
    if (entries.last.sameTargets(today)) return entries;
    final head = entries.sublist(0, entries.length - 1);
    if (before != null && before.sameTargets(today)) return head;
    return _capped([...head, today]);
  }

  static List<TargetEntry> _capped(List<TargetEntry> entries) =>
      entries.length <= maxEntries
          ? entries
          : entries.sublist(entries.length - maxEntries);

  /// Records today's effective targets when they differ from the last entry.
  /// Returns whether it wrote. Never throws; with no open user session, the
  /// kill switch set, or a profile that only resolves to the hard-coded
  /// fallback, it writes nothing.
  ///
  /// Synchronous on purpose: read, compute and `put` with no `await` between
  /// (Hive applies a put to the in-memory box at once), so two back-to-back
  /// calls cannot interleave.
  static bool reconcile({DateTime? now}) {
    try {
      final injected = debugFailNext;
      if (injected != null) {
        debugFailNext = null;
        throw injected;
      }
      if (HiveUserSession.currentOwnerFullId == null) return false;
      final hive = HiveService.instance;
      if (hive.configBox.get(killSwitch) == true) return false;
      final box = hive.userBox;
      // The same userBox['profile'] the list below sits beside.
      final profile = UserRepository.instance.getProfile();

      final at = now ?? nowWall();
      final strategyEnabled = DietStrategyFlags.enabled;
      final t = resolveNutritionTargets(
        profile,
        strategyEnabled: strategyEnabled,
        pro: strategyEnabled && SubscriptionService.instance.proStateSnapshot(),
        now: at,
      );
      // A zero calorie target is not a target (it would judge every day
      // "over"); nothing is recorded for it.
      if (t.isFallback || t.calories <= 0) return false;

      final today = TargetEntry(
        from: istDateStr(at),
        calories: t.calories.round(),
        protein: t.protein.round(),
        carbs: t.carbs.round(),
        fat: t.fat.round(),
        strategy: t.strategy.storageKey,
        atMs: at.millisecondsSinceEpoch,
      );
      final entries = parse(box.get(boxKey));
      final next = reconciled(entries, today);
      if (identical(next, entries)) return false;
      // Not awaited: the value is readable at once; the disk flush follows.
      unawaited(box
          .put(boxKey, [for (final e in next) e.toMap()])
          .catchError((Object e, StackTrace st) {
        // The disk flush failed (box closing, storage full). The next
        // trigger records again; this makes the failure visible.
        debugPrint('[TargetHistoryService.reconcile] put failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'target_history_put'));
      }));
      return true;
    } catch (e, st) {
      debugPrint('[TargetHistoryService.reconcile] $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'target_history_reconcile'));
      return false;
    }
  }
}
