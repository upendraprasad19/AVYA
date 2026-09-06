// ⑥ Batch 7-B-2 (W2.4 triggered deload): the EVAL + un-deload.
//
// At the week-3→4 rollover (invoked from `day_rollover_service._doRolloverWith
// Ref`, BEFORE the provider-invalidation block so a lifted week repaints),
// decides whether to KEEP the periodization deload (the SAFE default) or LIFT
// week 4 to a working week — reading the per-exercise `working_sets`/
// `working_reps` that Batch 7-B-1 stashes on the deload week (no migration;
// rides plan_json).
//
// SAFE POLARITY: `shouldLift = notBackstop && notDeloadPhase && readinessGood &&
// e1rmNoFatigue` — ALL clauses require POSITIVE evidence; any false / unknown /
// missing → KEEP (recovery is the safe failure mode).
//
// LIVE since 2026-09-01: gated on `disable_triggered_deload` AND `disable_readiness` (the
// readiness clause is a keep signal — running without readiness data would bias
// toward LIFTING). OFF → returns immediately → byte-identical to 7-B-1.
//
// State (user-scoped `workoutBox`, LOCAL-ONLY — never synced; a reinstall-reset
// is SAFE because a lost marker → notBackstop=false → keep, the prudent outcome):
//   - `last_actual_deload_phase`      : the phase a deload was last actually TAKEN.
//   - `deload_evaluated_for_phase_<N>`: idempotency; SET only on a FIRM decision.

import 'dart:async';

import 'package:icanbefitter/core/services/deload_e1rm_scan.dart';
import 'package:icanbefitter/core/services/health_read_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/deload_reason.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/periodization_engine.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_engine_flags.dart';

class DeloadEvaluator {
  DeloadEvaluator._();
  static final DeloadEvaluator instance = DeloadEvaluator._();

  static const String _kMarkerKey = 'last_actual_deload_phase';
  static const String _kFlagPrefix = 'deload_evaluated_for_phase_';
  static const String _kPlanKey = 'current_plan';

