@Timeout(Duration(minutes: 5))
library;

// L2b Landing B (B1) - the CLOUD-VISIBLE effect of
// HealthWriteService.logMeasurements, through the same stub server and cloud
// model as body_measurement_push_merge_safe_test.dart.
//
//   1. A call that edits two sites yields ONE upsert row that carries both
//      (and no key for a site the record does not hold: the push is
//      merge-safe, so the cloud keeps whatever another device entered).
//   2. A later call that adds a third site pushes the merged record, and the
//      cloud row ends with all three.
//   3. The write fans out BY ITSELF: an unpaused call reaches the stub server
//      with no explicit sync pass. This is the behavioural half of the
//      fan-out pin (the other half is the source pin in
//      measurement_write_batch_behavioral_test.dart, because the skip index
//      hides an extra pass from any upsert count).
//
// The cloud model assigns every key present in the body (nulls included) and
// leaves absent keys alone, which is PostgREST's merge-duplicates behaviour.
//
// Plan: docs/plans/coach-measurement-sheet-ui.md (B1, section 4)

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/health_write_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:icanbefitter/core/services/write_result.dart';

import '../helpers/hive_test_setup.dart' show kTestUserId;
import 'sync_domain_skip_harness.dart';

/// 2026-09-20 06:00Z is 11:30 IST on 2026-09-20.
final _day = DateTime.utc(2026, 9, 20, 6);

void main() {
  final h = SyncHarness();
  late Map<String, Map<String, dynamic>> cloud;
  late List<String> violations;

  setUp(() async {
    await h.setUp();
    h.server.clear();
    h.server.writeResponders.clear();
    h.server.pagedTables.clear();
    // The write must not push by itself unless a test says so.
    SyncService.pausedForSimulation = true;
    cloud = {};
    violations = [];
    h.server.writeResponders['body_measurements'] = (r) {
      if (!(r.headers['prefer'] ?? '').contains('resolution=merge-duplicates')) {
        violations.add('prefer=${r.headers['prefer']}');
      }
      if (r.query['on_conflict'] != 'user_id,date') {
        violations.add('on_conflict=${r.query['on_conflict']}');
      }
      for (final row in r.rows) {
        final target = cloud.putIfAbsent(row['date'] as String,
            () => <String, dynamic>{'date': row['date']});
        row.forEach((k, v) => target[k] = v);
      }
      return null; // return=minimal
    };
  });

  tearDown(() async {
    SyncService.pausedForSimulation = false;
    await h.tearDown();
  });

  Future<WriteResult> logMany(Map<String, double> sites) =>
      HealthWriteService.instance.logMeasurements(
        date: _day,
        sites: sites,
        source: WriteSource.manual,
      );

  Future<void> pass() async {
    SyncService.pausedForSimulation = false;
    await SyncService.instance
        .pushMeasurementsForSyncDomain()
        .timeout(const Duration(minutes: 2));
  }

  List<Map<String, dynamic>> bodies() => [
        for (final r in h.server.writesTo('body_measurements')) ...r.rows,
      ];

  test('a two-site call pushes ONE row that carries exactly those two sites',
      () async {
    expect((await logMany({'chest': 100.5, 'waist': 80.0})).success, isTrue);
    expect(bodies(), isEmpty, reason: 'paused: nothing has been pushed yet');

    await pass();

    expect(bodies(), hasLength(1), reason: 'one upsert row for the one day');
    final body = bodies().single;
    expect(body['user_id'], kTestUserId);
    expect(body['date'], '2026-09-20');
    expect(body['chest'], 100.5);
    expect(body['waist'], 80.0);
    expect(body.containsKey('hips'), isFalse,
        reason: 'a site the record does not hold is not sent, so it cannot '
            'blank what another device entered');
    expect(body.containsKey('arms'), isFalse);
    expect(cloud['2026-09-20']!['chest'], 100.5);
    expect(cloud['2026-09-20']!['waist'], 80.0);
    expect(violations, isEmpty);
  });

  test('a later call adding a third site pushes the merged record', () async {
    await logMany({'chest': 100.5, 'waist': 80.0});
    await pass();
    h.server.clear();

    SyncService.pausedForSimulation = true;
    expect((await logMany({'arms': 33.3})).success, isTrue);
    await pass();

    expect(bodies(), hasLength(1));
    final body = bodies().single;
    expect(body['chest'], 100.5, reason: 'the merged record keeps the others');
    expect(body['waist'], 80.0);
    expect(body['arms'], 33.3);
    expect(cloud['2026-09-20']!['chest'], 100.5);
    expect(cloud['2026-09-20']!['arms'], 33.3);
    expect(violations, isEmpty);
  });

  test('a rejected call pushes nothing, even on the next pass', () async {
    expect((await logMany({'chest': 100.5, 'waist': 3000})).success, isFalse);
    await pass();
    expect(bodies(), isEmpty);
  });

  test('the write fans out by itself: an unpaused call reaches the server '
      'with no explicit pass', () async {
    SyncService.pausedForSimulation = false;
    expect((await logMany({'chest': 100.5, 'waist': 80.0})).success, isTrue);

    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (bodies().isEmpty && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(bodies(), isNotEmpty,
        reason: 'logMeasurements must start syncMeasurementsNow itself');
    final body = bodies().first;
    expect(body['chest'], 100.5);
    expect(body['waist'], 80.0);
    expect(violations, isEmpty);
  });
}
