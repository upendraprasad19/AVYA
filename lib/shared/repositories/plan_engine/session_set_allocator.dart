import 'package:flutter/foundation.dart' show visibleForTesting;

import 'budget_muscle_groups.dart';
import 'models.dart';
import 'plan_engine_flags.dart';
import 'sequencing_engine.dart';
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

  /// Test-only: per day, how many BUDGETED exercises the selector handed the allocator
  /// (before any admission or removal). Lets a test compare two worlds at the selector
  /// stage, independent of rest and time.
  final List<int> slotsSeen = [];

  /// Test-only: per day, every exercise the selector handed the allocator, budgeted or not ([slotsSeen] plus the
  /// not-budgeted rows, e.g. an isometric hold). A rotated-in pick can swap a budgeted row for a not-budgeted one, so
  /// 'rotation adds or drops nothing' is a claim about this count, not [slotsSeen].
  final List<int> rowsSeen = [];

  /// Day indexes the guard filled (either counter).
  final List<int> forcedDays = [];

  /// OI-456 piece B: per day, the slots the count floor force-seated at 2 sets
  /// although they did not fit the clock (never past a cap or a weekly top, and
  /// the day stays at most [SessionBudget.maxForcedOverSeconds] over its budget).
  /// Variant B inherits A's entries for the days it copies.
  final Map<int, List<({String name, int sets})>> countForced = {};

  /// OI-456 piece B: days under their count floor although the selector supplied
  /// enough slots, with the cause: `cap_top` (a session cap or weekly top blocked
  /// every remaining slot) or `clock` (only the forcing bound did).
  final Map<int, String> belowCount = {};

  /// OI-456 piece B: days whose selector slots plus not-budgeted rows are fewer
  /// than the count floor (nothing the allocator can seat).
  final List<int> selectorThin = [];

  /// Hard sets per budget group across the week, after the allocation.
  final Map<String, int> weekly = {};

  /// For each group still below its weekly floor: `cap_limited`,
  /// `co_group_limited`, `time_limited`, `copy_day_limited` (variant B only: the
  /// exercises that could take a set sit on a day copied from A, which B never
  /// grows), `count_limited` (every slot crediting the group was left out by the
  /// level's exercise-count maximum, OI-456 piece B) or `not_trained_by_split`.
  final Map<String, String> belowFloor = {};

  /// One entry per allocated day that has a budgeted exercise: its lead lift
  /// (rank 0). [boundBy] names the group whose cap or top stopped it below
  /// [desired], or null when time (or nothing) did. [sets] is 0 when the lead
  /// lift was not kept (another exercise of the day was), and [groups] are the
  /// budget groups it credits.
  final List<FirstLift> firstLifts = [];

  /// Unit 2A (OI-486): which world this variant's allocation was kept from: `lead` (R1 + R2), `capped` (R2 only) or
  /// `main` (the pre-2A allocation, R3's fallback). Null when the lead-first rule is off.
  String? leadWorld;

  /// Unit 2A: one entry per allocated day that has an admitted budgeted exercise: the day's lead (the row the sequencer
  /// opens the day with, `SequencingEngine.openerOf`, which [firstLifts]' rank 0 often is not). [boundBy] is null when
  /// the lead reached the base sets, else the first group whose session cap or weekly top refuses its next set,
  /// `clock` when only the day's time does, or `unexplained` when nothing refuses it at the end. Filled in every world.
  /// A day variant B copies from A carries A's entry for it, so B's list covers B's whole week; in day order.
  final List<LeadSeat> leadSeats = [];
}

typedef LeadSeat = ({int day, int rank, String name, int sets, String? boundBy});