  /// Evaluate whether week 4's deload should be lifted. No-op unless both flags
  /// are on. Invoked from the day-rollover (cold-launch + resume converge there)
  /// BEFORE its provider-invalidation block, so a lifted week repaints via the
  /// rollover's own `currentPlan`/`todayWorkout`/`calendarWeek` invalidations —
  /// the eval itself takes no `ref`. The caller wraps this in a try/catch +
  /// `recordNonFatal`.
  Future<void> maybeEvaluate() async {
    // Guard 1 — flags (cheapest). Both required (see D5 flag-ordering).
    if (!PlanEngineFlags.triggeredDeloadEnabled) return;
    if (!PlanEngineFlags.readinessEnabled) return;

    final sched = WorkoutScheduleService.instance;
    // Guard 2 — not expired. The correctness anchor (NOT any auto-advance
    // ordering, which is a concurrent splash call, not a guarantee).
    if (sched.isPhaseExpired()) return;
    // Guard 3 — week 4.
    if (sched.getCurrentWeekNumber() < 4) return;

    final wk4 = sched.getWeek(4);
    if (wk4.isEmpty) return;

    // Derive the phase from the wk4 rows' own stamp (the phase this deload
    // belongs to) — read ONCE, threaded to the flag key + archetype + backstop +
    // (Batch 10) the reason key. The SAME derivation the reason READER uses
    // (`WorkoutScheduleReadService.currentDeloadReason`) → writer==reader.
    final phase = WorkoutScheduleReadService.deloadPhaseFromWeek4(wk4);
    if (phase == null) return;

    final box = HiveService.instance.workoutBox;

    // Guard 4 — idempotency (user-scoped; SET only on a FIRM decision, below).
    final flagKey = '$_kFlagPrefix$phase';
    if (box.get(flagKey) == true) return;

    // Guard 5 — COACH-2: ANY wk4 row coach-generated → keep (their own week-
    // numbering + unconditional wave + never-persisted base make an arithmetic
    // un-deload unsafe).
    final coachStamped = wk4.any(
        (r) => (r['generated_via'] ?? '').toString().startsWith('ai_coach'));
    if (coachStamped) return;

    final workoutRows =
        wk4.where((r) => (r['type'] ?? '') == 'workout').toList();
    if (workoutRows.isEmpty) return;

    // Guard 6 — still a DELOAD. A lifted week carries `week_character:'working'`,
    // so a cross-device / flag-loss re-eval of an already-lifted week is a
    // clean no-op here.
    final stillDeload =
        workoutRows.any((r) => (r['week_character'] ?? '') == 'deload');
    if (!stillDeload) return;

    // Guard 7 — stash presence (only 7-B-1-flag-ON plans stashed; legacy → keep,
    // can't un-deload losslessly).
    final hasStash = workoutRows.any((r) {
      final ex = r['exercises'];
      return ex is List && ex.any((e) => e is Map && e['working_sets'] is int);
    });
    if (!hasStash) return;

    // ── Decide (every clause requires POSITIVE evidence) ──
    final notDeloadPhase =
        PeriodizationEngine.archetypeForPhase(phase) != 'deload';
    final marker = box.get(_kMarkerKey);
    final markerPhase = marker is int ? marker : null;
    // A recent real deload (< 2 phases ago) permits a lift. Null / overdue /
    // future marker → notBackstop=false → keep (safe for ALL phases incl. 1).
    final notBackstop = markerPhase != null &&
        markerPhase <= phase &&
        (phase - markerPhase) < 2;
    final readiness = _readinessGood();
    final e1rm = DeloadE1rmScan.scan();

    final shouldLift =
        notBackstop && notDeloadPhase && readiness.good && e1rm.noFatigue;

    var liftedAny = false;
    if (shouldLift) {
      liftedAny = await _liftWeekFour(wk4);
      await box.put(flagKey, true); // lifted → lock (no deload taken this phase).
    } else {
      // KEEP. A FIRM keep (lock + seed the marker) is any keep NOT caused solely
      // by insufficient data — i.e. an intended deload phase, the backstop forcing
      // it, OR a clause failing on POSITIVE evidence. A pure insufficient-data keep
      // (no readiness entries AND no compound evidence — e.g. an in-flight restore)
      // sets NEITHER → re-evaluates next launch.
      final firmKeep = !notDeloadPhase ||
          !notBackstop ||
          readiness.hadData ||
          e1rm.hasCompoundEvidence;
      if (firmKeep) {
        await box.put(_kMarkerKey, phase); // a deload IS taken this phase.
        await box.put(flagKey, true);
      }
    }

    // W3.1 (Batch 10 explainability): stamp the one-line "why", keyed on THIS
    // deload's phase (the SAME derivation the reader uses → writer==reader), from
    // the ACTUAL outcome (`liftedAny` — a shouldLift with nothing eligible to lift
    // leaves the week a `deload`, so the copy must match the wave the strip shows).
    // Additive + LOCAL-only; only reached under the two flags (Guard 1) → inert off.
    //
    // Unit B: stored as a MAP carrying the outcome `week_character` beside the
    // prose, because the prose alone cannot be validated later. A regen re-stamps
    // week 4 back to `deload` (`workout_schedule_read_service.dart:388`,
    // `:227`) while the idempotency flag at :79 blocks
    // any re-eval from correcting the string — so the READER
    // ([WorkoutScheduleReadService.currentDeloadReason]) compares this character
    // against the blob the strip renders and drops a reason that no longer
    // describes the week. `liftedAny` is the same predicate the copy branches on
    // (`deload_reason.dart:41-43`), so this records what the text already assumes.
    await box.put(
      '${WorkoutScheduleReadService.deloadReasonKeyPrefix}$phase',
      <String, dynamic>{
        'week_character': liftedAny ? 'working' : 'deload',
        'text': deloadDecisionReason(
          shouldLift: shouldLift,
          liftedAny: liftedAny,
          notDeloadPhase: notDeloadPhase,
          notBackstop: notBackstop,
          hasDeloadOnRecord: markerPhase != null,
          readinessGood: readiness.good,
          readinessHadData: readiness.hadData,
          e1rmNoFatigue: e1rm.noFatigue,
          e1rmHasEvidence: e1rm.hasCompoundEvidence,
        ),
      },
    );
  }

  /// readinessGood requires POSITIVE evidence: ≥3 check-ins in the trailing 14
  /// IST days AND a majority green (fewer than half flagged red/yellow). Empty /
  /// sparse window → good=false (keep). `hadData` distinguishes "some readiness
  /// history exists" (a firm signal) from "none" (a possible in-flight restore).
  ({bool good, bool hadData}) _readinessGood() {
    try {
      final hist = HealthReadService.instance.readinessHistory();
      final cutoff = istDateStr(nowWall().subtract(const Duration(days: 14)));
      final window = hist.where((c) => c.date.compareTo(cutoff) >= 0).toList();
      if (window.isEmpty) return (good: false, hadData: false);
      if (window.length < 3) return (good: false, hadData: true);
      final flagged =
          window.where((c) => c.level != ReadinessLevel.green).length;
      // majority green ⇔ fewer than half flagged.
      return (good: flagged * 2 < window.length, hadData: true);
    } catch (_) {
      return (good: false, hadData: false);
    }
  }

