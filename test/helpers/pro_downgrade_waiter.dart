// test/helpers/pro_downgrade_waiter.dart
//
// Waits for `SubscriptionService._downgradeLocally` to FINISH, by its signal.
//
// WHY THIS EXISTS (diagnose b3f8e5, OI-242; recurrence of a3e9b7 + f3c7d2).
// `isPro()` on an expired row starts `_downgradeLocally()` WITHOUT awaiting it
// (`subscription_service.dart:480-483`) — correct production behaviour, since
// `isPro()` is a synchronous bool. `_downgradeLocally` then awaits its Hive
// writes one at a time (`:1191-1195`) and only afterwards fires
// `onStateChanged` (`:1199`) and `onDowngrade` (`:1213`). Hive puts a value
// into the in-memory keystore synchronously (`box_impl.dart:85`), but every
// write after the first `await` sits behind real, per-box-serialised file I/O.
// Tests that waited for that chain with a PROXY — `pumpEventQueue()`, a fixed
// sleep, a 3×10 ms quiescence sampler — lost the race on a loaded CI runner:
// the assertion read the pre-downgrade state, then `tearDown` closed Hive under
// the still-running chain and a trailing `HiveError: Box not found` stacked on
// top. Three fixes in a row widened the proxy. This waits for the signal.
//
// USAGE
//   SubscriptionService.onDowngrade = () => ...;   // the test's own hook, FIRST
//   final downgrade = ProDowngradeWaiter.arm();     // then arm (it CHAINS)
//   SubscriptionService.instance.isPro();           // start the chain
//   await downgrade.wait();                         // the chain has finished
//
// CONTRACT, and the reason for each rule:
//  - `onDowngrade`, not `onStateChanged`: `onDowngrade` fires ONLY from
//    `_downgradeLocally`; `onStateChanged` has other writers (`:70`, `:326`)
//    that would resolve a waiter early.
//  - It CHAINS the hook installed at `arm()` time, never replaces it. Arm AFTER
//    the test sets its own `onDowngrade`; `wait()` fails by name if a later
//    plain assignment dropped the chain.
//  - Nested arms are unsupported and fail immediately — no call site needs
//    them, and a second chain would make "is the installed hook still ours?"
//    unanswerable.
//  - Production calls the hook inside `try { … } catch (_) {}`
//    (`subscription_service.dart:1212-1214`), so a throwing chained hook is
//    swallowed there. The waiter completes in a `finally`, so such a throw
//    still reads as "fired" rather than as a misleading "never fired".
//  - `arm()` registers a SELF-DRAINING teardown. test_api runs teardowns
//    last-in-first-out, so it runs BEFORE the file's own `tearDown` closes Hive
//    or the session. It waits (bounded) for a chain that was started but never
//    awaited, NEVER throws (a teardown failure stacks on top of, and hides, the
//    real one — CLAUDE.md §4.9), then restores the previous hook.
//  - On a `wait()` TIMEOUT the hook is deliberately LEFT installed, so that
//    teardown can still see the chain finish before Hive closes.
//  - Restore is idempotent and never clobbers a hook installed after arm().
//
// PRECONDITION (not covered): after `onDowngrade`, `_downgradeLocally` runs
// `resetToFreeCapOnLapse()`, which STARTS — without awaiting — a progress write
// when `streak_freezes_available > 1`. A test that seeds freezes above 1 is
// NOT fully drained by this waiter.
//
// Not for `pausedForSimulation` paths: a paused `_downgradeLocally` returns
// before either hook, so `wait()` would time out (loudly, by name).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

class ProDowngradeWaiter {
  ProDowngradeWaiter._(this._previous);

  static ProDowngradeWaiter? _active;

  final void Function()? _previous;
  final Completer<void> _fired = Completer<void>();
  late final void Function() _hook;
  bool _restored = false;

  /// True once `onDowngrade` has fired since [arm].
  bool get fired => _fired.isCompleted;

  /// Chains `SubscriptionService.onDowngrade` and registers the self-draining
  /// teardown. Call AFTER the test installs its own `onDowngrade`, and BEFORE
  /// the call that starts the downgrade.
  static ProDowngradeWaiter arm({
    Duration teardownDrain = const Duration(seconds: 5),
  }) {
    final active = _active;
    if (active != null && !active._restored) {
      throw TestFailure(
          'ProDowngradeWaiter.arm() called while another waiter is still '
          'armed. Nested arms are unsupported: wait() on the first one before '
          'arming again.');
    }
    final w = ProDowngradeWaiter._(SubscriptionService.onDowngrade);
    w._hook = () {
      try {
        w._previous?.call();
      } finally {
        if (!w._fired.isCompleted) w._fired.complete();
      }
    };
    SubscriptionService.onDowngrade = w._hook;
    _active = w;
    addTearDown(() => w._drainInTearDown(teardownDrain));
    return w;
  }

  /// Completes once `_downgradeLocally` has fired `onDowngrade`, i.e. after all
  /// of its awaited writes have landed. Throws a [TestFailure] naming the wait
  /// on timeout — deliberately shorter than the 30 s default test budget, so
  /// the failure says what never happened instead of "test timed out".
  Future<void> wait({Duration timeout = const Duration(seconds: 10)}) async {
    if (!_fired.isCompleted &&
        !identical(SubscriptionService.onDowngrade, _hook)) {
      throw TestFailure(
          'ProDowngradeWaiter: SubscriptionService.onDowngrade was REPLACED '
          'after arm(), so the waiter can no longer observe the downgrade. '
          'Install the test\'s own onDowngrade BEFORE calling arm().');
    }
    try {
      await _fired.future.timeout(timeout);
    } on TimeoutException {
      // Hook LEFT installed on purpose: the chain may still be running, and the
      // self-draining teardown must see it finish before Hive is closed.
      throw TestFailure(
          'ProDowngradeWaiter: onDowngrade never fired within '
          '${timeout.inMilliseconds} ms. Either this call site does not '
          'downgrade (paused for simulation? a still-valid row?) or '
          '_downgradeLocally no longer reaches its hooks.');
    }
    _restore();
  }

  Future<void> _drainInTearDown(Duration timeout) async {
    if (!_restored && !_fired.isCompleted) {
      try {
        await _fired.future.timeout(timeout);
      } on TimeoutException {
        // NEVER throw from a teardown — see the header.
        // ignore: avoid_print
        print('[ProDowngradeWaiter] teardown: onDowngrade did not fire within '
            '${timeout.inMilliseconds} ms of the test ending; restoring the '
            'hook. If the test expected a downgrade, its real failure is above.');
      }
    }
    _restore();
    if (identical(_active, this)) _active = null;
  }

  void _restore() {
    if (_restored) return;
    _restored = true;
    if (identical(SubscriptionService.onDowngrade, _hook)) {
      SubscriptionService.onDowngrade = _previous;
    }
  }
}
