@Timeout(Duration(minutes: 5))
library;

// restore -> ExlogKeyMigrator -> push. The exercise-log RESTORE records the push
// fingerprint of every row it wrote (L1a-3, so a restored log is not pushed
// straight back). The restoring screen then runs `ExlogKeyMigrator` on every
// fresh device (its one-time flag is unset). The migrator must NOT rewrite a row
// that is already canonical: a rewrite stamps `updated_at_ms = now`, the push
// then sends `completed_at = max(resolved, updated_at_ms)`, `completed_at` is
// part of the fingerprint, and every fingerprint the restore recorded goes
// stale, so the next sweep re-uploads the whole history.
// Related: f3d2a7 (restored rows pushed straight back), f1c6b4 (same class: a
// stamped field defeats an unchanged-row comparison), L1a-3
// (test/sync/exlog_restore_fingerprint_l1a3_behavioral_test.dart).
// Plan docs/plans/2026-10-25-sync-storm-first-sweep.md W1. Against origin/main's
// migrator, cases 1, 2, 3, 4b, 8 and 9 are RED (1-3 and 4b: the restored row is
// stamped and pushed again; 8 and 9: the row must stay untouched). Cases 4, 4c, 5,
// 5b, 5c, 6, 7, 8b and 10 are regression pins that are GREEN on main (they exist
// to kill the mutants listed in the diagnose-doc).

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exlog_key_migrator.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/pending_exlog_deletes.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/workout_write_service.dart';

import '../helpers/hive_test_setup.dart';
import '../sync/sync_domain_skip_harness.dart';

const _day = '2026-09-01';
const _flag = 'exlog_key_migration_v8';

// Fixed ids: String.hashCode is platform-unstable (exlog_key_migrator.dart).
const _names = [
  'Bench Press',
  'Squat',
  'Deadlift',
  'Row',
  'Plank',
  'Treadmill',
];
int _slot(String name) {
  final i = _names.indexOf(name);
  if (i < 0) throw ArgumentError('add $name to _names');
  return i + 1;
}

String _id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

/// A cloud `workout_log_exercises` summary row.
Map<String, dynamic> _summary(
  String name, {
  required List<double> weights,
  int repsPerSet = 8,
  bool nullMetrics = false,
  int durationSeconds = 0,
}) =>
    {
      'id': _id(_slot(name) * 1000),
      'user_id': kTestUserId,
      'workout_log_id': SyncService.workoutLogIdForDate(_day),
      'exercise_id': name,
      'exercise_name': name,
      'set_number': weights.length,
      if (!nullMetrics) 'weight_kg': weights.reduce((a, b) => a > b ? a : b),
      if (!nullMetrics) 'reps': repsPerSet * weights.length,
      'duration_seconds': durationSeconds,
      'logging_type': 'weight_reps',
      'is_pr': false,
      'completed_at': '${_day}T10:00:00+00:00',
      'created_at': '${_day}T10:00:00+00:00',
      'deleted_at': null,
    };

/// The matching cloud `workout_log_sets` rows.
List<Map<String, dynamic>> _setRows(
  String name,
  List<double> weights, {
  int repsPerSet = 8,
}) =>
    [
      for (var i = 0; i < weights.length; i++)
        {
          'id': _id(_slot(name) * 1000 + i + 1),
          'user_id': kTestUserId,
          'workout_log_id': SyncService.workoutLogIdForDate(_day),
          'exercise_id': name,
          'set_number': i + 1,
          'weight_kg': weights[i],
          'reps': repsPerSet,
          'completed_at': '${_day}T10:00:00+00:00',
          'created_at': '${_day}T10:00:00+00:00',
        },
    ];

