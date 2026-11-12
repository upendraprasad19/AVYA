// Generator step 1A, Task 1 (docs/plans/2026-11-08-generator-step1-core-list.md
// section 1): the per-plan suitability audit, ported from the 2026-11-08 session
// script (`audit.py`) so the founder's "re-run the review after each step" is a
// repo command, not a scratchpad file.
//
// Pure Dart over the dump shape `plan_audit_dump_test.dart` writes (one map per
// plan) and the shipped library keyed by name. No Hive, no generator: the rules
// are unit-tested on fixtures in `plan_audit_lib_test.dart`.
//
// Dump shape (per plan):
//   k   "goal|days|level|tier|minutes|phase"
//   el  effective level
//   b   [weekly band bottom, top]
//   w   weeks: [{d: [{n: day name, x: [[name, sets, ...]], min: estimated minutes}],
//               v: {muscle group: week sets}}]
library;

const _household = {
  'bodyweight', 'wall', 'doorway', 'elevated surface', 'foot anchor', 'towel', 'none',
};
const _tierExtras = <String, Set<String>>{
  'bodyweight': {},
  'home_dumbbells': {'dumbbells', 'resistance band'},
  'basic_gym': {
    'dumbbells', 'barbell', 'bench', 'pull-up bar', 'cables', 'resistance band',
    'cardio machine', 'ab wheel', 'jump rope', 'parallel bars', 'plyo box',
    'medicine ball', 'battle ropes',
  },
  'full_gym': {
    'dumbbells', 'barbell', 'bench', 'pull-up bar', 'cables', 'resistance band',
    'cardio machine', 'ab wheel', 'jump rope', 'parallel bars', 'plyo box',
    'medicine ball', 'battle ropes', 'machines', 'smith machine', 'kettlebell',
    'ez-bar', 'suspension trainer',
  },
};
const _loaded = {
  'dumbbells', 'barbell', 'cables', 'machines', 'smith machine', 'kettlebell', 'ez-bar',
};
const majorMuscles = ['Chest', 'Back', 'Shoulders', 'Quads', 'Hamstrings', 'Glutes'];
const _loadablePatterns = {
  'elbow_flexion', 'elbow_extension', 'shoulder_isolation', 'hip_isolation',
  'horizontal_pull', 'vertical_pull', 'knee_dominant', 'hip_dominant', 'vertical_push',
};
const _unloadedFlagPatterns = {
  'elbow_flexion', 'elbow_extension', 'shoulder_isolation', 'hip_isolation',
  'hip_dominant', 'knee_dominant', 'vertical_push',
};
final _improvisedName = RegExp(
    r'self-resisted|towel|doorway|doorframe|\btable\b|backpack|wall triceps|sliding|isometric',
    caseSensitive: false);
const _levelRank = {'beginner': 0, 'intermediate': 1, 'advanced': 2};
const _heavyHinges = {
  'Deadlift', 'Romanian Deadlift', 'Sumo Deadlift', 'Trap Bar Deadlift',
  'Barbell Good Morning', 'Stiff Leg Deadlift',
};

List<String> _strs(Object? v) =>
    v is List ? [for (final e in v) e.toString()] : const <String>[];

Set<String> tierItems(String tier) =>
    {..._household, ...?_tierExtras[tier]};

/// One finding on one plan.
class AuditIssue {
  final String severity; // major | moderate | minor
  final String code;
  final String text;
  const AuditIssue(this.severity, this.code, this.text);
}

class PlanAuditResult {
  final String key;
  final String verdict; // not_suitable | needs_work | suitable
  final List<AuditIssue> issues;
  /// Section 1 measures for this plan.
  final int ohpDays, ohpPikeDays, isoFirstDays, jumpRowsWeek1, jumpLeadsWeek1;
  const PlanAuditResult({
    required this.key,
    required this.verdict,
    required this.issues,
    required this.ohpDays,
    required this.ohpPikeDays,
    required this.isoFirstDays,
    required this.jumpRowsWeek1,
    required this.jumpLeadsWeek1,
  });
  bool has(String code) => issues.any((i) => i.code == code);
}

