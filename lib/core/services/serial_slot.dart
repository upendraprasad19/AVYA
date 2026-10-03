/// Runs jobs ONE AFTER THE OTHER without a queue object: each caller gets a
/// [SerialTicket] that waits for the previous caller's ticket to be released.
///
/// closes-diagnose e5b2a9 (B-pass F2). `SyncService.weeklyFullSync` must not
/// overlap itself — a launch sweep and a retry sweep each inherit the OTHER's
/// failures if they interleave — and must not JOIN an older in-flight sweep (a
/// retry that joined one would report "swept after recovery" about a sweep that
/// started before the server came back). The slot/ticket logic lives here, free
/// of `SyncService`, so overlap order, release-on-every-path and reset-while-
/// waiting are fakeAsync-testable (the source-grep that used to guard it left
/// every one of those mutations green).
///
/// Usage — the ticket MUST be released in a `finally`, or every later caller
/// waits forever:
/// ```dart
/// final ticket = slot.enter();
/// await ticket.turn;
/// try { … } finally { ticket.release(); }
/// ```
library;

import 'dart:async';

class SerialSlot {
  Future<void>? _tail;

  /// Joins the line. The returned ticket's [SerialTicket.turn] completes when
  /// every earlier ticket has been released.
  SerialTicket enter() {
    final prior = _tail;
    final done = Completer<void>();
    final future = done.future;
    _tail = future;
    return SerialTicket._(this, prior, done, future);
  }

  /// Account switch: the line belongs to the previous owner. Tickets that are
  /// already waiting still run after the one they wait behind; a NEW caller
  /// starts immediately.
  void reset() {
    _tail = null;
  }
}

class SerialTicket {
  SerialTicket._(this._slot, this._prior, this._done, this._future);

  final SerialSlot _slot;
  final Future<void>? _prior;
  final Completer<void> _done;
  final Future<void> _future;

  /// Completes when it is this ticket's turn. Never throws: a predecessor that
  /// failed is simply finished.
  Future<void> get turn async {
    final p = _prior;
    if (p == null) return;
    try {
      await p;
    } catch (_) {}
  }

  /// Hands the line to the next ticket. Idempotent. Clears the slot's tail only
  /// if THIS ticket is still the newest (a later caller must keep waiting behind
  /// the middle ticket, not skip it).
  void release() {
    if (identical(_slot._tail, _future)) _slot._tail = null;
    if (!_done.isCompleted) _done.complete();
  }
}