/// A locally stored exlog row exactly as the migrator would rewrite it: the
/// aggregates equal what `ExlogKeyMigrator` recomputes from `sets`.
Map<String, dynamic> _localRow(
  String name,
  List<double> weights, {
  int repsPerSet = 8,
  int updatedAtMs = 1,
  Map<String, dynamic>? override,
}) {
  var volume = 0.0;
  for (final w in weights) {
    volume += w * repsPerSet;
  }
  return {
    'id': 'row-$name',
    'type': 'exercise_log',
    'exercise_name': name,
    'date': _day,
    'logging_type': 'weight_reps',
    'is_pr': false,
    'has_warmup_sets': false,
    'created_at': '${_day}T10:00:00+00:00',
    'workout_log_id': SyncService.workoutLogIdForDate(_day),
    'sets': [
      for (final w in weights)
        {'weight_kg': w, 'reps': repsPerSet, 'logged_at_ms': 1},
    ],
    'set_number': weights.length,
    'weight_kg': weights.reduce((a, b) => a > b ? a : b),
    'reps_completed': repsPerSet * weights.length,
    'volume_kg': volume,
    'updated_at_ms': updatedAtMs,
    ...?override,
  };
}

String _key(String name) =>
    WorkoutWriteService.exlogKey(DateTime.parse(_day), name);

