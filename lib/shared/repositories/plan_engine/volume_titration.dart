// Batch 9 (W2.7) — phase-boundary volume titration.
//
// At a genuine FRESH phase advance, nudge each MAJOR MUSCLE GROUP's weekly
// direct-set volume by ±1, clamped to [MEV=8, MRV=20] sets/group/week, from
// phase-N evidence:
//   • per-GROUP e1RM trend (reuses the W2.4 e1RM scan construction + the shared
//     `sessionMaxE1rm`) — the per-muscle performance signal;
//   • GLOBAL readiness soreness (W2.3) — a SYSTEMIC damper, not a per-muscle
//     input (soreness is a single daily axis, `readiness.dart`), governing the
//     +1 direction ONLY.
//
// SAFE polarity: −1 (pull volume back) fires on demonstrated e1RM DECLINE alone;
// +1 (add volume) requires POSITIVE recovery evidence (enough readiness rows AND
// not systemically sore). With readiness ship-dark (0 rows) titration therefore
// only ever TRIMS, never blindly adds.
//
// Two seams keep it inert:
//   • `enable_volume_titration` (default OFF) → `resolveDeltas` returns `{}`.
//   • the ORCHESTRATOR only calls this when the caller opts in (a fresh advance,
//     `pins == null`) — coach-regen / edit-profile / previews / hotel / onboarding
//     never do → untouched regardless of the flag.
// Empty deltas → `applyToWeeks` returns the SAME list reference → byte-identical.

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/core/utils/readiness.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';

import 'e1rm_history.dart';
import 'models.dart';
import 'muscle_groups.dart';
import 'plan_engine_flags.dart';

class VolumeTitration {
  VolumeTitration._();

  /// Effective per-GROUP weekly direct-set band (R5 landmark; same source of
  /// numbers as `plan_scorecard.dart` `_mev`/`_mrv`, but a DISTINCT measurement
  /// context — the scorecard scores a `default_sets` selection proxy; here the
  /// clamp is on the real periodized weekly set count).
  static const int _mevPerWeek = 8;
  static const int _mrvPerWeek = 20;

  /// Trailing IST-day window of `exlog_*` / `readiness_*` counted as CURRENT
  /// evidence (a phase is 28 days; the advance fires at the boundary). Mirrors
  /// `DeloadE1rmScan`'s 35-day recency bound.
  static const int _windowDays = 35;

  /// Minimum readiness check-ins in the window before a +1 bump is trusted.
  static const int _minReadinessSample = 3;

  /// Per-major-group set deltas (∈ {-1, +1}) for the NEXT phase, or `const {}`
  /// when the flag is OFF / phase < 2 / no evidence. Crash-safe (never throws).
  static Map<String, int> resolveDeltas({required int phase}) {
    try {
      if (!PlanEngineFlags.volumeTitrationEnabled || phase < 2) return const {};

      final cutoff =
          istDateStr(nowWall().subtract(const Duration(days: _windowDays)));

      // ── per-EXERCISE e1RM trend over the window (shared builder) ──
      // exerciseName -> (istDate -> max Epley e1RM that day). Batch 12-A extracted
      // this loop to `e1rm_history.dart` (ONE loop for deload + titration + plateau
      // — the #1 writer/reader-drift class; byte-identical to the old inline loop).
      final wbox = HiveService.instance.workoutBox;
      final byExercise = buildE1rmByDate(wbox, cutoff: cutoff);

      // Aggregate exercise → major GROUP trend. A group `dropped` if ANY of its
      // evaluable exercises' latest dated session < its prior; `hasEvidence` if
      // it has ≥1 evaluable exercise (≥2 dated sessions).
      final repo = ExerciseRepository.instance;
      final groupDropped = <String>{};
      final groupHasEvidence = <String>{};
      byExercise.forEach((name, dated) {
        if (dated.length < 2) return; // need ≥2 dated sessions
        final row = repo.getByExactName(name);
        if (row == null) return; // custom / absent → no group mapping
        final groups = _groupsForRow(row);
        if (groups.isEmpty) return;
        // top-2 most-recent DISTINCT dates (YYYY-MM-DD lexical desc)
        final dates = dated.keys.toList()..sort((a, b) => b.compareTo(a));
        final declining = dated[dates[0]]! < dated[dates[1]]!;
        for (final g in groups) {
          groupHasEvidence.add(g);
          if (declining) groupDropped.add(g);
        }
      });

      // ── global readiness recovery evidence (POSITIVE-evidence for +1) ──
      final recovered = _recovered(cutoff);

      // ── decision per group (sorted keys → deterministic) ──
      final deltas = <String, int>{};
      final groups = groupHasEvidence.toList()..sort();
      for (final g in groups) {
        if (groupDropped.contains(g)) {
          deltas[g] = -1; // demonstrated decline → trim (safe; no readiness needed)
        } else if (recovered) {
          deltas[g] = 1; // held/gained AND positively recovered → add
        }
        // else held-but-not-recovered / insufficient readiness → hold (omit)
      }
      return deltas;
    } catch (_) {
      return const {};
    }
  }

  /// True iff there are ≥ [_minReadinessSample] readiness check-ins in the window
  /// AND the user is NOT systemically sore (persistent Beat-up). No rows /
  /// insufficient sample → false (→ no +1; the SAFE default).
  static bool _recovered(String cutoff) {
    try {
      final hbox = HiveService.instance.healthBox;
      var n = 0, beatUp = 0;
      for (final entry in hbox.toMap().entries) {
        if (!entry.key.toString().startsWith('readiness_')) continue;
        final raw = entry.value;
        if (raw is! Map) continue;
        final c = ReadinessCheckin.fromMap(raw);
        if (c.date.isEmpty || c.date.compareTo(cutoff) < 0) continue;
        n++;
        if (c.soreness >= 2) beatUp++;
      }
      if (n < _minReadinessSample) return false;
      // systemic fatigue = persistent Beat-up (≥40% of check-ins, min 2).
      final systemicFatigue = beatUp >= 2 && beatUp >= (0.4 * n).ceil();
      return !systemicFatigue;
    } catch (_) {
      return false;
    }
  }

