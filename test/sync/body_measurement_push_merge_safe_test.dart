@Timeout(Duration(minutes: 5))
library;

// L2a (plan docs/plans/coach-measurement-entry-l2a.md, unit U1; OI-297): the
// body_measurements push is merge-safe. A device that holds only some sites
// must not blank the sites another device entered.
//
// The stub keeps no table state, so this file models the cloud in
// `writeResponders['body_measurements']`: an upsert ASSIGNS EVERY KEY PRESENT
// IN THE BODY (nulls included) and leaves absent keys alone, which is
// PostgREST's documented merge-duplicates behaviour (asserted by repo
// precedent, observed live only by the founder-owned probe). The model records
// a violation, never throws (a throw leaves the request unanswered), when the
// request lacks `Prefer: resolution=merge-duplicates` or
// `on_conflict=user_id,date`. The HEAD literals pinned here were captured from
// the unmodified tree.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync/sync_skip_index.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
import 'sync_domain_skip_harness.dart';

const _killSwitch = 'disable_measurement_merge_safe_push';
const _headBodyWaistOnly =
    '{"user_id":"$kTestUserId","date":"2026-09-20","chest":null,"waist":80.0,'
    '"hips":null,"arms":null,"notes":null,"created_at":"2026-09-20T06:00:00.000Z"}';
const _headFingerprintWaistOnly = '7f56e459-2867-508f-b1fc-7db509714c49';
const _headFingerprintFull = '91da4819-4221-5262-8393-0e247bb99d38';