class PlanAuditor {
  /// Library rows keyed by exact name.
  final Map<String, Map<String, dynamic>> lib;
  final _altCache = <String, List<String>>{};
  PlanAuditor(this.lib);

  Set<String> _items(String name) => _strs(lib[name]?['equipment_needed']).toSet();
  List<String> _patterns(String name) => _strs(lib[name]?['movement_pattern']);
  bool _isUnloaded(String name) => _household.containsAll(_items(name));
  bool _compound(String name) =>
      _strs(lib[name]?['exercise_type']).contains('compound');

  /// Unit 1B-F (OI-485 (3)): a day row's BUILT type, `x[7]` (`PlannedExercise.exerciseType` after the picker's
  /// `typeOverride`, the type SequencingEngine orders by); a row without it (an older dump) falls back to the library
  /// row's type. E143 Skater Squat is `calisthenics` in the library and `compound` when built in a compound slot.
  bool _builtCompound(List x) {
    final t = x.length > 7 ? x[7] : null;
    return t is String ? t == 'compound' : _compound(x[0] as String);
  }

  /// A jump row, as the core-list R2 partition defines it.
  bool isJump(String name) {
    final r = lib[name];
    return r != null &&
        (r['high_impact'] == true || r['discipline'] == 'plyometric');
  }

  /// Library rows on the same pattern and first muscle that need real load the
  /// user has, at the user's level.
  List<String> loadedAlternatives(String name, String tier, String level) =>
      _altCache.putIfAbsent('$name|$tier|$level', () {
        final r = lib[name];
        if (r == null) return const [];
        final pats = _strs(r['movement_pattern']).toSet();
        final prim = _strs(r['primary_muscles']);
        final first = prim.isEmpty ? '' : prim.first;
        final have = tierItems(tier);
        final lvl = level[0].toUpperCase() + level.substring(1);
        return [
          for (final o in lib.values)
            if (o['name'] != name &&
                o['is_active'] != false &&
                _strs(o['equipment_needed']).isNotEmpty &&
                have.containsAll(_strs(o['equipment_needed'])) &&
                _strs(o['equipment_needed']).any(_loaded.contains) &&
                _strs(o['movement_pattern']).any(pats.contains) &&
                _strs(o['primary_muscles']).contains(first) &&
                _strs(o['suitable_for']).contains(lvl))
              o['name'] as String
        ];
      });

