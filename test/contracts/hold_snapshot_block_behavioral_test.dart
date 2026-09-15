// BEHAVIORAL TEST — hold_snapshot_block (FOB-3 / OI-60)
//
// Concept:  hold_snapshot_block
// Writer:   lib/core/services/workout_schedule_write_service.dart holdWeek()
//           (stamps `is_hold` / `hold_ordinal` on each schedule_* row)
// Seam:     lib/core/services/workout_schedule_read_service.dart
//           holdSnapshotBlock()  → WorkoutScheduleService.holdSnapshotBlock()
// Reader:   lib/features/ai_coach/services/ai_snapshot_builder.dart
//           buildAiContext() emits `'hold': ?holdBlock`, and
//           trimSnapshotToBudget()'s keep set holds it whole.
//           Downstream: supabase/functions/_shared/captain_manual.ts reads
//           snapshot.hold — that half needs an ai-proxy redeploy to go live.
//
// THE BUG: the snapshot sends current_week: 4 for EVERY hold day at EVERY
// ordinal. Holds start at plan_start+28 and the projection clamps at the end of
// the phase, so the number is the same every week of every hold. Combined with
// the manual's "free locks at Phase I after 4 weeks" and tier: free, the model
// synthesizes "final week of Phase I / upgrade now" — a false milestone that
// repeats weekly, aimed at the user who just chose to stay. Nothing under
// supabase/functions/ read is_hold or hold_ordinal at all.
//
// SHIP-DARK EVIDENCE (§4.12.4). The `flag OFF` group proves that with
// `enable_hold_weeks` OFF and REAL hold rows on disk, the seam returns null and
// the snapshot gains NO `hold` key — so the snapshot is byte-identical to the
// pre-FOB-3 one for every user in the fleet. `'hold': null` would NOT satisfy
// this; the null-aware element that omits the key is the load-bearing detail.
//
// The holds are materialized by the REAL holdWeek() writer, so these assertions
// fail if the writer's field names or cadence drift from what the seam reads.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/services/workout_schedule_write_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/repositories/ai_coach_repository.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000063';

  // plan_start = Monday 2026-06-01; plan_end = +27 = Sunday 2026-06-28.
  final planStart = DateTime(2026, 6, 1);
  final planEnd = planStart.add(const Duration(days: 27));
  final hold1Start = DateTime(2026, 6, 29);

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('holdsnapshot_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );
    Hive.init(tempDir.path);
    for (final name in [
      HiveService.exerciseBoxName,
      HiveService.foodBoxName,
      HiveService.syncBoxName,
      HiveService.configBoxName,
      HiveService.migrationBoxName,
    ]) {
      await Hive.openBox(name);
    }
    await HiveUserSession.openForUser(fakeUserId);
    GuardedBox.testBypassOwnership = true;
    HiveService.debugMarkInitializedForTests();

    await HiveService.instance.configBox.delete('enable_hold_weeks');
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    await HiveService.instance.userBox.put('progress', {
      'current_phase': 1,
      'current_week': 1,
      'total_workouts_done': 12,
    });
    for (int week = 1; week <= 4; week++) {
      for (int d = 0; d < 7; d++) {
        final date = planStart.add(Duration(days: (week - 1) * 7 + d));
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: {
            'type': 'workout',
            'date': formatDateKey(date),
            'week': week,
            'phase': 1,
            'status': 'planned',
            'workout_name': 'Upper Body',
            'exercises': <Map<String, dynamic>>[
              {'name': 'Squat', 'sets': 3, 'reps': 5, 'weight': 100.0 + week},
            ],
          },
          source: WriteSource.schedSwap,
        );
      }
    }
  });

  tearDown(() async {
    resetTestClock();
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Materializes [count] consecutive holds, one per week from the Monday after
  /// plan_end — the real user path. Leaves the clock inside the LAST hold.
  Future<void> takeHolds(int count) async {
    for (var i = 0; i < count; i++) {
      setTestClockTo(hold1Start.add(Duration(days: 7 * i, hours: 10)));
      await WorkoutScheduleWriteService.instance.holdWeek();
    }
  }

  group('flag OFF — the ship-dark property', () {
    test('REAL hold rows on disk produce NO hold block and NO hold key',
        () async {
      // Materialize with the flag ON so holdWeek() actually writes, then turn
      // it OFF: this is the exact state a fleet rollback would leave behind,
      // and the state a flag check that lives in the wrong place would miss.
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(2);
      await HiveService.instance.configBox.put('enable_hold_weeks', false);
      setTestClockTo(hold1Start.add(const Duration(days: 7, hours: 10)));

      expect(read.holdSnapshotBlock(), isNull,
          reason: 'the seam must consult the SAME gated accessor every other '
              'production consumer uses; hold rows on disk are not a hold');

      final snapshot = AiCoachRepository.instance.buildAiContext();
      expect(snapshot.containsKey('hold'), isFalse,
          reason: "THE ship-dark assertion. `'hold': null` would satisfy a "
              'naive isNull check and still change every snapshot in the '
              'fleet. The key must be ABSENT.');
      expect(jsonEncode(snapshot), isNot(contains('"hold"')),
          reason: 'belt and braces: no hold key at any nesting depth');
    });
  });

  group('flag ON — the coach is told the truth', () {
    test('inside H1 the block carries the ordinal and the H label', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);

      final block = read.holdSnapshotBlock();
      expect(block, isNotNull);
      expect(block!['ordinal'], 1);
      expect(block['label'], 'H1',
          reason: 'the coach must quote the identity verbatim rather than '
              'reconstruct it and land on "Week 1"');
      expect(block['week_start'], istDateStr(hold1Start));
      expect(block.containsKey('sessions_completed'), isTrue);
      expect(block.containsKey('sessions_total'), isTrue);

      final snapshot = AiCoachRepository.instance.buildAiContext();
      expect(snapshot['hold'], isNotNull);
      expect((snapshot['hold'] as Map)['label'], 'H1');
    });

    test('the label tracks the ordinal — H2 at the second hold, not H1',
        () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(2);
      setTestClockTo(hold1Start.add(const Duration(days: 7, hours: 10)));

      final block = read.holdSnapshotBlock();
      expect(block!['ordinal'], 2);
      expect(block['label'], 'H2',
          reason: 'a hardcoded H1 would pass the previous test and be wrong '
              'for every user who holds twice');
      expect(block['week_start'],
          istDateStr(hold1Start.add(const Duration(days: 7))));
    });

    test('a NON-hold day inside the plan window emits no hold key', () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);
      // Week 3 of the plan — hold rows exist, but today is not one of them.
      setTestClockTo(planStart.add(const Duration(days: 15, hours: 10)));

      expect(read.holdSnapshotBlock(), isNull);
      expect(AiCoachRepository.instance.buildAiContext().containsKey('hold'),
          isFalse,
          reason: 'the presence of hold rows must not hijack a normal week');
    });

    test('sessions_completed reflects real logged days, not a constant',
        () async {
      await HiveService.instance.configBox.put('enable_hold_weeks', true);
      await takeHolds(1);
      setTestClockTo(hold1Start.add(const Duration(hours: 10)));

      final before = read.holdSnapshotBlock()!['sessions_completed'] as int;

      // Complete one training day inside the hold week.
      final box = HiveService.instance.workoutBox;
      for (var d = 0; d < 7; d++) {
        final date = hold1Start.add(Duration(days: d));
        final row = box.get('schedule_${formatDateKey(date)}');
        if (row is! Map) continue;
        if ((row['type'] ?? '').toString() != 'workout') continue;
        await WorkoutWriteService.instance.upsertScheduled(
          date: date,
          entry: {...row.cast<String, dynamic>(), 'status': 'completed'},
          source: WriteSource.schedSwap,
        );
        break;
      }

      expect(read.holdSnapshotBlock()!['sessions_completed'], before + 1,
          reason: 'a hardcoded 0 would make the coach tell every holder they '
              'have logged nothing all week');
    });
  });

  group('the trim must not eat the hold block', () {
    Map<String, dynamic> holdFixture() => <String, dynamic>{
          'ordinal': 2,
          'label': 'H2',
          'week_start': '2026-07-06',
          'is_deload': false,
          'sessions_completed': 3,
          'sessions_total': 5,
        };

    test('ordinary bloat trims to budget and leaves `hold` whole', () {
      final hold = holdFixture();
      final snapshot = <String, dynamic>{
        'profile': {'name': 'Amar'},
        'progress': {'current_phase': 1},
        'hold': hold,
        'personal_records': {
          for (var i = 0; i < 1500; i++) 'Exercise number $i': 100 + i,
        },
        'coaching_notes': List.generate(600, (i) => 'coaching note $i blah'),
      };
      expect(jsonEncode(snapshot).length, greaterThan(8500));

      final trimmed = AiSnapshotBuilder.trimSnapshotToBudget(snapshot);

      expect(jsonEncode(trimmed).length, lessThanOrEqualTo(8500));
      expect(trimmed['hold'], equals(hold));
    });

    test('THE KEEP-SET PROOF: when the KEPT fields alone blow the budget, '
        '`hold` still survives whole', () {
      // The previous test does NOT prove the keep-set line, and finding that
      // out is the reason this one exists: the trimmer shrinks the LARGEST
      // non-kept field each pass, so two giant fields absorb the whole overage
      // and the ~110-char hold block is never reached. Removing 'hold' from
      // the keep set leaves that test green — a mutation that changes nothing
      // observable is not a proof, it is the Gate-44 shape.
      //
      // This case forces the trimmer to reach `hold`: the KEPT fields alone
      // exceed the budget, so after the loop has nothing else to take, `hold`
      // is the only non-kept field left and gets halved BY INSERTION ORDER —
      // losing sessions_completed / sessions_total / is_deload and keeping
      // ordinal. That is the real failure mode: a hold block that says less
      // the more the user has logged, while still looking present.
      //
      // Not a contrived shape. `profile` and `current_plan_summary` are both
      // kept and both unbounded (injuries prose, a 7-day session plan with
      // every exercise), which is exactly the heavy-user snapshot diagnose
      // a9c3e2 was opened for.
      final hold = holdFixture();
      final snapshot = <String, dynamic>{
        'profile': {
          'name': 'Amar',
          'injuries': 'x' * 6000,
        },
        'current_plan_summary': {
          'phase': 1,
          'weekly_sessions': List.generate(
              40, (i) => {'name': 'Session $i', 'exercises': 'y' * 80}),
        },
        'hold': hold,
      };
      expect(jsonEncode(snapshot).length, greaterThan(8500),
          reason: 'the kept fields alone must already exceed the budget, '
              'otherwise the loop never looks at hold');

      final trimmed = AiSnapshotBuilder.trimSnapshotToBudget(snapshot);

      expect(trimmed['hold'], equals(holdFixture()),
          reason: "THE keep-set assertion — every key, byte for byte. Drop "
              "'hold' from trimSnapshotToBudget's keep set and this reddens "
              'with a 3-key block: {ordinal, label, week_start}.');
      expect((trimmed['hold'] as Map).length, 6,
          reason: 'halving a 6-key map yields 3 — assert the count directly '
              'so a partial block cannot pass on a loose matcher');
    });
  });
}
