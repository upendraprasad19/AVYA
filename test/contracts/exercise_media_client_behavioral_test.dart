// test/contracts/exercise_media_client_behavioral_test.dart
//
// Batch M2a (plan Task 6): the ONE HTTP class that reads the private exercise-media bucket. A fake `HttpClientAdapter` records
// every request and replays a script, so each case states exactly how many requests the client may make. The letter in
// brackets is the Task 6 Step 4 mutation that case must turn red. A timeout case throws from the fake, because the real
// adapters own the timers; the hanging case runs under `fakeAsync`.
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_client.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_webp.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/webp_fixture.dart';

const _base = 'https://project.example.test';
const _name = '0103-barbell-standing-ab-rollout_v1.webp';
const _route = '$_base/storage/v1/object/authenticated/exercise-media/$_name';

/// One scripted answer of the fake adapter.
sealed class _Step {}

class _Reply extends _Step {
  _Reply(this.status, [this.body]);
  final int status;
  final Uint8List? body;
}

class _Fail extends _Step {
  _Fail(this.make);
  final DioException Function(RequestOptions o) make;
}

class _Hang extends _Step {}

/// A response that reports its receive progress the way a real adapter does while it streams the body. If the request was
/// cancelled by then, the adapter throws the cancel error (real Dio closes the stream and fails the request the same way).
class _Chunked extends _Step {
  _Chunked({required this.received, required this.total, required this.body});
  final int received;
  final int total;
  final Uint8List body;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.script);
  final List<_Step> script;
  final List<RequestOptions> requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    // A request beyond the script answers 599 so an unexpected extra request is visible in `requests.length`.
    final step = requests.length <= script.length ? script[requests.length - 1] : _Reply(599);
    if (step is _Hang) return Completer<ResponseBody>().future;
    if (step is _Fail) throw step.make(options);
    if (step is _Chunked) {
      options.onReceiveProgress?.call(step.received, step.total);
      if (options.cancelToken?.isCancelled ?? false) {
        throw DioException.requestCancelled(requestOptions: options, reason: 'cancelled while receiving');
      }
      return ResponseBody.fromBytes(step.body, 200);
    }
    final r = step as _Reply;
    return ResponseBody.fromBytes(r.body ?? Uint8List(0), r.status);
  }

  @override
  void close({bool force = false}) {}
}

class _Tokens {
  final List<bool> calls = <bool>[];
  String? normal = 'tok-normal';
  String? forced = 'tok-forced';
  bool throwing = false;

  Future<String?> call({bool forceRefresh = false}) async {
    calls.add(forceRefresh);
    if (throwing) throw StateError('token seam failed');
    return forceRefresh ? forced : normal;
  }

  int get forcedCalls => calls.where((c) => c).length;
}

/// Advances [step] on every call.
class _Clock {
  _Clock(this.step);
  final Duration step;
  int _n = 0;
  DateTime call() => DateTime.utc(2026, 1, 1).add(step * (++_n));
}

Uint8List _good([int n = 400, int seed = 1]) => webpBytes(n, seed);

ExerciseMediaClient _client(
  _FakeAdapter adapter,
  _Tokens tokens, {
  bool anonymous = false,
  bool Function()? isAnonymous,
  DateTime Function()? now,
  bool isWeb = false,
}) {
  return ExerciseMediaClient(
    dio: Dio()..httpClientAdapter = adapter,
    tokenProvider: tokens.call,
    isAnonymous: isAnonymous ?? () => anonymous,
    baseUrl: _base,
    now: now ?? _Clock(Duration.zero).call,
    isWeb: isWeb,
  );
}

Future<String> _sessionJson({bool anonymous = false}) async {
  final expiresAt = DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000;
  return jsonEncode(<String, dynamic>{
    'access_token': 'REAL-SESSION-TOKEN',
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
      if (anonymous) 'is_anonymous': true,
    },
  });
}

