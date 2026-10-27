import 'package:flutter/foundation.dart' show visibleForTesting;

import 'budget_muscle_groups.dart';
import 'models.dart';
import 'session_budget.dart';

/// What one variant ('A' or 'B') of an allocation did, for the ON-world gate and
/// the report (plan Task 3 / Task 7). Read through
/// [SessionSetAllocator.debugLastStats].
class AllocationStats {
  /// Days the empty-day guard filled although the day's time was already spent
  /// (the day had budgeted exercises and admitted none): the lead lift, or, when
  /// a group of the lead lift had no weekly room, the first exercise that did.
  int timeForcedFirst = 0;

  /// Days where the guard had to put the lead lift on even though a group's weekly
  /// room was gone. The gate requires 0.
  int capForcedFirst = 0;

  /// Day indexes the guard filled (either counter).
  final List<int> forcedDays = [];

  /// Hard sets per budget group across the week, after the allocation.
  final Map<String, int> weekly = {};

  /// For each group still below its weekly floor: `cap_limited`,
  /// `co_group_limited`, `time_limited`, `copy_day_limited` (variant B only: the
  /// exercises that could take a set sit on a day copied from A, which B never
  /// grows) or `not_trained_by_split`.
  final Map<String, String> belowFloor = {};

  /// One entry per allocated day that has a budgeted exercise: its lead lift
  /// (rank 0). [boundBy] names the group whose cap or top stopped it below
  /// [desired], or null when time (or nothing) did. [sets] is 0 when the lead
  /// lift was not kept (another exercise of the day was), and [groups] are the
  /// budget groups it credits.
  final List<FirstLift> firstLifts = [];
}

typedef FirstLift = ({
  int day,
  int rank,
  int sets,
  int desired,
  double secondsLeft,
  String? boundBy,
  Set<String> groups,
});

/// Why a grant was refused, per group. [frozen] is only ever a floor label: the
/// slot could take a set but sits on a day variant B copied from A.
enum _Why { time, coGroup, cap, frozen }

/// One budgeted exercise in one variant of one day.
class _Slot {
  _Slot(this.day, this.rank, this.exercise, this.groups, this.archetype, this.rest, this.desired);

  final int day;
  final int rank;
  final PlannedExercise exercise;
  final Set<String> groups;
  final String archetype;
  final int rest;
  final int desired;

  int sets = 0;
  bool admitted = false;
  bool removed = false;
  Map<String, _Why> why = const {};
  String? boundBy;
}

/// Batch B2 (docs/plans/2026-10-22-session-set-budget.md), Task 3: sizes every
/// day of a plan by the user's minutes and the weekly bands, instead of by a
/// fixed exercise count.
///
/// Priority-rank admission across the WEEK: rank 0 of every day first (so each
/// day's lead lift reaches its intended dose before any accessory takes a share),
/// then rank 1, and so on. Then the floors (pass C), then the focus muscles (pass
/// D). Returns days whose `PlannedExercise.sets` are the BASELINE sets (weeks 1/3
/// for variant A, 2/4 for B) with removed exercises dropped; the periodization
/// stage reads them as-is.
///
/// The lead lift's protection (B-pass R1 P2-2): it is protected from the WEEK (the
/// rank-0 reservation keeps 2 sets for every later day that leads with the same
/// group) and from an EMPTY day (the guard), but not from the day's clock. When 2
/// sets of it cost more than the time left and a cheaper lift still fits, the cheaper
/// lift stays and the lead lift is dropped; its [AllocationStats.firstLifts] entry
/// then reads `sets: 0`, and the gate counts such days in the report.
///
/// Pure: no Hive, no flag read. Runs after the exercises are picked and BEFORE
/// `PeriodizationEngine.apply`, titration, sequencing and the superset pairer, so
/// the rank is the split's slot-priority order (not the compound-first order the
/// sequencer gives later) and there is no superset time credit (Ruling 5).
class SessionSetAllocator {
  SessionSetAllocator._();

  /// Set on every [allocate] call so the gate can read it after `generateV4`.
  /// Keys are the variants that were allocated: 'A', and 'B' when the plan is not
  /// 6-day.
  @visibleForTesting
  static Map<String, AllocationStats>? debugLastStats;

