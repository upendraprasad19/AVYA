@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'supabase_test_helper.dart';

/// Regression test for diagnose 3b7e1c.
///
/// `TestWidgetsFlutterBinding.ensureInitialized()` — which
/// `SupabaseTestHelper.init()` needs, because `Supabase.initialize()` requires
/// the mocked `shared_preferences` MethodChannel — installs an
/// `HttpOverrides.global` that answers EVERY request with status 400 and an
/// empty body, without opening a socket. Every file in `test/supabase/` is an
/// INTEGRATION test whose first act is a real `signIn()`, so under that stub
/// they all die in `setUpAll` with
/// `AuthUnknownException(... status code 400)` before reaching an assertion.
///
/// This is deliberately BEHAVIOURAL, not a source-grep for
/// `HttpOverrides.global = null`. A grep proves the line exists; only binding a
/// real socket and counting hits proves a request actually leaves the process
/// — and this repo has been bitten repeatedly by presence-only tests that pass
/// while the behaviour is broken (feedback_source_grep_false_confidence).
///
/// HERMETIC: binds 127.0.0.1 on an ephemeral port. It contacts no external
/// host, needs no credentials, and touches no Supabase project — so unlike the
/// rest of `test/supabase/`, it runs in the ordinary unit-test job too, where
/// the credential-gated files take their SKIPPED branch. That matters: it means
/// this protection holds even when the Actions secrets are absent, which is the
/// exact condition under which the bug hid for as long as it did.
void main() {
  late HttpServer server;
  late Uri uri;
  var hits = 0;

  setUp(() async {
    hits = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    uri = Uri.parse('http://127.0.0.1:${server.port}/ping');
    server.listen((HttpRequest req) async {
      hits++;
      req.response.statusCode = 200;
      req.response.write('real');
      await req.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
  });

  /// Issues one GET. The client is constructed AFTER the caller has set
  /// `HttpOverrides.global`, because `HttpClient()` resolves the override at
  /// construction time — building it earlier would silently test the wrong
  /// thing.
  Future<int> get(Uri target) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(target);
      final res = await req.close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test('the test binding really does stub HTTP (premise of the whole fix)',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // NOTE the asymmetric dart:io API: `HttpOverrides.global` is a SETTER only;
    // the readable side is `HttpOverrides.current`. Reading `.global` is a
    // compile error, not a null.
    final installed = HttpOverrides.current;

    expect(installed, isNotNull,
        reason: 'PREMISE: TestWidgetsFlutterBinding must install an '
            'HttpOverrides. If Flutter ever stops doing this, the fix under '
            'test becomes unnecessary and this file should be revisited rather '
            'than silently kept passing.');

    final status = await get(uri);

    expect(status, 400,
        reason: 'the stub answers 400 without a socket — this is the exact '
            'AuthUnknownException(... status code 400) seen in CI');
    expect(hits, 0,
        reason: 'the request must NOT have reached the real server; if it did, '
            'the stub is not active and the next test proves nothing');
  });

  test('restoreRealHttp() lets a request actually reach a real socket',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(HttpOverrides.current, isNotNull, reason: 'stub installed');

    SupabaseTestHelper.restoreRealHttp();

    expect(HttpOverrides.current, isNull,
        reason: 'the override must be cleared, not merely reassigned');

    final status = await get(uri);

    // THE ASSERTION THIS FILE EXISTS FOR. Delete the body of
    // restoreRealHttp() and this fails: status 400, hits 0.
    expect(status, 200,
        reason: 'after restoreRealHttp() a real request must reach the real '
            'server. A 400 here means the binding is still intercepting and '
            'every test/supabase/ integration test will fail in setUpAll.');
    expect(hits, 1,
        reason: 'the loopback server must have observed exactly one real '
            'request — the only proof that a socket was actually opened');
  });
}
