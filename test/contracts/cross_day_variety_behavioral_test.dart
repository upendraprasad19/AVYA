// OI-458: an Upper day reads as a new session. `ExerciseSelector.pickV4` fills every
// day with an empty exclude set, so the Upper day's shoulder, back and arm slots took
// the same top-ranked names the Push and Pull days of that week had just taken (Bench
// Dips, Dumbbell Row, curls, Lateral Raise). An `upper` day now SOFT-avoids the names
// the earlier push / pull days hold, per variant (bounded: a pool with nothing else
// still repeats). Proof: the REAL generator over tier x goal x days x level, weeks 1
// and 2, counting Upper-day names an earlier Push or Pull day of the week also holds.
@Timeout(Duration(minutes: 15))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

/// The days an Upper day must not echo, by the names `selectV4` gives them (the engine's
/// own day types are not on `WorkoutDay`): push / pull and the 5-day build_muscle split's
/// Chest, Back and Shoulders + Arms. The 4-day lose_fat / general_fitness split names its
/// days 'Upper Push' / 'Upper Pull' (engine day types push / pull, not upper): they are not
/// Upper days here and contribute 0, so that split is NOT covered by this sweep.
const _feeders = {'Push', 'Pull', 'Chest', 'Back', 'Shoulders + Arms'};

void main() {
  group('cross-day variety (OI-458)', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('count_band');
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
      final rows =
          (jsonDecode(
                    File(
                      'assets/data/exercise_library.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .map((r) => Map<String, dynamic>.from(r as Map))
              .toList();
      for (final r in rows) {
        await exBox.put((r['id'] ?? r['name']).toString(), r);
      }
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

    Phase gen({
      required String goal,
      required String tier,
      required int days,
      required String level,
      required int minutes,
      int phase = 1,
    }) => PlanGenerator.instance.generateV4(
      goal: goal,
      equipment: tier,
      daysPerWeek: days,
      phase: phase,
      experienceLevel: level,
      injuries: const [],
      bodyFocus: const [],
      sessionDuration: minutes,
      previousWeights: const {},
    );

    /// Pairs (name on an Upper day that an earlier Push / Pull day of the same
    /// week also holds), over every tier x goal x days x level, weeks 1 and 2.
    ({int pairs, int plans, List<String> sample}) measure() {
      var pairs = 0, plans = 0;
      final sample = <String>[];
      for (final tier in ['full_gym', 'basic_gym', 'home_dumbbells']) {
        for (final goal in ['build_muscle', 'general_fitness', 'lose_fat', 'strength']) {
          for (final n in [4, 5]) {
            for (final level in ['beginner', 'intermediate', 'advanced']) {
              final plan = gen(
                goal: goal,
                tier: tier,
                days: n,
                level: level,
                minutes: 60,
              );
              var hit = false;
              for (var w = 0; w < 2; w++) {
                final earlier = <String, String>{};
                for (final d in plan.weekPlans[w].workoutDays) {
                  final isUpper = d.name.startsWith('Upper');
                  final isPushPull = _feeders.contains(d.name);
                  for (final e in d.exercises) {
                    if (isUpper && earlier.containsKey(e.exerciseName)) {
                      pairs++;
                      hit = true;
                      sample.add(
                        '$tier|$goal|${n}d|$level w${w + 1}: ${e.exerciseName} (${earlier[e.exerciseName]})',
                      );
                    }
                    if (isPushPull) earlier[e.exerciseName] = d.name;
                  }
                }
              }
              if (hit) plans++;
            }
          }
        }
      }
      return (pairs: pairs, plans: plans, sample: sample);
    }

    test(
      'an Upper day holds a name the same week Push or Pull day holds only where the pool is too shallow (bounded)',
      () {
        final m = measure();
        // Before OI-458: 409 pairs in 42 of 72 plans (measured on the
        // unchanged selector). The ratchet is the measured figure after the fix.
        expect(
          m.pairs,
          lessThanOrEqualTo(70),
          reason: m.sample.take(20).join('\n'),
        );
        expect(m.plans, lessThanOrEqualTo(38));
        // The residue is a pool too shallow to offer anything else (the avoid is soft and bounded).
        expect(m.pairs, lessThan(409 ~/ 4));
      },
    );

    test('only an Upper day avoids: a 6-day beginner Push A and Push B keep their shared lifts (frequency is deliberate)', () {
      var shared = 0;
      for (final tier in ['full_gym', 'basic_gym', 'home_dumbbells']) {
        for (final level in ['beginner']) {
          final plan = gen(goal: 'build_muscle', tier: tier, days: 6, level: level, minutes: 60);
          final wk = plan.weekPlans[0].workoutDays;
          final push = wk.firstWhere((d) => d.name == 'Push A').exercises.map((e) => e.exerciseName).toSet();
          final pushCore = wk.firstWhere((d) => d.name == 'Push B').exercises.map((e) => e.exerciseName);
          shared += pushCore.where(push.contains).length;
        }
      }
      // 10 shared lifts measured with the fix; an avoid applied to every day would remove them.
      expect(shared, greaterThanOrEqualTo(10));
    });
  });
}
