// OI-348 Landing 1a-ii — the nutrition section (spec
// docs/plans/nutrition-slot-sync.md §4.6, §4.7, §4.12): ONE ticket for the
// nutrition domain, a generation bumped on every account change, the owed
// flags, the capability probe, and the only three bodies that take the ticket
// (push, pull, restore) plus the legacy-mode wrapper. Free of SyncService so
// the call graph is tested with a fake server and a real Hive box.
import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/serial_slot.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_engine.dart';
import 'package:icanbefitter/core/services/sync/nutrition_slot_remote.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';

/// §4.12: how long a restore waits for the ticket.
const Duration kNslotRestoreTicketWait = Duration(seconds: 15);

/// Result of a restore body (the caller turns a failure into
/// `restore_nutrition_slots` with [reason]).
class NslotRestoreResult {
  const NslotRestoreResult.ok()
      : ok = true,
        reason = null;
  const NslotRestoreResult.failed(this.reason) : ok = false;
  final bool ok;
  final String? reason;
}

class NslotSection {
  NslotSection({
    required this.nutritionBox,
    required this.configBox,
    required this.remoteFor,
    required this.ownerChangedSince,
    required this.reportFailure,
    required this.logLow,
    required this.invalidate,
    required this.clearUndoStash,
    required this.schedulePush,
    this.hashSkipDisabled,
  });

  final Box<dynamic> Function() nutritionBox;
  final Box<dynamic> Function() configBox;
  final NslotRemote Function(String userId) remoteFor;
  final bool Function(String userId) ownerChangedSince;
  final void Function(String opType, Object error) reportFailure;
  final void Function(String event, String message) logLow;
  final void Function() invalidate;
  final void Function() clearUndoStash;

  /// `unawaited(syncNutritionData())` — the coalesced push entry.
  final void Function() schedulePush;
  final bool Function()? hashSkipDisabled;

  SerialSlot _slot = SerialSlot();
  int _gen = 0;
  final Map<String, bool> _pushOwed = {};
  final Map<String, bool> _pullOwed = {};
  bool _probeOk = false;
  final Map<String, NslotRebaselineCache> _caches = {};
  Completer<bool>? _rebaselineRun;
  String? _rebaselineUser;
  final Set<String> _onceThisLaunch = {};

  @visibleForTesting
  int get generation => _gen;
  bool get busy => _slot.isBusy;

  /// §4.6: the kill switch is the ONLY way into legacy mode.
  bool get newMode => configBox().get(kDisableNutritionSlotSyncKey) != true;

  /// §4.7: account change. Old bodies stop at their next check (generation),
  /// a NEW body for the new account starts at once (fresh slot).
  void onUserChanged() {
    _gen++;
    _slot = SerialSlot();
    _pushOwed.clear();
    _pullOwed.clear();
    _probeOk = false;
    _caches.clear();
    _rebaselineRun = null;
    _rebaselineUser = null;
    // "Once per launch" means once per account session: another account's
    // stuck slot of the same date and meal must still be logged (B-pass
    // delta seat P3).
    _onceThisLaunch.clear();
  }

  void _lowOnce(String event, String message) {
    if (_onceThisLaunch.add(event)) logLow(event, message);
  }

  bool Function() _staleFor(String userId, int gen) =>
      () => ownerChangedSince(userId) || _gen != gen;

  /// Events about a slot that stays stuck (every pass retries it): logged
  /// once per launch per distinct message, not once per pass (B-pass seat B
  /// P3: an oversized slot logged on every meal log).
  static const Set<String> _kStuckSlotEvents = {
    'nslot_slot_too_large',
    'nslot_bad_meal_type',
  };

  void _engineLow(String event, String message) {
    if (!_kStuckSlotEvents.contains(event)) {
      logLow(event, message);
      return;
    }
    if (_onceThisLaunch.add('$event|$message')) logLow(event, message);
  }

  NslotEngine _engine(String userId, bool Function() stale) => NslotEngine(
        box: nutritionBox(),
        remote: remoteFor(userId),
        stale: stale,
        reportFailure: reportFailure,
        logLow: _engineLow,
        invalidate: invalidate,
        clearUndoStash: clearUndoStash,
      );