void main() {
  final h = SyncHarness();
  setUp(() async {
    await h.setUp();
    h.server.clear();
  });
  tearDown(() async {
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    await h.tearDown();
  });

  void seedCloud(
    Map<String, List<double>> exercises, {
    Map<String, Map<String, dynamic>> summaryOverrides = const {},
    Set<String> noSetRows = const {},
  }) {
    h.server.pagedTables['workout_log_exercises'] = [
      for (final e in exercises.entries)
        {
          ..._summary(e.key, weights: e.value),
          ...?summaryOverrides[e.key],
        },
    ];
    h.server.pagedTables['workout_log_sets'] = [
      for (final e in exercises.entries)
        if (!noSetRows.contains(e.key)) ..._setRows(e.key, e.value),
    ];
    h.server.clear();
  }

  Future<void> restore() => SyncService.instance
      .restoreExerciseLogsForSyncDomain(since: '2020-01-01T00:00:00Z')
      .timeout(const Duration(minutes: 2));
  Future<void> push() => SyncService.instance
      .pushExerciseLogsForSyncDomain()
      .timeout(const Duration(minutes: 2));
  int exlogUpserts() => h.server.writesTo('workout_log_exercises').length;
  Map<String, dynamic> index() => SyncSkipIndex.readIndex(
      HiveService.instance.workoutBox, SyncSkipDomain.exlog.indexKey);
  String canon(Object? v) => SyncFingerprint.canonicalJson(v);
  Map<dynamic, dynamic> row(String key) =>
      HiveService.instance.workoutBox.get(key) as Map;
  Set<String> dayIndex() => {
        for (final k in (HiveService.instance.workoutBox
                .get('exercise_log_index_$_day') as List? ??
            const []))
          k.toString(),
      };

  group('restore -> migrator -> push', () {
    test('1: a canonical restored row sends nothing, keeps no write stamp',
        () async {
      seedCloud({
        'Bench Press': [60.0, 60.0],
        'Squat': [60.0, 60.0],
      });
      await restore();
      final box = HiveService.instance.workoutBox;
      expect(index(), hasLength(2), reason: 'the restore recorded both rows');
      final before = dayIndex();

      expect(HiveService.instance.configBox.get(_flag), isNot(true));
      await ExlogKeyMigrator.runIfNeeded();

      for (final name in ['Bench Press', 'Squat']) {
        expect(row(_key(name)).containsKey('updated_at_ms'), isFalse,
            reason: '$name: a restored row carries no write stamp');
      }
      expect(dayIndex(), before, reason: 'the day index members are unchanged');
      expect(box.get(_flag) ?? HiveService.instance.configBox.get(_flag), true);

      h.server.clear();
      await push();
      expect(exlogUpserts(), 0,
          reason: 'a canonical restored row must still match its recorded '
              'fingerprint after the migrator');
    });

    test('2: pyramid weights, a bodyweight 0.0 row and 3-set rows send nothing',
        () async {
      seedCloud({
        'Bench Press': [60.0, 70.0, 80.0],
        'Row': [0.0, 0.0, 0.0],
        'Squat': [100.0, 100.0, 100.0],
      });
      await restore();
      expect(index(), hasLength(3));
      await ExlogKeyMigrator.runIfNeeded();
      h.server.clear();
      await push();
      expect(exlogUpserts(), 0);
    });

    test('3: a canonical local row with its own old stamp stays byte-identical',
        () async {
      // Seeded through box.put with a FIXED old stamp (never through
      // logExercise, whose `updated_at_ms = now` could equal the migrator's
      // `now` in the same millisecond and pass on main by chance).
      final box = HiveService.instance.workoutBox;
      final seeded = _localRow('Bench Press', [60.0, 70.0]);
      await box.put(_key('Bench Press'), seeded);
      final before = canon(row(_key('Bench Press')));
      await ExlogKeyMigrator.runIfNeeded();
      expect(canon(row(_key('Bench Press'))), before);
      expect(row(_key('Bench Press'))['updated_at_ms'], 1);
    });

    test(
        '4: a restored row whose cloud duration the push would not reproduce '
        'records no fingerprint, so it pushes once with or without the migrator',
        () async {
      // The fixture's logging_type is weight_reps (see `_summary`): the push
      // sends duration_seconds 0 for it, the cloud row says 600, so
      // restoredBundleEqualsCloud fails at its duration check. (A real timed
      // row is test 4b / 4c.)
      seedCloud(
        {
          'Treadmill': [0.0],
        },
        summaryOverrides: {
          'Treadmill': {
            'weight_kg': null,
            'reps': null,
            'duration_seconds': 600,
          },
        },
      );
      h.server.pagedTables['workout_log_sets'] = [
        {
          ..._setRows('Treadmill', [0.0]).single,
          'weight_kg': null,
          'reps': null,
          'duration_secs': 600,
        },
      ];
      await restore();
      expect(index().containsKey(_key('Treadmill')), isFalse,
          reason: 'the push would send duration_seconds 0 against the cloud '
              '600 (weight_reps), so no fingerprint is recorded and W1 '
              'neither helps nor hurts this shape');
      await ExlogKeyMigrator.runIfNeeded();
      expect(row(_key('Treadmill'))['updated_at_ms'], isNotNull,
          reason: 'the migrator adds the missing aggregates and stamps it');
      h.server.clear();
      await push();
      expect(exlogUpserts(), greaterThan(0));
    });

    test(
        '4b: a real timed row (logging_type timed, zero metrics, a per-set '
        'duration) is recorded by the restore and left alone by the migrator',
        () async {
      seedCloud(
        {
          'Treadmill': [0.0],
        },
        summaryOverrides: {
          'Treadmill': {
            'logging_type': 'timed',
            'weight_kg': 0.0,
            'reps': 0,
            'duration_seconds': 600,
          },
        },
      );
      h.server.pagedTables['workout_log_sets'] = [
        {
          ..._setRows('Treadmill', [0.0]).single,
          'weight_kg': 0.0,
          'reps': 0,
          'duration_secs': 600,
        },
      ];
      await restore();
      expect(index().containsKey(_key('Treadmill')), isTrue,
          reason: 'precondition: the push reproduces it, so the restore '
              'recorded a fingerprint');
      await ExlogKeyMigrator.runIfNeeded();
      expect(row(_key('Treadmill')).containsKey('updated_at_ms'), isFalse,
          reason: 'the migrator found nothing to change');
      h.server.clear();
      await push();
      expect(exlogUpserts(), 0);
    });

    test(
        '4c: a timed row whose cloud weight/reps are NULL is recorded, but the '
        'migrator adds zero aggregates, so it pushes once (the NULL columns '
        'become 0.0 / 0 in the pushed body)', () async {
      seedCloud(
        {
          'Plank': [0.0],
        },
        summaryOverrides: {
          'Plank': {
            'logging_type': 'timed',
            'weight_kg': null,
            'reps': null,
            'duration_seconds': 60,
          },
        },
      );
      h.server.pagedTables['workout_log_sets'] = [
        {
          ..._setRows('Plank', [0.0]).single,
          'weight_kg': null,
          'reps': null,
          'duration_secs': 60,
        },
      ];
      await restore();
      expect(index().containsKey(_key('Plank')), isTrue,
          reason: 'precondition: recorded');
      await ExlogKeyMigrator.runIfNeeded();
      expect(row(_key('Plank'))['weight_kg'], 0.0,
          reason: 'the migrator computes the aggregates the restore left out');
      h.server.clear();
      await push();
      expect(exlogUpserts(), greaterThan(0),
          reason: 'the pushed body changed (NULL -> 0.0), not just the stamp: '
              'residual shape 1 of the plan');
    });

    test('5: a legacy-shaped row (non-canonical key, no sets) is re-keyed and '
        'pushed', () async {
      final box = HiveService.instance.workoutBox;
      await box.put('exlog_1700000000000_12345', {
        'exercise_name': 'Bench Press',
        'date': _day,
        'weight_kg': 60.0,
        'reps_completed': 8,
        'set_number': 1,
        'logging_type': 'weight_reps',
        'created_at': '${_day}T10:00:00+00:00',
        'updated_at_ms': 1000,
      });
      await ExlogKeyMigrator.runIfNeeded();
      expect(box.containsKey('exlog_1700000000000_12345'), isFalse);
      expect(box.containsKey(_key('Bench Press')), isTrue);
      await push();
      expect(exlogUpserts(), greaterThan(0));
    });

    test(
        '5b: a canonical-keyed summary-only row (no sets) IS rewritten and '
        'pushed (documented hit-rate limit 2)', () async {
      seedCloud(
        {
          'Deadlift': [100.0],
        },
        noSetRows: {'Deadlift'},
      );
      await restore();
      expect(row(_key('Deadlift')).containsKey('sets'), isFalse,
          reason: 'precondition: restored without per-set rows');
      expect(index().containsKey(_key('Deadlift')), isTrue,
          reason: 'precondition: the restore recorded a fingerprint');
      await ExlogKeyMigrator.runIfNeeded();
      expect(row(_key('Deadlift'))['sets'], isNotEmpty,
          reason: 'the migrator synthesizes a set for a row without sets');
      h.server.clear();
      await push();
      expect(exlogUpserts(), greaterThan(0));
    });

    test(
        '5c: a canonical-keyed row whose aggregates already agree but that has '
        'no sets still gets its set synthesized', () async {
      // Differs from what the migrator would write ONLY by the missing `sets`
      // (the restored shape of 5b also lacks volume_kg, which would make it
      // differ for a second reason and hide a comparison that ignored `sets`).
      final box = HiveService.instance.workoutBox;
      final seeded = _localRow('Deadlift', [100.0], updatedAtMs: 1000)
        ..remove('sets');
      await box.put(_key('Deadlift'), seeded);
      await ExlogKeyMigrator.runIfNeeded();
      expect(row(_key('Deadlift'))['sets'], isNotEmpty,
          reason: 'the comparison counts the missing sets as a difference');
      expect((row(_key('Deadlift'))['updated_at_ms'] as num) > 1000, isTrue);
    });

    test('6: a rogue-keyed row WITH sets and agreeing aggregates is re-keyed',
        () async {
      final box = HiveService.instance.workoutBox;
      await box.put('exlog_${_day}_999999', _localRow('Bench Press', [60.0, 60.0]));
      await ExlogKeyMigrator.runIfNeeded();
      expect(box.containsKey('exlog_${_day}_999999'), isFalse,
          reason: 'the rogue key is gone');
      expect(box.containsKey(_key('Bench Press')), isTrue);
    });

    test('7: a canonical row whose aggregates differ is rewritten with a fresh '
        'stamp', () async {
      final box = HiveService.instance.workoutBox;
      await box.put(
        _key('Bench Press'),
        _localRow('Bench Press', [60.0, 70.0], override: {'weight_kg': 10.0}),
      );
      await ExlogKeyMigrator.runIfNeeded();
      final r = row(_key('Bench Press'));
      expect(r['weight_kg'], 70.0);
      expect((r['updated_at_ms'] as num) > 1, isTrue);
    });

    test(
        '8: canonical rows with an Infinity weight do not abort the run, are '
        'rewritten, and are reported ONCE; the clean rows around them are still '
        'compared and skipped', () async {
      final reasons = <String>[];
      ErrorTelemetry.debugOnRecordNonFatalForTests =
          (e, st, {required String reason, Map<String, String>? extra}) =>
              reasons.add(reason);
      final lines = <String>[];
      final oldPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) =>
          lines.add(message ?? '');
      addTearDown(() => debugPrint = oldPrint);

      final box = HiveService.instance.workoutBox;
      const throwing = ['Bench Press', 'Deadlift'];
      const clean = ['Squat', 'Row'];
      for (final n in throwing) {
        await box.put(_key(n), _localRow(n, [double.infinity, 60.0]));
      }
      for (final n in clean) {
        await box.put(_key(n), _localRow(n, [60.0, 60.0]));
      }
      // Precondition: the migrator walks groups in box-key order, so at least
      // one clean row must come AFTER the first throwing row, or a mutant that
      // stops comparing after the first throw would not be seen.
      final order = box.keys
          .map((k) => k.toString())
          .where((k) => k.startsWith('exlog_'))
          .toList();
      final throwKeys = {for (final n in throwing) _key(n)};
      final cleanKeys = {for (final n in clean) _key(n)};
      final firstThrow = order.indexWhere(throwKeys.contains);
      expect(order.skip(firstThrow + 1).any(cleanKeys.contains), isTrue,
          reason: 'fixture precondition (key order): $order');

      await ExlogKeyMigrator.runIfNeeded();
      expect(HiveService.instance.configBox.get(_flag), true,
          reason: 'the run completed');
      for (final n in throwing) {
        expect((row(_key(n))['updated_at_ms'] as num) > 1, isTrue,
            reason: '$n: the unreadable row falls back to the rewrite');
      }
      for (final n in clean) {
        expect(row(_key(n))['updated_at_ms'], 1,
            reason: '$n: still compared and skipped');
      }
      expect(reasons, ['sync_exlog_migrator_compare'],
          reason: 'two throwing rows, one report');
      expect(lines.any((l) => l.contains('unchanged=2 rewritten=2')), isTrue,
          reason: 'the counters the device check reads: $lines');
    });

    test(
        '8b: presence only: the compare-failure report keeps the default '
        'server post (no skipServerPost in the migrator)', () {
      final src = File('lib/core/services/exlog_key_migrator.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src.contains('skipServerPost'), isFalse);
    });

    test('9: a queued time-less delete for an unchanged canonical row is '
        'cancelled, the row is untouched', () async {
      final box = HiveService.instance.workoutBox;
      await box.put(_key('Bench Press'), _localRow('Bench Press', [60.0, 60.0]));
      await HiveService.instance.userBox.put('pending_exlog_deletes', [
        {
          'workout_log_id': SyncService.workoutLogIdForDate(_day),
          'exercise_id': 'Bench Press',
          'set_number': 2,
        },
      ]);
      await ExlogKeyMigrator.runIfNeeded();
      expect(PendingExlogDeletes.read(), isEmpty,
          reason: 'cancelFor ran exactly as on main');
      expect(row(_key('Bench Press'))['updated_at_ms'], 1);
    });

    test('10: kill switch engaged -> today\'s unconditional rewrite', () async {
      await HiveService.instance.configBox
          .put('disable_exlog_migrator_skip_unchanged', true);
      seedCloud({
        'Bench Press': [60.0, 60.0],
        'Squat': [60.0, 60.0],
      });
      await restore();
      await ExlogKeyMigrator.runIfNeeded();
      h.server.clear();
      await push();
      expect(exlogUpserts(), 2);
    });
  });
}
