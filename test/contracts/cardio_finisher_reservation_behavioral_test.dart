// Unit 3C (OI-396, founder 2026-10-22 / d56 / d61 / d74 / d75 / d76; plan
// docs/plans/2026-11-16-generator-step3c-cardio-finisher.md §2.1 / §2.2): the finisher through the REAL
// `PlanGenerator.instance.generateV4` over the real exercise library.
//
// - The finisher's time is taken from the days that carry it (d61): with the finisher counted, a finisher day stays
//   inside the user's minutes (plus the allocator's known bounds); with nothing reserved (`CardioFinisher.debugReserve`), the
//   same days run over.
// - The shape follows the minutes (d76: under 60 the 4-minute one) and the injury (d74: the bike in a gym, none at home).
// - Build plans never change.
@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/utils/injury_vocab.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/cardio_finisher.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/models.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_budget.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/session_set_allocator.dart';

const _user = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

Phase _gen({
  String goal = 'lose_fat',
  String tier = 'full_gym',
  int days = 4,
  String level = 'intermediate',
  int minutes = 60,
  int phase = 1,
  List<String> injuries = const [],
  List<String> exclusions = const [],
}) =>
    PlanGenerator.instance.generateV4(
      goal: goal,
      equipment: tier,
      daysPerWeek: days,
      phase: phase,
      experienceLevel: level,
      injuries: injuries,
      equipmentExclusions: exclusions,
      sessionDuration: minutes,
      previousWeights: const {},
    );

