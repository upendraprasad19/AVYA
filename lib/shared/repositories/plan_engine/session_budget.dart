import 'models.dart' show PlannedExercise, parseRepRange;

/// Batch B2 (docs/plans/2026-10-22-session-set-budget.md): the session set
/// budget. Behind `PlanEngineFlags.sessionSetBudgetEnabled` (ship-dark, default
/// OFF) a generated session's size follows the user's minutes and evidence-based
/// caps instead of a fixed exercise count.
///
/// Pure Dart: no Hive, no repository, no flag read. Callers pass everything in,
/// so the engine stays deterministic and every rule is testable on its own.
///
/// Citations behind the numbers (the plan's Global Constraints):
/// - Schoenfeld, Ogborn & Krieger 2017 (J Sports Sci; weekly dose-response);
/// - Pelland et al. 2026 (Sports Med 56(2):481-505; diminishing returns);
/// - Remmert, Pelland et al. 2025 (SportRxiv preprint, not peer reviewed;
///   per-session plateau of about 11 fractional sets).
class SessionBudget {
  SessionBudget._();

  // ── Session minutes ──────────────────────────────────────────────────────

  /// The minutes a session is budgeted at when nothing says otherwise (founder
  /// decision F2: an empty `session_duration_minutes` means 60, no new
  /// onboarding question).
  static const int defaultMinutes = 60;

  /// The range of minutes a caller or a saved profile may ask for. The Edit
  /// Profile screen offers 30 / 45 / 60 / 90; the wider range tolerates a value
  /// restored from an older client without ever feeding the model nonsense.
  static const int minMinutes = 15;
  static const int maxMinutes = 180;

  /// The session length to use, in minutes.
  ///
  /// 1. [param] if it is in [minMinutes]..[maxMinutes];
  /// 2. else [profileValue], if it is a finite number that rounds into that
  ///    range (a JSON double such as `90.0` is a number, a string is not);
  /// 3. else [defaultMinutes].
  ///
  /// Never throws: every input class lands on a usable number.
  static int resolveMinutes({int? param, Object? profileValue}) {
    if (param != null && param >= minMinutes && param <= maxMinutes) {
      return param;
    }
    if (profileValue is num) {
      final v = profileValue.toDouble();
      // Range-check BEFORE rounding: a huge finite double must not reach
      // `round()`, and `x.5` rounds up so the bounds are 14.5 and 180.5.
      if (v.isFinite && v >= minMinutes - 0.5 && v < maxMinutes + 0.5) {
        return v.round();
      }
    }
    return defaultMinutes;
  }

  /// The Edit Profile screen's initial session length for a stored [profile]
  /// map (Ruling 7: 60, no longer 90, when the field is missing). Reads the same
  /// field the generator reads, through the same resolution, so the screen and
  /// the plan can never disagree about what an empty value means.
  static int initialSessionDuration(Map<dynamic, dynamic> profile) =>
      resolveMinutes(profileValue: profile['session_duration_minutes']);

  // ── Time model (Ruling 2) ────────────────────────────────────────────────

  /// Seconds of work per set, by archetype (Q4 §4.2). ONE table: the allocator,
  /// `PeriodizationEngine.apply`, titration and the display all read it.
  static const Map<String, int> _workSeconds = {'H': 23, 'M': 35, 'I': 47, 'B': 40};

  /// Setup seconds per exercise, by archetype.
  static const Map<String, int> _overheadSeconds = {'H': 120, 'M': 90, 'I': 45, 'B': 30};

  /// The calibration factor over the raw sum (a calibrated assumption, Ruling 2).
  static const double timeFactor = 1.20;

  /// Seconds one exercise takes: `1.20 x (overhead + sets x work + (sets - 1) x
  /// rest)`. An unknown [archetype] is timed as `B`. Zero sets cost nothing.
  /// [workSeconds] replaces the archetype's per-set work for a long effort
  /// ([longEffortWorkSeconds]); null (every other row) keeps the table.
  static double exerciseSeconds({
    required String archetype,
    required int sets,
    required int restSeconds,
    int? workSeconds,
  }) {
    if (sets <= 0) return 0.0;
    final work = workSeconds ?? _workSeconds[archetype] ?? _workSeconds['B']!;
    final overhead = _overheadSeconds[archetype] ?? _overheadSeconds['B']!;
    return timeFactor * (overhead + sets * work + (sets - 1) * restSeconds);
  }