  /// Allocate [days]. Which exercises are budgeted is [SessionBudget.isBudgeted]
  /// (a custom, a timed / cardio / distance row and one with no library match keep
  /// their sets). A budgeted exercise's muscles are the ones it carries
  /// (`PlannedExercise.primaryMuscles`, copied from the row that was picked), else
  /// those of its row in [rowsByName] (lowercased name -> library row).
  static List<PopulatedDay> allocate({
    required List<PopulatedDay> days,
    required SessionBudgetContext ctx,
    required Map<String, Map<String, dynamic>> rowsByName,
    required bool is6Day,
  }) {
    final stats = <String, AllocationStats>{};
    final lists = [for (final d in days) d.exercisesA];
    final a = _variant(lists, days, ctx, rowsByName, null, stats['A'] = AllocationStats());

    List<List<PlannedExercise>> bOut;
    if (is6Day) {
      bOut = a.out;
    } else {
      // A day whose B list is the same object as A's, or has the same names, copies
      // A's allocation: those days stay identical in both variants and only the
      // rest are allocated (P2-7).
      final copy = <int, List<_Slot>>{};
      for (var d = 0; d < days.length; d++) {
        if (_sameNames(days[d].exercisesA, days[d].exercisesB)) copy[d] = a.byDay[d];
      }
      final b = _variant([for (final d in days) d.exercisesB], days, ctx, rowsByName, copy,
          stats['B'] = AllocationStats());
      bOut = b.out;
    }
    debugLastStats = stats;
    return [
      for (var d = 0; d < days.length; d++)
        PopulatedDay(
          name: days[d].name,
          focus: days[d].focus,
          dayType: days[d].dayType,
          intensity: days[d].intensity,
          exercisesA: a.out[d],
          exercisesB: bOut[d],
        ),
    ];
  }

