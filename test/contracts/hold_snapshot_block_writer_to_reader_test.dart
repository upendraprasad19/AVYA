// WRITER → READER CONTRACT — hold_snapshot_block (FOB-3 / OI-60)
//
// Writer: lib/core/services/workout_schedule_write_service.dart holdWeek()
//         stamps `is_hold` and `hold_ordinal` onto each schedule_<date> row
//         (workout_schedule_write_service.dart:288-289).
// Reader: lib/core/services/workout_schedule_read_service.dart
//         holdSnapshotBlock() → the coach snapshot's `hold` key.
//
// WHY THIS IS SEPARATE FROM hold_snapshot_block_behavioral_test.dart, which
// also drives the real writer: that file asserts what the BLOCK says (label,
// counts, ship-dark omission, trim survival). This one asserts the FIELD-NAME
// contract between the two ends and, more usefully, the four ways a row can be
// wrong. Writer/reader field drift is the default suspect class (CLAUDE.md
// §4.1), and it is invisible to a test that only ever writes correct rows —
// which is what a happy-path behavioral test does by construction.
//
// The rows here are hand-written rather than produced by holdWeek(), on
// purpose: a corrupt row is exactly what the real writer cannot produce, and
// the reader's behaviour on one is the thing worth pinning.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/guarded_box.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';
import 'package:icanbefitter/core/services/migrated_key.dart';
import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
import 'package:icanbefitter/core/utils/date_utils.dart' show formatDateKey;
import 'package:icanbefitter/core/utils/ist_date.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  const fakeUserId = 'aaaaaaaa-bbbb-cccc-dddd-000000000631';

  final planStart = DateTime(2026, 6, 1);
  final planEnd = planStart.add(const Duration(days: 27));
  final holdStart = DateTime(2026, 6, 29); // Monday after plan_end

  // ignore: deprecated_member_use_from_same_package
  final read = WorkoutScheduleReadService.instance;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('holdw2r_');
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

    await HiveService.instance.configBox.put('enable_hold_weeks', true);
    await MigratedKey.write('plan_start_date', planStart.toIso8601String());
    await MigratedKey.write('plan_end_date', planEnd.toIso8601String());
    setTestClockTo(holdStart.add(const Duration(hours: 10)));
  });

  tearDown(() async {
    resetTestClock();
    GuardedBox.testBypassOwnership = false;
    await HiveUserSession.closeAll();
    await Hive.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Writes a hold week's seven rows directly, so a field can be omitted or
  /// misspelled in a way the real writer never would.
  Future<void> writeHoldWeek({
    required int ordinal,
    String ordinalField = 'hold_ordinal',
    String holdFlagField = 'is_hold',
    bool includeOrdinal = true,
  }) async {
    final box = HiveService.instance.workoutBox;
    for (var d = 0; d < 7; d++) {
      final date = holdStart.add(Duration(days: d));
      await box.put('schedule_${formatDateKey(date)}', <String, dynamic>{
        'type': d == 6 ? 'rest' : 'workout',
        'date': formatDateKey(date),
        // The writer stamps the dishonest 4 + n here. The block must never
        // surface it — see the `week` assertion below.
        'week': 4 + ordinal,
        'phase': 1,
        'status': 'planned',
        'workout_name': 'Upper Body',
        holdFlagField: true,
        if (includeOrdinal) ordinalField: ordinal,
      });
    }
  }

  test('the writer\'s two stamps are what the block is built from', () async {
    await writeHoldWeek(ordinal: 2);

    final block = read.holdSnapshotBlock();

    expect(block, isNotNull);
    expect(block!['ordinal'], 2, reason: 'read straight from hold_ordinal');
    expect(block['label'], 'H2');
    expect(block['week_start'], istDateStr(holdStart));
    expect(block['is_deload'], isA<bool>());
    expect(block['sessions_completed'], isA<int>());
    expect(block['sessions_total'], isA<int>());
    expect(block.keys.length, 6,
        reason: 'the key set is fixed — a variable one degrades to '
            '{ordinal, label} under the trimmer\'s insertion-order halving');
  });

  test('the block NEVER surfaces the row-stamped 4 + ordinal', () async {
    // ordinal 5 -> the rows carry week: 9, which no other field in the block
    // can produce. Ordinal 2 would have made this test lie in the other
    // direction: 4 + 2 = 6 and sessions_total is ALSO 6 for a 6-workout week,
    // so a values-contains check went red on a legitimate coincidence. A
    // matcher that cannot tell a leak from a collision is not a leak test.
    await writeHoldWeek(ordinal: 5);

    final block = read.holdSnapshotBlock()!;

    expect(block.keys.toSet(), {
      'ordinal',
      'label',
      'week_start',
      'is_deload',
      'sessions_completed',
      'sessions_total',
    }, reason: 'the exact key set — no row-derived week under any name');
    expect(block.values.contains(9), isFalse,
        reason: 'OI-60\'s do_not: 4 + ordinal is the number the UI ruled '
            'dishonest, and it is sitting right there on the row this block '
            'is built from. 9 is reachable ONLY from that stamp — a 7-day week '
            'cannot produce it as a session count');
    expect(block['ordinal'], 5, reason: 'the ordinal, never the stamped week');
  });

  test('RENAMING the writer\'s ordinal field empties the block', () async {
    // The drift this whole class of test exists for: the writer changes
    // hold_ordinal -> holdOrdinal and every read silently returns nothing.
    await writeHoldWeek(ordinal: 2, ordinalField: 'holdOrdinal');

    expect(read.holdSnapshotBlock(), isNull,
        reason: 'if this ever returns a block, the reader has grown a second '
            'field name and the two ends can drift apart unnoticed');
  });

  test('RENAMING the writer\'s is_hold flag empties the block', () async {
    await writeHoldWeek(ordinal: 2, holdFlagField: 'isHold');

    expect(read.holdSnapshotBlock(), isNull);
  });

  test('a row flagged is_hold with NO ordinal produces no block at all',
      () async {
    // Not hypothetical drift — hold_week_labels.rowIsHold deliberately accepts
    // is_hold alone as a fail-safe so a corrupt row still SUPPRESSES the week
    // number on screen. The snapshot must not inherit that leniency: a block
    // needs an ordinal to be worth anything, and "Holding · H" is not a thing
    // to tell a model.
    await writeHoldWeek(ordinal: 2, includeOrdinal: false);

    expect(read.holdSnapshotBlock(), isNull,
        reason: 'the ordinal is the discriminator; without it there is no '
            'identity to state');
  });

  test('a hold week that is not TODAY produces no block', () async {
    await writeHoldWeek(ordinal: 1);
    // Jump to the week after the hold — rows exist, today is not one of them.
    setTestClockTo(holdStart.add(const Duration(days: 9, hours: 10)));

    expect(read.holdSnapshotBlock(), isNull);
  });
}