void main() {
  final h = SyncHarness();
  late Map<String, Map<String, dynamic>> cloud;
  late List<String> violations;

  Map<String, dynamic> cloudRow(String date) => cloud.putIfAbsent(
    date,
    () => <String, dynamic>{
      'id': 'cloud-$date',
      'user_id': kTestUserId,
      'date': date,
      'chest': null,
      'waist': null,
      'hips': null,
      'arms': null,
      'notes': null,
      'created_at':
          '$date'
          'T05:00:00.000Z',
    },
  );

  setUp(() async {
    await h.setUp();
    // The stub instance is shared across the tests of a file: reset it.
    h.server.clear();
    h.server.writeResponders.clear();
    h.server.pagedTables.clear();
    SyncService.pausedForSimulation = false;
    cloud = {};
    violations = [];
    h.server.writeResponders['body_measurements'] = (r) {
      if (!(r.headers['prefer'] ?? '').contains(
        'resolution=merge-duplicates',
      )) {
        violations.add('prefer=${r.headers['prefer']}');
      }
      if (r.query['on_conflict'] != 'user_id,date') {
        violations.add('on_conflict=${r.query['on_conflict']}');
      }
      for (final row in r.rows) {
        final target = cloudRow(row['date'] as String);
        row.forEach((k, v) => target[k] = v);
      }
      return null; // return=minimal
    };
  });
  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await HiveService.instance.configBox.delete(_killSwitch);
    await h.tearDown();
  });

  Future<void> pass() => SyncService.instance
      .pushMeasurementsForSyncDomain()
      .timeout(const Duration(minutes: 2));
  Future<void> put(String date, Map<String, dynamic> rec) =>
      HiveService.instance.healthBox.put('measurement_$date', rec);
  List<Map<String, dynamic>> bodies() => [
    for (final r in h.server.writesTo('body_measurements')) ...r.rows,
  ];
  Map<String, String> index() => SyncSkipIndex.readIndex(
    HiveService.instance.healthBox,
    SyncSkipDomain.measurement.indexKey,
  );

  Map<String, dynamic> waistOnly([double waist = 80.0]) => {
    'date': '2026-09-20',
    'waist': waist,
    'created_at': '2026-09-20T06:00:00.000Z',
  };

  test(
    'a record holding only waist pushes only waist; the cloud keeps chest',
    () async {
      cloudRow('2026-09-20')['chest'] = 100.5; // entered on another device
      await put('2026-09-20', waistOnly());
      await pass();
      expect(bodies(), hasLength(1));
      expect(bodies().single, {
        'user_id': kTestUserId,
        'date': '2026-09-20',
        'waist': 80.0,
        'created_at': '2026-09-20T06:00:00.000Z',
      });
      expect(cloud['2026-09-20']!['chest'], 100.5);
      expect(cloud['2026-09-20']!['waist'], 80.0);
      expect(violations, isEmpty);
    },
  );

  test(
    'NEGATIVE CONTROL: the kill switch sends HEAD\'s body and blanks chest',
    () async {
      await HiveService.instance.configBox.put(_killSwitch, true);
      cloudRow('2026-09-20')['chest'] = 100.5;
      await put('2026-09-20', waistOnly());
      await pass();
      expect(jsonEncode(bodies().single), _headBodyWaistOnly);
      expect(
        cloud['2026-09-20']!['chest'],
        isNull,
        reason: 'the legacy shape is the defect: the model blanks chest',
      );
      expect(violations, isEmpty);
    },
  );

  test('toggling the kill switch mid-life re-pushes nothing; the next edit '
      'pushes in the new shape', () async {
    await put('2026-09-20', waistOnly());
    await pass();
    expect(bodies(), hasLength(1));
    h.server.clear();

    await HiveService.instance.configBox.put(_killSwitch, true);
    await pass();
    expect(bodies(), isEmpty, reason: 'fingerprint is shape-independent');

    await put('2026-09-20', waistOnly(79.0));
    await pass();
    expect(
      jsonEncode(bodies().single),
      _headBodyWaistOnly.replaceFirst('80.0', '79.0'),
      reason: 'switch set: the legacy body',
    );
    h.server.clear();

    await HiveService.instance.configBox.delete(_killSwitch);
    await pass();
    expect(bodies(), isEmpty, reason: 'toggling back re-pushes nothing either');
    await put('2026-09-20', waistOnly(78.0));
    await pass();
    expect(bodies().single.keys.toList(), [
      'user_id',
      'date',
      'waist',
      'created_at',
    ]);
  });

  test('UPGRADE: HEAD\'s stored fingerprints still match, so the first pass '
      'sends nothing', () async {
    await put('2026-09-20', waistOnly());
    await put('2026-09-21', {
      'date': '2026-09-21',
      'chest': 100.5,
      'waist': 82.0,
      'hips': 95.0,
      'arms': 33.0,
      'notes': 'after run',
      'created_at': '2026-09-21T06:00:00.000Z',
    });
    await HiveService.instance.healthBox.put(
      SyncSkipDomain.measurement.indexKey,
      <String, String>{
        '2026-09-20': _headFingerprintWaistOnly,
        '2026-09-21': _headFingerprintFull,
      },
    );
    await pass();
    expect(h.server.writesTo('body_measurements'), isEmpty);
  });

  test('records from all three origins push only what they hold', () async {
    // logMeasurement-shaped (no null keys)
    await put('2026-09-20', {
      'id': 'meas_1',
      'date': '2026-09-20',
      'waist': 80.0,
      'source': 'ai_coach',
      'updated_at_ms': 1758000000000,
      'created_at': '2026-09-20T06:00:00.000Z',
    });
    // restore-shaped (explicit nulls, id, user_id, source)
    await put('2026-09-21', {
      'id': 'cloud-id',
      'user_id': kTestUserId,
      'date': '2026-09-21',
      'chest': 101.0,
      'waist': null,
      'hips': null,
      'arms': null,
      'notes': null,
      'created_at': '2026-09-21T06:00:00.000Z',
      'source': 'cloud_restore',
    });
    // pull-shaped (source telegram)
    await put('2026-09-22', {
      'id': 'cloud-id-2',
      'user_id': kTestUserId,
      'date': '2026-09-22',
      'hips': 96.0,
      'chest': null,
      'waist': null,
      'arms': null,
      'notes': 'from chat',
      'created_at': '2026-09-22T06:00:00.000Z',
      'source': 'telegram',
    });
    await pass();
    final byDate = {for (final b in bodies()) b['date'] as String: b};
    expect(byDate['2026-09-20']!.keys.toSet(), {
      'user_id',
      'date',
      'waist',
      'created_at',
    });
    expect(byDate['2026-09-21']!.keys.toSet(), {
      'user_id',
      'date',
      'chest',
      'created_at',
    });
    expect(byDate['2026-09-22']!.keys.toSet(), {
      'user_id',
      'date',
      'hips',
      'notes',
      'created_at',
    });
    expect(bodies(), hasLength(3), reason: 'one request per stored date');

    h.server.clear();
    await pass();
    expect(bodies(), isEmpty, reason: 'an unchanged second pass sends nothing');
  });

  test('the empty-row rule: site only and notes only push; neither pushes '
      'nothing and its seeded index entry survives', () async {
    // The empty record sorts FIRST (Hive keys iterate in sorted order), so a
    // `continue` turned into a `break` would also stop the two later days.
    await put('2026-09-19', {
      'date': '2026-09-19',
      'chest': null,
      'waist': null,
      'hips': null,
      'arms': null,
      'notes': null,
    });
    await put('2026-09-20', {'date': '2026-09-20', 'chest': 90.0});
    await put('2026-09-21', {'date': '2026-09-21', 'notes': 'felt strong'});
    // A HEAD-era fingerprint of an all-null record: only a SEEDED entry makes
    // `liveKeys.add(date)` before the `continue` observable (an empty date
    // never gets a fingerprint in this build).
    await HiveService.instance.healthBox.put(
      SyncSkipDomain.measurement.indexKey,
      <String, String>{'2026-09-19': '00000000-0000-5000-8000-000000000000'},
    );
    await pass();
    final dates = bodies().map((b) => b['date']).toSet();
    expect(dates, {'2026-09-20', '2026-09-21'});
    expect(
      index().containsKey('2026-09-19'),
      isTrue,
      reason: 'a live date keeps its stored fingerprint',
    );
    expect(index().containsKey('2026-09-20'), isTrue);
    expect(index().containsKey('2026-09-21'), isTrue);
  });

  test('kill switch set: an all-null record still pushes HEAD\'s body (the '
      'old path has no empty-row skip)', () async {
    await HiveService.instance.configBox.put(_killSwitch, true);
    await put('2026-09-22', {
      'date': '2026-09-22',
      'chest': null,
      'waist': null,
      'hips': null,
      'arms': null,
      'notes': null,
      'created_at': '2026-09-22T06:00:00.000Z',
    });
    await pass();
    expect(
      jsonEncode(bodies().single),
      '{"user_id":"$kTestUserId","date":"2026-09-22","chest":null,'
      '"waist":null,"hips":null,"arms":null,"notes":null,'
      '"created_at":"2026-09-22T06:00:00.000Z"}',
    );
    expect(index().containsKey('2026-09-22'), isTrue);
  });

  test('a NaN site beside a finite sibling pushes the sibling and reports '
      'no failure', () async {
    await put('2026-09-20', {
      'date': '2026-09-20',
      'chest': double.nan,
      'waist': 80.0,
      'created_at': '2026-09-20T06:00:00.000Z',
    });
    await pass();
    expect(bodies().single.containsKey('chest'), isFalse);
    expect(bodies().single['waist'], 80.0);
    // Deterministic: pushIfChanged forgets a failed push and stores a
    // confirmed one, so a stored fingerprint IS "the push did not fail".
    expect(
      index().containsKey('2026-09-20'),
      isTrue,
      reason: 'a confirmed push stores its fingerprint',
    );
    // And no failure report reaches log-client-error. That report is
    // fire-and-forget, so settle before looking (custom_item_skip_test.dart),
    // and filter on the FAILURE op_type: the success event posts to the same
    // function under another op_type.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final reports = h.server.requests.where(
      (r) =>
          r.path == '/functions/v1/log-client-error' &&
          r.body is Map &&
          (r.body! as Map)['op_type'] == SyncSkipDomain.measurement.opType,
    );
    expect(reports, isEmpty);
  });

  test('FLOW (the two-device bug): device B holds only hips; the cloud keeps '
      'what device A entered', () async {
    cloudRow('2026-09-22')
      ..['chest'] = 100.0
      ..['waist'] = 85.0;
    SyncService.pausedForSimulation =
        true; // logMeasurement fires a background pass
    final r = await HealthWriteService.instance.logMeasurement(
      date: DateTime.utc(2026, 9, 22, 6),
      partName: 'hips',
      valueCm: 95.0,
      source: WriteSource.aiCoach,
    );
    SyncService.pausedForSimulation = false;
    expect(r.success, isTrue);
    await pass();
    expect(cloud['2026-09-22']!['chest'], 100.0);
    expect(cloud['2026-09-22']!['waist'], 85.0);
    expect(cloud['2026-09-22']!['hips'], 95.0);
    expect(violations, isEmpty);
  });

  test(
    'FLOW with the real restore: restore, then a new site, then a pass',
    () async {
      final created = DateTime.now()
          .toUtc()
          .subtract(const Duration(hours: 1))
          .toIso8601String();
      cloudRow('2026-09-22')
        ..['chest'] = 100.0
        ..['waist'] = 85.0
        ..['created_at'] = created;
      h.server.pagedTables['body_measurements'] = [
        {...cloud['2026-09-22']!},
      ];
      await SyncService.instance
          .restoreMeasurementsForSyncDomain(since: '2020-01-01T00:00:00Z')
          .timeout(const Duration(minutes: 2));
      final local = HiveService.instance.healthBox.get(
        'measurement_2026-09-22',
      );
      expect(local, isA<Map>(), reason: 'the restore wrote the local record');
      expect((local as Map)['chest'], 100.0);

      SyncService.pausedForSimulation = true;
      await HealthWriteService.instance.logMeasurement(
        date: DateTime.utc(2026, 9, 22, 6),
        partName: 'hips',
        valueCm: 95.0,
        source: WriteSource.aiCoach,
      );
      SyncService.pausedForSimulation = false;
      await pass();
      expect(bodies().single.keys.toSet(), {
        'user_id',
        'date',
        'chest',
        'waist',
        'hips',
        'created_at',
      });
      expect(cloud['2026-09-22']!['hips'], 95.0);
      expect(cloud['2026-09-22']!['chest'], 100.0);
      expect(violations, isEmpty);
    },
  );

  group('the cross-channel pull (_pullMeasurements, through the test seam)', () {
    // `pullRecentCrossChannelLogs` returns without a signed-in user and the
    // stub harness has none, so these drive `_pullMeasurements` itself through
    // `pullMeasurementsForTest`: the merge call, its argument order and the
    // `put` are executed, not grepped.
    Map<String, dynamic> cloudRowFor(String date, Map<String, dynamic> extra) =>
        {
          'id': 'cloud-id-$date',
          'user_id': kTestUserId,
          'date': date,
          'chest': null,
          'waist': null,
          'hips': null,
          'arms': null,
          'notes': null,
          'created_at': '${date}T05:00:00.000Z',
          ...extra,
        };
    Future<void> pull() => SyncService.instance
        .pullMeasurementsForTest(since: '2020-01-01T00:00:00Z')
        .timeout(const Duration(minutes: 2));
    Map<dynamic, dynamic> local(String date) =>
        HiveService.instance.healthBox.get('measurement_$date')
            as Map<dynamic, dynamic>;
    int pullReads() => h.server.requests
        .where((r) => r.table == 'body_measurements' && !r.isWrite)
        .length;

    test(
      'fills only the sites that are null locally and touches nothing else',
      () async {
        await put('2026-09-22', {
          'id': 'meas_1',
          'date': '2026-09-22',
          'waist': 80.0,
          'source': 'ai_coach',
          'updated_at_ms': 1758000000000,
          'created_at': '2026-09-22T06:00:00.000Z',
        });
        h.server.pagedTables['body_measurements'] = [
          cloudRowFor('2026-09-22', {
            'chest': 100.0,
            'waist': 85.0, // the cloud's value must NOT replace the local one
            'hips': 95.0,
            'arms': null, // a null cloud site must not become an explicit key
            'notes': 'from chat', // only sites are merged, never notes
            'source': 'telegram',
          }),
        ];
        await pull();
        expect(
          pullReads(),
          greaterThan(0),
          reason: 'the seam reached the stub',
        );
        final rec = local('2026-09-22');
        expect(rec['chest'], 100.0, reason: 'a null local site is filled');
        expect(rec['hips'], 95.0);
        expect(
          rec['waist'],
          80.0,
          reason: 'a local value is never overwritten',
        );
        expect(
          rec.containsKey('arms'),
          isFalse,
          reason: 'a null cloud site writes nothing',
        );
        expect(
          rec.containsKey('notes'),
          isFalse,
          reason: 'notes are not merged',
        );
        expect(rec['id'], 'meas_1');
        expect(rec['source'], 'ai_coach');
        expect(rec['updated_at_ms'], 1758000000000);
        expect(rec['created_at'], '2026-09-22T06:00:00.000Z');
      },
    );

    test('a day with no local record is stored as the cloud row, source '
        'telegram', () async {
      h.server.pagedTables['body_measurements'] = [
        cloudRowFor('2026-09-23', {'hips': 96.0, 'notes': 'from chat'}),
      ];
      await pull();
      final rec = local('2026-09-23');
      expect(rec['hips'], 96.0);
      expect(rec['notes'], 'from chat');
      expect(rec['source'], 'telegram');
      expect(rec['date'], '2026-09-23');
    });

    test('RESIDUAL (founder rule "last sync or write wins", OQ-L2a): a pull '
        'fill re-fingerprints the day, so the next push sends every held '
        'site, a stale one included', () async {
      await put('2026-09-22', {
        'id': 'meas_1',
        'date': '2026-09-22',
        'waist': 80.0,
        'created_at': '2026-09-22T06:00:00.000Z',
      });
      await pass();
      expect(cloud['2026-09-22']!['waist'], 80.0);
      h.server.clear();
      // Another device corrected waist to 85 and added chest in the cloud.
      cloud['2026-09-22']!
        ..['waist'] = 85.0
        ..['chest'] = 100.0;
      h.server.pagedTables['body_measurements'] = [
        {...cloud['2026-09-22']!},
      ];
      await pull();
      expect(local('2026-09-22')['chest'], 100.0);
      expect(
        local('2026-09-22')['waist'],
        80.0,
        reason: 'the pull keeps local',
      );
      await pass();
      expect(
        bodies().single.keys.toSet(),
        {'user_id', 'date', 'chest', 'waist', 'created_at'},
        reason:
            'the filled site changed the fingerprint: every held site '
            'is sent',
      );
      expect(
        cloud['2026-09-22']!['waist'],
        80.0,
        reason:
            'documented residual: the stale held value overwrote the '
            'corrected one. A per-site pending set (the L2b entry '
            'criterion) is what would change this assertion.',
      );
    });
  });
}