  PlanAuditResult audit(Map<String, dynamic> p) {
    final parts = (p['k'] as String).split('|');
    final goal = parts[0], days = int.parse(parts[1]), level = parts[2];
    final tier = parts[3], minutes = int.parse(parts[4]);
    final el = p['el'] as String;
    final bottom = (p['b'] as List)[0] as int, top = (p['b'] as List)[1] as int;
    final weeks = [for (final w in p['w'] as List) Map<String, dynamic>.from(w as Map)];
    final issues = <AuditIssue>[];
    void add(String sev, String code, String text) =>
        issues.add(AuditIssue(sev, code, text));
    List<Map<String, dynamic>> daysOf(Map<String, dynamic> w) =>
        [for (final d in w['d'] as List) Map<String, dynamic>.from(d as Map)];
    List<List> xs(Map<String, dynamic> d) => [for (final x in d['x'] as List) x as List];
    int vol(Map<String, dynamic> w, String m) =>
        ((w['v'] as Map?)?[m] as num?)?.toInt() ?? 0;

    // Exercise choice.
    final improvised = <String, List<String>>{};
    final bandInGym = <String, List<String>>{};
    final unloadedGym = <String, List<String>>{};
    final tooHard = <String>{};
    final stretch = <String>{};
    for (var wi = 0; wi < weeks.length; wi++) {
      for (final d in daysOf(weeks[wi])) {
        final seen = <String, int>{};
        for (final x in xs(d)) {
          seen[x[0] as String] = (seen[x[0] as String] ?? 0) + 1;
        }
        seen.forEach((n, c) {
          if (c > 1) {
            add('major', 'dup_in_day', '$n appears $c times on ${d['n']} (week ${wi + 1}).');
          }
        });
        for (final x in xs(d)) {
          final n = x[0] as String;
          final diff = lib[n]?['difficulty_level'] as String?;
          if ((_levelRank[diff] ?? 0) > _levelRank[el]! + 1 ||
              (el == 'beginner' && diff == 'advanced')) {
            tooHard.add(n);
          } else if (el == 'intermediate' && diff == 'advanced') {
            stretch.add(n);
          }
          if (tier == 'bodyweight') continue;
          final pats = _patterns(n).toSet();
          if (_isUnloaded(n) && pats.any(_loadablePatterns.contains)) {
            final a = loadedAlternatives(n, tier, el);
            if (a.isNotEmpty) {
              if (_improvisedName.hasMatch(n)) {
                improvised.putIfAbsent(n, () => a.take(3).toList());
              } else if ((el != 'beginner' && pats.any(_unloadedFlagPatterns.contains)) ||
                  (el == 'beginner' &&
                      pats.any({'vertical_push', 'hip_dominant'}.contains))) {
                unloadedGym.putIfAbsent(n, () => a.take(3).toList());
              }
            }
          }
          if ((tier == 'basic_gym' || tier == 'full_gym') &&
              _items(n).contains('resistance band')) {
            final a = loadedAlternatives(n, tier, el);
            if (a.isNotEmpty) bandInGym.putIfAbsent(n, () => a.take(3).toList());
          }
        }
      }
    }
    improvised.forEach((n, a) => add('major', 'improvised',
        '$n is a household substitute, but this user has real equipment (e.g. ${a.join(', ')}).'));
    unloadedGym.forEach((n, a) => add('moderate', 'unloaded',
        '$n uses no load although ${a.join(', ')} could be loaded and progressed.'));
    bandInGym.forEach((n, a) =>
        add('moderate', 'band_in_gym', '$n uses a band in a gym that has ${a.join(', ')}.'));
    for (final n in tooHard) {
      add('major', 'too_hard',
          '$n is rated ${lib[n]?['difficulty_level']} but the plan trains at $el level.');
    }
    for (final n in stretch) {
      add('minor', 'stretch_lift',
          '$n is rated advanced; this plan trains at intermediate level'
          '${level == 'beginner' ? ' (a beginner moved up in phase 3)' : ''}.');
    }

    // Volume (weeks 1-3; week 4 is the deload).
    for (var wi = 0; wi < weeks.length && wi < 3; wi++) {
      final zero = [for (final m in majorMuscles) if (vol(weeks[wi], m) == 0) m];
      if (zero.isNotEmpty) {
        add('major', 'zero_muscle', 'Week ${wi + 1}: no sets at all for ${zero.join(', ')}.');
      }
    }
    final w1 = weeks.first;
    final low = [
      for (final m in majorMuscles)
        if (vol(w1, m) > 0 && vol(w1, m) < bottom * 0.5) m
    ];
    if (low.isNotEmpty) {
      add(minutes >= 45 ? 'moderate' : 'minor', 'low_volume',
          'Week 1: ${low.map((m) => '$m ${vol(w1, m)}').join(', ')} sets, under half the weekly target of $bottom.');
    }
    final under = [for (final m in majorMuscles) if (vol(w1, m) < bottom) m];
    if (under.isNotEmpty) {
      add('minor', 'under_floor',
          'Week 1: ${under.length} of 6 major muscles under the $bottom-set target (${under.join(', ')}).');
    }
    final over = [for (final m in majorMuscles) if (vol(w1, m) > top) m];
    if (over.isNotEmpty) {
      add('minor', 'over_top', 'Week 1: ${over.join(', ')} above the $top-set top.');
    }
    if (weeks.length > 1) {
      for (final m in majorMuscles) {
        final a = vol(weeks[0], m), b = vol(weeks[1], m);
        if (a >= 4 && b <= a / 2 && b > 0) {
          add('moderate', 'ab_swing', '$m: $a sets in week 1 but only $b in week 2.');
        }
      }
    }

    // Time and count.
    for (var wi = 0; wi < weeks.length; wi++) {
      for (final d in daysOf(weeks[wi])) {
        final mins = (d['min'] as num?)?.toInt();
        if (mins != null && mins > minutes + 10) {
          add('major', 'over_time', 'Week ${wi + 1} ${d['n']}: about $mins min for a $minutes-min session.');
        } else if (mins != null && mins > minutes + 5) {
          add('moderate', 'over_time', 'Week ${wi + 1} ${d['n']}: about $mins min for a $minutes-min session.');
        }
      }
    }
    final spare = [
      for (final d in daysOf(w1))
        if (d['min'] != null && minutes >= 45 && (d['min'] as num) < minutes * 0.8)
          '${d['n']} ${d['min']} min'
    ];
    if (spare.isNotEmpty && under.isNotEmpty) {
      add('moderate', 'unused_time',
          'Week 1 leaves time unused (${spare.join(', ')} of $minutes) while muscles are under target.');
    }

    // Order and set distribution (week 1), plus the section 1 measures.
    var ohpDays = 0, ohpPike = 0, isoFirst = 0, jumps = 0, jumpLeads = 0;
    for (final d in daysOf(w1)) {
      final list = xs(d);
      if (list.isEmpty) {
        add('major', 'empty_day', '${d['n']} has no exercises.');
        continue;
      }
      for (var i = 0; i < list.length; i++) {
        if (isJump(list[i][0] as String)) {
          jumps++;
          if (i == 0) jumpLeads++;
        }
      }
      if (goal == 'strength' &&
          days == 4 &&
          (tier == 'basic_gym' || tier == 'full_gym') &&
          d['n'] == 'OHP Day') {
        ohpDays++;
        if (list.any((x) => x[0] == 'Pike Push Up')) ohpPike++;
      }
      final lead = list.first;
      var biggest = list.first;
      for (final x in list) {
        if ((x[1] as int) > (biggest[1] as int)) biggest = x;
      }
      if (_compound(lead[0] as String) &&
          (biggest[1] as int) >= (lead[1] as int) + 2 &&
          !_compound(biggest[0] as String)) {
        add('moderate', 'lead_starved',
            '${d['n']}: lead lift ${lead[0]} gets ${lead[1]} sets while ${biggest[0]} gets ${biggest[1]}.');
      }
      final types = [for (final x in list) _builtCompound(x)];
      if (!types.first && types.skip(1).any((t) => t)) {
        isoFirst++;
        add('minor', 'iso_first',
            '${d['n']}: opens with isolation ${list.first[0]} before ${list[types.indexOf(true)][0]}.');
      }
      final hinges = [for (final x in list) if (_heavyHinges.contains(x[0])) x[0]];
      if (hinges.length >= 2 && el == 'beginner') {
        add('moderate', 'double_hinge',
            '${d['n']}: two heavy hinges for a beginner (${hinges.join(', ')}).');
      }
    }

    // Deload.
    if (weeks.length >= 4) {
      int sets(Map<String, dynamic> w) => daysOf(w)
          .expand(xs)
          .fold(0, (s, x) => s + (x[1] as int));
      final s3 = sets(weeks[2]), s4 = sets(weeks[3]);
      if (s4 >= s3) {
        add('minor', 'no_deload',
            'Week 4 has $s4 sets against $s3 in week 3; the deload does not reduce volume.');
      }
    }

    final sev = {for (final i in issues) i.severity};
    return PlanAuditResult(
      key: p['k'] as String,
      verdict: sev.contains('major')
          ? 'not_suitable'
          : sev.contains('moderate')
              ? 'needs_work'
              : 'suitable',
      issues: issues,
      ohpDays: ohpDays,
      ohpPikeDays: ohpPike,
      isoFirstDays: isoFirst,
      jumpRowsWeek1: jumps,
      jumpLeadsWeek1: jumpLeads,
    );
  }
}

