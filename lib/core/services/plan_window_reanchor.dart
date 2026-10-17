// lib/core/services/plan_window_reanchor.dart
//
// Free-tier "Hold the Line" durability #1 — the monotonic, phase-gated
// plan-window re-anchor shared by BOTH restore writers (`_restoreWorkoutPlan`
// in sync/sync_workout.dart and `PlanIntegrityReconciler.reconcile`).
//
// The bug it fixes: a free-tier hold extends `plan_end` LOCALLY (holdWeek), but
// a stale cloud `plan_json` snapshot (pushed before the hold) would, on
// re-anchor, overwrite `plan_end` back to its pre-hold value → the materialized
// hold rows fall outside `[plan_start, plan_end]` → invisible → phantom expiry.
//
// The fix must stay surgical: the unconditional re-anchor was itself a
// deliberate fix (diagnose a7d3f1) for a STALE `plan_start` that inflated the
// displayed week number. We keep that: `plan_start` always tracks cloud, and a
// stale-local-plan_start install (different from cloud) still takes cloud
// verbatim. Only a SAME-PHASE snapshot keeps the later `plan_end`. One more
// case (2026-10-16, ensure-current plan A1.8b): a device that has ADVANCED to a
// newer phase (later local `plan_start` AND a higher local plan-blob phase)
// keeps its window against a stale cloud snapshot whose advance push never
// landed; same-phase regens still take cloud, so the a7d3f1 heal is intact.
//
// One shared implementation (no 2nd copy of the rule — the #1 bug class).
// Design + ×2-review record: docs/plan-reviews/hold-mechanic.md.

/// The plan-window values to persist after a phase-gated re-anchor.
/// A `null` field means "nothing to write" (the caller leaves the local value).
class PlanWindowReanchor {
  final String? planStart;
  final String? planEnd;
  const PlanWindowReanchor(this.planStart, this.planEnd);

  /// Resolve the re-anchor given the local + cloud ISO date strings.
  ///
  /// - Fresh install (`localStart == null`) OR a phase advance (cloud
  ///   `plan_start` differs from local, compared date-only) → cloud is
  ///   authoritative: take cloud `plan_start` + cloud `plan_end` verbatim.
  /// - Same phase (cloud `plan_start` == local `plan_start`) → keep the LATER
  ///   `plan_end` (monotonic-up: a hold only ever extends the window; it is
  ///   never legitimately shrunk within a phase). `plan_start` = cloud (== local
  ///   anyway).
  /// - Newer LOCAL phase (opt-in via [keepNewerLocalPhase]): the local
  ///   `plan_start` is strictly AFTER the cloud's AND the local plan blob's
  ///   phase number is strictly greater than the cloud bundle's (both ints) →
  ///   the device has advanced and the cloud snapshot is stale (the advance's
  ///   plan push has not landed). Return `(null, null)` — nothing to write, the
  ///   local window stays and the next plan push corrects the cloud. The phase
  ///   condition is what keeps the a7d3f1 heals working: a same-phase regen
  ///   (login-restore regen, Train repair regen) also yields a later local
  ///   start, and there cloud must still win. A missing / non-int phase on
  ///   either side falls back to the cloud-verbatim rule.
  ///
  /// - Pinned ([localWindowPinned], set while `withPhaseAdvanceLock` is held and
  ///   a local window exists): `(null, null)` - the advance owns the window.
  ///
  /// NOTE (behavioral): within a phase this preserves a spuriously-high local
  /// `plan_end` rather than healing it down to cloud (the old unconditional
  /// re-anchor healed any local value). No current writer produces a
  /// spurious-high `plan_end` — redoWeek4 / holdWeek / generateAndSchedule all
  /// write legitimate ends — so this is a theoretical residual; the behavioral
  /// test pins the intended monotonic-up semantics so a future writer bug can't
  /// hide behind it.
  static PlanWindowReanchor resolve({
    required String? localStart,
    required String? localEnd,
    required String? cloudStart,
    required String? cloudEnd,
    Object? localPlanPhase,
    Object? cloudPlanPhase,
    bool keepNewerLocalPhase = false,
    bool localWindowPinned = false,
  }) {
    // A phase advance is rewriting the local window right now (plan_start and
    // plan_end land before current_plan): a cloud snapshot read mid-write must
    // not move it (B-pass finding 3a, d9b3e7). Only when a local window exists.
    if (localWindowPinned && localStart != null) {
      return const PlanWindowReanchor(null, null);
    }
    final samePhase = localStart != null &&
        cloudStart != null &&
        _sameDay(localStart, cloudStart);
    if (!samePhase) {
      if (keepNewerLocalPhase &&
          localPlanPhase is int &&
          cloudPlanPhase is int &&
          localPlanPhase > cloudPlanPhase &&
          _strictlyAfterDay(localStart, cloudStart)) {
        return const PlanWindowReanchor(null, null);
      }
      // Fresh install or phase advance → cloud authoritative.
      return PlanWindowReanchor(cloudStart, cloudEnd);
    }
    // Same phase → keep the later plan_end (a hold extension must survive).
    return PlanWindowReanchor(cloudStart, _laterIso(localEnd, cloudEnd));
  }

  /// The phase number (1..N) stamped in a `current_plan` blob / bundle `plan`
  /// map (`Phase.toMap` emits `'phase'`), or null when the blob is absent, not
  /// a map, or carries no integral phase. A web JSON double with an integral
  /// value (3.0) counts as 3.
  static int? blobPhase(Object? blob) {
    if (blob is! Map) return null;
    final v = blob['phase'];
    if (v is int) return v;
    if (v is num && v == v.truncateToDouble()) return v.toInt();
    return null;
  }

  /// True when both parse and the calendar day of [a] is strictly after [b]'s.
  static bool _strictlyAfterDay(String? a, String? b) {
    if (a == null || b == null) return false;
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return false;
    return DateTime(da.year, da.month, da.day)
        .isAfter(DateTime(db.year, db.month, db.day));
  }

  static bool _sameDay(String a, String b) {
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null || db == null) return a == b;
    return da.year == db.year && da.month == db.month && da.day == db.day;
  }

  /// The later of two ISO date strings (nulls yield the other; unparseable
  /// yields the parseable one).
  static String? _laterIso(String? a, String? b) {
    if (a == null) return b;
    if (b == null) return a;
    final da = DateTime.tryParse(a);
    final db = DateTime.tryParse(b);
    if (da == null) return b;
    if (db == null) return a;
    return da.isAfter(db) ? a : b;
  }
}
