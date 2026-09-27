@Timeout(Duration(minutes: 2))
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/sync_stub_server.dart';
import 'sync_domain_skip_harness.dart';

/// Writes a minimal HTTP/1.1 POST with a `Content-Length` LARGER than the
/// body it actually sends, so the server's `_handle` starts reading the
/// body and is left waiting for bytes that never arrive -- the exact shape
/// `_reportSyncFailure`'s fire-and-forget `log-client-error` POST can be in
/// when a test's `tearDown` force-closes the server mid-flight (diagnose
/// `a9d3f6`). [socket] is left open and connected; the caller decides how
/// the connection ends (a forced server stop, or a client-side destroy).
Future<Socket> _openIncompletePost(int port) async {
  final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
  socket.write('POST /functions/v1/log-client-error HTTP/1.1\r\n'
      'Host: 127.0.0.1\r\n'
      'Content-Type: application/json\r\n'
      'Content-Length: 1000\r\n'
      '\r\n'
      '{"op_type":"probe"');
  await socket.flush();
  // Give the server a moment to parse the headers and start blocking on the
  // (never-completing) body read before the caller acts.
  await Future.delayed(const Duration(milliseconds: 60));
  return socket;
}

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

  // F2 (Task 17 review, Minor) -- the `_stopping`-gated catch around the
  // body read (diagnose `a9d3f6`) had no dedicated test; only validated
  // indirectly via repeated runs of saved_meal_skip_test.dart and the nlog
  // flake test. Both tests below use their OWN standalone SyncStubServer
  // (not `h.server`/`h.setUp`) so `.start()`'s `s.listen(_handle)` binds to
  // a zone this test creates and controls via `runZonedGuarded` -- `h`'s
  // server is started inside flutter_test's own per-test zone (via
  // `setUp`), which this file cannot reach into to intercept an escaping
  // async error without risking attributing it to some OTHER test, exactly
  // the failure mode diagnose `a9d3f6` itself describes.
  test('a read failure during an in-progress stop() is swallowed, not thrown '
      '(F2a)', () async {
    final srv = SyncStubServer();
    Object? uncaught;
    await runZonedGuarded(() async {
      await srv.start();
      final port = Uri.parse(srv.url).port;
      final socket = await _openIncompletePost(port);
      // stop() sets `_stopping = true` BEFORE force-closing -- this is the
      // exact ordering the fix depends on: the force-close destroys our
      // still-open, still-reading connection while the flag is already up.
      await srv.stop();
      await Future.delayed(const Duration(milliseconds: 150));
      socket.destroy();
    }, (error, stack) => uncaught = error);
    expect(uncaught, isNull,
        reason: 'a read failure caused by stop()\'s own force-close must be '
            'swallowed, not surfaced as an uncaught error attributable to '
            'whichever test runs next');
  });

  test('the same read failure OUTSIDE the stopping window is NOT swallowed '
      '(F2b, the mirror)', () async {
    final srv = SyncStubServer();
    Object? uncaught;
    await runZonedGuarded(() async {
      await srv.start();
      final port = Uri.parse(srv.url).port;
      final socket = await _openIncompletePost(port);
      // Never call stop() here -- this is a genuine CLIENT-initiated
      // connection fault, not a deliberate shutdown, so `_stopping` stays
      // false and the exception must propagate rather than vanish.
      socket.destroy();
      await Future.delayed(const Duration(milliseconds: 300));
    }, (error, stack) => uncaught = error);
    expect(uncaught, isNotNull,
        reason: 'a genuine connection fault outside stop() must not be '
            'silently swallowed -- that would hide a real server-side fault '
            'the same way the pre-fix bug hid it during shutdown');
    expect(uncaught, anyOf(isA<HttpException>(), isA<SocketException>()));
    await srv.stop();
  });
}
