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

  /// Unit 2B (OI-452, founder d30-d33): per day, each slot the 3-exercise floor seated at 2 sets. [FloorSeat.overTop]
  /// names the groups it took past their weekly top; [FloorSeat.overClock] is true when the seat did not fit the day's
  /// remaining seconds when it was seated (d33: the floor is not bound by the clock). A floor seat is never in
  /// [countForced]. Variant B inherits A's entries for the days it copies.
  final Map<int, List<FloorSeat>> floorSeats = {};

  /// Hard sets per budget group across the week, after the allocation.
  final Map<String, int> weekly = {};

  /// Unit 2C-b (hold credit): the groups of the library holds (timed rows) this variant kept.
  final Set<String> holdGroups = {};

  /// Unit 2C-b: the groups this variant credits: [weekly], plus each group only a kept hold trains (read as 1).
  Map<String, int> get credited => {...weekly, for (final g in holdGroups) if (!weekly.containsKey(g)) g: 1};

  /// Unit 2C-b (S3, founder d35 / d38): per day, each slot the weekly minimum seated at 2 sets and the group it was
  /// seated for. Never in [countForced]. Variant B inherits A's entries for the days it copies.
  final Map<int, List<({String name, String group})>> minimumSeats = {};

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

/// Unit 2B: one slot the 3-exercise day floor seated (see [AllocationStats.floorSeats]). [overBy] is each over-top
/// group's excess this seat added (week + 2 - top at seat time, capped at the seat's 2 sets); [overSeconds] is the part of
/// the seat's seconds that did not fit the day's remaining seconds (0 unless [overClock]).
typedef FloorSeat = ({
  String name,
  int sets,
  List<String> overTop,
  Map<String, int> overBy,
  bool overClock,
  double overSeconds,
});

/// Unit 2A, R3: the three allocations each variant is tried in.
enum _World { lead, capped, main }

