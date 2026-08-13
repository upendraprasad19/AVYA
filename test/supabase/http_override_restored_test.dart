@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'supabase_test_helper.dart';

/// Regression test for diagnose 3b7e1c.
///
/// `TestWidgetsFlutterBinding.ensureInitialized()` — which every
/// `test/supabase/` and `test/edge_functions/` integration file needs, because
/// `Supabase.initialize()` requires the mocked `shared_preferences`
/// MethodChannel — installs an `HttpOverrides.global` that answers EVERY request
/// with status 400 and an empty body, without opening a socket. Those files are
/// INTEGRATION tests whose first act is a real `signIn()`, so under that stub
/// they all die in `setUpAll` with `AuthUnknownException(... status code 400)`
/// before reaching an assertion.
///
/// BEHAVIOURAL, not a source-grep: binds a real socket and counts hits. A grep
/// proves the line exists; only observing a request leave the process proves the
/// behaviour (feedback_source_grep_false_confidence).
///
/// HERMETIC: 127.0.0.1 on an ephemeral port. No external host, no credentials,
/// no Supabase project — so it runs in the ordinary unit-test job, where the
/// credential-gated files take their SKIPPED branch. That matters: this
/// protection holds even when the Actions secrets are absent, which is the exact
/// condition under which the bug hid.
///
/// ORDER-INDEPENDENT. `restoreRealHttp()` nulls a process-global for the whole
/// isolate, so an earlier test could otherwise leave a later one asserting
/// against the wrong baseline. Round-2 review reproduced that with
/// `--test-randomize-ordering-seed`. Every test here re-installs the binding's
/// stub in `setUp` and restores it in `tearDown`.
void main() {
  late HttpOverrides? bindingStub;
  late HttpServer server;
  late Uri uri;
  var hits = 0;

  setUpAll(() {
    // Capture the binding's own override ONCE. It cannot be reconstructed
    // (`_MockHttpOverrides` is private to flutter_test), so it is captured
    // rather than rebuilt.
    TestWidgetsFlutterBinding.ensureInitialized();
    bindingStub = HttpOverrides.current;
  });

  setUp(() async {
    HttpOverrides.global = bindingStub; // every test starts stubbed
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
    HttpOverrides.global = bindingStub;
    await server.close(force: true);
  });

  /// One GET. The client is built AFTER the caller sets `HttpOverrides.global`,
  /// because `HttpClient()` resolves the override at construction time —
  /// building it earlier would silently test the wrong thing.
  Future<int> get(Uri target) async {
    final client = HttpClient();
    try {
      final res = await (await client.getUrl(target)).close();
      await res.drain<void>();
      return res.statusCode;
    } finally {
      client.close(force: true);
    }
  }

  test('the test binding really does stub HTTP (premise of the whole fix)',
      () async {
    expect(bindingStub, isNotNull,
        reason: 'PREMISE: TestWidgetsFlutterBinding must install an '
            'HttpOverrides. If Flutter stops doing this the fix under test is '
            'unnecessary and this file should be revisited, not silently kept '
            'passing.');

    expect(await get(uri), 400,
        reason: 'the stub answers 400 without a socket — the exact '
            'AuthUnknownException(... status code 400) seen in CI');
    expect(hits, 0,
        reason: 'the request must NOT reach the real server; if it did, the '
            'stub is inactive and the next tests prove nothing');
  });

  test('restoreRealHttp() lets a request reach a real socket', () async {
    SupabaseTestHelper.restoreRealHttp();

    expect(HttpOverrides.current, isNull,
        reason: 'the override must be cleared, not merely reassigned');
    expect(await get(uri), 200,
        reason: 'a 400 here means the binding is still intercepting');
    expect(hits, 1,
        reason: 'the loopback server observing exactly one request is the only '
            'proof a socket was actually opened');
  });

  test('prepareBinding() installs the binding AND undoes its stub — IN ORDER',
      () async {
    // THE WIRING + ORDER PROOF, and the gap round-2 review found: the test
    // above drives restoreRealHttp() DIRECTLY, so it stayed green when the call
    // was deleted from init(), and when the two lines were swapped. Both
    // mutations are real regressions — the second is especially quiet, because
    // installing the binding AFTER clearing the override re-installs the stub
    // and the fix evaporates with every line still present.
    //
    // Starts from the stubbed state (setUp), so passing means prepareBinding()
    // itself did the work.
    expect(HttpOverrides.current, isNotNull, reason: 'stubbed at entry');

    SupabaseTestHelper.prepareBinding();

    expect(HttpOverrides.current, isNull,
        reason: 'prepareBinding() must leave NO override installed. If this '
            'fails with an override present, the two calls are in the wrong '
            'order: _mockSharedPreferences() installs the binding, so clearing '
            'must come AFTER it.');
    expect(await get(uri), 200);
    expect(hits, 1,
        reason: 'a real socket after prepareBinding() is what init() depends on');
  });
}