/// The section 1 table's numbers for one world (OFF or ON).
class AuditSummary {
  final int plans;
  final Map<String, int> verdicts;
  final Map<String, int> codes; // plans carrying each code
  final int ohpDays, ohpPikeDays, isoFirstPlans, isoFirstDays, jumpRows, jumpLeads;
  const AuditSummary({
    required this.plans,
    required this.verdicts,
    required this.codes,
    required this.ohpDays,
    required this.ohpPikeDays,
    required this.isoFirstPlans,
    required this.isoFirstDays,
    required this.jumpRows,
    required this.jumpLeads,
  });

  factory AuditSummary.of(Iterable<PlanAuditResult> rs) {
    final verdicts = <String, int>{}, codes = <String, int>{};
    var n = 0, ohp = 0, pike = 0, isoP = 0, isoD = 0, j = 0, jl = 0;
    for (final r in rs) {
      n++;
      verdicts[r.verdict] = (verdicts[r.verdict] ?? 0) + 1;
      for (final c in {for (final i in r.issues) i.code}) {
        codes[c] = (codes[c] ?? 0) + 1;
      }
      ohp += r.ohpDays;
      pike += r.ohpPikeDays;
      if (r.isoFirstDays > 0) isoP++;
      isoD += r.isoFirstDays;
      j += r.jumpRowsWeek1;
      jl += r.jumpLeadsWeek1;
    }
    return AuditSummary(
      plans: n,
      verdicts: verdicts,
      codes: codes,
      ohpDays: ohp,
      ohpPikeDays: pike,
      isoFirstPlans: isoP,
      isoFirstDays: isoD,
      jumpRows: j,
      jumpLeads: jl,
    );
  }