  /// Seconds of work per set for a row whose prescription is a LONG effort, else
  /// null (B-pass R3 P2-1). A `cardio`, `distance` or `timed` row whose `reps` text
  /// names minutes ("20-40 min", "3 min rounds") works that long per set (the
  /// average of a range), instead of the archetype B's 40 s: a user-added treadmill
  /// run is half an hour, not a minute. A prescription in seconds or metres keeps
  /// the table (Ruling 2: a typical hold or carry is about 40 s a set). Rep-based
  /// rows never take it.
  static int? longEffortWorkSeconds({required String loggingType, required String reps}) {
    if (loggingType != 'cardio' && loggingType != 'distance' && loggingType != 'timed') {
      return null;
    }
    final lower = reps.toLowerCase();
    if (!_minutesUnit.hasMatch(lower)) return null;
    final numbers = _numbersIn(lower);
    if (numbers.isEmpty) return null;
    final minutes = numbers.reduce((a, b) => a + b) ~/ numbers.length;
    return (minutes * 60).clamp(1, 7200);
  }

  static final RegExp _minutesUnit = RegExp(r'\bmin(?:ute)?s?\b');

  /// The positive integers in [text], in order, each capped at 100000 so a corrupt
  /// digit run can neither overflow a sum nor price a set at years.
  static List<int> _numbersIn(String text) => [
        for (final m in RegExp(r'\d+').allMatches(text))
          if ((int.tryParse(m.group(0)!) ?? 0) > 0)
            int.parse(m.group(0)!).clamp(1, 100000),
      ];

  /// The seconds of one set of a `timed` item: the same rules as the Train screen's
  /// `parseTimedDurationSecs` (pinned equal by `session_estimate_display_test.dart`),
  /// plus the plan writer's own `duration_seconds`. Explicit numeric fields first
  /// (`prescribed_time_secs`, `default_duration_secs`, `default_duration_seconds`,
  /// `duration_seconds`), then the digits of `reps` / `prescribed_reps` /
  /// `default_reps` (a range averages, "min" multiplies by 60), else 30.
  static int timedItemSeconds(Map<dynamic, dynamic> m) {
    for (final key in const [
      'prescribed_time_secs',
      'default_duration_secs',
      'default_duration_seconds',
      'duration_seconds',
    ]) {
      final v = m[key];
      if (v is num && v.isFinite && v > 0) return v.toInt().clamp(1, 7200);
    }
    final raw = [m['reps'], m['prescribed_reps'], m['default_reps']]
            .whereType<String>()
            .firstOrNull ??
        '';
    if (raw.isEmpty) return 30;
    final lower = raw.toLowerCase();
    final numbers = _numbersIn(lower);
    if (numbers.isEmpty) return 30;
    final avg = numbers.reduce((a, b) => a + b) ~/ numbers.length;
    if (lower.contains('min') || lower.contains('m ')) return (avg * 60).clamp(1, 7200);
    return avg > 0 ? avg.clamp(1, 7200) : 30;
  }

  /// Warm-up plus cool-down minutes for a session of [minutes] (Ruling 3):
  /// 30 -> 6, 45 -> 8, 60 -> 10, 75 -> 12, 90 -> 14, linear between, clamped to
  /// [6, 14].
  static double warmCoolMinutes(int minutes) {
    final v = 6.0 + (minutes - 30) * 2.0 / 15.0;
    return v < 6.0 ? 6.0 : (v > 14.0 ? 14.0 : v);
  }

  /// Seconds of the cardio lead-in and of the cool-down walk for a session of
  /// [minutes] (Ruling 3): `round(60 x (W+C - 4) / 2)`, which is 60 s at 30
  /// minutes, 180 s at 60 and 300 s at 90 (today's fixed value).
  static int warmCoolItemSeconds(int minutes) =>
      (60 * (warmCoolMinutes(minutes) - 4) / 2).round();