  /// Whether two lists name the same exercises in the same order (the same list
  /// object counts). Compared name by name, not by `List.toString()`, which would
  /// run two names that contain ", " together.
  static bool _sameNames(List<PlannedExercise> a, List<PlannedExercise> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].exerciseName != b[i].exerciseName) return false;
    }
    return true;
  }

  /// The budget-group tokens of [ex]: the muscles it carries (copied from the row
  /// that was actually picked), else those of [row]. A value that is not a list
  /// reads as none, never throws.
  static Set<String> _groupsOf(PlannedExercise ex, Map<String, dynamic>? row) {
    final raw = ex.primaryMuscles ?? row?['primary_muscles'];
    return BudgetMuscleGroups.of([
      if (raw is List)
        for (final m in raw)
          if (m != null) '$m',
    ]);
  }

  // ── One variant ──────────────────────────────────────────────────────────

  static ({List<List<PlannedExercise>> out, List<List<_Slot>> byDay}) _variant(
    List<List<PlannedExercise>> lists,
    List<PopulatedDay> days,
    SessionBudgetContext ctx,
    Map<String, Map<String, dynamic>> rows,
    Map<int, List<_Slot>>? copy,
    AllocationStats stats,
  ) {
    final n = days.length;
    final ledger = BudgetLedger(ctx, n);
    final byDay = List<List<_Slot>>.generate(n, (_) => <_Slot>[]);
    // Per day, per exercise: its slot, or null when the exercise is not budgeted.
    final entries = List<List<(PlannedExercise, _Slot?)>>.generate(n, (_) => []);
    final all = <_Slot>[];

    // 1. Classify, and spend the not-budgeted rows' time first.
    for (var d = 0; d < n; d++) {
      final dayRest = SessionBudget.restFor(days[d].intensity);
      var rank = 0;
      for (final ex in lists[d]) {
        final arch = SessionBudget.archetypeOfPlanned(ex, ctx);
        if (!SessionBudget.isBudgeted(ex, ctx)) {
          // Ruling 8: a timed row at its OWN rest, a rep-based custom at the day's.
          final rest = SessionBudget.isRepBased(ex.loggingType) ? dayRest : ex.restSeconds;
          ledger.add(d, const {}, 0,
              SessionBudget.plannedExerciseSeconds(ex, ctx, sets: ex.sets, restSeconds: rest));
          entries[d].add((ex, null));
        } else {
          final slot = _Slot(
            d,
            rank++,
            ex,
            _groupsOf(ex, rows[ex.exerciseName.toLowerCase()]),
            arch,
            dayRest,
            SessionBudget.desiredFor(days[d].intensity),
          );
          byDay[d].add(slot);
          entries[d].add((ex, slot));
          all.add(slot);
        }
      }
    }

    // 2. Days copied from variant A enter the ledger as they are.
    final allocateDays = [for (var d = 0; d < n; d++) if (copy == null || !copy.containsKey(d)) d];
    if (copy != null) {
      for (final e in copy.entries) {
        final mine = byDay[e.key];
        for (var i = 0; i < mine.length && i < e.value.length; i++) {
          final src = e.value[i];
          mine[i]
            ..sets = src.sets
            ..admitted = src.admitted
            ..removed = src.removed
            ..why = src.why;
          if (src.admitted) {
            ledger.add(e.key, mine[i].groups, src.sets,
                SessionBudget.exerciseSeconds(archetype: mine[i].archetype, sets: src.sets, restSeconds: mine[i].rest));
          }
        }
      }
    }

    double seconds(_Slot s, int sets) =>
        SessionBudget.exerciseSeconds(archetype: s.archetype, sets: sets, restSeconds: s.rest);

    // 3. Pass A: priority-rank admission.
    var maxRank = 0;
    for (final d in allocateDays) {
      if (byDay[d].length > maxRank) maxRank = byDay[d].length;
    }
    for (var r = 0; r < maxRank; r++) {
      for (final d in allocateDays) {
        if (r >= byDay[d].length) continue;
        final s = byDay[d][r];
        // Rank-0 reservation (round-3 P1-1): leave room for the later days' lead lifts.
        final later = <String, int>{};
        if (r == 0) {
          for (final g in s.groups) {
            later[g] = allocateDays
                .where((d2) => d2 > d && byDay[d2].isNotEmpty && byDay[d2].first.groups.contains(g))
                .length;
          }
        }
        bool reserved(int k) {
          if (r != 0) return true;
          for (final g in s.groups) {
            if (ledger.weeklyTop(g) - (ledger.week(g) + k) < 2 * later[g]!) return false;
          }
          return true;
        }

        var granted = 0;
        for (var k = s.desired; k >= 2; k--) {
          if (!ledger.fits(d, s.groups, k, seconds(s, k))) continue;
          if (!reserved(k)) continue;
          granted = k;
          break;
        }
        if (granted > 0) {
          s
            ..sets = granted
            ..admitted = true;
          ledger.add(d, s.groups, granted, seconds(s, granted));
          if (r == 0 && granted < s.desired) {
            // The ledger already holds the `granted` sets, so what stopped the NEXT
            // one is asked of ONE more set, not of granted + 1 (B-pass R1 P2-1).
            s.boundBy = _firstBlockingGroup(ledger, d, s, 1, later);
          }
        } else {
          s.removed = true;
          s.why = _whyFlags(ledger, d, s, 2, seconds(s, 2), r == 0 ? later : null);
          if (r == 0) s.boundBy = _firstBlockingGroup(ledger, d, s, 2, later);
        }
      }
    }

    // 4. Empty-day guard: a day with budgeted exercises and none admitted.
    for (final d in allocateDays) {
      if (byDay[d].isEmpty || byDay[d].any((s) => s.admitted)) continue;
      bool room(_Slot s) => s.groups.every((g) => ledger.weeklyTop(g) - ledger.week(g) >= 2);
      // The first exercise (rank 0 when it can) whose groups all have room; rank 0
      // regardless when none does.
      _Slot? pick;
      for (final s in byDay[d]) {
        if (room(s)) {
          pick = s;
          break;
        }
      }
      if (pick == null) {
        pick = byDay[d].first;
        stats.capForcedFirst++;
      } else {
        stats.timeForcedFirst++;
      }
      stats.forcedDays.add(d);
      pick
        ..sets = 2
        ..admitted = true
        ..removed = false;
      ledger.add(d, pick.groups, 2, seconds(pick, 2));
    }

    // 5. Passes C and D: +1 rounds until a round adds nothing.
    void grow(Map<String, int> targets) {
      final order = <_Slot>[
        for (final s in all)
          if (s.admitted && allocateDays.contains(s.day)) s,
      ]..sort((x, y) => x.rank != y.rank ? x.rank.compareTo(y.rank) : x.day.compareTo(y.day));
      var changed = true;
      while (changed) {
        changed = false;
        for (final g in BudgetMuscleGroups.groups) {
          final target = targets[g];
          if (target == null || ledger.week(g) >= target) continue;
          for (final s in order) {
            if (!s.groups.contains(g) || s.sets >= SessionBudget.maxSetsPerExercise) continue;
            final dt = seconds(s, s.sets + 1) - seconds(s, s.sets);
            if (ledger.fits(s.day, s.groups, 1, dt)) {
              s.sets++;
              ledger.add(s.day, s.groups, 1, dt);
              changed = true;
              break;
            }
          }
        }
      }
    }

    final bottom = SessionBudget.weeklyBand(ctx.planGoal, ctx.level).bottom;
    grow({for (final g in BudgetMuscleGroups.groups) g: bottom});
    // In a lighter phase the ledger's weekly top IS the band bottom for every group,
    // focus included, so this pass cannot add a set there.
    grow({for (final g in ctx.focusGroups) g: SessionBudget.focusWeeklyTop});

    // 6. Stats.
    for (final g in BudgetMuscleGroups.groups) {
      final w = ledger.week(g);
      if (w > 0) stats.weekly[g] = w;
      if (w < bottom) stats.belowFloor[g] = _label(g, all, ledger, copy?.keys.toSet() ?? const <int>{});
    }
    for (final d in allocateDays) {
      if (byDay[d].isEmpty) continue;
      final lead = byDay[d].first;
      final sets = lead.admitted ? lead.sets : 0;
      stats.firstLifts.add((
        day: d,
        rank: 0,
        sets: sets,
        desired: lead.desired,
        secondsLeft: ledger.secondsLeft(d),
        boundBy: sets < lead.desired ? lead.boundBy : null,
        groups: lead.groups,
      ));
    }

    final out = <List<PlannedExercise>>[
      for (var d = 0; d < n; d++)
        [
          for (final (ex, slot) in entries[d])
            if (slot == null)
              ex
            else if (slot.admitted)
              ex.copyWith(sets: slot.sets),
        ],
    ];
    return (out: out, byDay: byDay);
  }

  // ── Why a grant was refused ──────────────────────────────────────────────

  /// For each group of [s], whether refusing [addSets] more sets was down to time
  /// alone, to a co-group's cap or top alone, or to anything else (this group's
  /// own cap or top, the lead-lift reservation, or a mixture).
  static Map<String, _Why> _whyFlags(
    BudgetLedger ledger,
    int day,
    _Slot s,
    int addSets,
    double addSeconds,
    Map<String, int>? later,
  ) {
    final timeFail = addSeconds > ledger.secondsLeft(day);
    final groupFail = <String, bool>{};
    for (final g in s.groups) {
      var f = ledger.week(g) + addSets > ledger.weeklyTop(g) ||
          ledger.session(day, g) + addSets > ledger.cap(g);
      if (later != null && ledger.weeklyTop(g) - (ledger.week(g) + addSets) < 2 * (later[g] ?? 0)) {
        f = true;
      }
      groupFail[g] = f;
    }
    final out = <String, _Why>{};
    for (final t in s.groups) {
      final own = groupFail[t]!;
      final other = groupFail.entries.any((e) => e.key != t && e.value);
      if (timeFail && !own && !other) {
        out[t] = _Why.time;
      } else if (other && !own && !timeFail) {
        out[t] = _Why.coGroup;
      } else {
        out[t] = _Why.cap;
      }
    }
    return out;
  }

  /// The first group (in report order) whose cap, top or lead-lift reservation
  /// refuses [addSets] on [day], or null when only time does.
  static String? _firstBlockingGroup(
    BudgetLedger ledger,
    int day,
    _Slot s,
    int addSets,
    Map<String, int>? later,
  ) {
    for (final g in BudgetMuscleGroups.groups) {
      if (!s.groups.contains(g)) continue;
      if (ledger.week(g) + addSets > ledger.weeklyTop(g) ||
          ledger.session(day, g) + addSets > ledger.cap(g)) {
        return g;
      }
      if (later != null && ledger.weeklyTop(g) - (ledger.week(g) + addSets) < 2 * (later[g] ?? 0)) {
        return g;
      }
    }
    return null;
  }

  /// The label for a group still below its floor: the FIRST that applies, in this
  /// order (round-4 P2-5). [copyDays] are the days variant B copied from A: a slot
  /// there that could still take a set is `copy_day_limited`, because B never grows
  /// a copied day (without this it fell through to `cap_limited`, B-pass R1 P3-3).
  static String _label(String g, List<_Slot> all, BudgetLedger ledger, Set<int> copyDays) {
    final crediting = [for (final s in all) if (s.groups.contains(g)) s];
    if (crediting.isEmpty) return 'not_trained_by_split';
    final reasons = <_Why>[];
    for (final s in crediting) {
      if (s.admitted) {
        if (s.sets >= SessionBudget.maxSetsPerExercise) {
          reasons.add(_Why.cap);
        } else {
          final dt = SessionBudget.exerciseSeconds(archetype: s.archetype, sets: s.sets + 1, restSeconds: s.rest) -
              SessionBudget.exerciseSeconds(archetype: s.archetype, sets: s.sets, restSeconds: s.rest);
          if (copyDays.contains(s.day) && ledger.fits(s.day, s.groups, 1, dt)) {
            reasons.add(_Why.frozen);
          } else {
            reasons.add(_whyFlags(ledger, s.day, s, 1, dt, null)[g]!);
          }
        }
      } else if (s.removed) {
        reasons.add(s.why[g] ?? _Why.cap);
      }
    }
    if (reasons.contains(_Why.time)) return 'time_limited';
    if (reasons.contains(_Why.coGroup)) return 'co_group_limited';
    if (reasons.contains(_Why.frozen)) return 'copy_day_limited';
    return 'cap_limited';
  }
}