/// One variant's allocation: its rows per day, its slots per day and the holds it evicted per day.
typedef _Alloc = ({List<List<PlannedExercise>> out, List<List<_Slot>> byDay, Map<int, Set<int>> evicted});

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

  /// Unit 2C-b: the `allowance` the last [allocate] call stamped on its days (S4), so a test reading a whole
  /// `generateV4` plan can apply the shared oracle's allowance excuse. No production reader.
  @visibleForTesting
  static bool? debugLastAllowance;

  /// Unit 2B, F2: whether the day floor prefers candidate [a] to [b]: the fewer groups taken past their weekly top
  /// ([over]), then the smaller sum of those excesses ([excess]), then the cheaper seat at 2 sets ([seconds]). A full tie
  /// is false, so the caller, walking a day's slots in rank order, keeps the lowest rank. No lead preference.
  @visibleForTesting
  static bool floorPrefers(
    ({int over, int excess, double seconds}) a,
    ({int over, int excess, double seconds}) b,
  ) {
    if (a.over != b.over) return a.over < b.over;
    if (a.excess != b.excess) return a.excess < b.excess;
    return a.seconds < b.seconds;
  }

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
  /// [dayFloor] turns the Unit 2B 3-exercise day floor on or off for this call; null reads its kill switch
  /// (`PlanEngineFlags.dayFloorEnabled`, default ON). Off is the pre-2B allocation byte for byte, in both 2A paths.
  /// [balancedWeek] turns Unit 2C-b (the weekly minimum and the under-60 allowance) on or off for this call; null reads
  /// 2C's kill switch (`PlanEngineFlags.balancedWeekEnabled`, default ON). 2C-b runs only on the lead-first path with
  /// the floor on; off, or on any other path, the allocation is the pre-2C-b one byte for byte.
  static List<PopulatedDay> allocate({
    required List<PopulatedDay> days,
    required SessionBudgetContext ctx,
    required Map<String, Map<String, dynamic>> rowsByName,
    required bool is6Day,
    bool? leadFirst,
    bool? dayFloor,
    bool? balancedWeek,
  }) {
    final floorOn = dayFloor ?? PlanEngineFlags.dayFloorEnabled;
    if (leadFirst ?? PlanEngineFlags.leadFirstEnabled) {
      return _allocateLeadFirst(
          days: days,
          ctx: ctx,
          rowsByName: rowsByName,
          is6Day: is6Day,
          dayFloor: floorOn,
          balancedWeek: floorOn && (balancedWeek ?? PlanEngineFlags.balancedWeekEnabled));
    }
    final stats = <String, AllocationStats>{};
    final lists = [for (final d in days) d.exercisesA];
    final a = _variant(lists, days, ctx, rowsByName, null, stats['A'] = AllocationStats(), dayFloor: floorOn);

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
          stats['B'] = AllocationStats(), copyFrom: stats['A'], copyEvicted: a.evicted, dayFloor: floorOn);
      bOut = b.out;
    }
    debugLastStats = stats;
    debugLastAllowance = false;
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
    required bool dayFloor,
    required bool balancedWeek,
  }) {
    // Unit 2C-b (S4): true when the returned days were sized with the under-60 allowance; read by `_weekTwoGains`.
    var allowanceUsed = false;
    final under60 = ctx.minutes < 60;
    final floor = SessionBudget.countFloor(ctx.minutes);
    List<int> rowsOf(List<List<PlannedExercise>> out) => [for (final d in out) d.length];
    bool worse(List<List<PlannedExercise>> w, AllocationStats ws, List<List<PlannedExercise>> m, AllocationStats ms) =>
        worldIsWorse(rowsOf(w), ws.weekly, rowsOf(m), ms.weekly, floor);

    final listsA = [for (final d in days) d.exercisesA];
    final sAM = AllocationStats()..leadWorld = 'main';
    final aM = _variant(listsA, days, ctx, rowsByName, null, sAM);
    var sA = AllocationStats()..leadWorld = 'lead';
    var a = _variant(listsA, days, ctx, rowsByName, null, sA, world: _World.lead);
    var wA = _World.lead;
    if (worse(a.out, sA, aM.out, sAM)) {
      final sC = AllocationStats()..leadWorld = 'capped';
      final c = _variant(listsA, days, ctx, rowsByName, null, sC, world: _World.capped);
      if (!worse(c.out, sC, aM.out, sAM)) {
        (a, sA) = (c, sC);
        wA = _World.capped;
      } else {
        wA = _World.main;
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
      var wB = _World.main;
      for (final w in const [_World.lead, _World.capped]) {
        final st = AllocationStats()..leadWorld = w.name;
        final b = _variant(listsB, days, ctx, rowsByName, copyOf(a.byDay), st,
            copyFrom: sA, copyEvicted: a.evicted, world: w);
        if (!worse(b.out, st, bM.out, sBM)) {
          (kept, sB, wB) = (b, st, w);
          break;
        }
      }
      if (kept == null || sB == null) {
        wA = _World.main;
        wB = _World.main;
      }
      if (dayFloor) {
        // Unit 2B, F3: the worlds were chosen with the floor off; the chosen ones are re-run with it on, A first, then
        // B copying the FLOORED A (a copied day carries its floor sets and `floorSeats` into B's week).
        final sAF = AllocationStats()..leadWorld = wA.name;
        a = _variant(listsA, days, ctx, rowsByName, null, sAF, world: wA, dayFloor: true);
        final sBF = AllocationStats()..leadWorld = wB.name;
        final bF = _variant(listsB, days, ctx, rowsByName, copyOf(a.byDay), sBF,
            copyFrom: sAF, copyEvicted: a.evicted, world: wB, dayFloor: true);
        stats['A'] = sAF;
        stats['B'] = sBF;
        bOut = bF.out;
        if (balancedWeek) {
          // Unit 2C-b (plan docs/plans/2026-11-14-generator-step2c-b-weekly-minimum.md, founder d35-d49). The floor
          // re-run above is the reference R (the pre-2C-b output). Every re-run below keeps the chosen worlds; under 60
          // it takes the allowance (S4), at most R's rows per day (d44: sets, never an extra exercise) and R's hold
          // evictions; at 60+ it runs without them, so only minimum seats can differ from R.
          final aR = a, sAR = sAF, bR = bF, sBR = sBF;
          final capA = under60 ? [for (final d in aR.out) d.length] : null;
          final capB = under60 ? [for (final d in bR.out) d.length] : null;
          final refA = under60 ? aR.evicted : null;
          final refB = under60 ? bR.evicted : null;
          _Alloc runA(AllocationStats st, Set<String> minGroups) => _variant(listsA, days, ctx, rowsByName, null, st,
              world: wA, dayFloor: true, allowance: under60, minGroups: minGroups, rowCap: capA, refEvicted: refA);
          _Alloc runB(_Alloc aNow, AllocationStats sANow, AllocationStats st, Set<String> minGroups) =>
              _variant(listsB, days, ctx, rowsByName, copyOf(aNow.byDay), st,
                  copyFrom: sANow,
                  copyEvicted: aNow.evicted,
                  world: wB,
                  dayFloor: true,
                  allowance: under60,
                  minGroups: minGroups,
                  rowCap: capB,
                  refEvicted: refB);

          // Step 1: the allowance re-run, A then B copying the new A.
          final sA1 = AllocationStats()..leadWorld = wA.name;
          final a1 = runA(sA1, const {});
          final sB1 = AllocationStats()..leadWorld = wB.name;
          final b1 = runB(a1, sA1, sB1, const {});
          a = a1;
          stats['A'] = sA1;
          stats['B'] = sB1;
          bOut = b1.out;

          // Step 2, the targets. 1 (d35): a group the other variant credits and this one does not; 2 (d38): a focus
          // group this variant does not credit; 3 (protective): a group R or step 1 credits that is now at 0. Calves
          // under 45 minutes is never a target of any kind (d45, d49).
          bool exempt(String g) => g == 'Calves' && ctx.minutes < 45;
          Set<String> need(Map<String, int> mine, Map<String, int> other) => {
                for (final e in other.entries)
                  if (e.value > 0 && (mine[e.key] ?? 0) == 0 && !exempt(e.key)) e.key,
                for (final g in ctx.focusGroups)
                  if ((mine[g] ?? 0) == 0 && !exempt(g)) g,
              };
          Set<String> lost(Map<String, int> pre, Map<String, int> now, Set<String> t) => {
                for (final e in pre.entries)
                  if (e.value > 0 && (now[e.key] ?? 0) == 0 && !t.contains(e.key) && !exempt(e.key)) e.key,
              };
          final preA = {for (final e in sAR.credited.entries) if (e.value > 0) e.key: e.value};
          final preB = {for (final e in sBR.credited.entries) if (e.value > 0) e.key: e.value};
          for (final e in sA1.credited.entries) {
            if (e.value > 0) preA[e.key] = e.value;
          }
          for (final e in sB1.credited.entries) {
            if (e.value > 0) preB[e.key] = e.value;
          }
          var tA = {...need(sA1.credited, sB1.credited), ...lost(preA, sA1.credited, const {})};
          var tB = lost(preB, sB1.credited, const {});

          // Step 3: the fixpoint, at most 4 rounds: A with its targets, then B against the new A (target 1 for B is
          // read against the current A); a protective group now at 0 joins its variant's targets.
          for (var it = 0; it < 4; it++) {
            if (tA.isNotEmpty) {
              final st = AllocationStats()..leadWorld = wA.name;
              a = runA(st, tA);
              stats['A'] = st;
            } else {
              a = a1;
              stats['A'] = sA1;
            }
            tB = {...tB, ...need(sB1.credited, stats['A']!.credited)};
            if (tA.isNotEmpty || tB.isNotEmpty) {
              final st = AllocationStats()..leadWorld = wB.name;
              bOut = runB(a, stats['A']!, st, tB).out;
              stats['B'] = st;
            }
            final lA = lost(preA, stats['A']!.credited, tA);
            final lB = lost(preB, stats['B']!.credited, tB);
            if (lA.isEmpty && lB.isEmpty) break;
            tA = {...tA, ...lA};
            tB = {...tB, ...lB};
          }

          bool anyLost() =>
              lost(preA, stats['A']!.credited, const {}).isNotEmpty ||
              lost(preB, stats['B']!.credited, const {}).isNotEmpty;
          // Step 4, protect-first: a group R or step 1 credits is still at 0, so a NEW target (1 or 2) took its row.
          // Re-run both variants with the protective targets only.
          if (anyLost()) {
            final pA = {for (final g in tA) if ((preA[g] ?? 0) > 0) g};
            final pB = {for (final g in tB) if ((preB[g] ?? 0) > 0) g};
            final sAP = AllocationStats()..leadWorld = wA.name;
            a = pA.isEmpty ? a1 : runA(sAP, pA);
            stats['A'] = pA.isEmpty ? sA1 : sAP;
            final sBP = AllocationStats()..leadWorld = wB.name;
            bOut = runB(a, stats['A']!, sBP, pB).out;
            stats['B'] = sBP;
          }
          // Step 5, the terminal guard: still a protective group at 0, so the output is R verbatim (no allowance
          // either). Nothing runs after it.
          if (anyLost()) {
            a = aR;
            stats['A'] = sAR;
            stats['B'] = sBR;
            bOut = bR.out;
          } else {
            allowanceUsed = under60;
          }
        }
      } else if (kept == null || sB == null) {
        // Neither B world holds: the whole plan falls back to main (A = M, B = M_B; A's stats become M's).
        a = aM;
        stats['A'] = sAM;
        stats['B'] = sBM;
        bOut = bM.out;
      } else {
        stats['B'] = sB;
        bOut = kept.out;
      }
    } else if (dayFloor) {
      // Unit 2B, F3 on the 6-day path (B = A): the chosen A world re-run with the floor.
      final sAF = AllocationStats()..leadWorld = wA.name;
      a = _variant(listsA, days, ctx, rowsByName, null, sAF, world: wA, dayFloor: true);
      stats['A'] = sAF;
      bOut = a.out;
      if (balancedWeek) {
        // Unit 2C-b on the 6-day path: the same steps with B = A; no target 1, and the protective set is R's credit.
        final aR = a, sAR = sAF;
        final cap6 = under60 ? [for (final d in aR.out) d.length] : null;
        final ref6 = under60 ? aR.evicted : null;
        _Alloc run6(AllocationStats st, Set<String> minGroups) => _variant(listsA, days, ctx, rowsByName, null, st,
            world: wA, dayFloor: true, allowance: under60, minGroups: minGroups, rowCap: cap6, refEvicted: ref6);
        bool exempt(String g) => g == 'Calves' && ctx.minutes < 45;
        final s1 = AllocationStats()..leadWorld = wA.name;
        a = run6(s1, const {});
        stats['A'] = s1;
        bOut = a.out;
        final pre6 = {for (final e in sAR.credited.entries) if (e.value > 0) e.key: e.value};
        Set<String> lost6(Map<String, int> now, Set<String> t) => {
              for (final e in pre6.entries)
                if (e.value > 0 && (now[e.key] ?? 0) == 0 && !t.contains(e.key) && !exempt(e.key)) e.key,
              for (final g in ctx.focusGroups)
                if ((now[g] ?? 0) == 0 && !t.contains(g) && !exempt(g)) g,
            };
        var t6 = lost6(s1.credited, const {});
        for (var it = 0; it < 4 && t6.isNotEmpty; it++) {
          final st = AllocationStats()..leadWorld = wA.name;
          a = run6(st, t6);
          stats['A'] = st;
          bOut = a.out;
          final l = lost6(st.credited, t6);
          if (l.isEmpty) break;
          t6 = {...t6, ...l};
        }
        Set<String> prot6(Map<String, int> now) => {
              for (final e in pre6.entries)
                if (e.value > 0 && (now[e.key] ?? 0) == 0 && !exempt(e.key)) e.key,
            };
        var fellBack = false;
        if (prot6(stats['A']!.credited).isNotEmpty) {
          final p6 = {for (final g in t6) if ((pre6[g] ?? 0) > 0) g};
          final sP = AllocationStats()..leadWorld = wA.name;
          a = run6(sP, p6);
          stats['A'] = sP;
          bOut = a.out;
          if (prot6(sP.credited).isNotEmpty) {
            a = aR;
            stats['A'] = sAR;
            bOut = a.out;
            fellBack = true;
          }
        }
        allowanceUsed = under60 && !fellBack;
      }
    }
    debugLastStats = stats;
    debugLastAllowance = allowanceUsed;
    return [
      for (var d = 0; d < days.length; d++)
        PopulatedDay(
          name: days[d].name,
          focus: days[d].focus,
          dayType: days[d].dayType,
          intensity: days[d].intensity,
          exercisesA: a.out[d],
          exercisesB: bOut[d],
          allowance: allowanceUsed,
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

  /// Unit 2C-b's arguments (all off by default, so every other call is unchanged): [minGroups] are the weekly
  /// minimum's targets (the walk and the minimum pass); [allowance] builds the ledger with the under-60 allowance
  /// (`SessionBudget.allowanceSeconds`, forcing bound 0); [rowCap] caps each day's rows at the reference's (d44);
  /// [refEvicted] evicts the holds the reference evicted on the days this variant does not copy.
  static _Alloc _variant(
    List<List<PlannedExercise>> lists,
    List<PopulatedDay> days,
    SessionBudgetContext ctx,
    Map<String, Map<String, dynamic>> rows,
    Map<int, List<_Slot>>? copy,
    AllocationStats stats, {
    AllocationStats? copyFrom,
    Map<int, Set<int>>? copyEvicted,
    _World world = _World.main,
    bool dayFloor = false,
    Set<String> minGroups = const {},
    bool allowance = false,
    List<int>? rowCap,
    Map<int, Set<int>>? refEvicted,
  }) {
    final n = days.length;
    final ledger = BudgetLedger(ctx, n, allowance: allowance);
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
          if (((copy?.containsKey(d) ?? false) && (copyEvicted?[d]?.contains(pos) ?? false)) ||
              (!(copy?.containsKey(d) ?? false) && (refEvicted?[d]?.contains(pos) ?? false))) {
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
        final fo = copyFrom.floorSeats[d];
        if (fo != null) stats.floorSeats[d] = List.of(fo);
        final mo = copyFrom.minimumSeats[d];
        if (mo != null) stats.minimumSeats[d] = List.of(mo);
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
    if (rowCap != null) {
      for (var d = 0; d < n; d++) {
        final c = rowCap[d] - nonBudgeted[d];
        if (c < target[d]) target[d] = c < 0 ? 0 : c;
      }
    }
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

    // Unit 2C-b, the walk: pass A walks [walk], a copy of [byDay] in which each target group's cheapest slot follows the
    // rank-0 slot, the day's 2A opener (when it sits later) and earlier moved targets (a target already inside that
    // segment counts as moved). byDay (ranks, copies, passes B / C / D, every other reader) keeps the selector order.
    final walk = [for (final l in byDay) [...l]];
    final moved = List<int>.filled(n, 0);
    for (final g in ([...minGroups]..sort())) {
      if (allocateDays.any((d) => byDay[d].isNotEmpty && byDay[d][0].groups.contains(g))) continue;
      _Slot? best;
      var bd = -1;
      for (final d in allocateDays) {
        for (var i = 1; i < byDay[d].length; i++) {
          final s = byDay[d][i];
          if (!s.groups.contains(g)) continue;
          if (best == null || seconds(s, 2) < seconds(best, 2)) {
            best = s;
            bd = d;
          }
        }
      }
      if (best != null) {
        final op = opener[bd];
        final opAt = op == null ? 0 : walk[bd].indexOf(op);
        final base = (opAt > 0 ? opAt : 0) + 1;
        final at = walk[bd].indexOf(best);
        if (at > base + moved[bd]) {
          walk[bd].remove(best);
          walk[bd].insert(base + moved[bd], best);
        }
        if (at >= base) moved[bd]++;
      }
    }

    // 3. Pass A: priority-rank admission.
    var maxRank = 0;
    for (final d in allocateDays) {
      if (byDay[d].length > maxRank) maxRank = byDay[d].length;
    }
    for (var r = 0; r < maxRank; r++) {
      for (final d in allocateDays) {
        if (r >= byDay[d].length) continue;
        final s = walk[d][r];
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
              evictFor(d, s.rank, seconds(s, k), {...s.groups, ...seatedGroups},
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
        ledger.secondsLeft(d) - seconds(s, 2) >= -ledger.forcingBound;

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

    // Unit 2B (OI-452): the label a day under its count floor gets is what stopped pass A2 (`clock` or `cap_top`); it is
    // taken BEFORE the floor, which can seat the very slots `canForce` reads (plan v6 §2 F4).
    final labelBeforeFloor = <int, String>{};
    for (final d in allocateDays) {
      if (reachRows[d] >= floorBase && rowsOf(d) < floorBase) {
        final remaining = [
          for (final s in byDay[d])
            if (!s.admitted && !s.reserveBlocked && !s.why.values.contains(_Why.target)) s,
        ];
        labelBeforeFloor[d] = remaining.any((s) => canForce(d, s)) ? 'clock' : 'cap_top';
      }
    }

    // 4b'. Unit 2B (OI-452, founder d30-d33): the 3-exercise day floor. A day whose rows (budgeted and not) are under
    // min(3, its reach) seats a remaining slot at 2 sets past a group's weekly top, with no limit on the excess (d30), in
    // every phase (d31), up to its reach (d32), and not bound by the clock (d33); never past a session cap, never a
    // slot the rank-0 reservation blocked. One slot per day per round. Choice: the fewest groups over their top, then
    // the least excess, then the cheapest; no lead preference; ties to the lowest rank.
    if (dayFloor) {
      const floorRows = 3;
      int excessAfter(_Slot s, String g) => ledger.week(g) + 2 - ledger.weeklyTop(g);
      int overCount(_Slot s) => s.groups.where((g) => excessAfter(s, g) > 0).length;
      int overSum(_Slot s) => s.groups.fold(0, (a, g) => a + (excessAfter(s, g) > 0 ? excessAfter(s, g) : 0));
      // No count-target guard is needed: a slot is target-removed only once `seated[d] >= target[d]`, i.e. the day holds
      // the level's count max (5 or more) in rows, and the floor acts only below 3 rows (pinned in
      // day_floor_behavioral_test, 'the count target').
      bool canFloor(int d, _Slot s) {
        if (s.admitted || s.reserveBlocked) return false;
        for (final g in s.groups) {
          if (ledger.session(d, g) + 2 > ledger.cap(g)) return false;
        }
        return true;
      }

      var seatedAny = true;
      while (seatedAny) {
        seatedAny = false;
        for (final d in allocateDays) {
          final want = reachRows[d] < floorRows ? reachRows[d] : floorRows;
          if (byDay[d].isEmpty || rowsOf(d) >= want) continue;
          _Slot? best;
          for (final s in byDay[d]) {
            if (!canFloor(d, s)) continue;
            if (best == null) {
              best = s;
              continue;
            }
            if (floorPrefers((over: overCount(s), excess: overSum(s), seconds: seconds(s, 2)),
                (over: overCount(best), excess: overSum(best), seconds: seconds(best, 2)))) {
              best = s;
            }
          }
          if (best == null) continue;
          final overBy = {
            for (final g in best.groups)
              if (excessAfter(best, g) > 0) g: excessAfter(best, g) > 2 ? 2 : excessAfter(best, g),
          };
          final overTop = overBy.keys.toList();
          final left = ledger.secondsLeft(d);
          final overClock = seconds(best, 2) > left;
          final overSeconds = !overClock ? 0.0 : (left > 0 ? seconds(best, 2) - left : seconds(best, 2));
          best
            ..sets = 2
            ..admitted = true
            ..removed = false
            ..why = const {};
          ledger.add(d, best.groups, 2, seconds(best, 2));
          (stats.floorSeats[d] ??= []).add(
              (
                name: best.exercise.exerciseName,
                sets: 2,
                overTop: overTop,
                overBy: overBy,
                overClock: overClock,
                overSeconds: overSeconds,
              ));
          seatedAny = true;
        }
      }
    }

    // Unit 2C-b, the weekly minimum (S3): each target group still at 0 this week, and not credited by a hold this run
    // kept, takes its cheapest remaining slot at 2 sets (ties: the day with the most seconds left): never an admitted,
    // reservation-blocked or count-target-refused slot, never past the day's admitted-row target (which holds the row
    // cap), a session cap or another group's weekly top, and within the ledger's forcing bound.
    final targets = minGroups.toList()..sort();
    final keptHoldGroups = <String>{
      for (var d = 0; d < n; d++)
        for (final t in timed[d])
          if (!evicted.contains(t.ex)) ...t.groups,
    };
    for (final g in targets) {
      if (ledger.week(g) > 0 || keptHoldGroups.contains(g)) continue;
      _Slot? best;
      var bd = -1;
      for (final d in allocateDays) {
        for (final s in byDay[d]) {
          if (s.admitted || s.reserveBlocked || !s.groups.contains(g)) continue;
          if (s.why.values.contains(_Why.target) || byDay[d].where((x) => x.admitted).length >= target[d]) continue;
          if (s.groups.any((x) => ledger.session(d, x) + 2 > ledger.cap(x))) continue;
          if (s.groups.any((x) => x != g && ledger.week(x) + 2 > ledger.weeklyTop(x))) continue;
          if (ledger.secondsLeft(d) - seconds(s, 2) < -ledger.forcingBound) continue;
          if (best == null || seconds(s, 2) < seconds(best, 2) ||
              (seconds(s, 2) == seconds(best, 2) && ledger.secondsLeft(d) > ledger.secondsLeft(bd))) {
            best = s;
            bd = d;
          }
        }
      }
      if (best == null) continue;
      best
        ..sets = 2
        ..admitted = true
        ..removed = false
        ..why = const {};
      ledger.add(bd, best.groups, 2, seconds(best, 2));
      seated[bd]++;
      (stats.minimumSeats[bd] ??= []).add((name: best.exercise.exerciseName, group: g));
    }

    // The count verdict is final here (passes B, C and D add no row), and it is read BEFORE the grow
    // passes spend weekly top, so a day short only because of the forcing bound still says `clock`
    // (B-pass P3-1).
    for (final d in allocateDays) {
      if (reachRows[d] < floorBase) {
        stats.selectorThin.add(d);
      } else if (rowsOf(d) < floorBase) {
        stats.belowCount[d] = labelBeforeFloor[d]!;
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
    for (var d = 0; d < n; d++) {
      for (final t in timed[d]) {
        if (!evicted.contains(t.ex)) stats.holdGroups.addAll(t.groups);
      }
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
