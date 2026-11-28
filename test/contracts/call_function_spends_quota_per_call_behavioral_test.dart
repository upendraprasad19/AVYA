import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OI-414 — FORWARDING, run for real: `SupabaseService.callFunction` hands
/// `spendsQuotaPerCall` to the re-send loop, so a flagged call reaches a
/// gateway 502 once and the server sees ONE request.
///
/// The loop itself is pinned in `edge_function_cold_start_retry_behavioral_test
/// .dart` with a mock invoker; that cannot see a `callFunction` that drops the
/// argument on the way. This file drives the real method over real HTTP against
/// a loopback server that answers 502 and counts requests. A session is set
/// with `setInitialSession` (no network) and `ensureFreshToken` finds it fresh,
/// so no refresh call is made.
///
/// The paywall's and the day swap's own ARGUMENT at their call sites is not run
/// here (a widget run needs the paywall provider tree): it is source-pinned in
/// `spends_quota_per_call_source_pins_test.dart` (presence only).
void main() {
  late HttpServer server;
  late int hits;
  final events = <String>[];

  setUp(() async {
    // A neighbouring test file may leave an HttpOverrides in place; a stub
    // client in it would answer instead of the loopback server below.
    HttpOverrides.global = null;
    hits = 0;
    events.clear();
    ErrorTelemetry.debugOnLogEventForTests = (opType, {message}) {
      events.add('$opType:$message');
    };
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      if (req.uri.path.endsWith('/functions/v1/validate-promo')) hits++;
      await req.drain<void>();
      req.response.statusCode = 502;
      req.response.headers.contentType = ContentType.json;
      req.response.write('{"message":"bad gateway"}');
      await req.response.close();
    });
    final client =
        SupabaseClient('http://127.0.0.1:${server.port}', 'stub-anon-key');
    final expiresAt =
        DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/
            1000;
    await client.auth.setInitialSession(jsonEncode(<String, dynamic>{
      'access_token': 'stub-access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': expiresAt,
      'refresh_token': 'stub-refresh-token',
      'user': <String, dynamic>{
        'id': 'stub-user-id',
        'aud': 'authenticated',
        'app_metadata': <String, dynamic>{},
        'user_metadata': <String, dynamic>{},
        'created_at': '2026-01-01T00:00:00Z',
      },
    }));
    SupabaseService.clientOverrideForTest = client;
  });

  tearDown(() async {
    SupabaseService.clientOverrideForTest = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
    await server.close(force: true);
  });

  test('a flagged call reaches a gateway 502 once: the server sees ONE request',
      () async {
    await expectLater(
      () => SupabaseService.instance
          .callFunction('validate-promo',
              body: {'code': 'NOPE'}, spendsQuotaPerCall: true)
          .timeout(const Duration(seconds: 8)),
      throwsA(isA<FunctionException>().having((e) => e.status, 'status', 502)),
      reason: 'a TimeoutException means the call was still waiting to be '
          'sent again (the flag did not reach the loop)',
    );
    expect(hits, 1);
    expect(events,
        ['edge_function_no_retry_quota_call:fn=validate-promo status=502']);
  });

  test('(control) the same call WITHOUT the flag is sent again after 2 s',
      () async {
    // Proves the harness drives the re-send path at all: without this, "one
    // request" above could hold for the wrong reason (a call that never sent).
    final pending = SupabaseService.instance
        .callFunction('validate-promo', body: {'code': 'NOPE'});
    // The rest of the schedule (6 s, 12 s) runs after this test; its outcome is
    // consumed here so a late failure is not reported against another test.
    unawaited(pending.then<void>((_) {}, onError: (Object _) {}));
    // Poll for the second request (first backoff is 2 s) instead of sleeping a
    // fixed time, so a slow machine does not turn this into a flake.
    final deadline = DateTime.now().add(const Duration(seconds: 6));
    while (hits < 2 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(hits, greaterThanOrEqualTo(2),
        reason: 'the unflagged path re-sends after the first backoff');
    expect(events.first, startsWith('edge_function_cold_start_retry:'));
  });
}
