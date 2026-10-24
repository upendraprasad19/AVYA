import 'dart:async';

/// Coalesces a fire-and-forget async "push" so a burst of triggers collapses
/// into 1–2 actual passes instead of one pass per trigger.
///
/// Unit H / H1a (2026-06-27, offline-first cost optimization). Live telemetry
/// proved a fresh signup fired `syncWorkoutData()` ~18× — once per onboarding
/// Hive write — each a full cloud fan-out, flooding the free-tier backend. The
/// fix is to coalesce at the single fan-out entry point: while a pass is
/// in-flight, further triggers set a `_dirty` flag instead of starting a
/// concurrent pass; when the in-flight pass finishes, if dirty, it runs
/// trailing passes **until clean**.
///
/// The trailing loop is a `do { _dirty = false; await task(); } while (_dirty)`
/// — the dirty flag is cleared BEFORE each pass and re-checked AFTER it, so a
/// trigger that arrives *during* a pass (the fan-out streams the box one row at
/// a time across many awaits) is never dropped: it re-raises `_dirty` and the
/// loop runs one more pass. Clearing only at the start without the post-pass
/// re-check would silently lose the last write until the next unrelated sync
/// (the regression the Opus-4.8 review caught — `sync_coalescer_behavioral_test`
/// pins the no-loss semantic).
///
/// Offline-first safe: Hive is the source of truth, every push is idempotent
/// (natural-key upserts), and the next login's full sweep re-pushes anything a
/// coalesced/dropped pass missed. The caller owns the kill-switch
/// (`disable_sync_debounce`) and the app-pause flush.
class SyncCoalescer {
  bool _inFlight = false;
  bool _dirty = false;

  /// True while a pass is currently running. Exposed for tests + the
  /// app-pause flush (which can skip a flush when a drain is already underway).
  bool get isInFlight => _inFlight;

  /// True when a trigger arrived during the in-flight pass and a trailing pass
  /// is still owed. Exposed for tests.
  bool get isDirty => _dirty;

  /// Trigger a pass.
  ///
  /// - If a pass is already in-flight: mark dirty and return immediately (the
  ///   in-flight pass's trailing loop will pick the new state up).
  /// - Otherwise: run [task], then drain any triggers that arrived during it,
  ///   running trailing passes until none are owed.
  ///
  /// Never rethrows — [task] is expected to swallow its own errors (the sync
  /// fan-out already routes failures to telemetry). A throwing [task] still
  /// clears the in-flight flag via the `finally`, so the coalescer can never
  /// wedge.
  Future<void> trigger(Future<void> Function() task) async {
    if (_inFlight) {
      _dirty = true;
      return;
    }
    _inFlight = true;
    try {
      do {
        _dirty = false;
        try {
          await task();
        } catch (_) {
          // [task] is expected to handle its own errors (the sync fan-out
          // routes failures to telemetry). Swallow defensively so a throwing
          // pass can neither wedge the coalescer nor surface as an unhandled
          // fire-and-forget async error; keep draining if a trigger arrived.
        }
      } while (_dirty);
    } finally {
      _inFlight = false;
      _dirty = false;
    }
  }
}