  /// The archetype of an exercise: `H` (heavy compound), `M` (other compound, or
  /// moderate calisthenics), `I` (isolation) or `B` (everything else, and every
  /// timed / cardio / distance exercise).
  ///
  /// - **Type precedence:** compound > isolation > calisthenics > other.
  /// - **H:** compound with a rep-range lower bound <= 6.
  /// - **M:** any other compound, or calisthenics with a lower bound <= 10.
  /// - **I:** isolation.
  /// - **B:** any other calisthenics, any other type (flexibility, activation,
  ///   cardio, yoga), and anything logged `timed`, `cardio` or `distance`.
  ///
  /// [reps] is the library `rep_range` string ("5-8"); one that does not parse
  /// has no lower bound, so a compound reads as `M` and calisthenics as `B`.
  static String archetypeOf({
    required List<String> exerciseTypes,
    required String reps,
    required String loggingType,
  }) {
    if (loggingType == 'timed' || loggingType == 'cardio' || loggingType == 'distance') {
      return 'B';
    }
    final types = {for (final t in exerciseTypes) t.trim().toLowerCase()};
    final lower = parseRepRange(reps)?.$1;
    if (types.contains('compound')) return (lower != null && lower <= 6) ? 'H' : 'M';
    if (types.contains('isolation')) return 'I';
    if (types.contains('calisthenics')) return (lower != null && lower <= 10) ? 'M' : 'B';
    return 'B';
  }

  /// [archetypeOf] for a library row or a custom exercise (customs store
  /// `exercise_type` and `rep_range` too). `exercise_type` may be a List, a
  /// String or null; null or empty is read as `['compound']` (the same rule the
  /// display uses, Task 6b), and a missing `logging_type` as rep-based.
  static String archetypeOfRow(Map<dynamic, dynamic> row) => archetypeOf(
        exerciseTypes: _typesOf(row['exercise_type']),
        reps: '${row['rep_range'] ?? ''}',
        loggingType: '${row['logging_type'] ?? 'weight_reps'}',
      );

  /// The exercise types in a stored `exercise_type` value: a List (a null element
  /// is skipped, never read as the string "null"), a String or absent; empty or
  /// blank entries are dropped and nothing left reads as `['compound']`.
  static List<String> _typesOf(Object? raw) {
    final Iterable<String> all = raw is List
        ? [for (final t in raw) if (t != null) '$t']
        : [if (raw is String) raw];
    final types = all.where((t) => t.trim().isNotEmpty).toList();
    return types.isEmpty ? const ['compound'] : types;
  }

  /// The archetype of a planned exercise: its library row's (`archetypeByName`
  /// holds one entry per library row, lowercased), else derived from the
  /// exercise's own stored type, rep range and logging type, as for a custom.
  /// The ONE place the allocator, `PeriodizationEngine.apply` and titration ask.
  static String archetypeOfPlanned(PlannedExercise ex, SessionBudgetContext ctx) =>
      ctx.archetypeByName[ex.exerciseName.toLowerCase()] ??
      archetypeOf(
        exerciseTypes: [ex.exerciseType ?? 'compound'],
        reps: ex.repRange ?? '',
        loggingType: ex.loggingType,
      );

  /// Whether the budget sizes [ex] (Ruling 8): it is neither a custom
  /// (`customOrigin != null`), nor logged timed / cardio / distance, and the
  /// library has a row for it. Everything else keeps its sets and only spends
  /// the day's time.
  ///
  /// The ONE place that decides it: the allocator, `PeriodizationEngine.apply` and
  /// titration all ask here, so they cannot disagree about which rows are sized.
  static bool isBudgeted(PlannedExercise ex, SessionBudgetContext ctx) =>
      ex.customOrigin == null &&
      !const {'timed', 'cardio', 'distance'}.contains(ex.loggingType) &&
      ctx.archetypeByName.containsKey(ex.exerciseName.toLowerCase());

  /// Whether [loggingType] is one the engine progresses by reps (it takes the
  /// day's rest and a rep prescription): `weight_reps`, `bodyweight_reps`,
  /// `weighted_bodyweight`, `reps_only`. The ONE set: the allocator, the week-2
  /// gains and `PeriodizationEngine._applyWave` all read it.
  static bool isRepBased(String loggingType) =>
      loggingType == 'weight_reps' ||
      loggingType == 'bodyweight_reps' ||
      loggingType == 'weighted_bodyweight' ||
      loggingType == 'reps_only';

  /// Seconds [ex] takes at [sets] sets and [restSeconds] rest: [exerciseSeconds] at
  /// its archetype ([archetypeOfPlanned]), with the per-set work of a long effort
  /// ([longEffortWorkSeconds]) for a cardio, distance or timed row prescribed in
  /// minutes. The ONE pricing of a planned exercise for the allocator's
  /// not-budgeted rows, `PeriodizationEngine.apply` week 2 and titration.
  static double plannedExerciseSeconds(
    PlannedExercise ex,
    SessionBudgetContext ctx, {
    required int sets,
    required int restSeconds,
  }) =>
      exerciseSeconds(
        archetype: archetypeOfPlanned(ex, ctx),
        sets: sets,
        restSeconds: restSeconds,
        workSeconds: longEffortWorkSeconds(loggingType: ex.loggingType, reps: ex.reps),
      );