  /// Lift week 4: rewrite each qualifying schedule row + the `current_plan` blob
  /// from the stashed working base, then fire durability UNAWAITED.
  Future<bool> _liftWeekFour(List<Map<String, dynamic>> wk4) async {
    // Re-fetch the box (the getter re-asserts ownership per fetch).
    final box = HiveService.instance.workoutBox;
    final todayKey = istDateStr(nowWall());
    var liftedAny = false;

    // 1. Schedule rows — today-or-future, clean planned rows only.
    for (final row in wk4) {
      if ((row['type'] ?? '') != 'workout') continue;
      if (row['status'] != 'planned') continue;
      if (row['shortened_via'] != null) continue; // time-shortened day
      if (row['is_swapped'] == true) continue; // day-swap
      final dateStr = row['date'] as String?;
      if (dateStr == null) continue;
      if (dateStr.compareTo(todayKey) < 0) continue; // past → leave as-is
      final exRaw = row['exercises'];
      if (exRaw is! List) continue;
      if (!exRaw.any((e) => e is Map && e['working_sets'] is int)) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      // FULL-row read-modify-write (upsertScheduled full-REPLACES the row).
      final newRow = Map<String, dynamic>.from(row);
      newRow['exercises'] =
          exRaw.map((e) => e is Map ? _liftExercise(e) : e).toList();
      newRow['week_character'] = 'working';
      await WorkoutWriteService.instance.upsertScheduled(
        date: date,
        entry: newRow,
        source: WriteSource.planGenerator,
      );
      liftedAny = true;
    }

    // If NO eligible row was lifted (e.g. the week is already all completed /
    // swapped / past), the week WAS effectively a deload → leave the blob's
    // 'deload' char honest + skip the durability sync (nothing changed).
    if (!liftedAny) return false;

    // 2. Dual-write the `current_plan` blob's deload week (week_plans[3]).
    final planRaw = box.get(_kPlanKey);
    if (planRaw is Map) {
      final plan = Map<String, dynamic>.from(planRaw);
      final weeks = plan['week_plans'];
      if (weeks is List && weeks.length >= 4 && weeks[3] is Map) {
        final wp = Map<String, dynamic>.from(weeks[3] as Map);
        if ((wp['week_character'] ?? '') == 'deload') {
          wp['week_character'] = 'working';
          wp['overload_notes'] =
              'Working week — recovered, full volume restored.';
          final days = wp['workout_days'];
          if (days is List) {
            wp['workout_days'] = days.map((d) {
              if (d is! Map) return d;
              final dm = Map<String, dynamic>.from(d);
              final ex = dm['exercises'];
              if (ex is List) {
                dm['exercises'] =
                    ex.map((e) => e is Map ? _liftExercise(e) : e).toList();
              }
              return dm;
            }).toList();
          }
          final newWeeks = List<dynamic>.from(weeks);
          newWeeks[3] = wp;
          plan['week_plans'] = newWeeks;
          await box.put(_kPlanKey, plan);
        }
      }
    }

    // 3. Durability — UNAWAITED (offline-first). `upsertScheduled` already fires
    // its own unawaited sync, and the local-wins-non-empty reconciler protects
    // the lifted rows on any later restore. Awaiting here would block cold-launch
    // home navigation (`runRolloverNow` is awaited before `context.go`).
    unawaited(SyncService.instance.pushSnapshot());
    return true;
  }

  /// Rewrite one exercise map from its stash: sets←working_sets, reps←
  /// working_reps, weight_cue←generic. An exercise WITHOUT `working_sets` (an
  /// exercise-level swap-in) is left untouched (per-exercise granularity).
  Map<String, dynamic> _liftExercise(Map<dynamic, dynamic> ex) {
    final m = Map<String, dynamic>.from(ex);
    final ws = m['working_sets'];
    if (ws is int) {
      m['sets'] = ws;
      final wr = m['working_reps'];
      if (wr != null) m['reps'] = wr;
      m['weight_cue'] = 'Working week — full sets and reps';
    }
    return m;
  }
}