  /// The distinct major groups a library row's `primary_muscles` map to.
  static Set<String> _groupsForRow(Map row) {
    final out = <String>{};
    final pm = row['primary_muscles'];
    final tokens =
        pm is List ? pm : (pm is String && pm.isNotEmpty ? [pm] : const []);
    for (final t in tokens) {
      final g = muscleGroupOf(t.toString());
      if (g != null) out.add(g);
    }
    return out;
  }

  /// Apply per-group ±1 to the generated weeks (pure). Empty deltas → the SAME
  /// list reference (byte-identical inertness — the literal first statement).
  /// Weeks 0/1/2 (baseline/overreach/peak) adjust the visible `sets`; the deload
  /// week (idx 3) leaves visible sets untouched but adjusts a stashed
  /// `workingSets` symmetrically (so a triggered un-deload restores the TITRATED
  /// peak — F1). Clamp: the group's weekly total stays in [MEV,MRV]; one exercise
  /// is adjusted at most once/week (dedup); groups processed in sorted order.
  static List<WeekPlan> applyToWeeks(
      List<WeekPlan> weeks, Map<String, int> deltas) {
    if (deltas.isEmpty) return weeks;
    final sortedGroups = deltas.keys.toList()..sort();
    return [for (final week in weeks) _titrateWeek(week, deltas, sortedGroups)];
  }

  static WeekPlan _titrateWeek(
      WeekPlan week, Map<String, int> deltas, List<String> sortedGroups) {
    final isDeload = week.weekCharacter == 'deload';
    // Mutable per-day copies we can rewrite in place.
    final dayExercises = [for (final d in week.workoutDays) [...d.exercises]];
    final bumped = <String>{}; // "di:xi" already adjusted this week

    for (final g in sortedGroups) {
      final d = deltas[g]!;
      // The group's matching exercises this week + its current weekly base sets.
      final matches = <(int, int)>[];
      var weeklyBase = 0;
      for (var di = 0; di < dayExercises.length; di++) {
        final exs = dayExercises[di];
        for (var xi = 0; xi < exs.length; xi++) {
          if (_matchesGroup(exs[xi], g)) {
            matches.add((di, xi));
            weeklyBase += exs[xi].sets;
          }
        }
      }
      if (matches.isEmpty) continue;

      if (!isDeload) {
        if (d > 0 && weeklyBase < _mrvPerWeek) {
          _applyBump(dayExercises, matches, bumped, 1, working: false);
        } else if (d < 0 && weeklyBase > _mevPerWeek) {
          _applyBump(dayExercises, matches, bumped, -1, working: false);
        }
      } else {
        // Deload week: the stashed workingSets ≈ the peak-week (idx 2) sets, so
        // clamping on the workingSets aggregate mirrors the peak-week decision.
        var workingBase = 0;
        for (final (di, xi) in matches) {
          workingBase += dayExercises[di][xi].workingSets ?? 0;
        }
        if (workingBase == 0) continue; // no stash (deload flag OFF at gen)
        if (d > 0 && workingBase < _mrvPerWeek) {
          _applyBump(dayExercises, matches, bumped, 1, working: true);
        } else if (d < 0 && workingBase > _mevPerWeek) {
          _applyBump(dayExercises, matches, bumped, -1, working: true);
        }
      }
    }

    return WeekPlan(
      weekNumber: week.weekNumber,
      weekInPhase: week.weekInPhase,
      overloadNotes: week.overloadNotes,
      weekCharacter: week.weekCharacter,
      workoutDays: [
        for (var di = 0; di < week.workoutDays.length; di++)
          _rebuildDay(week.workoutDays[di], dayExercises[di]),
      ],
    );
  }

  /// Adjust the FIRST not-yet-bumped matching exercise's `sets` (or `workingSets`)
  /// by [delta], never below 1. Skips an exercise already floored (so a −1 rolls
  /// to the next candidate).
  static void _applyBump(
    List<List<PlannedExercise>> dayExercises,
    List<(int, int)> matches,
    Set<String> bumped,
    int delta, {
    required bool working,
  }) {
    for (final (di, xi) in matches) {
      final id = '$di:$xi';
      if (bumped.contains(id)) continue;
      final ex = dayExercises[di][xi];
      if (working) {
        final cur = ex.workingSets;
        if (cur == null) continue;
        final next = cur + delta;
        if (next < 1) continue;
        dayExercises[di][xi] = ex.copyWith(workingSets: next);
      } else {
        final next = ex.sets + delta;
        if (next < 1) continue;
        dayExercises[di][xi] = ex.copyWith(sets: next);
      }
      bumped.add(id);
      return;
    }
  }

  static bool _matchesGroup(PlannedExercise ex, String group) {
    final pm = ex.primaryMuscles;
    if (pm == null) return false;
    for (final t in pm) {
      if (muscleGroupOf(t) == group) return true;
    }
    return false;
  }

  static WorkoutDay _rebuildDay(WorkoutDay day, List<PlannedExercise> exercises) {
    return WorkoutDay(
      dayNumber: day.dayNumber,
      name: day.name,
      focus: day.focus,
      exercises: exercises,
      warmup: day.warmup,
      cooldown: day.cooldown,
      finisher: day.finisher,
    );
  }
}
