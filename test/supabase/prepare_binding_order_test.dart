@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'supabase_test_helper.dart';

/// ONE test, in its OWN FILE, on purpose — `flutter test` gives each file its
/// own isolate, and a VIRGIN isolate is the only place this bug is observable.
///
/// WHAT IT PINS: that `SupabaseTestHelper.prepareBinding()` installs the test
/// binding BEFORE clearing its HTTP stub. Inverting those two lines silently
/// re-installs the stub and diagnose 3b7e1c returns with every line still
/// present — the quietest possible regression.
///
/// WHY IT CANNOT LIVE IN http_override_restored_test.dart: that file's `setUpAll`
/// calls `TestWidgetsFlutterBinding.ensureInitialized()` so it can capture the
/// stub. `ensureInitialized()` is IDEMPOTENT — once the binding exists, calling
/// it again does not re-install `HttpOverrides.global`. So after any earlier
/// touch, both orderings behave identically and the assertion proves nothing.
/// Measured, not assumed: with the ordering test in that file, inverting the two
/// lines left the suite GREEN. Moving it here makes the same mutation RED.
///
/// Consequence for future edits: this file must NEVER gain a second test, a
/// `setUpAll`, or any import whose top level touches the binding. Its isolate
/// being untouched IS the assertion. A second test here would silently disarm it
/// — the same way the first attempt disarmed itself.
void main() {
  test('prepareBinding() in a virgin isolate leaves real HTTP working',
      () async {
    expect(HttpOverrides.current, isNull,
        reason: 'PREMISE: nothing may have touched the binding yet in this '
            'isolate. If this fails, something in this file (a setUpAll, a '
            'second test, an import side effect) initialised the binding first '
            'and the ordering assertion below is now vacuous.');

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var hits = 0;
    server.listen((HttpRequest req) async {
      hits++;
      req.response.statusCode = 200;
      req.response.write('real');
      await req.response.close();
    });

    try {
      SupabaseTestHelper.prepareBinding();

      expect(HttpOverrides.current, isNull,
          reason: 'ORDER IS WRONG: an override is installed after '
              'prepareBinding(). _mockSharedPreferences() calls '
              'ensureInitialized(), which INSTALLS the stub — so '
              'restoreRealHttp() must run AFTER it, not before.');

      final client = HttpClient();
      try {
        final res = await (await client
                .getUrl(Uri.parse('http://127.0.0.1:${server.port}/ping')))
            .close();
        await res.drain<void>();
        expect(res.statusCode, 200);
      } finally {
        client.close(force: true);
      }

      expect(hits, 1,
          reason: 'a real socket reaching the loopback server is the only proof '
              'the stub is genuinely gone rather than merely reassigned');
    } finally {
      await server.close(force: true);
    }
  });
}
