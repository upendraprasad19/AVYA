import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/shared/repositories/user_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `assess-body-composition` refuses with a status and a `code`.
/// `functions.invoke` THROWS on any non-2xx answer, so the old
/// `response.status != 200` branch could never run and every refusal read as
/// "Assessment failed". This drives the real repository method over real HTTP
/// against a loopback server.
void main() {
  late HttpServer server;
  late int status;
  late Map<String, Object?> body;

  setUp(() async {
    HttpOverrides.global = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      await req.drain<void>();
      req.response.statusCode = status;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(body));
      await req.response.close();
    });
    final client =
        SupabaseClient('http://127.0.0.1:${server.port}', 'stub-anon-key');
    await client.auth.setInitialSession(jsonEncode(<String, dynamic>{
      'access_token': 'stub-access-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'expires_at': DateTime.now()
              .add(const Duration(hours: 1))
              .millisecondsSinceEpoch ~/
          1000,
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
    await server.close(force: true);
  });

  Future<Map<String, dynamic>> assess() => UserRepository.assessBodyComposition(
        imageBase64: 'AQID',
        mimeType: 'image/jpeg',
        weightKg: 75,
        heightCm: 175,
        gender: 'male',
        age: 30,
      ).timeout(const Duration(seconds: 10));

  test('rate_limited carries the next allowed date', () async {
    status = 429;
    body = {
      'error': 'Body composition can only be assessed once every 30 days.',
      'code': 'rate_limited',
      'next_allowed_at': '2026-12-20T10:00:00.000Z',
    };
    await expectLater(
      assess(),
      throwsA(isA<BodyCompositionAssessmentException>()
          .having((e) => e.code, 'code', 'rate_limited')
          .having((e) => e.status, 'status', 429)
          .having((e) => e.nextAllowedAt, 'nextAllowedAt',
              '2026-12-20T10:00:00.000Z')),
    );
  });

  test('unsuitable_image carries the function\'s own message', () async {
    status = 422;
    body = {'error': 'Photo not suitable.', 'code': 'unsuitable_image'};
    await expectLater(
      assess(),
      throwsA(isA<BodyCompositionAssessmentException>()
          .having((e) => e.code, 'code', 'unsuitable_image')
          .having((e) => e.message, 'message', 'Photo not suitable.')),
    );
  });

  test('pro_required is a refusal too', () async {
    status = 403;
    body = {'error': 'PRO required', 'code': 'pro_required'};
    await expectLater(
      assess(),
      throwsA(isA<BodyCompositionAssessmentException>()
          .having((e) => e.code, 'code', 'pro_required')),
    );
  });

  test('mirror: a server error stays a FunctionException (no raw text shown)',
      () async {
    status = 500;
    body = {'error': 'Internal server error', 'request_id': 'abc'};
    await expectLater(
      assess(),
      throwsA(isA<FunctionException>().having((e) => e.status, 'status', 500)),
    );
  });

  test('mirror: a code the function never sends is not read as its refusal',
      () async {
    status = 400;
    body = {'code': 'BOOT_ERROR', 'message': 'worker failed to boot'};
    await expectLater(assess(), throwsA(isA<FunctionException>()));
  });

  test('a success returns the result', () async {
    status = 200;
    body = {'bf_low': 16, 'bf_high': 20, 'assessed_at': 'now'};
    expect(await assess(), body);
  });
}
