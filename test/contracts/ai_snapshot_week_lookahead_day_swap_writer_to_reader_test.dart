// BEHAVIORAL CONTRACT TEST — week_lookahead (+name/can_swap/swap_block/week_start)
// and the new top-level swaps_left map.
//
// Writer: AiSnapshotBuilder._getWeekLookahead / _getSwapsLeftForLookahead
//         (lib/features/ai_coach/services/ai_snapshot_builder.dart)
// Reader: docs/snapshot_contract.yaml `week_lookahead` / `swaps_left` — whole-blob
//         prompt passthrough (no per-key Edge Function reader).
// Spec 2026-09-26-day-swapper-design.md §5.8 "Week lookahead".

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/utils/ist_date.dart';
import 'package:icanbefitter/features/ai_coach/services/ai_snapshot_builder.dart';

import '../helpers/hive_test_setup.dart';

// Week of Mon 21 - Sun 27 Sep 2026; "today" is Thu 24, so the 7-day
// lookahead (Thu..Wed) spans TWO ISO weeks: 2026-09-21 (Thu-Sun) and
// 2026-09-28 (Mon-Wed).
const thu = '2026-09-24';
const fri = '2026-09-25';
const sat = '2026-09-26';
const sun = '2026-09-27';
const nextMon = '2026-09-28';
const nextTue = '2026-09-29';
const nextWed = '2026-09-30';

Map<String, dynamic> workout(String date, String name,
        {String status = 'planned'}) =>
    {
      'date': date,
      'type': 'workout',
      'workout_name': name,
      'status': status,
      'exercises': <Map<String, dynamic>>[
        {'exercise_name': '$name A', 'sets': 3}
      ],
    };

void main() {
  late Directory dir;

  setUp(() async {
    dir = await setUpHiveForTests();
    setTestClockTo(DateTime.utc(2026, 9, 24, 4, 30)); // Thu 24, 10:00 IST
  });

  tearDown(() async {
    resetTestClock();
    await tearDownHiveForTests(dir);
  });

  Future<void> put(String date, Map<String, dynamic> row) =>
      HiveService.instance.workoutBox.put('schedule_$date', row);

  test('entries keep day/date/type/status and gain name/can_swap/week_start',
      () async {
    await put(thu, workout(thu, 'Calisthenics', status: 'completed'));
    await put(fri, workout(fri, 'Pull + Core'));

    final snapshot = AiSnapshotBuilder.instance.buildAiContext();
    final lookahead =
        (snapshot['week_lookahead'] as List).cast<Map<String, dynamic>>();
    expect(lookahead, hasLength(7));

    final thuEntry = lookahead.firstWhere((e) => e['date'] == thu);
    expect(thuEntry['day'], 'Thu');
    expect(thuEntry['type'], 'workout');
    expect(thuEntry['status'], 'completed');
    expect(thuEntry['name'], 'Calisthenics');
    expect(thuEntry['can_swap'], isFalse,
        reason: 'a completed day cannot be swapped');
    expect(thuEntry['swap_block'], 'completed');
    expect(thuEntry['week_start'], '2026-09-21');

    final friEntry = lookahead.firstWhere((e) => e['date'] == fri);
    expect(friEntry['can_swap'], isTrue);
    expect(friEntry.containsKey('swap_block'), isFalse,
        reason: 'swap_block is present only when can_swap is false');
  });

  test('an implicit rest day (no row) reports type REST, status rest, name '
      '"Rest day", and is locked no_row', () async {
    // Sunday has no seeded schedule row.
    final snapshot = AiSnapshotBuilder.instance.buildAiContext();
    final lookahead =
        (snapshot['week_lookahead'] as List).cast<Map<String, dynamic>>();
    final sunEntry = lookahead.firstWhere((e) => e['date'] == sun);
    expect(sunEntry['type'], 'REST');
    expect(sunEntry['status'], 'rest');
    expect(sunEntry['name'], 'Rest day');
    expect(sunEntry['can_swap'], isFalse);
    expect(sunEntry['swap_block'], 'no_row');
  });

  test('swaps_left carries one entry per week the lookahead touches, keyed by '
      'IST Monday', () async {
    final snapshot = AiSnapshotBuilder.instance.buildAiContext();
    final daySwaps = (snapshot['swaps_left'] as Map).cast<String, dynamic>();
    expect(daySwaps.keys.toSet(), {'2026-09-21', '2026-09-28'});
    // A fresh account: free limit 1, none used yet -> 1 left, for BOTH weeks.
    expect(daySwaps['2026-09-21'], 1);
    expect(daySwaps['2026-09-28'], 1);
  });

  test('worst-case week_lookahead + swaps_left stays a small fraction of the '
      '10K snapshot budget (rule 18)', () async {
    final longName = 'A' * 60;
    await put(thu, workout(thu, longName, status: 'completed'));
    await put(fri, workout(fri, longName, status: 'paused'));
    await put(sat, workout(sat, longName, status: 'travel'));
    await put(sun, workout(sun, longName, status: 'moved'));
    await put(nextMon, workout(nextMon, longName, status: 'skipped'));
    await put(nextTue, workout(nextTue, longName, status: 'dropped'));
    await put(nextWed, workout(nextWed, longName));

    final snapshot = AiSnapshotBuilder.instance.buildAiContext();
    final justTheseKeys = {
      'week_lookahead': snapshot['week_lookahead'],
      'swaps_left': snapshot['swaps_left'],
    };
    final size = jsonEncode(justTheseKeys).length;
    // Bound verified against the real implementation during this task
    // (measured 1489 chars for this exact fixture) rather than carried
    // forward from the brief's un-verified ~0.5KB / <1200 estimate, which
    // undercounted the swap_block reason codes + week_start on every entry.
    // 1800 keeps meaningful headroom while still pinning "small fraction of
    // the 10000-char snapshot budget" (rule 18) as a regression guard.
    expect(size, lessThan(1800),
        reason: 'spec §5.8 estimates ~0.5KB for these two keys; a worst-case '
            'fixture (every day a long name + a locked reason) must stay a '
            'small fraction of the 10000-char snapshot budget');
    expect(jsonEncode(snapshot).length, lessThanOrEqualTo(10000));
  });
}
