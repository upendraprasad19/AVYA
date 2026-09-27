@Timeout(Duration(minutes: 2))
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

void main() {
  final h = SyncHarness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  test('the real water-log push reaches the stub with live-schema keys', () async {
    await HiveService.instance.healthBox.put('water_ml_2026-09-20', 750);
    await SyncService.instance.pushWaterLogsForSyncDomain();
    final writes = h.server.writesTo('water_logs');
    expect(writes, hasLength(1));
    expect(writes.single.method, 'POST');
    expect(writes.single.query['on_conflict'], 'user_id,date');
    expect(writes.single.rows.single['total_ml'], 750);
    expectWritesMatchLiveSchema(h.server);
  });

  test('maybeSingle reads the scripted row; delete, rpc and functions are recorded', () async {
    h.server.getResponders['workout_templates'] = (_) => [
          {'id': 'tmpl-cloud-1'}
        ];
    final c = SupabaseService.instance.client;
    final row = await c
        .from('workout_templates')
        .select('id')
        .eq('user_id', 'u')
        .eq('name', 'x')
        .maybeSingle();
    expect(row, {'id': 'tmpl-cloud-1'});
    await c.from('template_exercises').delete().eq('template_id', 't').gte('order_index', 3);
    await c.rpc('consume_quota', params: {'p_limit': 1});
    await c.functions.invoke('log-client-error', body: {'op_type': 'x'});
    final del = h.server.requests.singleWhere((r) => r.method == 'DELETE');
    expect(del.table, 'template_exercises');
    expect(del.query['order_index'], 'gte.3');
    expect(h.server.requests.where((r) => r.path == '/rest/v1/rpc/consume_quota'), hasLength(1));
    expect(h.server.requests.where((r) => r.path == '/functions/v1/log-client-error'), hasLength(1));
  });

  test('failWritesTo makes the client throw', () async {
    h.server.failWritesTo.add('water_logs');
    await expectLater(
        SupabaseService.instance.client.from('water_logs').upsert({'user_id': 'u'}),
        throwsA(isA<PostgrestException>()));
  });

  test('expectWritesMatchLiveSchema rejects a key that is not a live column', () {
    h.server.requests.add(StubRequest(
        'POST', '/rest/v1/water_logs', const {}, const {}, {'bogus_col': 1}));
    expect(() => expectWritesMatchLiveSchema(h.server),
        throwsA(isA<TestFailure>()));
  });
}