void main() {
  setUp(() {
    ExerciseMediaClient.resetCooldown();
    SupabaseService.clientOverrideForTest = null;
  });
  tearDown(() {
    SupabaseService.clientOverrideForTest = null;
    ErrorTelemetry.debugOnRecordNonFatalForTests = null;
    ErrorTelemetry.debugOnLogEventForTests = null;
  });

  group('the request', () {
    test('[o] a 200 with a WebP body is fetched; the request is the authenticated route with BOTH headers', () async {
      final body = _good();
      final a = _FakeAdapter([_Reply(200, body)]);
      final r = await _client(a, _Tokens()).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.fetched);
      expect(r.bytes, body);
      expect(r.status, 200);
      expect(a.requests, hasLength(1));
      final o = a.requests.single;
      expect(o.method, 'GET');
      expect(o.uri.toString(), _route);
      expect(o.headers['Authorization'], 'Bearer tok-normal');
      expect(o.headers.containsKey('apikey'), isTrue);
      expect(o.headers['apikey'], AppConstants.supabaseAnonKey);
      expect(o.responseType, ResponseType.bytes);
    });

    test('[j] every request has followRedirects false', () async {
      final a = _FakeAdapter([_Reply(400), _Reply(200, _good())]);
      await _client(a, _Tokens(), now: _Clock(const Duration(seconds: 61)).call).fetch(_name);
      expect(a.requests, hasLength(2));
      for (final o in a.requests) {
        expect(o.followRedirects, isFalse);
      }
    });

    test('[l] web options carry a 120 s receiveTimeout, native 20 s (connectTimeout 10 s on both)', () async {
      final web = _FakeAdapter([_Reply(200, _good())]);
      await _client(web, _Tokens(), isWeb: true).fetch(_name);
      expect(web.requests.single.receiveTimeout, const Duration(seconds: 120));
      expect(web.requests.single.connectTimeout, const Duration(seconds: 10));

      final native = _FakeAdapter([_Reply(200, _good())]);
      await _client(native, _Tokens(), isWeb: false).fetch(_name);
      expect(native.requests.single.receiveTimeout, const Duration(seconds: 20));
      expect(native.requests.single.connectTimeout, const Duration(seconds: 10));
    });

    test('[i] an invalid object name is refused with ZERO requests', () async {
      for (final bad in ['../x_v1.webp', 'a/b_v1.webp', 'A_v1.webp', 'a_v0.webp', 'a.webp', '', 'a_v1.webp?x=1', 'a b_v1.webp']) {
        final a = _FakeAdapter([_Reply(200, _good())]);
        final r = await _client(a, _Tokens()).fetch(bad);
        expect(r.outcome, MediaFetchOutcome.refused, reason: bad);
        expect(a.requests, isEmpty, reason: bad);
      }
    });
  });

  group('auth', () {
    test('400 then 200: exactly two requests, the second after tokenProvider(forceRefresh: true) and carrying the new token [r]', () async {
      final t = _Tokens();
      final a = _FakeAdapter([_Reply(400), _Reply(200, _good())]);
      final r = await _client(a, t).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.fetched);
      expect(a.requests, hasLength(2));
      expect(t.calls, [false, true]);
      expect(a.requests[0].headers['Authorization'], 'Bearer tok-normal');
      expect(a.requests[1].headers['Authorization'], 'Bearer tok-forced');
    });

    test('[a] 400 then 400: exactly two requests, refused (the cooldown does not mask a third attempt)', () async {
      final a = _FakeAdapter([_Reply(400), _Reply(400), _Reply(200, _good())]);
      final r = await _client(a, _Tokens(), now: _Clock(const Duration(seconds: 61)).call).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.refused);
      expect(r.status, 400);
      expect(a.requests, hasLength(2));
    });

    test('a 401 is retried like a 400: two requests, refused', () async {
      final a = _FakeAdapter([_Reply(401), _Reply(401), _Reply(200, _good())]);
      final r = await _client(a, _Tokens(), now: _Clock(const Duration(seconds: 61)).call).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.refused);
      expect(r.status, 401);
      expect(a.requests, hasLength(2));
    });

    test('[c] a second 400 file inside 60 s makes ONE request and no refresh', () async {
      final t = _Tokens();
      final a = _FakeAdapter([_Reply(400), _Reply(400), _Reply(400)]);
      final c = _client(a, t, now: _Clock(const Duration(seconds: 1)).call);
      await c.fetch(_name); // 400 -> forced refresh -> 400: two requests
      expect(a.requests, hasLength(2));
      expect(t.forcedCalls, 1);
      final r = await c.fetch('0104-other_v1.webp'); // inside 60 s: no refresh, no retry
      expect(r.outcome, MediaFetchOutcome.refused);
      expect(a.requests, hasLength(3), reason: 'exactly ONE more request');
      expect(t.forcedCalls, 1, reason: 'no second refresh inside the cooldown');
    });

    test('[bp6] the cooldown is process-wide: a second client INSTANCE inside 60 s makes ONE request and no refresh', () async {
      final t1 = _Tokens();
      final c1 = _client(_FakeAdapter([_Reply(400), _Reply(400)]), t1, now: _Clock(const Duration(seconds: 1)).call);
      await c1.fetch(_name); // 400 -> forced refresh -> 400
      expect(t1.forcedCalls, 1);

      final t2 = _Tokens();
      final a2 = _FakeAdapter([_Reply(400), _Reply(400)]);
      final c2 = _client(a2, t2, now: _Clock(const Duration(seconds: 1)).call);
      final r = await c2.fetch('0104-other_v1.webp');
      expect(r.outcome, MediaFetchOutcome.refused);
      expect(a2.requests, hasLength(1), reason: 'no retry: another instance refreshed 1 s ago');
      expect(t2.forcedCalls, 0);
    });

    test('[bp7] a clock stepped BACK after a forced refresh does not freeze the retry: the next 400 refreshes again', () async {
      final times = <DateTime>[DateTime.utc(2026, 1, 1, 12), DateTime.utc(2026, 1, 1, 11)]; // the second read is an hour EARLIER
      var n = 0;
      DateTime clock() => times[n < times.length ? n++ : times.length - 1];
      final t = _Tokens();
      final a = _FakeAdapter([_Reply(400), _Reply(400), _Reply(400), _Reply(200, _good())]);
      final c = _client(a, t, now: clock);
      await c.fetch(_name); // 400 -> forced refresh (stamped 12:00) -> 400
      expect(t.forcedCalls, 1);
      final r = await c.fetch('0104-other_v1.webp'); // the clock now reads 11:00: the stamp is in the future, so it is expired
      expect(t.forcedCalls, 2, reason: 'a negative difference is not "inside the cooldown"');
      expect(r.outcome, MediaFetchOutcome.fetched);
    });

    test('[q] a null forced token is refused after exactly ONE request', () async {
      final t = _Tokens()..forced = null;
      final a = _FakeAdapter([_Reply(400), _Reply(200, _good())]);
      final r = await _client(a, t).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.refused);
      expect(a.requests, hasLength(1));
    });

    test('[p] a 403 and a 404 are each refused after ONE request (no retry on other 4xx)', () async {
      for (final status in [403, 404]) {
        final t = _Tokens();
        final a = _FakeAdapter([_Reply(status), _Reply(200, _good())]);
        final r = await _client(a, t).fetch(_name);
        expect(r.outcome, MediaFetchOutcome.refused, reason: '$status');
        expect(r.status, status);
        expect(a.requests, hasLength(1), reason: '$status');
        expect(t.forcedCalls, 0, reason: '$status');
      }
    });

    test('[g] a null (or empty) token is unauthenticated with ZERO requests', () async {
      for (final token in <String?>[null, '']) {
        final a = _FakeAdapter([_Reply(200, _good())]);
        final r = await _client(a, _Tokens()..normal = token).fetch(_name);
        expect(r.outcome, MediaFetchOutcome.unauthenticated, reason: '$token');
        expect(a.requests, isEmpty, reason: '$token');
      }
    });

    test('a throwing tokenProvider and a throwing isAnonymous are unauthenticated with ZERO requests', () async {
      final a1 = _FakeAdapter([_Reply(200, _good())]);
      final r1 = await _client(a1, _Tokens()..throwing = true).fetch(_name);
      expect(r1.outcome, MediaFetchOutcome.unauthenticated);
      expect(a1.requests, isEmpty);

      final a2 = _FakeAdapter([_Reply(200, _good())]);
      final r2 = await _client(a2, _Tokens(), isAnonymous: () => throw StateError('anon seam failed')).fetch(_name);
      expect(r2.outcome, MediaFetchOutcome.unauthenticated);
      expect(a2.requests, isEmpty);
    });

    test('[f] an anonymous session (injected seam) is unauthenticated with ZERO requests', () async {
      final a = _FakeAdapter([_Reply(200, _good())]);
      final t = _Tokens();
      final r = await _client(a, t, anonymous: true).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.unauthenticated);
      expect(a.requests, isEmpty);
    });
  });

  group('the DEFAULT seams over SupabaseService.clientOverrideForTest', () {
    Future<SupabaseClient> clientWithSession({bool anonymous = false, bool withSession = true}) async {
      final c = SupabaseClient('http://127.0.0.1:1', 'stub-anon-key');
      if (withSession) await c.auth.setInitialSession(await _sessionJson(anonymous: anonymous));
      return c;
    }

    ExerciseMediaClient defaults(_FakeAdapter a) => ExerciseMediaClient(dio: Dio()..httpClientAdapter = a, baseUrl: _base, isWeb: false);

    test('a real session: one request carrying that session\'s token', () async {
      SupabaseService.clientOverrideForTest = await clientWithSession();
      final a = _FakeAdapter([_Reply(200, _good())]);
      final r = await defaults(a).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.fetched);
      expect(a.requests, hasLength(1));
      expect(a.requests.single.headers['Authorization'], 'Bearer REAL-SESSION-TOKEN');
    });

    test('[f] the same session with is_anonymous true is unauthenticated with ZERO requests', () async {
      SupabaseService.clientOverrideForTest = await clientWithSession(anonymous: true);
      final a = _FakeAdapter([_Reply(200, _good())]);
      final r = await defaults(a).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.unauthenticated);
      expect(a.requests, isEmpty);
    });

    test('no session is unauthenticated with ZERO requests', () async {
      SupabaseService.clientOverrideForTest = await clientWithSession(withSession: false);
      final a = _FakeAdapter([_Reply(200, _good())]);
      final r = await defaults(a).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.unauthenticated);
      expect(a.requests, isEmpty);
    });

    test('[n] with NO override at all (Supabase uninitialised: an AssertionError, which is not an Exception) fetch is unauthenticated and does not throw', () async {
      expect(SupabaseService.clientOverrideForTest, isNull);
      final a = _FakeAdapter([_Reply(200, _good())]);
      final r = await defaults(a).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.unauthenticated);
      expect(a.requests, isEmpty);
    });
  });

  group('what the body and the status mean', () {
    test('[m] a 200 whose body is not a well-formed WebP is refused, with ZERO refreshes', () async {
      final riffx = webpBytes(40, 1)..[3] = 0x58; // RIFX with a consistent size field
      final wrongSize = webpBytes(40, 1)..[4] = 31;
      final bodies = <String, Uint8List>{
        'json error': Uint8List.fromList(utf8.encode('{"error"')),
        'RIFX magic': riffx,
        'empty': Uint8List(0),
        '1,500,001 bytes': webpBytes(1500001, 1),
        'wrong RIFF size': wrongSize,
      };
      for (final e in bodies.entries) {
        final t = _Tokens();
        final a = _FakeAdapter([_Reply(200, e.value), _Reply(200, _good())]);
        final r = await _client(a, t).fetch(_name);
        expect(r.outcome, MediaFetchOutcome.refused, reason: e.key);
        expect(r.status, 200, reason: e.key);
        expect(a.requests, hasLength(1), reason: e.key);
        expect(t.forcedCalls, 0, reason: '${e.key}: a 200 never triggers a refresh');
      }
    });

    test('[k] a 500 is unreachable and a 418 is refused; [u] the results carry their status', () async {
      final a500 = _FakeAdapter([_Reply(500)]);
      final r500 = await _client(a500, _Tokens()).fetch(_name);
      expect(r500.outcome, MediaFetchOutcome.unreachable);
      expect(r500.status, 500);

      final a418 = _FakeAdapter([_Reply(418)]);
      final r418 = await _client(a418, _Tokens()).fetch(_name);
      expect(r418.outcome, MediaFetchOutcome.refused);
      expect(r418.status, 418);

      final a400 = _FakeAdapter([_Reply(400), _Reply(400)]);
      final r400 = await _client(a400, _Tokens(), now: _Clock(const Duration(seconds: 61)).call).fetch(_name);
      expect(r400.status, 400);
    });

    test('a connection error and a thrown receive timeout are unreachable with a null status', () async {
      for (final make in <DioException Function(RequestOptions)>[
        (o) => DioException.connectionError(requestOptions: o, reason: 'no route'),
        (o) => DioException.receiveTimeout(timeout: const Duration(seconds: 20), requestOptions: o),
        (o) => DioException.connectionTimeout(timeout: const Duration(seconds: 10), requestOptions: o),
      ]) {
        final r = await _client(_FakeAdapter([_Fail(make)]), _Tokens()).fetch(_name);
        expect(r.outcome, MediaFetchOutcome.unreachable);
        expect(r.status, isNull);
      }
    });

    test('[s] a 302 is refused after ONE request; a 204 and a 100 are refused too', () async {
      for (final status in [302, 204, 100]) {
        final a = _FakeAdapter([_Reply(status), _Reply(200, _good())]);
        final r = await _client(a, _Tokens()).fetch(_name);
        expect(r.outcome, MediaFetchOutcome.refused, reason: '$status');
        expect(a.requests, hasLength(1), reason: '$status');
      }
    });

    test('[t] a badCertificate and a cancel DioException are unreachable', () async {
      for (final make in <DioException Function(RequestOptions)>[
        (o) => DioException.badCertificate(requestOptions: o),
        (o) => DioException.requestCancelled(requestOptions: o, reason: 'cancelled'),
      ]) {
        final r = await _client(_FakeAdapter([_Fail(make)]), _Tokens()).fetch(_name);
        expect(r.outcome, MediaFetchOutcome.unreachable);
      }
    });
  });

  group('time and secrets', () {
    test('[h] a request that never completes: fetch returns unreachable after 60 s and the request\'s CancelToken is cancelled', () {
      fakeAsync((async) {
        final a = _FakeAdapter([_Hang()]);
        final c = _client(a, _Tokens());
        MediaFetchResult? result;
        c.fetch(_name).then((r) => result = r);
        // Dio schedules its dispatch with a zero-duration timer, which flushMicrotasks alone does not run.
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        expect(a.requests, hasLength(1));
        expect(result, isNull, reason: 'still waiting');
        async.elapse(const Duration(seconds: 61));
        expect(result?.outcome, MediaFetchOutcome.unreachable);
        expect(a.requests.single.cancelToken?.isCancelled, isTrue);
      });
    });

    test('[bp8] on WEB there is no 60 s whole-fetch cap (the xhr carries its own, 130 s): a request still pending after 61 s is not cancelled', () {
      fakeAsync((async) {
        final a = _FakeAdapter([_Hang()]);
        final c = _client(a, _Tokens(), isWeb: true);
        MediaFetchResult? result;
        c.fetch(_name).then((r) => result = r);
        async.flushMicrotasks();
        async.elapse(const Duration(milliseconds: 1));
        expect(a.requests, hasLength(1));
        async.elapse(const Duration(seconds: 61));
        expect(result, isNull, reason: 'web waits for the xhr cap, not for the native 60 s bound');
        expect(a.requests.single.cancelToken?.isCancelled, isFalse);
      });
    });

    test('[bp9] a body that reports more than the WebP size cap is cancelled while it streams and refused, with NO retry', () async {
      final t = _Tokens();
      final a = _FakeAdapter([_Chunked(received: kMaxWebpBytes + 1, total: -1, body: _good())]);
      final r = await _client(a, t).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.refused);
      expect(a.requests, hasLength(1));
      expect(a.requests.single.cancelToken?.isCancelled, isTrue);
      expect(t.forcedCalls, 0);
    });

    test('[bp9b] a declared length over the cap cancels it as well, before a single byte counts', () async {
      final a = _FakeAdapter([_Chunked(received: 10, total: kMaxWebpBytes + 1, body: _good())]);
      final r = await _client(a, _Tokens()).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.refused);
      expect(a.requests.single.cancelToken?.isCancelled, isTrue);
    });

    test('[bp9c] the mirror: a body that reports exactly the cap is NOT cancelled and is fetched', () async {
      final a = _FakeAdapter([_Chunked(received: kMaxWebpBytes, total: kMaxWebpBytes, body: _good())]);
      final r = await _client(a, _Tokens()).fetch(_name);
      expect(r.outcome, MediaFetchOutcome.fetched);
      expect(a.requests.single.cancelToken?.isCancelled, isFalse);
    });

    test('[e] the token is never logged: no occurrence of the sentinel, "Authorization" or the full URL in debugPrint or telemetry', () async {
      const sentinel = 'SENTINEL-TOKEN-123';
      final captured = <String>[];
      final oldPrint = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => captured.add(m ?? '');
      ErrorTelemetry.debugOnRecordNonFatalForTests = (error, stack, {required reason, extra}) => captured.add('$error $reason $extra');
      ErrorTelemetry.debugOnLogEventForTests = (opType, {message}) => captured.add('$opType $message');
      addTearDown(() => debugPrint = oldPrint);

      // POSITIVE CONTROL (B-pass): the three capture hooks really capture. Without it this case would also pass if a hook were
      // never installed.
      debugPrint('control-print');
      await ErrorTelemetry.recordNonFatal(StateError('control-error'), StackTrace.current, reason: 'control-reason');
      await ErrorTelemetry.logEvent('control_op', message: 'control-message');
      expect(captured.join('\n'), allOf(contains('control-print'), contains('control-error'), contains('control_op control-message')));

      // A throwing adapter (a connection error whose own text carries the URL) and a 500, both with the sentinel token.
      for (final step in <_Step>[_Fail((o) => DioException.connectionError(requestOptions: o, reason: 'boom')), _Reply(500), _Reply(400), _Reply(400)]) {
        ExerciseMediaClient.resetCooldown();
        final t = _Tokens()
          ..normal = sentinel
          ..forced = sentinel;
        await _client(_FakeAdapter([step, step]), t, now: _Clock(const Duration(seconds: 61)).call).fetch(_name);
      }
      final joined = captured.join('\n');
      expect(joined.contains(sentinel), isFalse);
      expect(joined.contains('Authorization'), isFalse);
      expect(joined.contains(_route), isFalse);
      expect(joined.contains('/storage/v1/object'), isFalse);
    });
  });
}