  // ── Display estimate (Ruling 13) ─────────────────────────────────────────

  /// The archetype of one exercise map of a STORED plan day (a `schedule_*` row's
  /// `exercises` entry): its library row's, found by `exercise_id`, else by its
  /// exact name in [rowsByName] (a template-built day carries no id), else derived
  /// from the entry's own `exercise_type` (a List, a String or absent, which is
  /// read as `['compound']`), `rep_range` and `logging_type`, as for a custom.
  /// The same answer [archetypeOfPlanned] gives the engine for the same exercise.
  static String archetypeOfPlanDayExercise(
    Map<dynamic, dynamic> e,
    Map<String, Map<String, dynamic>> rowsById, {
    Map<String, Map<String, dynamic>> rowsByName = const {},
  }) {
    final id = e['exercise_id'];
    final name = e['exercise_name'] ?? e['name'];
    final row = (id is String ? rowsById[id] : null) ??
        (name is String ? rowsByName[name.toLowerCase()] : null);
    if (row != null) return archetypeOfRow(row);
    return archetypeOfRow(e);
  }

  /// Modelled seconds of a stored plan day: [exerciseSeconds] over every exercise
  /// (user-added ones included, they are part of the real session) plus the
  /// seconds of the warm-up and cool-down items. This is what Train and Home
  /// DISPLAY under the budget flag; both call it, so they cannot disagree.
  ///
  /// - **Sets:** `sets`, else `prescribed_sets`, else `default_sets`, else 3
  ///   (clamped to 0..100).
  /// - **Rest:** `rest_seconds` (a number, or the digits of a string such as
  ///   `90s`; clamped to 0..3600); absent is 60 (the display parser's default);
  ///   anything else is 75.
  /// - **Long efforts:** a cardio / distance / timed exercise whose `reps` names
  ///   minutes works that long per set ([longEffortWorkSeconds]).
  /// - **Warm-up / cool-down item:** a `timed` item is its own seconds
  ///   ([timedItemSeconds]); any other item is priced as archetype `B` at its own
  ///   sets and rest.
  ///
  /// Never throws: a non-map entry is skipped, a missing list counts as none and a
  /// corrupt number lands on a default.
  static double estimateDaySecondsFromPlanDay(
    Map<dynamic, dynamic> planDay,
    Map<String, Map<String, dynamic>> rowsById, {
    Map<String, Map<String, dynamic>> rowsByName = const {},
  }) {
    var total = 0.0;
    for (final e in _mapsOf(planDay['exercises'])) {
      total += exerciseSeconds(
        archetype: archetypeOfPlanDayExercise(e, rowsById, rowsByName: rowsByName),
        sets: _setsOf(e['sets'] ?? e['prescribed_sets'] ?? e['default_sets']),
        restSeconds: _restSecondsOf(e['rest_seconds']),
        workSeconds: longEffortWorkSeconds(
          loggingType: '${e['logging_type'] ?? 'weight_reps'}',
          reps: [e['reps'], e['prescribed_reps'], e['default_reps']]
                  .whereType<String>()
                  .firstOrNull ??
              '',
        ),
      );
    }
    for (final key in const ['warmup', 'cooldown']) {
      for (final item in _mapsOf(planDay[key])) {
        total += _itemSeconds(item);
      }
    }
    return total;
  }

  /// [estimateDaySecondsFromPlanDay] rounded to whole minutes.
  static int estimateDayMinutesFromPlanDay(
    Map<dynamic, dynamic> planDay,
    Map<String, Map<String, dynamic>> rowsById, {
    Map<String, Map<String, dynamic>> rowsByName = const {},
  }) =>
      (estimateDaySecondsFromPlanDay(planDay, rowsById, rowsByName: rowsByName) / 60).round();

  static Iterable<Map<dynamic, dynamic>> _mapsOf(Object? raw) =>
      raw is List ? raw.whereType<Map<dynamic, dynamic>>() : const [];

  static int? _intOf(Object? raw) {
    if (raw is num) return raw.isFinite ? raw.toInt() : null;
    if (raw is String) return int.tryParse(raw.trim());
    return null;
  }

