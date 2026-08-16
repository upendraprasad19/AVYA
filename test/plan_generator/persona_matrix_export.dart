// Headless persona-matrix sweep of the REAL plan generator.
//
// Boots a Hive test harness (mirrors test/contracts/physique_focus_bringup_test.dart),
// seeds the bundled exercise_library.json into exerciseBox exactly as
// SeedService does, turns ON all 13 ship-dark plan-engine flags, then loops a
// ~18-persona matrix and calls the PRODUCTION `PlanGenerator.instance.generateV4`
// for phases 1/2/3 of each persona. Every phase's days + exercises are serialized
// to a structured JSON file for downstream analysis.
//
// This file ONLY CALLS the generator + seeds Hive — it does not modify any engine
// file (CLAUDE.md rule 14). A fallback / universal-pool / (none) pick is RECORDED
// in the JSON (via a heuristic `source` marker + per-day counts + a library-tag
// contraindication check), never "fixed".
//
// Run: flutter test test/plan_generator/persona_matrix_export.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/exercise_selector.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/volume_filter.dart';

// ── Config ──────────────────────────────────────────────────────────

const _outputPath =
    r'C:\Users\upend\AppData\Local\Temp\claude\C--Upendra-Claude-Code-Fitness-App\eeddf6fb-9ed1-4556-83cf-8f1890ae8a50\scratchpad\persona_plans.json';

const _testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

/// The 13 ship-dark plan-engine kill-switches (all OFF by default in prod). Turn
/// them ALL ON so the sweep exercises the fullest-featured generation path.
const _shipDarkFlags = <String>[
  'enable_graded_progression',
  'enable_session_detraining_cut',
  'enable_physique_focus_bringup',
  'enable_equipment_exclusions',
  'enable_readiness',
  'enable_phase_arc',
  'enable_triggered_deload',
  'enable_adherence_gate',
  'enable_volume_titration',
  'enable_exercise_id_history',
  'enable_injury_substitute_pref',
  'enable_cross_phase_variety',
  'enable_plateau_escalation',
];

const _phasesToGenerate = <int>[1, 2, 3];

/// Union of every universal-pool bodyweight fallback NAME (attempt-5 pool),
/// lowercased. Used as a heuristic `source` marker: a pick whose name is in this
/// set is one of the hardcoded bodyweight fallbacks — expected for a bodyweight
/// persona, but for a full-gym tier it suggests an attempt-5 / shallow-pool pick.
final Set<String> _universalPoolNames = {
  for (final entry in ExerciseSelector.universalPoolV4.values)
    for (final name in entry) name.toLowerCase(),
};

// ── Persona matrix ──────────────────────────────────────────────────

class Persona {
  final String id;
  final String label;
  final String goal;
  final String equipment;
  final int days;
  final String experience;
  final List<String> injuries;
  final String? physiqueFocus;

  const Persona({
    required this.id,
    required this.label,
    this.goal = 'build_muscle',
    this.equipment = 'full_gym',
    this.days = 4,
    this.experience = 'intermediate',
    this.injuries = const [],
    this.physiqueFocus,
  });
}

/// Baseline = build_muscle · full_gym · intermediate · 4-day · no injury · no
/// focus. Each persona varies exactly ONE dimension from the baseline.
const _personas = <Persona>[
  Persona(id: 'p01_baseline', label: 'Baseline (build_muscle/full_gym/int/4d)'),
  // Goal sweep
  Persona(id: 'p02_lose_fat', label: 'Goal: lose_fat', goal: 'lose_fat'),
  Persona(
      id: 'p03_general_fitness',
      label: 'Goal: general_fitness',
      goal: 'general_fitness'),
  Persona(id: 'p04_strength', label: 'Goal: strength', goal: 'strength'),
  Persona(id: 'p05_recompose', label: 'Goal: recompose', goal: 'recompose'),
  // Equipment sweep
  Persona(
      id: 'p06_bodyweight',
      label: 'Equipment: bodyweight',
      equipment: 'bodyweight'),
  Persona(
      id: 'p07_home_dumbbells',
      label: 'Equipment: home_dumbbells',
      equipment: 'home_dumbbells'),
  Persona(
      id: 'p08_basic_gym', label: 'Equipment: basic_gym', equipment: 'basic_gym'),
  // Experience sweep
  Persona(
      id: 'p09_beginner', label: 'Experience: beginner', experience: 'beginner'),
  Persona(
      id: 'p10_advanced', label: 'Experience: advanced', experience: 'advanced'),
  // Injury sweep (canonical library tokens)
  Persona(
      id: 'p11_injury_lower_back',
      label: 'Injury: lower_back',
      injuries: ['lower_back']),
  Persona(
      id: 'p12_injury_shoulder',
      label: 'Injury: shoulder',
      injuries: ['shoulder']),
  Persona(id: 'p13_injury_knee', label: 'Injury: knee', injuries: ['knee']),
  Persona(id: 'p14_injury_wrist', label: 'Injury: wrist', injuries: ['wrist']),
  // Frequency sweep
  Persona(id: 'p15_days_3', label: 'Days/week: 3', days: 3),
  Persona(id: 'p16_days_6', label: 'Days/week: 6', days: 6),
  // Physique-focus sweep (drives the profile physique_focus read → +1 set)
  Persona(
      id: 'p17_focus_glutes_legs',
      label: 'Physique focus: glutes_legs',
      physiqueFocus: 'glutes_legs'),
  Persona(
      id: 'p18_focus_chest_shoulders_arms',
      label: 'Physique focus: chest_shoulders_arms',
      physiqueFocus: 'chest_shoulders_arms'),
];

