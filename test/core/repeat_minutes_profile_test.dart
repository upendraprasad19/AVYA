// Unit 2D (OI-453, plan docs/plans/2026-11-15-generator-step2d-repeat-minutes.md S1 / S2): `generateAndSchedule`
// stores the RESOLVED session minutes in `last_phase_profile` (`session_minutes`), and a later REPEAT compares its own
// resolved minutes against that OLD stored value, read before this call rewrites the profile. More minutes: the
// repeat appends accessories; the same minutes, or a profile written before 2D, leave the repeat unchanged.
//
// Layers: (A) the pure `repeatMinutesRose`; (B) the real `generateAndSchedule` over the seeded library in Hive, through
// the production pin path (`buildRepeatPinsForAdvance`).

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('repeatMinutesRose (pure)', () {
    bool rose(Map? stored, int now) => WorkoutScheduleReadService.repeatMinutesRose(stored, now);
    test('absent profile, absent key, null: not raised (a pre-2D profile never appends)', () {
      expect(rose(null, 90), isFalse);
      expect(rose(const {'plan_goal': 'build_muscle'}, 90), isFalse);
      expect(rose(const {'session_minutes': null}, 90), isFalse);
    });
    test('only a strictly larger now than a stored int is raised', () {
      expect(rose(const {'session_minutes': 45}, 45), isFalse, reason: 'equal');
      expect(rose(const {'session_minutes': 60}, 45), isFalse, reason: 'lower');
      expect(rose(const {'session_minutes': 45}, 46), isTrue, reason: 'higher');
      expect(rose(const {'session_minutes': 0}, 30), isTrue);
    });
    test('a non-int stored value reads as not raised', () {
      expect(rose(const {'session_minutes': 45.0}, 60), isFalse);
      expect(rose(const {'session_minutes': '45'}, 60), isFalse);
    });
  });

  group('generateAndSchedule (Hive, seeded library)', () {
    const testUser = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
    late Directory tempDir;

    setUpAll(() async {
      tempDir = await Directory.systemTemp.createTemp('repeat_minutes');
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
      for (final r in rows.whereType<Map>()) {
        await exBox.put((r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
      }
      HiveService.instance.markInitializedForTests();
      await HiveUserSession.openForUser(testUser);
    });

    tearDownAll(() async {
      await HiveUserSession.closeAll();
      GuardedBox.testBypassOwnership = false;
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    const goal = 'general_fitness', tier = 'full_gym', level = 'intermediate', days = 3;
    final svc = WorkoutScheduleReadService.instance;

    Set<String> namesOfWeeks() => {
          for (final w in [svc.getWeek(1), svc.getWeek(2)])
            for (final r in w)
              if (r['type'] == 'workout')
                for (final e in ((r['exercises'] as List?) ?? const []).whereType<Map>()) '${e['exercise_name']}',
        };

    Future<void> phaseOne(int? minutes) async {
      await MigratedKey.delete('last_phase_profile');
      await svc.generateAndSchedule(
          goal: goal,
          equipment: tier,
          daysPerWeek: days,
          startDate: DateTime(2026, 3, 2),
          experienceLevel: level,
          phase: 1,
          sessionDuration: minutes);
    }

    /// The repeat the advance runs: pins from the production path, then phase 2 at [minutes]. Returns the names in the
    /// new weeks 1-2 that are not pins.
    Future<Set<String>> repeatAt(int minutes) async {
      final pins = svc.buildRepeatPinsForAdvance(
          goal: goal, equipment: tier, daysPerWeek: days, experienceLevel: level, newPhase: 2, sessionDuration: minutes);
      expect(pins, isNotNull, reason: 'the same profile repeats');
      final pinned = {
        for (final p in pins!.values) ...[...p.a, ...p.b],
      };
      await svc.generateAndSchedule(
          goal: goal,
          equipment: tier,
          daysPerWeek: days,
          startDate: DateTime(2026, 3, 30),
          experienceLevel: level,
          phase: 2,
          sessionDuration: minutes,
          pinnedExercisesByDay: pins);
      return namesOfWeeks().difference(pinned);
    }

    test('the profile stores the RESOLVED minutes (an absent param resolves to the default)', () async {
      await phaseOne(30);
      expect(MigratedKey.read<Map>('last_phase_profile')!['session_minutes'], 30);
      await phaseOne(null);
      expect(MigratedKey.read<Map>('last_phase_profile')!['session_minutes'], isA<int>(),
          reason: 'never the raw null param');
    });

    test('a repeat at more minutes appends accessories; the profile then holds the new minutes', () async {
      await phaseOne(30);
      final extra = await repeatAt(60);
      expect(extra, isNotEmpty, reason: 'the old stored 30 was read before the write');
      expect(MigratedKey.read<Map>('last_phase_profile')!['session_minutes'], 60);
    });

    test('a repeat at the same minutes appends nothing', () async {
      await phaseOne(30);
      expect(await repeatAt(30), isEmpty);
    });

    test('a profile written before 2D (no session_minutes) appends nothing', () async {
      await phaseOne(30);
      final p = Map<String, dynamic>.from(MigratedKey.read<Map>('last_phase_profile')!)..remove('session_minutes');
      await MigratedKey.write('last_phase_profile', p);
      expect(await repeatAt(60), isEmpty);
    });
  });
}