  /// A stored set count: absent or unreadable is 3, and 0..100 bounds a corrupt value.
  static int _setsOf(Object? raw) => (_intOf(raw) ?? 3).clamp(0, 100);

  /// A stored rest in seconds, bounded to 0..3600: absent is 60, a number or the
  /// first digit run of a string is itself, anything else (and a digit run too
  /// long to be a number) is 75.
  static int _restSecondsOf(Object? raw) {
    if (raw == null) return 60;
    if (raw is num) return raw.isFinite ? raw.toInt().clamp(0, 3600) : 75;
    if (raw is String) {
      final digits = RegExp(r'\d+').firstMatch(raw)?.group(0);
      final v = digits == null ? null : int.tryParse(digits);
      return v == null ? 75 : v.clamp(0, 3600);
    }
    return 75;
  }

  static double _itemSeconds(Map<dynamic, dynamic> item) {
    if (item['logging_type'] == 'timed') return timedItemSeconds(item).toDouble();
    return exerciseSeconds(
      archetype: 'B',
      sets: (_intOf(item['sets']) ?? 1).clamp(0, 100),
      restSeconds: _restSecondsOf(item['rest_seconds'] ?? 0),
    );
  }

  // ── Day intensity ────────────────────────────────────────────────────────
  // Mirrors `PeriodizationEngine._profileParams` (sets, rest). The two tables are
  // pinned equal by session_budget_test.dart, which drives the real engine.

  /// The rest, in seconds, the engine stamps on a rep-based exercise of a day of
  /// [intensity]: strength 150, hypertrophy 75, endurance 38. An unknown
  /// intensity uses hypertrophy, as the engine does (M4).
  static int restFor(String intensity) => switch (intensity) {
        'strength' => 150,
        'endurance' => 38,
        _ => 75,
      };

  /// The base sets per exercise the engine gives a day of [intensity]: strength
  /// 4, hypertrophy 3, endurance 2, unknown 3.
  static int desiredFor(String intensity) => switch (intensity) {
        'strength' => 4,
        'endurance' => 2,
        _ => 3,
      };

  // ── Bands and caps (Ruling 4) ────────────────────────────────────────────

  /// A focus muscle may go to this many hard sets a week (founder F3).
  static const int focusWeeklyTop = 25;

  /// A focus muscle's per-session cap (founder F5).
  static const int focusSessionCap = 12;

  /// No single exercise is grown past this many sets (M5).
  static const int maxSetsPerExercise = 5;

  static const Map<String, Map<String, ({int bottom, int top})>> _bands = {
    'build_muscle': {
      'beginner': (bottom: 10, top: 12),
      'intermediate': (bottom: 12, top: 16),
      'advanced': (bottom: 14, top: 20),
    },
    'strength': {
      'beginner': (bottom: 10, top: 12),
      'intermediate': (bottom: 10, top: 14),
      'advanced': (bottom: 12, top: 16),
    },
    'lose_fat': {
      'beginner': (bottom: 10, top: 12),
      'intermediate': (bottom: 10, top: 14),
      'advanced': (bottom: 12, top: 16),
    },
    'general_fitness': {
      'beginner': (bottom: 10, top: 10),
      'intermediate': (bottom: 10, top: 12),
      'advanced': (bottom: 12, top: 14),
    },
  };

  static const Map<String, Map<String, int>> _caps = {
    'build_muscle': {'beginner': 6, 'intermediate': 8, 'advanced': 10},
    'strength': {'beginner': 6, 'intermediate': 8, 'advanced': 10},
    'lose_fat': {'beginner': 6, 'intermediate': 8, 'advanced': 8},
    'general_fitness': {'beginner': 6, 'intermediate': 8, 'advanced': 8},
  };

  static String _goalKey(String planGoal) =>
      _bands.containsKey(planGoal) ? planGoal : 'build_muscle';

  static String _levelKey(String level) =>
      const {'beginner', 'intermediate', 'advanced'}.contains(level) ? level : 'intermediate';

  /// Weekly hard sets per muscle group for [planGoal] and [level]. An unknown
  /// goal uses build_muscle; an unknown level uses intermediate.
  static ({int bottom, int top}) weeklyBand(String planGoal, String level) =>
      _bands[_goalKey(planGoal)]![_levelKey(level)]!;

  /// The most hard sets one muscle group may get in ONE session (non-focus).
  static int sessionCap(String planGoal, String level) =>
      _caps[_goalKey(planGoal)]![_levelKey(level)]!;
}

