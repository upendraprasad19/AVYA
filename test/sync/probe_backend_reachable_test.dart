@Timeout(Duration(minutes: 2))
library;

// Contract — closes-diagnose e5b2a9 (B-pass F3). The reachability probe must be
// ONE request, must treat an answered "no" as REACHABLE and an outage shape as
// NOT reachable, and must not read a user-typed echo in `details` as an outage.
// Driven through probeBackendWithClient against the local stub server (the
// SyncService wrapper only adds the session guard and the 8 s ceiling).

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/backend_probe.dart';

import '../helpers/sync_stub_server.dart';

void main() {
  final server = SyncStubServer();

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await server.start();
  });
  tearDown(() async {
    await server.stop();
    server.clear();
    server.readReplies.clear();
  });

  Future<bool> probe() => probeBackendWithClient(server.client(), 'u-1');

  test('a 200 answer is reachable, in ONE request, against the users table', () async {
    server.getResponders['users'] = (_) => [
          {'id': 'u-1'}
        ];
    expect(await probe(), isTrue);
    expect(server.requests.where((r) => r.table == 'users').length, 1);
    expect(server.requests.single.query['id'], 'eq.u-1');
  });

  test('PGRST002 (HTTP 503, the real outage shape) is NOT reachable — and costs ONE request, not four',
      () async {
    server.readReplies['users'] = const StubReadReply(503, {
      'code': 'PGRST002',
      'message': 'Could not query the database for the schema cache. Retrying.',
    });
    expect(await probe(), isFalse);
    expect(server.requests.where((r) => r.table == 'users').length, 1,
        reason: 'the SDK retries a 503 GET three more times unless the query opts out');
  });

  test('a Cloudflare 521 plain-text answer is NOT reachable', () async {
    server.readReplies['users'] = const StubReadReply(521, 'error code: 521');
    expect(await probe(), isFalse);
  });

  test('MIRROR: an auth rejection (PGRST301 / 401) means the server ANSWERED — reachable', () async {
    server.readReplies['users'] =
        const StubReadReply(401, {'code': 'PGRST301', 'message': 'JWT expired'});
    expect(await probe(), isTrue);
  });

  test('MIRROR: a 500 carrying a Postgres check-violation whose DETAILS echo user text is reachable',
      () async {
    server.readReplies['users'] = const StubReadReply(500, {
      'code': '23514',
      'message': 'new row violates check constraint',
      'details': 'Failing row contains (my workout timed out yesterday)',
    });
    expect(await probe(), isTrue,
        reason: 'text echoed into details is the user\'s, not an outage signal');
  });

  test('a connection refused (server down) is NOT reachable', () async {
    final client = server.client();
    await server.stop();
    expect(await probeBackendWithClient(client, 'u-1'), isFalse);
  });
}