  /// §4.7 holder's finally: release, then read and clear this user's owed
  /// flags and fire each, only while the user and generation are unchanged —
  /// one synchronous run.
  void _release(SerialTicket ticket, String userId, int gen,
      {bool pushAfter = false, bool pullAfter = false}) {
    ticket.release();
    // An older generation's holder must not consume this generation's owed
    // flags (they are keyed by user only): after A -> B -> A the old A holder
    // released last and ate the new A body's owed push (B-pass seat B P3).
    if (ownerChangedSince(userId) || _gen != gen) return;
    final push = (_pushOwed.remove(userId) ?? false) || pushAfter;
    final pull = (_pullOwed.remove(userId) ?? false) || pullAfter;
    if (push) schedulePush();
    if (pull) unawaited(_owedPull(userId));
  }

  /// An owed or follow-up pull, fired from [_release] with nobody awaiting
  /// it. `SyncService.pullNutritionSlots` is the guard of the launch and
  /// resume pulls; this one had none, so a throw past the engine's own
  /// network catch (a Hive error while applying, a closed box after a user
  /// switch) was an unhandled async error with no `pull_nutrition_slots`
  /// report (B-pass seat B P2, 2026-11-23).
  Future<void> _owedPull(String userId) async {
    try {
      await pullBody(userId);
    } catch (e) {
      reportFailure('pull_nutrition_slots', e);
    }
  }

  /// §4.6 capability probe, memoized only on success. Returns null when the
  /// RPCs answer, else the error (missing or network).
  Future<Object?> _probe(String userId) async {
    if (_probeOk) return null;
    try {
      await remoteFor(userId).serverNow().timeout(kNslotRpcTimeout);
      _probeOk = true;
      return null;
    } catch (e) {
      if (nslotIsRpcMissing(e)) {
        _lowOnce('nslot_rpc_missing', '$e');
      }
      return e;
    }
  }

  // ------------------------------------------------------------------ push

  /// New-mode push body. Never waits for the ticket: busy → owed.
  Future<bool> pushBody(String userId) async {
    if (_slot.isBusy) {
      _pushOwed[userId] = true;
      return true;
    }
    final gen = _gen;
    final ticket = _slot.enter();
    await ticket.turn;
    var pullAfter = false;
    try {
      final stale = _staleFor(userId, gen);
      if (stale()) return true;
      final engine = _engine(userId, stale);
      if (!engine.rebaselined) {
        _lowOnce('nslot_push_gated_not_rebaselined', 'user gate closed');
        return true;
      }
      final probe = await _probe(userId);
      if (probe != null) {
        // Missing: nothing sent, nothing recorded. Network: outage-shaped,
        // so the retry sweep re-arms (R13 P2-1).
        if (!nslotIsRpcMissing(probe)) reportFailure('sync_nslot_put', probe);
        return true;
      }
      final index = SyncSkipIndex(
        box: nutritionBox(),
        domain: SyncSkipDomain.nslot,
        disabled: hashSkipDisabled?.call() ?? false,
        ownerChangedNow: stale,
        reportFailure: (op, e, st) => reportFailure(op, e),
      );
      final out = await engine.push(index, Stopwatch()..start());
      if (out.rpcMissing) _probeOk = false;
      if (out.stoppedOnBudget && out.confirmedRpcs > 0) {
        _pushOwed[userId] = true;
      }
      if (out.legacySeen) pullAfter = true;
      if (out.wroteLocal) invalidate();
      return true;
    } finally {
      _release(ticket, userId, gen, pullAfter: pullAfter);
    }
  }

  // ------------------------------------------------------------------ pull

  /// New-mode pull body (launch, resume, owed). Busy → owed, never waits.
  Future<void> pullBody(String userId) async {
    if (!newMode) return;
    if (_slot.isBusy) {
      _pullOwed[userId] = true;
      return;
    }
    final gen = _gen;
    final ticket = _slot.enter();
    await ticket.turn;
    var pushAfter = false;
    var pullAfter = false;
    try {
      final stale = _staleFor(userId, gen);
      if (stale()) return;
      final probe = await _probe(userId);
      if (probe != null) {
        if (!nslotIsRpcMissing(probe)) {
          reportFailure('pull_nutrition_slots', probe);
        }
        return;
      }
      final engine = _engine(userId, stale);
      if (!engine.rebaselined) {
        pushAfter = await _rebaselineLocked(engine, userId);
        return;
      }
      final out = await engine.pull();
      if (out.legacySeen) pullAfter = true;
      if (out.wroteLocal) invalidate();
      if (out.wroteLocal || out.dirty) pushAfter = true;
    } finally {
      _release(ticket, userId, gen,
          pushAfter: pushAfter, pullAfter: pullAfter);
    }
  }