/// Everything the budget needs to know about one generation, immutable. `null`
/// where a consumer takes one means today's code path, verbatim.
class SessionBudgetContext {
  SessionBudgetContext({
    required this.minutes,
    required this.planGoal,
    required this.level,
    required this.lighterPhase,
    required Set<String> focusGroups,
    this.finisherSeconds = 0,
    required Map<String, String> archetypeByName,
  })  : focusGroups = Set.unmodifiable(focusGroups),
        archetypeByName = Map.unmodifiable(archetypeByName);

  /// The session length, already resolved ([SessionBudget.resolveMinutes]).
  final int minutes;

  /// The plan goal ("build_muscle", ...) and the EFFECTIVE experience level.
  final String planGoal;
  final String level;

  /// True in an archetype-`deload` phase (4 / 8 / 12): every group's weekly top
  /// is the band's bottom, focus included (Ruling 1).
  final bool lighterPhase;

  /// Budget muscle groups the user wants more of (`BudgetMuscleGroups.of`).
  final Set<String> focusGroups;

  /// Always 0 while no screen shows the finisher (Ruling 6).
  final int finisherSeconds;

  /// Lowercased exercise name -> archetype, computed once from the library rows.
  final Map<String, String> archetypeByName;
}

/// The one headroom predicate shared by the allocator, `PeriodizationEngine.apply`
/// week 2 and titration (P2-3): a group's weekly total, its per-session total and
/// the day's remaining seconds. Callers pass seconds, so the ledger never reads an
/// intensity (M4).
///
/// Not-budgeted rows (customs, timed / cardio / distance, rows with no library
/// match) enter through [add] with an empty group set and zero sets: they spend
/// the day's time and nothing else.
class BudgetLedger {
  BudgetLedger(this.ctx, int dayCount)
      : _spentSeconds = List<double>.filled(dayCount, 0.0),
        _session = List<Map<String, int>>.generate(dayCount, (_) => <String, int>{}),
        _dayBudgetSeconds = (ctx.minutes - SessionBudget.warmCoolMinutes(ctx.minutes)) * 60.0 -
            ctx.finisherSeconds;

  final SessionBudgetContext ctx;
  final double _dayBudgetSeconds;
  final List<double> _spentSeconds;
  final List<Map<String, int>> _session;
  final Map<String, int> _week = <String, int>{};

  /// The weekly ceiling for [group]: the band's top, 25 for a focus group, and
  /// the band's BOTTOM for every group in a lighter phase.
  int weeklyTop(String group) {
    final band = SessionBudget.weeklyBand(ctx.planGoal, ctx.level);
    if (ctx.lighterPhase) return band.bottom;
    if (ctx.focusGroups.contains(group)) return SessionBudget.focusWeeklyTop;
    return band.top;
  }

  /// The per-session ceiling for [group]: 12 for a focus group outside a lighter
  /// phase, else the ordinary cap.
  int cap(String group) {
    if (!ctx.lighterPhase && ctx.focusGroups.contains(group)) {
      return SessionBudget.focusSessionCap;
    }
    return SessionBudget.sessionCap(ctx.planGoal, ctx.level);
  }

  /// Hard sets credited to [group] across the week.
  int week(String group) => _week[group] ?? 0;

  /// Hard sets credited to [group] on [day].
  int session(int day, String group) => _session[day][group] ?? 0;

  /// Seconds left on [day] after everything [add]ed so far.
  double secondsLeft(int day) => _dayBudgetSeconds - _spentSeconds[day];

  /// Whether [addSets] more sets (costing [addSeconds]) fit on [day] for every
  /// one of [groups]: under each group's session cap and weekly top, and within
  /// the day's remaining time. An empty [groups] is checked against time only.
  bool fits(int day, Set<String> groups, int addSets, double addSeconds) {
    if (addSeconds > secondsLeft(day)) return false;
    for (final g in groups) {
      if (week(g) + addSets > weeklyTop(g)) return false;
      if (session(day, g) + addSets > cap(g)) return false;
    }
    return true;
  }

  /// Credit [addSets] to every group in [groups] on [day] and spend [addSeconds].
  void add(int day, Set<String> groups, int addSets, double addSeconds) {
    for (final g in groups) {
      _week[g] = week(g) + addSets;
      _session[day][g] = session(day, g) + addSets;
    }
    _spentSeconds[day] += addSeconds;
  }
}