  int code(String c) => codes[c] ?? 0;
}

/// Section 1 of the plan, OFF beside ON.
/// The plan's section 1 table, one column per (label, summary). Unit 1B-F made the dump one-world; a comparison
/// against a pre-change tree passes that tree's summary as a second column.
String sectionOneTable(List<(String, AuditSummary)> cols) {
  String row(String label, String Function(AuditSummary s) cell) =>
      '| $label | ${cols.map((c) => cell(c.$2)).join(' | ')} |';
  return [
    '| measure | ${cols.map((c) => c.$1).join(' | ')} |',
    '|---|${cols.map((_) => '---|').join()}',
    row('plans', (s) => '${s.plans}'),
    row('verdict not suitable / needs work / suitable',
        (s) => '${s.verdicts['not_suitable'] ?? 0} / ${s.verdicts['needs_work'] ?? 0} / ${s.verdicts['suitable'] ?? 0}'),
    row('plans with a household substitute while the user has real equipment', (s) => '${s.code('improvised')}'),
    row('plans with an unloaded pick where a loaded row fits', (s) => '${s.code('unloaded')}'),
    row('Strength 4-day gym OHP Day with Pike Push Up', (s) => '${s.ohpPikeDays} of ${s.ohpDays}'),
    row('plans with a major muscle at 0 sets in week 1, 2 or 3', (s) => '${s.code('zero_muscle')}'),
    row('week-1 days opening with a non-compound (plans / days)', (s) => '${s.isoFirstPlans} / ${s.isoFirstDays}'),
    row('jump rows in week 1 (as the lead)', (s) => '${s.jumpRows} (${s.jumpLeads})'),
    row('plans with a lead lift 2+ sets under an isolation', (s) => '${s.code('lead_starved')}'),
  ].join('\n');
}
