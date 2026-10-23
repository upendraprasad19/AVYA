// Injury re-check (seed v14) — docs/plans/2026-10-23-library-injury-recheck.md,
// diagnose docs/diagnoses/2026-10-23-library-injury-recheck-d30de7.md.
//
// Founder decision 2026-10-23: the 13-B "kept safe for variety" principle is
// rejected; 102 library rows gain 146 injury tags (additions only). This file
// pins, in three layers:
//  (A) DATA — every founder call as a literal on a name, the closed vocabulary,
//      the table the applier reads, the 33-row safe pool (and nothing else
//      left untagged).
//  (B) BEHAVIOUR — the REAL PlanGenerator.generateV4 (flag OFF, the path users
//      get) and the REAL queryV4 filter. Every absence has a positive control:
//      the same persona / the unfiltered query holds the move.
//  (C) The curated injury substitutes only name moves that are safe for the
//      injury they are listed under.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/shared/repositories/exercise_repository.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/injury_substitutes.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

import '../helpers/injury_safe_pool.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
  late Directory tempDir;
  late List<Map<String, dynamic>> library;
  late Map<String, Set<String>> tagsByName; // lowercased name → tokens
  late Map<String, Set<String>> tagsById;
  late Map<String, dynamic> table;

  Set<String> toks(Object? v) => {
        if (v is List) ...v.map((t) => t.toString()),
      };

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('injury_recheck_v14');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    library = (jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .toList();
    tagsByName = {};
    tagsById = {};
    for (final r in library) {
      await exBox.put(r['id'] as String, r);
      final t = toks(r['injury_contraindications']);
      tagsById[r['id'] as String] = t;
      tagsByName[(r['name'] as String).toLowerCase()] = t;
    }
    table = jsonDecode(
      File('scripts/data/library_injury_additions_v14.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(testUser);
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Set<String> tagsOf(String name) {
    final t = tagsByName[name.toLowerCase()];
    expect(t, isNotNull, reason: '"$name" is not a library row');
    return t!;
  }

  // ---------------------------------------------------------------- (A) DATA
  group('(A) v14 data contract', () {
    test('the table: 102 rows, 146 tokens, canonical tokens, known ids', () {
      final additions = Map<String, dynamic>.from(table['additions'] as Map);
      expect(additions.length, 102);
      var tokens = 0;
      for (final e in additions.entries) {
        expect(tagsById.containsKey(e.key), isTrue, reason: '${e.key} unknown id');
        final t = toks(e.value);
        expect(t, isNotEmpty, reason: '${e.key} adds nothing');
        expect(InjuryVocab.canonicalTokens.containsAll(t), isTrue,
            reason: '${e.key} has a non-canonical token: $t');
        tokens += t.length;
      }
      expect(tokens, 146);
      expect((table['reasons'] as Map).keys.toSet(), additions.keys.toSet(),
          reason: 'every added row carries a one-line reason');
    });

    test('every table token is in the library row; touched lists are sorted; every token is canonical', () {
      final additions = Map<String, dynamic>.from(table['additions'] as Map);
      for (final e in additions.entries) {
        expect(tagsById[e.key]!.containsAll(toks(e.value)), isTrue,
            reason: '${e.key} lost a v14 token');
        // The applier sorts the rows it touches. 16 untouched rows (E229, E248, ...)
        // kept their v13 order, which the filter never reads, so only the table's
        // rows are held to sorted.
        final list = (library.firstWhere((r) => r['id'] == e.key)['injury_contraindications']
                as List)
            .cast<String>();
        expect(list, [...list]..sort(), reason: '${e.key} list not sorted');
      }
      for (final r in library) {
        final list = (r['injury_contraindications'] as List).cast<String>();
        expect(InjuryVocab.canonicalTokens.containsAll(list), isTrue,
            reason: '${r['id']} has a non-canonical token');
      }
    });

    test('founder calls, literally', () {
      expect(tagsOf('Kettlebell Goblet Press'), contains('shoulder'));
      expect(tagsOf('Lat Pulldown'), contains('shoulder'));
      // "chinup is elbow": elbow, and NOT shoulder.
      expect(tagsOf('Chin Up'), contains('elbow'));
      expect(tagsOf('Chin Up'), isNot(contains('shoulder')));
      // "wrist and shoulders".
      expect(tagsOf('Push Up'), {'shoulder', 'wrist'});
      expect(tagsOf('Hollow Body Hold'), contains('lower_back'));
      expect(tagsOf('Hip Abduction Machine'), contains('hip'));
      expect(tagsOf('Hip Adduction Machine'), contains('hip'));
      for (final n in ['Burpee', 'Mountain Climber']) {
        expect(tagsOf(n), containsAll(['shoulder', 'wrist']), reason: n);
      }
      // CARVEOUT-E173-E127 closed as "keep".
      expect(tagsOf('Decline Sit Up'), contains('lower_back'));
      expect(tagsOf('Reverse Hyper'), contains('lower_back'));
      // "We cannot give a bicycle crunch or a V-up or a Russian twist to a
      // injured user."
      for (final n in ['Crunches', 'Bicycle Crunch', 'V-Up', 'Russian Twist']) {
        expect(tagsOf(n), contains('lower_back'), reason: n);
      }
    });

    test('every elbow_flexion / elbow_extension row carries elbow', () {
      final rows = library.where((r) => (r['movement_pattern'] as List)
          .any((p) => p == 'elbow_flexion' || p == 'elbow_extension'));
      expect(rows.length, 30, reason: 'denominator: library rows in the two patterns');
      for (final r in rows) {
        expect(toks(r['injury_contraindications']), contains('elbow'),
            reason: '${r['id']} ${r['name']}');
      }
    });

    test('the safe pool: 33 named rows stay untagged, and nothing else does', () {
      expect(kV14SafePool.length, 33);
      for (final n in kV14SafePool) {
        expect(tagsOf(n), isEmpty, reason: '"$n" must stay untagged (low-load / rehab)');
      }
      final safe = kV14SafePool.map((n) => n.toLowerCase()).toSet();
      final untaggedOutside = [
        for (final r in library)
          if (toks(r['injury_contraindications']).isEmpty &&
              !safe.contains((r['name'] as String).toLowerCase()))
            '${r['id']} ${r['name']}'
      ];
      expect(untaggedOutside, isEmpty,
          reason: 'the founder wants every row outside the safe pool tagged');
    });
  });

  // ------------------------------------------------- (B) BEHAVIOUR, generator
  group('(B) the real generator, flag OFF', () {
    Set<String> planNames(String tier, String goal, String level, int days,
        List<String> injuries) {
      final Phase p = PlanGenerator.instance.generateV4(
        goal: goal,
        equipment: tier,
        daysPerWeek: days,
        phase: 1,
        experienceLevel: level,
        injuries: injuries,
        previousWeights: const {},
      );
      return {
        for (final w in p.weekPlans)
          for (final d in w.workoutDays)
            for (final e in d.exercises) e.exerciseName
      };
    }

    // (move, injury, tier, level, days): personas found by a reach search on
    // 144 uninjured plans (4 tiers x 4 goals x 3 levels x 3/4/5 days), all
    // build_muscle. Each move IS in the uninjured plan (positive control).
    const reached = <(String, String, String, String, int)>[
      ('Push Up', 'shoulder', 'bodyweight', 'beginner', 3),
      ('Lat Pulldown', 'shoulder', 'basic_gym', 'beginner', 3),
      ('Chin Up', 'elbow', 'basic_gym', 'beginner', 5),
      ('Russian Twist', 'lower_back', 'bodyweight', 'beginner', 3),
      ('Crunches', 'lower_back', 'bodyweight', 'advanced', 3),
      ('Bicycle Crunch', 'lower_back', 'bodyweight', 'advanced', 3),
      ('Hip Abduction Machine', 'hip', 'full_gym', 'beginner', 5),
      ('Hip Adduction Machine', 'hip', 'full_gym', 'intermediate', 3),
    ];
    for (final (move, injury, tier, level, days) in reached) {
      test('$move: in the uninjured $tier/$level/${days}d plan, gone for $injury', () {
        expect(planNames(tier, 'build_muscle', level, days, const []), contains(move),
            reason: 'positive control');
        expect(planNames(tier, 'build_muscle', level, days, [injury]),
            isNot(contains(move)));
      });
    }

    test('elbow: no elbow_flexion / elbow_extension row survives; uninjured has one', () {
      final elbowRows = {
        for (final r in library)
          if ((r['movement_pattern'] as List)
              .any((p) => p == 'elbow_flexion' || p == 'elbow_extension'))
            r['name'] as String
      };
      final healthy = planNames('bodyweight', 'build_muscle', 'beginner', 3, const []);
      expect(healthy.intersection(elbowRows), isNotEmpty, reason: 'positive control');
      expect(planNames('bodyweight', 'build_muscle', 'beginner', 3, ['elbow'])
          .intersection(elbowRows), isEmpty);
    });
  });

  // ----------------------------------------------- (B) BEHAVIOUR, the filter
  group('(B) queryV4 on moves no persona picks', () {
    List<String> query(String pattern, List<String>? injuries) => [
          for (final r in ExerciseRepository.instance.queryV4(
            movementPattern: pattern,
            injuryExclusions: injuries,
            exclusions: const {},
            capability: null,
          ))
            r['name'] as String
        ];

    const pairs = <(String, String, String)>[
      ('Kettlebell Goblet Press', 'vertical_push', 'shoulder'),
      ('V-Up', 'core', 'lower_back'),
      ('Hollow Body Hold', 'core', 'lower_back'),
      ('Burpee', 'cardio', 'shoulder'),
      ('Burpee', 'cardio', 'wrist'),
      ('Mountain Climber', 'cardio', 'shoulder'),
      ('Mountain Climber', 'cardio', 'wrist'),
    ];
    for (final (name, pattern, token) in pairs) {
      test('$name: queryV4($pattern) drops it for $token', () {
        expect(query(pattern, null), contains(name), reason: 'positive control');
        expect(query(pattern, [token]), isNot(contains(name)));
      });
    }

    test('the mirror of "Chin Up is elbow": shoulder keeps Chin Up, drops Lat Pulldown', () {
      expect(query('vertical_pull', ['shoulder']), contains('Chin Up'));
      expect(query('vertical_pull', ['shoulder']), isNot(contains('Lat Pulldown')));
      expect(query('vertical_pull', ['elbow']), contains('Lat Pulldown'));
      expect(query('vertical_pull', ['elbow']), isNot(contains('Chin Up')));
    });
  });

  // ------------------------------------------- (C) curated substitutes safe
  group('(C) curated injury substitutes', () {
    test('every curated name is a library row NOT tagged for its own injury', () {
      for (final tok in InjuryVocab.canonicalTokens) {
        for (final lc in InjurySubstitutes.preferredFor([tok])) {
          expect(tagsByName.containsKey(lc), isTrue,
              reason: '$tok: "$lc" is not a library row');
          expect(tagsByName[lc], isNot(contains(tok)),
              reason: '$tok lists "$lc", which is tagged for $tok: a dead substitute');
        }
      }
    });

    test('the shoulder list: the three founder-approved additions are in, the dead ones are out', () {
      final s = InjurySubstitutes.preferredFor(['shoulder']);
      expect(s, containsAll([
        'machine chest press', 'floor press', 'chest squeeze press',
        'face pull', 'band pull apart', 'machine high row', 'chin up',
        'tricep pushdown (cable)',
      ]));
      expect(s, isNot(contains('push up')));
      expect(s, isNot(contains('dumbbell bench press')));
      expect(s, isNot(contains('kettlebell goblet press')));
      expect(s, isNot(contains('lat pulldown')));
    });

    test('elbow has no curated list (every elbow-pattern row is tagged elbow)', () {
      expect(InjurySubstitutes.preferredFor(['elbow']), isEmpty);
    });
  });
}
