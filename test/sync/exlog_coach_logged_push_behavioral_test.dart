// Coach workout parity 1c (C1b, A4-F1): the sticky `coach_logged` marker on an
// `exlog_*` row is Hive-LOCAL. A real push through the stub server must send
// the SAME `workout_log_exercises` summary and the same `workout_log_sets`
// rows with and without it (the cloud table has no such column; the restore
// never writes it, residual R6). Pattern: exlog_push_u3_behavioral_test.dart.
@Timeout(Duration(minutes: 5))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

import 'sync_domain_skip_harness.dart';

Map<String, dynamic> _bench({Map<String, dynamic> extra = const {}}) => {
      'exercise_name': 'Bench Press',
      'date': '2026-09-01',
      'logging_type': 'weight_reps',
      'weight_kg': 60.0,
      'reps_completed': 16,
      'set_number': 2,
      'source': 'ai_coach',
      'created_at': '2026-09-01T10:00:00.000Z',
      'sets': [
        {'weight_kg': 60.0, 'reps': 8},
        {'weight_kg': 60.0, 'reps': 8},
      ],
      ...extra,
    };

void main() {
  final h = SyncHarness();

  Future<({List<Map<String, dynamic>> summaries, List<Map<String, dynamic>> sets})>
      pushOnce(Map<String, dynamic> row) async {
    await h.setUp();
    try {
      h.server.clear();
      await HiveService.instance.workoutBox.put('exlog_2026-09-01_a1b2', row);
      await SyncService.instance
          .pushExerciseLogsForSyncDomain()
          .timeout(const Duration(minutes: 2));
      List<Map<String, dynamic>> rows(String table) => [
            for (final r in h.server.writesTo(table))
              ...(r.body is List
                  ? (r.body! as List)
                      .map((e) => Map<String, dynamic>.from(e as Map))
                  : [Map<String, dynamic>.from(r.body! as Map)]),
          ];
      return (
        summaries: rows('workout_log_exercises'),
        sets: rows('workout_log_sets'),
      );
    } finally {
      await h.tearDown();
    }
  }

  test('the pushed summary and per-set rows are identical with and without '
      'coach_logged', () async {
    final plain = await pushOnce(_bench());
    final marked = await pushOnce(_bench(extra: {'coach_logged': true}));
    expect(plain.summaries, isNotEmpty);
    expect(plain.sets, isNotEmpty);
    expect(marked.summaries, plain.summaries);
    expect(marked.sets, plain.sets);
    for (final s in marked.summaries) {
      expect(s.containsKey('coach_logged'), isFalse);
    }
  });
}