  /// Runs the re-baseline with a shared result future, so a restore that
  /// meets a running one awaits it (R12 P2-2). Locked: the caller holds the
  /// ticket.
  Future<bool> _rebaselineLocked(NslotEngine engine, String userId) async {
    final run = Completer<bool>();
    _rebaselineRun = run;
    _rebaselineUser = userId;
    var committed = false;
    try {
      committed =
          await engine.rebaseline(_caches[userId] ??= NslotRebaselineCache());
      return committed;
    } catch (e) {
      reportFailure('rebaseline_nutrition', e);
      return false;
    } finally {
      if (identical(_rebaselineRun, run)) {
        _rebaselineRun = null;
        _rebaselineUser = null;
      }
      run.complete(committed);
    }
  }

  // --------------------------------------------------------------- restore

  /// New-mode restore body. [fetchRows] reads the rows (today's paging, each
  /// page under the pull's 20 s timeout); it is not called when the device
  /// is not re-baselined (the re-baseline reads everything itself, and
  /// [preFetched] carries no tombstones and no server time).
  Future<NslotRestoreResult> restoreBody(
    String userId, {
    List<Map<String, dynamic>>? preFetched,
    required Future<List<Map<String, dynamic>>> Function() fetchRows,
  }) async {
    final running = _rebaselineRun;
    if (running != null && _rebaselineUser == userId) {
      final ok = await running.future;
      return ok
          ? const NslotRestoreResult.ok()
          : const NslotRestoreResult.failed('rebaseline_not_committed');
    }
    final gen = _gen;
    final ticket = _slot.enter();
    try {
      await ticket.turn.timeout(kNslotRestoreTicketWait);
    } on TimeoutException {
      // Abandon-on-turn: when its turn comes, release at once, run nothing.
      unawaited(ticket.turn.then((_) => ticket.release()));
      return const NslotRestoreResult.failed('ticket_timeout');
    }
    var pushAfter = false;
    try {
      final stale = _staleFor(userId, gen);
      if (stale()) return const NslotRestoreResult.failed('owner_changed');
      final probe = await _probe(userId);
      if (probe != null) {
        return const NslotRestoreResult.failed('capability_unavailable');
      }
      final engine = _engine(userId, stale);
      if (!engine.rebaselined) {
        final ok = await _rebaselineLocked(engine, userId);
        pushAfter = ok;
        return ok
            ? const NslotRestoreResult.ok()
            : const NslotRestoreResult.failed('rebaseline_not_committed');
      }
      final rows = preFetched ?? await fetchRows();
      if (stale()) return const NslotRestoreResult.failed('owner_changed');
      final out = await engine.restoreSteady(rows);
      if (out.wroteLocal) {
        invalidate();
        pushAfter = true;
      }
      if (out.legacySeen) {
        return const NslotRestoreResult.failed('legacy_seen_rebaseline');
      }
      return const NslotRestoreResult.ok();
    } finally {
      // A legacy-seen stop schedules the pull that runs the FULL re-baseline.
      _release(ticket, userId, gen,
          pushAfter: pushAfter,
          pullAfter: _needsPull(userId));
    }
  }

  bool _needsPull(String userId) {
    try {
      final meta = nutritionBox().get(kNslotMetaKey);
      return meta is Map &&
          meta['rebaselined'] == false &&
          meta['full'] == 'legacy_seen';
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------- legacy

  /// §4.6: every legacy-mode pass runs inside the ticket, and before the
  /// verbatim legacy body starts it sets `rebaselined := false`,
  /// `full := 'legacy_pass'`, so the next new-mode pass re-baselines FULL.
  /// A push finding the section busy sets owed; a restore waits (bounded).
  Future<void> legacyPass(String userId, Future<void> Function() body,
      {required bool isPush}) async {
    if (isPush && _slot.isBusy) {
      _pushOwed[userId] = true;
      return;
    }
    final gen = _gen;
    final ticket = _slot.enter();
    if (isPush) {
      await ticket.turn;
    } else {
      try {
        await ticket.turn.timeout(kNslotRestoreTicketWait);
      } on TimeoutException {
        unawaited(ticket.turn.then((_) => ticket.release()));
        reportFailure('restore_nutrition_logs',
            TimeoutException('nutrition section busy', kNslotRestoreTicketWait));
        return;
      }
    }
    try {
      if (ownerChangedSince(userId) || _gen != gen) return;
      final box = nutritionBox();
      final raw = box.get(kNslotMetaKey);
      final meta = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      meta['rebaselined'] = false;
      meta['full'] = 'legacy_pass';
      final metaWrite = box.put(kNslotMetaKey, meta);
      await metaWrite;
      if (ownerChangedSince(userId) || _gen != gen) return;
      await body();
    } finally {
      _release(ticket, userId, gen);
    }
  }
}