// ── Seed helper ─────────────────────────────────────────────────────

/// Loads assets/data/exercise_library.json from disk (flutter test has fs
/// access; rootBundle does not work headlessly) and keys each row by its `id`
/// exactly as SeedService._parseJsonToIdMap does.
Map<String, dynamic> _loadExerciseSeed() {
  final candidates = <String>[
    'assets/data/exercise_library.json',
    '${Directory.current.path}/assets/data/exercise_library.json',
  ];
  File? file;
  for (final path in candidates) {
    final f = File(path);
    if (f.existsSync()) {
      file = f;
      break;
    }
  }
  if (file == null) {
    throw StateError(
        'exercise_library.json not found (cwd=${Directory.current.path}). '
        'Run `flutter test` from the package root.');
  }
  final list = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  final map = <String, dynamic>{};
  for (final item in list) {
    final row = Map<String, dynamic>.from(item as Map);
    final id = row['id'] as String?;
    if (id != null) map[id] = row;
  }
  return map;
}

// ── Serialization ───────────────────────────────────────────────────

bool _sameNames(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Week 2's workout days (variant B) IFF they differ from week 1 (variant A);
/// null otherwise (6-day splits + slotsB-null splits reuse variant A).
List<WorkoutDay>? _distinctVariantB(Phase phase) {
  if (phase.weekPlans.length < 2) return null;
  final a = phase.weekPlans[0].workoutDays;
  final b = phase.weekPlans[1].workoutDays;
  for (var i = 0; i < a.length && i < b.length; i++) {
    final an = a[i].exercises.map((e) => e.exerciseName).toList();
    final bn = b[i].exercises.map((e) => e.exerciseName).toList();
    if (!_sameNames(an, bn)) return b;
  }
  return null;
}

/// Classifies a pick's origin without touching the engine:
///  - `universal_fallback_synthetic` — name absent from the library entirely
///    (a hardcoded `_buildUniversalFallback` placeholder). Strong anomaly.
///  - `universal_pool_name` — name IS an attempt-5 bodyweight-pool move (present
///    in the library). Expected for bodyweight tiers; suspicious for gym tiers.
///  - `library` — a normal cascade pick.
String _sourceMarker(PlannedExercise e, Map<String, dynamic>? libRow) {
  if (libRow == null) return 'universal_fallback_synthetic';
  if (_universalPoolNames.contains(e.exerciseName.toLowerCase())) {
    return 'universal_pool_name';
  }
  return 'library';
}

/// The library injury_contraindications tags that intersect [injuries], if any.
List<String> _contraHits(Map<String, dynamic>? libRow, List<String> injuries) {
  if (libRow == null || injuries.isEmpty) return const [];
  final contra = libRow['injury_contraindications'];
  if (contra is! List) return const [];
  final tags = contra.map((c) => c.toString().toLowerCase()).toSet();
  return injuries
      .map((i) => i.toLowerCase())
      .where(tags.contains)
      .toList();
}

Map<String, dynamic> _exerciseJson(PlannedExercise e, List<String> injuries) {
  final libRow = ExerciseRepository.instance.getByExactName(e.exerciseName);
  final source = _sourceMarker(e, libRow);
  final contra = _contraHits(libRow, injuries);
  return <String, dynamic>{
    'name': e.exerciseName,
    'sets': e.sets,
    'reps': e.reps,
    'rest': e.restSeconds,
    'weight': e.suggestedWeight,
    'variant': e.variant,
    'exercise_type': e.exerciseType,
    'equipment_needed': e.equipmentNeeded,
    'primary_muscles': e.primaryMuscles,
    'source': source,
    if (e.workingSets != null) 'working_sets': e.workingSets,
    if (e.workingReps != null) 'working_reps': e.workingReps,
    if (injuries.isNotEmpty) 'contra_hit': contra.isNotEmpty,
    if (contra.isNotEmpty) 'contra_tags': contra,
  };
}

Map<String, dynamic> _dayJson(WorkoutDay d, List<String> injuries) {
  return <String, dynamic>{
    'day': d.name,
    'focus': d.focus,
    'exercise_count': d.exercises.length,
    'exercises':
        d.exercises.map((e) => _exerciseJson(e, injuries)).toList(),
  };
}

Map<String, dynamic> _phaseJson(
    Phase phase, Persona p, List<WorkoutDay>? variantB) {
  final effExp = PlanGenerator.effectiveLevel(p.experience, phase.phase);
  final week1 = phase.weekPlans.isNotEmpty
      ? phase.weekPlans.first.workoutDays
      : phase.workouts;
  return <String, dynamic>{
    'phase': phase.phase,
    'name': phase.name,
    'focus': phase.focus,
    'weeks': phase.weeks,
    'dailyCalories': phase.dailyCalories,
    'proteinGrams': phase.proteinGrams,
    'effective_experience': effExp,
    'expected_per_day': VolumeFilter.targetCount(effExp, p.days),
    'week_characters':
        phase.weekPlans.map((w) => w.weekCharacter).toList(),
    'days': week1.map((d) => _dayJson(d, p.injuries)).toList(),
    if (variantB != null)
      'days_variant_b':
          variantB.map((d) => _dayJson(d, p.injuries)).toList(),
  };
}

Map<String, dynamic> _personaJson(Persona p, List<Phase> phases) {
  final phasesJson = <Map<String, dynamic>>[];

  var universalPoolPicks = 0;
  var syntheticPicks = 0;
  var contraHitCount = 0;
  var emptyDays = 0;
  var shortDays = 0; // days with fewer exercises than the expected target
  var minPerDay = -1;
  final distinct = <String>{};
  final contraExamples = <String>{};

  for (final phase in phases) {
    final variantB = _distinctVariantB(phase);
    final week1 = phase.weekPlans.isNotEmpty
        ? phase.weekPlans.first.workoutDays
        : phase.workouts;
    final effExp = PlanGenerator.effectiveLevel(p.experience, phase.phase);
    final expected = VolumeFilter.targetCount(effExp, p.days);

    // Summarize over the two DISTINCT representative variants (A = week1, and
    // B = week2 only when it differs) so duplicate weeks don't inflate counts.
    final summaryDays = <WorkoutDay>[
      ...week1,
      if (variantB != null) ...variantB,
    ];
    for (final d in summaryDays) {
      if (d.exercises.isEmpty) emptyDays++;
      if (d.exercises.length < expected) shortDays++;
      if (minPerDay < 0 || d.exercises.length < minPerDay) {
        minPerDay = d.exercises.length;
      }
      for (final e in d.exercises) {
        distinct.add(e.exerciseName);
        final libRow =
            ExerciseRepository.instance.getByExactName(e.exerciseName);
        final source = _sourceMarker(e, libRow);
        if (source == 'universal_fallback_synthetic') {
          syntheticPicks++;
        } else if (source == 'universal_pool_name') {
          universalPoolPicks++;
        }
        final contra = _contraHits(libRow, p.injuries);
        if (contra.isNotEmpty) {
          contraHitCount++;
          contraExamples.add('${e.exerciseName} (${contra.join("/")})');
        }
      }
    }

    phasesJson.add(_phaseJson(phase, p, variantB));
  }

  return <String, dynamic>{
    'id': p.id,
    'label': p.label,
    'goal': p.goal,
    'equipment': p.equipment,
    'days': p.days,
    'experience': p.experience,
    'injuries': p.injuries,
    'physique_focus': p.physiqueFocus,
    'age': 30,
    'phases': phasesJson,
    'summary': <String, dynamic>{
      'distinct_exercise_count': distinct.length,
      'universal_pool_name_picks': universalPoolPicks,
      'synthetic_fallback_picks': syntheticPicks,
      'contra_hits': contraHitCount,
      'contra_examples': contraExamples.toList(),
      'empty_days': emptyDays,
      'short_days': shortDays,
      'min_exercises_per_day': minPerDay,
    },
  };
}

// ── Test ────────────────────────────────────────────────────────────

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('persona_matrix_export');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;

    // Shared boxes the generator + flags read directly.
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    await Hive.openBox(HiveService.exerciseBoxName);
    HiveService.instance.markInitializedForTests();

    // Seed the exercise library (keyed by id, exactly as SeedService does).
    await HiveService.instance.exerciseBox.putAll(_loadExerciseSeed());

    // Turn ON all 13 ship-dark flags BEFORE generating.
    for (final flag in _shipDarkFlags) {
      await HiveService.instance.configBox.put(flag, true);
    }

    // Open the user-scoped boxes (userBox drives the physique_focus /
    // equipment_exclusions profile reads).
    await HiveUserSession.openForUser(_testUser);
  });

  tearDownAll(() async {
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  test('exercise library seeds + is queryable (guards against all-fallback plans)',
      () {
    final all = ExerciseRepository.instance.getAll();
    expect(all.length, greaterThan(200),
        reason: 'Seed failed — the generator would emit all-fallback plans.');
    // Sanity: a full-gym compound push exists to fill a real slot.
    final hasBench = all.any((e) =>
        (e['name'] as String?)?.toLowerCase().contains('bench press') ?? false);
    expect(hasBench, isTrue);
  });

  test('persona matrix → generateV4 phases 1-3 → structured JSON export',
      () async {
    final personasOut = <Map<String, dynamic>>[];
    final errors = <String>[];

    for (final p in _personas) {
      // Seed the persona profile. Only physique_focus + equipment_exclusions are
      // read by generateV4; the rest are set for faithfulness / robustness.
      await HiveService.instance.userBox.put('profile', <String, dynamic>{
        'id': _testUser,
        'goal': p.goal,
        'equipment_access': p.equipment,
        'days_per_week': p.days,
        'fitness_experience': p.experience,
        'injuries': p.injuries,
        'physique_focus': p.physiqueFocus ?? 'balanced',
        'age': 30,
      });

      try {
        final phases = <Phase>[];
        for (final phaseNum in _phasesToGenerate) {
          final phase = PlanGenerator.instance.generateV4(
            goal: p.goal,
            equipment: p.equipment,
            daysPerWeek: p.days,
            phase: phaseNum,
            experienceLevel: p.experience,
            injuries: p.injuries,
            // bodyFocus left default so the physique_focus PROFILE read drives it.
          );
          phases.add(phase);
        }
        personasOut.add(_personaJson(p, phases));
      } catch (e, st) {
        errors.add('${p.id}: $e\n$st');
        personasOut.add(<String, dynamic>{
          'id': p.id,
          'label': p.label,
          'error': e.toString(),
        });
      }
    }

    // Top-level anomaly roll-up (recorded, never fixed).
    final anomalies = <Map<String, dynamic>>[];
    for (final persona in personasOut) {
      final summary = persona['summary'] as Map<String, dynamic>?;
      if (summary == null) continue;
      final synthetic = summary['synthetic_fallback_picks'] as int? ?? 0;
      final pool = summary['universal_pool_name_picks'] as int? ?? 0;
      final contra = summary['contra_hits'] as int? ?? 0;
      final empty = summary['empty_days'] as int? ?? 0;
      if (synthetic > 0 || pool > 0 || contra > 0 || empty > 0) {
        anomalies.add(<String, dynamic>{
          'id': persona['id'],
          'label': persona['label'],
          'synthetic_fallback_picks': synthetic,
          'universal_pool_name_picks': pool,
          'contra_hits': contra,
          'contra_examples': summary['contra_examples'],
          'empty_days': empty,
        });
      }
    }

    final output = <String, dynamic>{
      'generated_at': DateTime.now().toIso8601String(),
      'generator': 'PlanGenerator.instance.generateV4',
      'ship_dark_flags_enabled': _shipDarkFlags,
      'phases_per_persona': _phasesToGenerate,
      'persona_count': _personas.length,
      'anomalies': anomalies,
      'personas': personasOut,
    };

    // Write the JSON (create the scratchpad dir if needed).
    final outFile = File(_outputPath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(output));

    // Structural assertions (fallback/none/contra are DATA, not failures).
    expect(outFile.existsSync(), isTrue);
    expect(outFile.lengthSync(), greaterThan(0));
    expect(personasOut.length, _personas.length);
    for (var i = 0; i < _personas.length; i++) {
      final persona = personasOut[i];
      final phasesJson = persona['phases'] as List<dynamic>?;
      expect(phasesJson, isNotNull,
          reason: '${_personas[i].id} produced no phases');
      expect(phasesJson!.length, _phasesToGenerate.length,
          reason: '${_personas[i].id} missing a phase');
      // Each phase must produce exactly daysPerWeek workout days.
      for (final ph in phasesJson) {
        final days = (ph as Map<String, dynamic>)['days'] as List<dynamic>;
        expect(days.length, _personas[i].days,
            reason:
                '${_personas[i].id} phase ${ph['phase']} day-count drift');
      }
    }
    // A real generator crash still fails the harness (JSON is written first).
    expect(errors, isEmpty, reason: errors.join('\n---\n'));

    // ignore: avoid_print
    print('[persona_matrix_export] wrote ${personasOut.length} personas × '
        '${_phasesToGenerate.length} phases → $_outputPath '
        '(${anomalies.length} personas flagged)');
  });
}