List<String> _finisherNames(WorkoutDay d) => [for (final e in d.finisher) e.exerciseName];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Map<String, Map<String, dynamic>> rowsById;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('finisher_reservation');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    GuardedBox.testBypassOwnership = true;
    await Hive.openBox(HiveService.configBoxName);
    await Hive.openBox(HiveService.migrationBoxName);
    final exBox = await Hive.openBox(HiveService.exerciseBoxName);
    final rows = jsonDecode(File('assets/data/exercise_library.json').readAsStringSync()) as List;
    rowsById = {};
    for (final r in rows.whereType<Map>()) {
      final id = (r['id'] ?? r['name']).toString();
      await exBox.put(id, Map<String, dynamic>.from(r));
      rowsById[id] = Map<String, dynamic>.from(r);
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser(_user);
  });

  tearDownAll(() async {
    CardioFinisher.debugReserve = true;
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  tearDown(() async {
    CardioFinisher.debugReserve = true;
    await HiveService.instance.configBox.delete('disable_equipment_exclusions');
  });

  /// The days of every week that carry a finisher, and the finisher's names on each.
  Map<int, Set<int>> finisherDays(Phase p) => {
        for (var w = 0; w < p.weekPlans.length; w++)
          w: {
            for (var d = 0; d < p.weekPlans[w].workoutDays.length; d++)
              if (p.weekPlans[w].workoutDays[d].finisher.isNotEmpty) d,
          },
      };

  group('the shape (d74, d76)', () {
    test('Cut 60 / 90 minutes: the HIIT with its round rest on days {0, 2} of every week', () {
      for (final m in [60, 90]) {
        final p = _gen(minutes: m);
        for (final w in p.weekPlans) {
          expect(w.workoutDays.length, 4, reason: 'one day per populated day, every week');
        }
        for (final days in finisherDays(p).values) {
          expect(days, {0, 2}, reason: '$m');
        }
        final d0 = p.weekPlans.first.workoutDays.first;
        expect(_finisherNames(d0), ['Burpees', 'Mountain Climbers', 'Jump Squats']);
        expect(CardioFinisher.secondsOf(d0.finisher), 540, reason: '$m');
      }
    });

    test('under 60 minutes (d76): the 4-minute mini HIIT', () {
      for (final m in [30, 45]) {
        final d0 = _gen(minutes: m).weekPlans.first.workoutDays.first;
        expect(_finisherNames(d0), ['High Knees', 'Burpees', 'Mountain Climbers'], reason: '$m');
        expect(CardioFinisher.secondsOf(d0.finisher), 240, reason: '$m');
      }
    });

    test('any injury in a gym (d74): only the bike, 8 rounds at 60, 4 under 60', () {
      for (final token in InjuryVocab.canonicalTokens) {
        final p = _gen(injuries: [token]);
        for (final w in p.weekPlans) {
          for (final d in w.workoutDays) {
            for (final name in _finisherNames(d)) {
              expect(name, CardioFinisher.injuredGymFinisherName, reason: token);
            }
          }
        }
        expect(CardioFinisher.secondsOf(p.weekPlans.first.workoutDays.first.finisher), 480, reason: token);
      }
      expect(CardioFinisher.secondsOf(_gen(injuries: const ['knee'], minutes: 45).weekPlans.first.workoutDays.first.finisher),
          240);
    });

    test('an injured user at home, or with the cardio machine excluded, gets no finisher', () {
      for (final tier in ['bodyweight', 'home_dumbbells']) {
        expect(finisherDays(_gen(tier: tier, injuries: const ['knee'])).values.every((s) => s.isEmpty), isTrue,
            reason: tier);
      }
      expect(
          finisherDays(_gen(injuries: const ['knee'], exclusions: const ['cardio machine'])).values.every((s) => s.isEmpty),
          isTrue);
    });

    test('the equipment exclusions switch set: an injured gym user gets no finisher (accepted, plan §2.1)', () async {
      await HiveService.instance.configBox.put('disable_equipment_exclusions', true);
      expect(finisherDays(_gen(injuries: const ['knee'])).values.every((s) => s.isEmpty), isTrue);
    });

    test('free text no alias maps is not an injury (the engine normalisation)', () {
      final d0 = _gen(injuries: const ['xyz free text']).weekPlans.first.workoutDays.first;
      expect(_finisherNames(d0), ['Burpees', 'Mountain Climbers', 'Jump Squats']);
    });
  });

  group('the reservation (d61)', () {
    /// The day as the screens price it, finisher included.
    double shown(WorkoutDay d) => SessionBudget.estimateDaySecondsFromPlanDay(d.toMap(), rowsById,
        finisher: [for (final f in d.finisher) f.toMap()]);

    /// Seconds the allocator may legitimately run past the minutes (the count floor's forcing bound, the under-60
    /// allowance, rounding).
    double slack(int minutes) =>
        SessionBudget.maxForcedOverSeconds + (minutes < 60 ? SessionBudget.allowanceSeconds : 0) + 120.0;

    test('with the finisher counted, every finisher day of Cut and Maintain stays within the minutes', () {
      final over = <String>[];
      for (final goal in ['lose_fat', 'general_fitness']) {
        for (final m in [30, 45, 60, 90]) {
          for (final days in [3, 4, 5]) {
            for (final level in ['beginner', 'intermediate']) {
              final p = _gen(goal: goal, minutes: m, days: days, level: level);
              for (var w = 0; w < p.weekPlans.length; w++) {
                for (final d in p.weekPlans[w].workoutDays.where((d) => d.finisher.isNotEmpty)) {
                  if (shown(d) > m * 60 + slack(m)) over.add('$goal $m $days $level w$w ${d.name} ${shown(d) ~/ 60}');
                }
              }
            }
          }
        }
      }
      expect(over, isEmpty, reason: over.take(10).join('; '));
    });

    test('positive control: with nothing reserved (debugReserve false) the same finisher days run over', () async {
      // The finisher is built as stored (its round rest included), only its time is not taken from the day.
      CardioFinisher.debugReserve = false;
      var over = 0;
      for (final m in [45, 60]) {
        final p = _gen(minutes: m);
        for (final w in p.weekPlans) {
          for (final d in w.workoutDays.where((d) => d.finisher.isNotEmpty)) {
            if (shown(d) > m * 60 + 120) over++;
          }
        }
      }
      expect(over, greaterThan(0), reason: 'the oracle above must be able to see an unreserved finisher');
    });

    test('a non-finisher day of the same Cut plan keeps its whole budget (the reservation is per day)', () async {
      // Reserving on every day (the mutant) would cost each non-finisher day the finisher's time too (~240-540 s).
      // With the per-day reservation those days stay where the unreserved world prices them (the shared weekly
      // ledger moves a little either way).
      var loss = 0.0, n = 0;
      for (final m in [45, 60, 90]) {
        for (final days in [3, 4, 5]) {
          final on = _gen(minutes: m, days: days);
          CardioFinisher.debugReserve = false;
          final off = _gen(minutes: m, days: days);
          CardioFinisher.debugReserve = true;
          for (var w = 0; w < on.weekPlans.length; w++) {
            for (var d = 0; d < on.weekPlans[w].workoutDays.length; d++) {
              final dOn = on.weekPlans[w].workoutDays[d];
              if (dOn.finisher.isNotEmpty) continue;
              final dOff = off.weekPlans[w].workoutDays[d];
              loss += SessionBudget.estimateDaySecondsFromPlanDay(dOff.toMap(), rowsById, finisher: const []) -
                  shown(dOn);
              n++;
            }
          }
        }
      }
      expect(n, greaterThan(0));
      expect(loss / n, lessThan(120), reason: 'mean seconds a non-finisher day lost: ${(loss / n).round()}');
    });

    test('a non-finisher day keeps its whole budget: Build plans are unchanged by the unit', () async {
      for (final m in [30, 60]) {
        final on = jsonEncode(_gen(goal: 'build_muscle', minutes: m).toMap());
        CardioFinisher.debugReserve = false;
        final off = jsonEncode(_gen(goal: 'build_muscle', minutes: m).toMap());
        CardioFinisher.debugReserve = true;
        expect(on, off, reason: '$m');
      }
    });

    test('the allocator sees the finisher days: its stats run per variant, phases 1, 4 and 5', () {
      for (final phase in [1, 4, 5]) {
        SessionSetAllocator.debugLastStats = null;
        final p = _gen(phase: phase, minutes: 45);
        expect(SessionSetAllocator.debugLastStats, isNotNull, reason: '$phase');
        for (final days in finisherDays(p).values) {
          expect(days, {0, 2}, reason: '$phase');
        }
      }
    });
  });
}