/// Unit 2A, R3: the three allocations each variant is tried in.
enum _World { lead, capped, main }

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
enum _Why { time, coGroup, cap, frozen, target }

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

  /// Pass A refused it only because the lead-lift reservation would break (rank 0).
  bool reserveBlocked = false;
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
/// Unit 2A (OI-486, founder d26-d29): with the lead-first rule on, a day's LEAD is the budgeted row the sequencer
/// will open it with (`SequencingEngine.openerOf`); R1 seats it at the base sets in pass A when that fits, R2 keeps
/// every other budgeted row at most 1 set above it in pass C (pass D, the focus pass, is exempt), and R3 keeps, per
/// variant, the first of the lead, capped and main worlds that is not worse than main ([worldIsWorse]).
///
/// Pure apart from one flag read: [allocate] reads `PlanEngineFlags.leadFirstEnabled` when its `leadFirst` argument
/// is null. Runs after the exercises are picked and BEFORE
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

  /// Ruling 5, guard (c): whether a slot costing [need] seconds fits [left] seconds, with a 1e-6 tolerance. Eviction
  /// sums the freed seconds in its own order while the ledger subtracts each hold's cost one at a time, so at an exact
  /// boundary the two can differ by an ulp; the decision and the check after the evictions both use this one
  /// comparison so they agree (B-pass, seat A).
  @visibleForTesting
  static bool fitsAfterEviction(double need, double left) => need <= left + 1e-6;

  /// Allocate [days]. Which exercises are budgeted is [SessionBudget.isBudgeted]
  /// (a custom, a timed / cardio / distance row and one with no library match keep
  /// their sets). A budgeted exercise's muscles are the ones it carries
  /// (`PlannedExercise.primaryMuscles`, copied from the row that was picked), else
  /// those of its row in [rowsByName] (lowercased name -> library row).
  ///
  /// [leadFirst] turns the Unit 2A rule on or off for this call; null reads the kill switch
  /// (`PlanEngineFlags.leadFirstEnabled`, default ON). Off is the pre-2A allocation byte for byte.
  static List<PopulatedDay> allocate({
    required List<PopulatedDay> days,
    required SessionBudgetContext ctx,
    required Map<String, Map<String, dynamic>> rowsByName,
    required bool is6Day,
    bool? leadFirst,
  }) {
    if (leadFirst ?? PlanEngineFlags.leadFirstEnabled) {
      return _allocateLeadFirst(days: days, ctx: ctx, rowsByName: rowsByName, is6Day: is6Day);
    }
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
          stats['B'] = AllocationStats(), copyFrom: stats['A'], copyEvicted: a.evicted);
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

  /// Unit 2A, R3: whether a world's allocation is worse than main's: a day holds fewer rows (budgeted and not) than
  /// `min(floor, main's rows that day)`, or a group main trains in the week (weekly sets > 0) is at 0. Pure. Says
  /// nothing about a group's weekly sets otherwise, a swapped exercise or a day's minutes (plan section 3).
  @visibleForTesting
  static bool worldIsWorse(
    List<int> rows,
    Map<String, int> weekly,
    List<int> mainRows,
    Map<String, int> mainWeekly,
    int floor,
  ) {
    for (var d = 0; d < mainRows.length; d++) {
      final want = mainRows[d] < floor ? mainRows[d] : floor;
      if ((d < rows.length ? rows[d] : 0) < want) return true;
    }
    for (final e in mainWeekly.entries) {
      if (e.value > 0 && (weekly[e.key] ?? 0) == 0) return true;
    }
    return false;
  }

  /// Unit 2A, R3: each variant allocated in the lead (L), capped (C) and main (M) worlds; a variant keeps L when it is
  /// not worse than M, else C when C is not, else M. B's M is main's B (over main A's copied days); B's L and C copy
  /// the CHOSEN A's days and stats. When neither B world holds, the whole plan falls back to main (A = M, B = M_B), so
  /// the kept B is never an unchecked mix. The 6-day path keeps B = A.
  static List<PopulatedDay> _allocateLeadFirst({
    required List<PopulatedDay> days,
    required SessionBudgetContext ctx,
    required Map<String, Map<String, dynamic>> rowsByName,
    required bool is6Day,
  }) {
    final floor = SessionBudget.countFloor(ctx.minutes);
    List<int> rowsOf(List<List<PlannedExercise>> out) => [for (final d in out) d.length];
    bool worse(List<List<PlannedExercise>> w, AllocationStats ws, List<List<PlannedExercise>> m, AllocationStats ms) =>
        worldIsWorse(rowsOf(w), ws.weekly, rowsOf(m), ms.weekly, floor);

    final listsA = [for (final d in days) d.exercisesA];
    final sAM = AllocationStats()..leadWorld = 'main';
    final aM = _variant(listsA, days, ctx, rowsByName, null, sAM);
    var sA = AllocationStats()..leadWorld = 'lead';
    var a = _variant(listsA, days, ctx, rowsByName, null, sA, world: _World.lead);
    if (worse(a.out, sA, aM.out, sAM)) {
      final sC = AllocationStats()..leadWorld = 'capped';
      final c = _variant(listsA, days, ctx, rowsByName, null, sC, world: _World.capped);
      if (!worse(c.out, sC, aM.out, sAM)) {
        (a, sA) = (c, sC);
      } else {
        // Not reachable today (B review, seat 3, M14): the capped world seats exactly main's rows (passes A, A2 and B
        // are main's; passes C and D seat nothing and only add sets), so it is never worse than main in A; the gate
        // pins A's worlds at lead / capped only. Kept so a later pass that seats or removes after pass B stays safe.
        (a, sA) = (aM, sAM);
      }
    }

    final stats = <String, AllocationStats>{'A': sA};
    var bOut = a.out;
    if (!is6Day) {
      // A day whose B list is the same object as A's, or has the same names, copies the given A allocation (P2-7).
      Map<int, List<_Slot>> copyOf(List<List<_Slot>> byDay) => {
            for (var d = 0; d < days.length; d++)
              if (_sameNames(days[d].exercisesA, days[d].exercisesB)) d: byDay[d],
          };
      final listsB = [for (final d in days) d.exercisesB];
      final sBM = AllocationStats()..leadWorld = 'main';
      final bM = _variant(listsB, days, ctx, rowsByName, copyOf(aM.byDay), sBM,
          copyFrom: sAM, copyEvicted: aM.evicted);
      ({List<List<PlannedExercise>> out, List<List<_Slot>> byDay, Map<int, Set<int>> evicted})? kept;
      AllocationStats? sB;
      for (final w in const [_World.lead, _World.capped]) {
        final st = AllocationStats()..leadWorld = w.name;
        final b = _variant(listsB, days, ctx, rowsByName, copyOf(a.byDay), st,
            copyFrom: sA, copyEvicted: a.evicted, world: w);
        if (!worse(b.out, st, bM.out, sBM)) {
          (kept, sB) = (b, st);
          break;
        }
      }
      if (kept == null || sB == null) {
        // Neither B world holds: the whole plan falls back to main (A = M, B = M_B; A's stats become M's).
        a = aM;
        stats['A'] = sAM;
        stats['B'] = sBM;
        bOut = bM.out;
      } else {
        stats['B'] = sB;
        bOut = kept.out;
      }
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

  /// The six major muscle groups (the audit's flip criterion and the parent plan's flip row).
  static const _majorGroups = {'Chest', 'Back', 'Shoulders', 'Quads', 'Hamstrings', 'Glutes'};

  /// The budget-group tokens of [ex]: the muscles it carries (copied from the row
  /// that was actually picked), else those of [row]. A value that is not a list
  /// reads as none, never throws.
  static Set<String> _groupsOf(PlannedExercise ex, Map<String, dynamic>? row, SessionBudgetContext ctx) {
    final raw = ex.primaryMuscles ?? row?['primary_muscles'];
    return BudgetMuscleGroups.creditedOf([
      if (raw is List)
        for (final m in raw)
          if (m != null) '$m',
    ], quadPrimaryCreditsGlutes: ctx.quadPrimaryCreditsGlutes);
  }

  // ── One variant ──────────────────────────────────────────────────────────

  static ({List<List<PlannedExercise>> out, List<List<_Slot>> byDay, Map<int, Set<int>> evicted}) _variant(
    List<List<PlannedExercise>> lists,
    List<PopulatedDay> days,
    SessionBudgetContext ctx,
    Map<String, Map<String, dynamic>> rows,
    Map<int, List<_Slot>>? copy,
    AllocationStats stats, {
    AllocationStats? copyFrom,
    Map<int, Set<int>>? copyEvicted,
    _World world = _World.main,
  }) {
    final n = days.length;
    final ledger = BudgetLedger(ctx, n);
    final byDay = List<List<_Slot>>.generate(n, (_) => <_Slot>[]);
    // Per day, per exercise: its slot, or null when the exercise is not budgeted.
    final entries = List<List<(PlannedExercise, _Slot?)>>.generate(n, (_) => []);
    final all = <_Slot>[];
    final nonBudgeted = List<int>.filled(n, 0);
    // A copied day's holds that variant A evicted: not in this variant's ledger or count, but the selector supplied
    // them, so `rowsSeen` (the selector's rows before any eviction, both variants) still counts them.
    final copiedEvicted = List<int>.filled(n, 0);
    // OI-489 (Unit 1B-F, Ruling 5): the day's library timed rows ("holds"), spent first like every not-budgeted row,
    // but a hold ranked AFTER a time-starved slot may give way to it (pass A). `before` is the number of budgeted
    // slots ahead of the hold, `pos` its index in the day's list (a copied B day mirrors A's evictions by position,
    // since two holds can share a name).
    final timed = List<List<({int before, int pos, PlannedExercise ex, double cost, Set<String> groups})>>.generate(
        n, (_) => []);
    final evicted = <PlannedExercise>{};

    // 1. Classify, and spend the not-budgeted rows' time first.
    for (var d = 0; d < n; d++) {
      var rank = 0;
      for (var pos = 0; pos < lists[d].length; pos++) {
        final ex = lists[d][pos];
        final arch = SessionBudget.archetypeOfPlanned(ex, ctx);
        if (!SessionBudget.isBudgeted(ex, ctx)) {
          // Ruling 8: a timed row at its OWN rest, a rep-based custom at its archetype's
          // (OI-456: the rest follows the exercise, not the day).
          final rest = SessionBudget.isRepBased(ex.loggingType)
              ? SessionBudget.restForArchetype(arch)
              : ex.restSeconds;
          final cost = SessionBudget.plannedExerciseSeconds(ex, ctx, sets: ex.sets, restSeconds: rest);
          if (ex.customOrigin == null &&
              ex.loggingType == 'timed' &&
              ctx.archetypeByName.containsKey(ex.exerciseName.toLowerCase())) {
            timed[d].add((
                before: rank,
                pos: pos,
                ex: ex,
                cost: cost,
                groups: _groupsOf(ex, rows[ex.exerciseName.toLowerCase()], ctx)));
          }
          if ((copy?.containsKey(d) ?? false) && (copyEvicted?[d]?.contains(pos) ?? false)) {
            evicted.add(ex);
            copiedEvicted[d]++;
          } else {
            ledger.add(d, const {}, 0, cost);
            nonBudgeted[d]++;
          }
          entries[d].add((ex, null));
        } else {
          final slot = _Slot(
            d,
            rank++,
            ex,
            _groupsOf(ex, rows[ex.exerciseName.toLowerCase()], ctx),
            arch,
            SessionBudget.restForArchetype(arch),
            SessionBudget.baseSets,
          );
          byDay[d].add(slot);
          entries[d].add((ex, slot));
          all.add(slot);
        }
      }
    }

    // The selector's own reach per day, before any eviction: the count floor and `selectorThin` read it.
    final reachRows = [for (var d = 0; d < n; d++) nonBudgeted[d] + byDay[d].length];
    for (var d = 0; d < n; d++) {
      stats.slotsSeen.add(byDay[d].length);
      stats.rowsSeen.add(byDay[d].length + nonBudgeted[d] + copiedEvicted[d]);
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

    if (copy != null && copyFrom != null) {
      for (final d in copy.keys) {
        final f = copyFrom.countForced[d];
        if (f != null) stats.countForced[d] = List.of(f);
        // A copied day is as short as A's was, for the same reason: name it in B's stats too.
        final below = copyFrom.belowCount[d];
        if (below != null) stats.belowCount[d] = below;
        if (copyFrom.selectorThin.contains(d)) stats.selectorThin.add(d);
        // Unit 2A: a copied day's lead is A's lead on it, at A's sets (B review, seat 1 finding 2).
        stats.leadSeats.addAll(copyFrom.leadSeats.where((e) => e.day == d));
      }
    }

    double seconds(_Slot s, int sets) =>
        SessionBudget.exerciseSeconds(archetype: s.archetype, sets: sets, restSeconds: s.rest);

    // OI-456 piece B: how many main exercises each day may hold, and how many of
    // them pass A has seated so far.
    final levelMax = SessionBudget.countMax(ctx.level) < SessionBudget.hardMax
        ? SessionBudget.countMax(ctx.level)
        : SessionBudget.hardMax;
    final target = <int>[
      for (var d = 0; d < n; d++) levelMax - nonBudgeted[d] < 0 ? 0 : levelMax - nonBudgeted[d],
    ];
    final seated = List<int>.filled(n, 0);
    for (final e in (copy ?? const <int, List<_Slot>>{}).entries) {
      seated[e.key] = byDay[e.key].where((s) => s.admitted).length;
    }

    // Ruling 5: which library holds of day [d], ranked after rank [rank], give way so a slot costing [need] seconds
    // fits the clock. Scanned last first; never a hold whose groups [credited] (with the other kept holds) would no
    // longer cover, never below the day's count floor, a hold crediting a major or focus group only when [bringsMajor];
    // decided before anything is evicted (all or nothing). Evicts the chosen holds and returns whether any went.
    bool evictFor(int d, int rank, double need, Set<String> credited, {required bool bringsMajor}) {
      final kept = [for (final t in timed[d]) if (!evicted.contains(t.ex)) t];
      Set<String> creditedWithout(Set<PlannedExercise> gone) => {
            ...credited,
            for (final t in kept) if (!gone.contains(t.ex)) ...t.groups,
          };
      // The day's reach (its kept holds plus every slot the selector supplied) after n evictions must stay at or
      // above the count floor, so pass A2 can still bring the day to it.
      final reachNow = nonBudgeted[d] + byDay[d].length;
      final floor = SessionBudget.countFloor(ctx.minutes);
      final chosen = <PlannedExercise>{};
      var freed = 0.0;
      for (final t in kept.reversed) {
        if (t.before <= rank) continue;
        if (fitsAfterEviction(need, ledger.secondsLeft(d) + freed)) break;
        if (reachNow - (chosen.length + 1) < floor) break;
        if (!bringsMajor && t.groups.any(_majorGroups.contains)) continue;
        // A hold crediting a group the user focuses on gives way only to a slot that brings a major group (rounds
        // 9-10: majors first, then focus, then the other minors).
        if (!bringsMajor && t.groups.any(ctx.focusGroups.contains)) continue;
        final trial = {...chosen, t.ex};
        if (!t.groups.every(creditedWithout(trial).contains)) continue;
        chosen.add(t.ex);
        freed += t.cost;
      }
      // Guard (c): the same comparison, with its tolerance, as pass A's check after the evictions.
      if (chosen.isEmpty || !fitsAfterEviction(need, ledger.secondsLeft(d) + freed)) return false;
      for (final t in kept) {
        if (!chosen.contains(t.ex)) continue;
        evicted.add(t.ex);
        ledger.add(d, const {}, 0, -t.cost);
        nonBudgeted[d]--;
        target[d]++;
      }
      return true;
    }

    // Unit 2A: each day's opener, the budgeted row the sequencer will put first, taken before allocation (R1's lead).
    _Slot? openerAmong(Iterable<_Slot> slots) {
      final list = slots.toList();
      final ex = SequencingEngine.openerOf([for (final o in list) o.exercise]);
      for (final o in list) {
        if (identical(o.exercise, ex)) return o;
      }
      return null;
    }

    final opener = <_Slot?>[
      for (var d = 0; d < n; d++) world == _World.main ? null : openerAmong(byDay[d]),
    ];

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

        // OI-456 piece B: the day holds at most [target] main exercises, so a
        // slot past it is left out by the count, not by time, cap or top.
        if (seated[d] >= target[d]) {
          s
            ..removed = true
            ..why = {for (final g in s.groups) g: _Why.target};
          continue;
        }

        // Unit 2A, R1: the lead world seats the day's lead at the base sets when that fits (time, caps, top and, at
        // rank 0, the reservation; never an eviction). Else it is handled exactly as on main, below.
        if (world == _World.lead && identical(s, opener[d])) {
          const kb = SessionBudget.baseSets;
          if (ledger.fits(d, s.groups, kb, seconds(s, kb)) && reserved(kb)) {
            s
              ..sets = kb
              ..admitted = true;
            seated[d]++;
            ledger.add(d, s.groups, kb, seconds(s, kb));
            continue;
          }
        }

        // Every exercise is SEATED at 2 sets; pass B grows it to the base sets.
        const k = 2;
        var fitsNow = ledger.fits(d, s.groups, k, seconds(s, k));
        if (!fitsNow && reserved(k) && ledger.fits(d, s.groups, k, double.negativeInfinity)) {
          // Time alone refuses a slot that would give the day its FIRST credit for one of its groups:
          // library timed rows ranked AFTER it may give way, last first, but never a hold that is the
          // day's only credit for one of its own groups; decided before anything is evicted, and never
          // below the day's count floor.
          final seatedGroups = {
            for (final o in byDay[d]) if (o.admitted) ...o.groups,
          };
          // Week-aware (rounds 6-7): only a group the week has no credit for yet counts as new: no budgeted set in the
          // ledger and no kept library timed row on any day of this variant, this day included (holds enter the
          // ledger with no groups).
          final weekHoldGroups = {
            for (final dayTimed in timed)
              for (final t in dayTimed)
                if (!evicted.contains(t.ex)) ...t.groups,
          };
          final newGroups = {
            for (final g in s.groups)
              // A slot seated on this day has already put its sets in the ledger, so `week(g) == 0` covers it.
              if (ledger.week(g) == 0 && !weekHoldGroups.contains(g))
                g,
          };
          // A hold that credits a major group gives way only to a slot whose new credit includes a major group.
          if (newGroups.isNotEmpty &&
              evictFor(d, r, seconds(s, k), {...s.groups, ...seatedGroups},
                  bringsMajor: newGroups.any(_majorGroups.contains))) {
            // Caps and tops were checked before anything was evicted, and an eviction changes neither.
            fitsNow = fitsAfterEviction(seconds(s, k), ledger.secondsLeft(d));
          }
        }
        if (fitsNow && !reserved(k)) s.reserveBlocked = true;
        if (fitsNow && reserved(k)) {
          s
            ..sets = k
            ..admitted = true;
          seated[d]++;
          ledger.add(d, s.groups, k, seconds(s, k));
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
      // Ruling 5c (Unit 1B-F, found by the session-budget gate once every goal ran on the core-list pool): the lead
      // comes in either way, so the first-credit condition of pass A does not apply; the holds ranked after it give way
      // under pass A's other guards when that brings the day back inside its minutes. Without it the lead is forced past
      // the clock (lose_fat|4|advanced|bodyweight|30|1, Upper Pull: four holds and Sliding Lat Pull, 32.6 minutes).
      if (seconds(pick, 2) > ledger.secondsLeft(d)) {
        evictFor(d, pick.rank, seconds(pick, 2), pick.groups,
            bringsMajor: pick.groups.any(_majorGroups.contains));
      }
      pick
        ..sets = 2
        ..admitted = true
        ..removed = false;
      ledger.add(d, pick.groups, 2, seconds(pick, 2));
    }

    // 4b. Pass A2 (OI-456 piece B): the count floor. Pass A already skips a slot that
    // does not fit and carries on, so the only thing left to do here is FORCE: a day
    // under its floor takes its cheapest remaining slot at 2 sets even though the
    // clock says no, never past a session cap or weekly top and only while the day
    // stays within [SessionBudget.maxForcedOverSeconds] of its budget. One slot per
    // day per round (so no day starves another's weekly room), until nothing changes.
    final floorBase = SessionBudget.countFloor(ctx.minutes);
    int rowsOf(int d) => nonBudgeted[d] + byDay[d].where((s) => s.admitted).length;
    int floorOf(int d) {
      final reach = reachRows[d];
      return floorBase < reach ? floorBase : reach;
    }

    bool canForce(int d, _Slot s) {
      for (final g in s.groups) {
        if (ledger.week(g) + 2 > ledger.weeklyTop(g)) return false;
        if (ledger.session(d, g) + 2 > ledger.cap(g)) return false;
      }
      return true;
    }

    bool forceable(int d, _Slot s) =>
        !s.admitted &&
        !s.reserveBlocked &&
        canForce(d, s) &&
        ledger.secondsLeft(d) - seconds(s, 2) >= -SessionBudget.maxForcedOverSeconds;

    var forcedAny = true;
    while (forcedAny) {
      forcedAny = false;
      for (final d in allocateDays) {
        if (byDay[d].isEmpty || rowsOf(d) >= floorOf(d)) continue;
        // The lead lift when the bound allows it (B-pass P3-2), else the cheapest remaining slot.
        _Slot? best = forceable(d, byDay[d].first) ? byDay[d].first : null;
        if (best == null) {
          for (final s in byDay[d]) {
            if (!forceable(d, s)) continue;
            if (best == null || seconds(s, 2) < seconds(best, 2)) best = s;
          }
        }
        if (best == null) continue;
        final fitted = ledger.fits(d, best.groups, 2, seconds(best, 2));
        best
          ..sets = 2
          ..admitted = true
          ..removed = false
          ..why = const {};
        ledger.add(d, best.groups, 2, seconds(best, 2));
        if (!fitted) {
          (stats.countForced[d] ??= []).add((name: best.exercise.exerciseName, sets: 2));
        }
        forcedAny = true;
      }
    }

    // The count verdict is final here (passes B, C and D add no row), and it is read BEFORE the grow
    // passes spend weekly top, so a day short only because of the forcing bound still says `clock`
    // (B-pass P3-1).
    for (final d in allocateDays) {
      if (reachRows[d] < floorBase) {
        stats.selectorThin.add(d);
      } else if (rowsOf(d) < floorBase) {
        final remaining = [
          for (final s in byDay[d])
            if (!s.admitted && !s.reserveBlocked && !s.why.values.contains(_Why.target)) s,
        ];
        stats.belowCount[d] = remaining.any((s) => canForce(d, s)) ? 'clock' : 'cap_top';
      }
    }

    // 4c. Pass B: grow every seated exercise to the base sets, rank by rank.
    {
      final order = <_Slot>[
        for (final s in all)
          if (s.admitted && allocateDays.contains(s.day)) s,
      ]..sort((x, y) => x.rank != y.rank ? x.rank.compareTo(y.rank) : x.day.compareTo(y.day));
      for (final s in order) {
        while (s.sets < SessionBudget.baseSets) {
          final dt = seconds(s, s.sets + 1) - seconds(s, s.sets);
          if (!ledger.fits(s.day, s.groups, 1, dt)) break;
          s.sets++;
          ledger.add(s.day, s.groups, 1, dt);
        }
      }
    }

    // Unit 2A: the day's lead once admission is final (passes B to D seat nothing): the opener when admitted, else
    // the opener of the admitted slots, the row week 2 caps against too.
    final lead = <_Slot?>[
      for (var d = 0; d < n; d++)
        opener[d] != null && opener[d]!.admitted
            ? opener[d]
            : openerAmong([for (final o in byDay[d]) if (o.admitted) o]),
    ];

    // Unit 2A, R2: outside the main world, a budgeted slot that is not its day's lead never grows past the lead's
    // sets + 1. Pass B is not capped (it grows to the base sets, and the lead holds at least 2).
    bool underLead(_Slot s) {
      if (world == _World.main) return true;
      final l = lead[s.day];
      if (l == null || identical(l, s)) return true;
      return s.sets + 1 <= l.sets + 1;
    }

    // 5. Passes C and D: +1 rounds until a round adds nothing. [focusPass]: pass D, exempt from R2 (founder d27).
    void grow(Map<String, int> targets, {bool focusPass = false}) {
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
            if (!focusPass && !underLead(s)) continue;
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
    grow({for (final g in ctx.focusGroups) g: SessionBudget.focusWeeklyTop}, focusPass: true);

    // 6. Stats.
    for (final g in BudgetMuscleGroups.groups) {
      final w = ledger.week(g);
      if (w > 0) stats.weekly[g] = w;
      if (w < bottom) stats.belowFloor[g] = _label(g, all, ledger, copy?.keys.toSet() ?? const <int>{});
    }
    for (final d in allocateDays) {
      if (byDay[d].isEmpty) continue;
      final lead = byDay[d].first;
      // OI-456 piece B: the lead lift reaches its base sets AFTER every later day's
      // lead is seated, so what stopped the next set is asked without the reservation.
      if (lead.admitted && lead.sets < lead.desired) {
        lead.boundBy = _firstBlockingGroup(ledger, d, lead, 1, null);
      }
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

    for (final d in allocateDays) {
      final l = world == _World.main
          ? openerAmong([for (final o in byDay[d]) if (o.admitted) o])
          : lead[d];
      if (l == null) continue;
      String? boundBy;
      if (l.sets < SessionBudget.baseSets) {
        final dt = seconds(l, l.sets + 1) - seconds(l, l.sets);
        boundBy = _firstBlockingGroup(ledger, d, l, 1, null) ??
            (dt > ledger.secondsLeft(d) ? 'clock' : 'unexplained');
      }
      stats.leadSeats.add((day: d, rank: l.rank, name: l.exercise.exerciseName, sets: l.sets, boundBy: boundBy));
    }
    stats.leadSeats.sort((x, y) => x.day.compareTo(y.day));

    final out = <List<PlannedExercise>>[
      for (var d = 0; d < n; d++)
        [
          for (final (ex, slot) in entries[d])
            if (slot == null) ...[
              if (!evicted.contains(ex)) ex,
            ] else if (slot.admitted)
              ex.copyWith(sets: slot.sets),
        ],
    ];
    final ev = <int, Set<int>>{};
    for (var d = 0; d < n; d++) {
      for (final t in timed[d]) {
        if (evicted.contains(t.ex)) (ev[d] ??= {}).add(t.pos);
      }
    }
    return (out: out, byDay: byDay, evicted: ev);
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
    if (reasons.isNotEmpty && reasons.every((r) => r == _Why.target)) return 'count_limited';
    return 'cap_limited';
  }
}
