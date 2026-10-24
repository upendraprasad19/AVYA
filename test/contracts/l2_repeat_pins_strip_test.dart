// c3e9a4 (d4b8e1 Batch 0b) — a REPEAT phase advance re-pins the just-finished
// phase's exercise names (buildPinnedDays resolves a non-library name through
// the customs). Rows the removed lever L2 polluted would carry its customs into
// the next phase, so _buildRepeatPins strips them first (the predicate shared
// with the repair migrator). A coach-swapped custom IS pinned. A failing custom
// read fails OPEN: pins are still built, unstripped.
//
// Real Hive + the full bundled library, the production entry
// WorkoutScheduleReadService.buildRepeatPinsForAdvance.
// Mutation (rule 21): remove the _withoutAutoAppendedCustoms call in
// _buildRepeatPins → (1) RED.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:icanbefitter/core/constants/fitness_goals.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/shared/repositories/plan_engine/plan_generator.dart';

const _start = '2026-09-14'; // a Monday: week 1 = 09-14..20, week 2 = 09-21..27

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late Box wb;
  late List<String> nonFatals;

  Map<String, dynamic> ex(String name, {bool coach = false}) => {
        'exercise_name': name,
        'sets': 3,
        if (coach) 'swapped_via': 'ai_coach',
      };

  Future<void> putDay(String date, List<Map<String, dynamic>> exercises) =>
      wb.put('schedule_$date', {
        'type': 'workout',
        'status': 'planned',
        'workout_day_index': 0,
        'exercises': exercises,
      });

  Map<int, ({List<String> a, List<String> b})>? pins() =>
      WorkoutScheduleReadService.instance.buildRepeatPinsForAdvance(
        goal: 'build_muscle',
        equipment: 'full_gym',
        daysPerWeek: 4,
        experienceLevel: 'intermediate',
        newPhase: 5,
      );

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('l2_repeat_pins_strip');
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
    final rows = jsonDecode(
      File('assets/data/exercise_library.json').readAsStringSync(),
    ) as List;
    for (final r in rows.whereType<Map>()) {
      await exBox.put(
          (r['id'] ?? r['name']).toString(), Map<String, dynamic>.from(r));
    }
    HiveService.instance.markInitializedForTests();
    await HiveUserSession.openForUser('c3e9a4aa-0000-4000-8000-00000000c3e9');
    wb = HiveService.instance.workoutBox;
  });

  tearDownAll(() async {
    await HiveUserSession.closeAll();
    GuardedBox.testBypassOwnership = false;
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await wb.clear();
    await HiveService.instance.customBox.clear();
    await HiveService.instance.configBox.clear();
    await HiveService.instance.customBox.put('custom_exercise_rp0', {
      'type': 'exercise',
      'name': 'tuck planche',
      'primary_muscles': ['Chest'],
    });
    await MigratedKey.write('plan_start_date', _start);
    await MigratedKey.write('last_phase_profile', {
      'plan_goal': FitnessGoals.of('build_muscle').planGoal,
      'equipment': 'full_gym',
      'days_per_week': 4,
      'effective_exp': PlanGenerator.effectiveLevel('intermediate', 5),
    });
    expect(istDateStr(DateTime.parse(_start)), _start);
    nonFatals = <String>[];
    ErrorTelemetry.debugOnRecordNonFatalForTests =
        (e, st, {required reason, extra}) => nonFatals.add(reason);
    WorkoutScheduleReadService.debugRepeatPinCustomNames = null;
  });

  tearDown(() {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    WorkoutScheduleReadService.debugRepeatPinCustomNames = null;
  });

  test('(1) an auto-appended custom in the finished phase is NOT re-pinned',
      () async {
    await putDay('2026-09-14', [ex('Cable Fly'), ex('tuck planche')]);
    await putDay('2026-09-21', [ex('Skull Crusher'), ex('Tuck Planche ')]);

    final p = pins();

    expect(p, isNotNull);
    expect(p![0]!.a, ['Cable Fly']);
    expect(p[0]!.b, ['Skull Crusher']);
  });

  test('(2) a coach-swapped custom IS re-pinned', () async {
    await putDay('2026-09-14', [ex('Cable Fly'), ex('tuck planche', coach: true)]);
    await putDay('2026-09-21', [ex('Skull Crusher')]);

    expect(pins()![0]!.a, ['Cable Fly', 'tuck planche']);
  });

  test('(2b) a custom a previous repeat pinned (custom_origin) IS re-pinned',
      () async {
    await putDay('2026-09-14', [
      ex('Cable Fly'),
      {...ex('tuck planche'), 'custom_origin': 'repeat_pin'},
    ]);
    await putDay('2026-09-21', [ex('Skull Crusher')]);

    expect(pins()![0]!.a, ['Cable Fly', 'tuck planche']);
  });

  test('(2c) a community-approved row of the custom\'s name is not library: '
      'still NOT re-pinned', () async {
    final exBox = HiveService.instance.exerciseBox;
    await exBox.put('0c0ffee0-community-tuck-planche',
        {'name': 'tuck planche', 'source': 'community'});
    addTearDown(() => exBox.delete('0c0ffee0-community-tuck-planche'));
    await putDay('2026-09-14', [ex('Cable Fly'), ex('tuck planche')]);
    await putDay('2026-09-21', [ex('Skull Crusher')]);

    expect(pins()![0]!.a, ['Cable Fly']);
  });

  test('(3) a failing custom read fails OPEN: pins built, unstripped, '
      'non-fatal recorded', () async {
    WorkoutScheduleReadService.debugRepeatPinCustomNames =
        () => throw StateError('customBox closed');
    await putDay('2026-09-14', [ex('Cable Fly'), ex('tuck planche')]);
    await putDay('2026-09-21', [ex('Skull Crusher')]);

    final p = pins();

    expect(p![0]!.a, ['Cable Fly', 'tuck planche']);
    expect(nonFatals, ['repeat_pins_custom_strip']);
  });

  test('(4) kill switch disable_l2_custom_strip: pre-repair pins', () async {
    await HiveService.instance.configBox.put('disable_l2_custom_strip', true);
    await putDay('2026-09-14', [ex('Cable Fly'), ex('tuck planche')]);
    await putDay('2026-09-21', [ex('Skull Crusher')]);

    expect(pins()![0]!.a, ['Cable Fly', 'tuck planche']);
  });

  test('(5) the stored rows are not changed by the read', () async {
    await putDay('2026-09-14', [ex('Cable Fly'), ex('tuck planche')]);
    await putDay('2026-09-21', [ex('Skull Crusher')]);

    pins();

    final names = [
      for (final e in (wb.get('schedule_2026-09-14') as Map)['exercises'] as List)
        (e as Map)['exercise_name'],
    ];
    expect(names, ['Cable Fly', 'tuck planche']);
  });
}
