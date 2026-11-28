import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import 'helpers/wws_test_setup.dart';

final _fri = DateTime.utc(2026, 9, 25);
final _sat = DateTime.utc(2026, 9, 26);
const _friKey = 'schedule_2026-09-25';
const _satKey = 'schedule_2026-09-26';

Map<String, dynamic> _row(String name, {String status = 'planned'}) => {
      'date': 'x',
      'type': 'workout',
      'workout_name': name,
      'status': status,
      'exercises': [
        {'name': '$name A', 'sets': 3}
      ],
    };

Map<String, dynamic>? _get(String k) {
  final raw = HiveService.instance.workoutBox.get(k);
  return raw is Map ? Map<String, dynamic>.from(raw) : null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(wwsTestSetup);
  tearDown(wwsTestTeardown);

  Future<void> seed() async {
    final box = HiveService.instance.workoutBox;
    await box.put(_friKey, _row('Pull + Core'));
    await box.put(_satKey, _row('Legs + Core'));
  }

  test('writes both rows from the build result, stamped day_swap', () async {
    await seed();
    ScheduledDaySwapLive? seen;
    final r = await WorkoutWriteService.instance.swapScheduledDays(
      dateA: _fri,
      dateB: _sat,
      build: (live) {
        seen = live;
        return (
          rowA: {...live.rowB!, 'is_swapped': true},
          rowB: {...live.rowA!, 'is_swapped': true},
          displacedA: null,
          displacedB: null,
        );
      },
    );
    expect(r.success, isTrue);
    expect(seen!.rowA!['workout_name'], 'Pull + Core');
    final fri = _get(_friKey)!;
    final sat = _get(_satKey)!;
    expect(fri['workout_name'], 'Legs + Core');
    expect(sat['workout_name'], 'Pull + Core');
    expect(fri['date'], '2026-09-25');
    expect(sat['date'], '2026-09-26');
    expect(fri['source'], 'day_swap');
    expect(fri['updated_at_ms'], isA<int>());
  });

  test('build returning null writes nothing and reports a refusal', () async {
    await seed();
    final r = await WorkoutWriteService.instance.swapScheduledDays(
        dateA: _fri, dateB: _sat, build: (_) => null);
    expect(r.success, isFalse);
    expect(r.errorMessage, WorkoutWriteService.daySwapRefusedMessage);
    expect(_get(_friKey)!['workout_name'], 'Pull + Core');
  });

  test('a completed day is never moved, whatever build returns', () async {
    final box = HiveService.instance.workoutBox;
    await box.put(_friKey, _row('Pull + Core', status: 'completed'));
    await box.put(_satKey, _row('Legs + Core'));
    final r = await WorkoutWriteService.instance.swapScheduledDays(
      dateA: _fri,
      dateB: _sat,
      build: (live) => (
        rowA: live.rowB!,
        rowB: live.rowA!,
        displacedA: null,
        displacedB: null,
      ),
    );
    expect(r.success, isFalse);
    expect(_get(_friKey)!['status'], 'completed');
    expect(_get(_satKey)!['workout_name'], 'Legs + Core');
  });

  test('both or neither: a failing second write restores the first', () async {
    await seed();
    final r = await WorkoutWriteService.instance.swapScheduledDays(
      dateA: _fri,
      dateB: _sat,
      build: (live) => (
        rowA: live.rowB!,
        // Hive cannot serialise an Object without an adapter → the put throws.
        rowB: {...live.rowA!, 'poison': Object()},
        displacedA: null,
        displacedB: null,
      ),
    );
    expect(r.success, isFalse);
    expect(_get(_friKey)!['workout_name'], 'Pull + Core',
        reason: 'the first write must be rolled back');
    expect(_get(_satKey)!['workout_name'], 'Legs + Core');
  });

  test('displaced backups are written, moved and deleted as build says', () async {
    await seed();
    final box = HiveService.instance.workoutBox;
    await box.put('displaced_2026-09-25', {'workout_name': 'Old Fri', 'date': '2026-09-25'});
    final r = await WorkoutWriteService.instance.swapScheduledDays(
      dateA: _fri,
      dateB: _sat,
      build: (live) => (
        rowA: live.rowB!,
        rowB: live.rowA!,
        displacedA: null,
        displacedB: {...live.displacedA!, 'date': '2026-09-26'},
      ),
    );
    expect(r.success, isTrue);
    expect(box.containsKey('displaced_2026-09-25'), isFalse);
    expect((box.get('displaced_2026-09-26') as Map)['workout_name'], 'Old Fri');
  });

  test('a failing backup write rolls back BOTH rows', () async {
    await seed();
    final r = await WorkoutWriteService.instance.swapScheduledDays(
      dateA: _fri,
      dateB: _sat,
      build: (live) => (
        rowA: live.rowB!,
        rowB: live.rowA!,
        displacedA: {'poison': Object()},
        displacedB: null,
      ),
    );
    expect(r.success, isFalse);
    expect(_get(_friKey)!['workout_name'], 'Pull + Core');
    expect(_get(_satKey)!['workout_name'], 'Legs + Core');
    expect(HiveService.instance.workoutBox.containsKey('displaced_2026-09-25'), isFalse);
  });

  test('the same date twice is refused before any lock or read', () async {
    final r = await WorkoutWriteService.instance.swapScheduledDays(
        dateA: _fri, dateB: _fri, build: (_) => fail('build must not run'));
    expect(r.success, isFalse);
  });

  test('build sees deep copies: mutating them does not touch Hive', () async {
    await seed();
    await WorkoutWriteService.instance.swapScheduledDays(
      dateA: _fri,
      dateB: _sat,
      build: (live) {
        (live.rowA!['exercises'] as List).clear();
        return null;
      },
    );
    expect((_get(_friKey)!['exercises'] as List), hasLength(1));
  });
}
