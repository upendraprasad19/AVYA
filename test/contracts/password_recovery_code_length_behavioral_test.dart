// Behavioral regression test for diagnose fa621a — the password-reset code field
// must accept whatever code the hosted project issues. It also closes OI-109:
// until this file existed, ForgotPasswordSheet's two-step flow (email -> code ->
// verifyOTP -> /reset) had no test at all.
//
// THE INCIDENT (2026-10-03): the hosted Supabase project was configured to email
// 8-digit recovery codes (`mailer_otp_length`, a dashboard setting). The sheet's
// code field had `maxLength: 6` with the counter hidden, so digits 7-8 were
// silently dropped, and `_verifyCode` rejected anything not exactly 6 long. No
// code attempt ever reached GoTrue (auth logs: one POST /recover, zero /verify).
// diagnose c9e2b7 had hard-coded "6-digit" from Supabase's own docs and never
// read the setting. GoTrue clamps the setting to 6-10 and zero-pads, so the
// contract is: digits only, a floor of 6, NO ceiling.
//
// THE DISCRIMINATOR is the 8-digit case. On the old sheet `enterText('12345678')`
// leaves the field holding `123456` and the /verify body carries that truncated
// token; asserting the field text AND the exact request token makes truncation
// (maxLength) and rejection (the length guard) fail for different reasons.
//
// THE REST OF THE FILE is the B-pass (docs/reviews/auth-recovery-code-length-
// bpass.md): the first version of the fix left the sheet able to be dismissed
// mid-request, to send twice on a double tap, to pop the page underneath it, and
// to refuse a code carrying a character the user cannot see. Each of those has a
// case here that was written against the broken behaviour.
//
// HARNESS: every widget case gets its own recording SupabaseClient through the
// existing `SupabaseService.clientOverrideForTest` seam. It is built in `setUp`
// (the real zone) and disposed in `tearDown` — NEVER inside the testWidgets body:
// the client constructor spawns a real isolate, and inside the FakeAsync zone
// `dispose()` then never completes (plan-review round 2, R2-1). `Supabase
// .initialize` is deliberately not used: it is a one-shot singleton, so cases
// after the first would silently reuse the first case's client and requests.
// `autoRefreshToken: false` keeps GoTrue's periodic refresh timer out of the zone.
//
// Characters the user cannot see are built from code points, never typed: a
// literal U+200B in this file would be invisible to the next reader, which is
// the bug class under test.
//
// The two mid-animation cases are LAST in the widget group on purpose: against a
// broken sheet they leave the navigator unusable and a performance-mode request
// undisposed, which fails whatever testWidgets case runs next.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:icanbefitter/core/router/app_router.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
import 'package:icanbefitter/core/utils/recovery_code_format.dart';
import 'package:icanbefitter/features/auth/widgets/forgot_password_sheet.dart';

const _email = 'recruit@example.com';
const _otherEmail = 'second@example.com';
const _jsonHeaders = {'content-type': 'application/json'};

/// A session-bearing GoTrue `/verify` response. Round 1 and 2 of the plan review
/// confirmed `Session` parsing does not decode the JWT eagerly.
final _sessionJson = jsonEncode({
  'access_token': 'fake-access-token',
  'token_type': 'bearer',
  'expires_in': 3600,
  'refresh_token': 'fake-refresh-token',
  'user': {
    'id': 'fake-user-id',
    'aud': 'authenticated',
    'email': _email,
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
  },
});

/// A GoTrue error body, the shape an `AuthApiException` is parsed from.
String _err(int code, String errorCode, String msg) =>
    jsonEncode({'code': code, 'error_code': errorCode, 'msg': msg});

/// PKCE's `resetPasswordForEmail` writes a code verifier to async storage, so a
/// client built without Supabase.initialize must be given one.
class _MemoryStorage extends GotrueAsyncStorage {
  final Map<String, String> _items = {};

  /// When set, the next write waits for it and then throws a NON-Auth error.
  /// GoTrue stores the PKCE verifier before it posts /recover, so this is the
  /// only way to reach `_send`'s generic catch while the sheet is still on
  /// screen (a missing client reaches it too, but synchronously).
  Completer<void>? failWritesAfter;

  @override
  Future<String?> getItem({required String key}) async => _items[key];

  @override
  Future<void> setItem({required String key, required String value}) async {
    final gate = failWritesAfter;
    if (gate != null) {
      await gate.future;
      throw StateError('disk full (test)');
    }
    _items[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _items.remove(key);
  }
}

/// The router of the case under test, so a case can ask where it ended up.
GoRouter? _router;

Widget _harness() {
  final router = _router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (ctx, _) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => ForgotPasswordSheet.show(ctx),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ),
      // Placeholder: the real ResetPasswordScreen reads Supabase.instance, which
      // this file deliberately never initialises.
      GoRoute(
        path: '/reset',
        builder: (_, _) => const Scaffold(body: Text('RESET PLACEHOLDER')),
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

Future<void> _pumpSome(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 25));
  }
}

Future<void> _openSheet(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_harness());
  await tester.pump();
  await tester.tap(find.text('OPEN'));
  await tester.pumpAndSettle();
}

Future<void> _goToCodeStep(WidgetTester tester) async {
  await _openSheet(tester);
  await tester.enterText(find.byType(TextField), _email);
  await tester.tap(find.text('SEND CODE'));
  await _pumpSome(tester);
}

/// Types [typed] into the code field and taps VERIFY CODE.
Future<void> _submitCode(WidgetTester tester, String typed) async {
  await tester.enterText(find.byType(TextField), typed);
  await tester.tap(find.text('VERIFY CODE'));
  await _pumpSome(tester);
}

String _fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

/// The input type the focused field announced to the platform text-input
/// channel — what the soft keyboard is actually told, not what the widget holds.
Object? _platformInputType(WidgetTester tester) {
  final inputType = tester.testTextInput.setClientArgs?['inputType'];
  return inputType is Map ? inputType['name'] : null;
}

/// Taps the modal barrier — the same dismissal as a swipe-down or a back press.
Future<void> _tapBarrier(WidgetTester tester) =>
    tester.tapAt(const Offset(10, 10));

String _cp(int codePoint) => String.fromCharCode(codePoint);

String _u(int codePoint) =>
    'U+${codePoint.toRadixString(16).toUpperCase().padLeft(4, '0')}';

/// Source with whole-line comments removed — the sheet keeps a comment that
/// quotes the OLD button label, and a pin must not trip on prose.
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  group('normalizeRecoveryCode — removes what the user cannot see, nothing else',
      () {
    // Every one of these is invisible in a text field, so the user can neither
    // spot nor delete it. Separators (Z*), controls (Cc) and format characters
    // (Cf): a copy-paste out of a mail client or chat app can carry any of them.
    final invisible = <int, String>{
      0x0009: 'CHARACTER TABULATION',
      0x000A: 'LINE FEED',
      0x000D: 'CARRIAGE RETURN',
      0x0020: 'SPACE',
      0x0085: 'NEXT LINE',
      0x00A0: 'NO-BREAK SPACE',
      0x00AD: 'SOFT HYPHEN',
      0x200B: 'ZERO WIDTH SPACE',
      0x200C: 'ZERO WIDTH NON-JOINER',
      0x200D: 'ZERO WIDTH JOINER',
      0x200E: 'LEFT-TO-RIGHT MARK',
      0x200F: 'RIGHT-TO-LEFT MARK',
      0x2028: 'LINE SEPARATOR',
      0x2029: 'PARAGRAPH SEPARATOR',
      0x202E: 'RIGHT-TO-LEFT OVERRIDE',
      0x202F: 'NARROW NO-BREAK SPACE',
      0x2060: 'WORD JOINER',
      0x3000: 'IDEOGRAPHIC SPACE',
      0xFEFF: 'ZERO WIDTH NO-BREAK SPACE (BOM)',
    };

    for (final e in invisible.entries) {
      test('${_u(e.key)} ${e.value}: gone at the start, in the middle and at '
          'the end', () {
        final c = _cp(e.key);
        expect(normalizeRecoveryCode('${c}12345678'), '12345678');
        expect(normalizeRecoveryCode('1234${c}5678'), '12345678');
        expect(normalizeRecoveryCode('12345678$c'), '12345678');
      });
    }

    // The mirror: VISIBLE junk must survive, so the shape check can refuse it
    // and the user can see what to fix. Stripping every non-digit would turn
    // `12a45678` into a different, valid-looking code and send it.
    for (final s in const [
      '12a45678',
      '+12345678',
      '1234-5678',
      '1234.5678',
      '１２３４５６', // full-width digits
      '१२३४५६', // Devanagari digits
      '00123456', // a leading zero is part of the code
      '',
    ]) {
      test('visible ${jsonEncode(s)} is left exactly as typed', () {
        expect(normalizeRecoveryCode(s), s);
      });
    }

    test('an input made ONLY of invisible characters becomes empty, which the '
        'shape check then refuses', () {
      final onlyInvisible = invisible.keys.map(_cp).join();
      expect(normalizeRecoveryCode(onlyInvisible), '');
      expect(isPlausibleRecoveryCode(normalizeRecoveryCode(onlyInvisible)),
          isFalse);
    });
  });

  group('isPlausibleRecoveryCode — digits only, floor 6, no ceiling', () {
    const accept = [
      '123456',
      '00123456', // GoTrue zero-pads: a leading zero is a legal code
      '12345678',
      '1234567890',
      '123456789012', // no ceiling: never the client's job to cap the length
    ];
    // The caller normalizes first; this predicate itself stays strict, so a
    // space or a newline that reaches it is refused.
    const reject = [
      '12345', // below GoTrue's floor
      '',
      '+12345', // int.tryParse used to accept these three
      '-123456',
      '0x1234',
      '123 456',
      '123456\n',
      '12a45678',
      '１２３４５６', // full-width digits
      '१२३४५६', // Devanagari digits
    ];

    test('the floor is 6 (GoTrue never issues fewer)', () {
      expect(kRecoveryCodeMinLength, 6);
    });

    for (final c in accept) {
      test('accepts ${jsonEncode(c)}', () {
        expect(isPlausibleRecoveryCode(c), isTrue);
      });
    }
    for (final c in reject) {
      test('rejects ${jsonEncode(c)}', () {
        expect(isPlausibleRecoveryCode(c), isFalse);
      });
    }
  });

  group('source pins (presence-only; the behavioral cases below are the proof)',
      () {
    // "6-digit code", "6 digit OTP", "six-digit PIN"... — a count word next to
    // OTP/code/PIN. Deliberately not a bare "digit": a phone-NUMBER hint may
    // legitimately say how long a phone number is.
    final digitCount = RegExp(
        r'(\d+|six|seven|eight|nine|ten)[ -]?digit\s+(otp|code|pin)',
        caseSensitive: false);

    for (final path in const [
      'lib/features/auth/widgets/forgot_password_sheet.dart',
      'lib/features/auth/screens/reset_password_screen.dart',
      'lib/features/auth/screens/sign_in_screen.dart',
    ]) {
      test('$path states no OTP/recovery digit count', () {
        expect(digitCount.hasMatch(_code(path)), isFalse);
      });
    }

    test('the sheet has no hint literal, no stale "reset link", no maxLength',
        () {
      final src = _code('lib/features/auth/widgets/forgot_password_sheet.dart');
      expect(src.contains("'123456'"), isFalse);
      expect(src.contains('reset link'), isFalse);
      expect(src.contains('maxLength'), isFalse,
          reason: 'a maxLength on the code field is the silent-drop failure');
    });
  });

  group('ForgotPasswordSheet — the recovery-code flow (OI-109)', () {
    late List<http.Request> requests;
    late _MemoryStorage storage;
    // Nullable on purpose: if setUp throws before assigning it, tearDown must
    // not raise a second error that masks the first.
    SupabaseClient? client;

    // When set, the matching endpoint answers only once the Completer does, so a
    // case can act (dismiss the sheet, tap again) while the request is in flight.
    Completer<http.Response>? recoverGate;
    Completer<http.Response>? verifyGate;

    setUp(() {
      requests = <http.Request>[];
      recoverGate = null;
      verifyGate = null;
      storage = _MemoryStorage();
      _router = null;
      AppRouter.isPasswordRecovery = false;
      client = SupabaseClient(
        'https://fake-project.supabase.co',
        'fake-anon-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          final path = request.url.path;
          if (path.endsWith('/auth/v1/recover')) {
            final gate = recoverGate;
            if (gate != null) return gate.future;
            return http.Response('{}', 200, headers: _jsonHeaders);
          }
          if (path.endsWith('/auth/v1/verify')) {
            final gate = verifyGate;
            if (gate != null) return gate.future;
            return http.Response(_sessionJson, 200, headers: _jsonHeaders);
          }
          return http.Response('{}', 404, headers: _jsonHeaders);
        }),
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: storage,
        ),
      );
      SupabaseService.clientOverrideForTest = client;
    });

    tearDown(() async {
      SupabaseService.clientOverrideForTest = null;
      AppRouter.isPasswordRecovery = false;
      await client?.dispose();
    });

    Iterable<http.Request> hits(String suffix) =>
        requests.where((r) => r.url.path.endsWith(suffix));

    Map<String, dynamic> bodyOf(http.Request r) =>
        jsonDecode(r.body) as Map<String, dynamic>;

    group('the two steps', () {
      testWidgets('send step -> exactly one /recover, then the code step names '
          'the address and states no digit count', (tester) async {
        await _goToCodeStep(tester);

        expect(hits('/auth/v1/recover'), hasLength(1));
        expect(bodyOf(hits('/auth/v1/recover').single)['email'], _email);
        expect(find.text('VERIFY CODE'), findsOneWidget,
            reason: 'the sheet advanced to the code step. The address finder '
                'below also matches the email field\'s own text, so it cannot '
                'prove that on its own');
        expect(find.text('SEND CODE'), findsNothing);
        expect(find.textContaining(_email), findsOneWidget,
            reason: 'the code step confirms where the code was sent');
        expect(find.textContaining('digit'), findsNothing,
            reason: 'the digit count belongs to a hosted setting the client '
                'cannot read — stating one is how this incident happened');
        expect(find.text('123456'), findsNothing,
            reason: 'the hint must not imply a length either');
        expect(
          find.byWidgetPredicate(
              (w) => w is Text && RegExp(r'\d{4,}').hasMatch(w.data ?? '')),
          findsNothing,
          reason: 'no visible text may carry a run of 4+ digits: that is how a '
              'placeholder such as 123456 or 000000 implies a code length',
        );
      });

      testWidgets('a padded email is trimmed on the wire and in the copy',
          (tester) async {
        await _openSheet(tester);
        await tester.enterText(find.byType(TextField), '  $_email  ');
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);

        final recovers = hits('/auth/v1/recover').toList();
        expect(recovers, hasLength(1));
        expect(bodyOf(recovers.single)['email'], _email,
            reason: 'a mobile keyboard appends a space after autocomplete');
        expect(find.textContaining('sent a code to $_email.'), findsOneWidget);
      });

      for (final typed in ['', 'not-an-email']) {
        testWidgets('the email ${jsonEncode(typed)} is refused locally and a '
            'good one still works afterwards', (tester) async {
          await _openSheet(tester);
          if (typed.isNotEmpty) {
            await tester.enterText(find.byType(TextField), typed);
          }
          await tester.tap(find.text('SEND CODE'));
          await _pumpSome(tester);

          expect(hits('/auth/v1/recover'), isEmpty,
              reason: 'an address without @ must not leave the device');
          expect(find.text('Enter a valid email.'), findsOneWidget);
          expect(find.text('SEND CODE'), findsOneWidget,
              reason: 'a locally refused email must leave the button live');

          await tester.enterText(find.byType(TextField), _email);
          await tester.tap(find.text('SEND CODE'));
          await _pumpSome(tester);
          expect(hits('/auth/v1/recover'), hasLength(1));
          expect(find.text('VERIFY CODE'), findsOneWidget);
        });
      }
    });

    group('the code a user can type', () {
      for (final code in [
        '123456',
        '12345678',
        '1234567890',
        '123456789012',
        '00123456',
      ]) {
        testWidgets('a ${code.length}-digit code "$code" is typed intact and '
            'reaches /verify unchanged', (tester) async {
          await _goToCodeStep(tester);
          expect(AppRouter.isPasswordRecovery, isFalse,
              reason: 'the flag is static — it must start false so the '
                  'success case below cannot pass vacuously');

          await tester.enterText(find.byType(TextField), code);
          expect(_fieldText(tester), code,
              reason: 'TRUNCATION: today\'s maxLength: 6 leaves the field '
                  'holding the first 6 digits of an 8-digit code');

          await tester.tap(find.text('VERIFY CODE'));
          await _pumpSome(tester);

          final verifies = hits('/auth/v1/verify').toList();
          expect(verifies, hasLength(1),
              reason: 'REJECTION: a length guard that refuses this code sends '
                  'no request at all');
          final body = bodyOf(verifies.single);
          expect(body['token'], code,
              reason: 'the exact string the user typed — a leading zero must '
                  'survive, so it is never parsed to an int');
          expect(body['type'], 'recovery');
          expect(body['email'], _email);
        });
      }

      testWidgets('there is no ceiling: a 10,000-digit paste reaches /verify '
          'whole', (tester) async {
        final huge = '1' * 10000;
        await _goToCodeStep(tester);
        await _submitCode(tester, huge);

        final verifies = hits('/auth/v1/verify').toList();
        expect(verifies, hasLength(1),
            reason: 'NO CEILING, by design (fa621a): a cap only catches an '
                'over-long typo and turns a future change of the hosted setting '
                'into a silent lockout again. The server refuses a wrong code '
                'with its own message.');
        expect(bodyOf(verifies.single)['token'], huge);
      });

      for (final entry in {
        'a code that is too short': '12345',
        'letters': 'abcdefgh',
        'a letter inside the digits': '12a45678',
        'a leading plus': '+12345678',
        'a visible hyphen': '1234-5678',
        'only invisible characters': '${_cp(0x200B)} ${_cp(0x00A0)}',
      }.entries) {
        testWidgets('${entry.key} is refused locally: no /verify, a plain '
            'message', (tester) async {
          await _goToCodeStep(tester);

          await _submitCode(tester, entry.value);

          expect(hits('/auth/v1/verify'), isEmpty);
          expect(find.text('Enter the code from your email.'), findsOneWidget);
        });
      }
    });

    group('a pasted code', () {
      // Whitespace and invisible characters anywhere in a paste are removed, so
      // /verify carries the bare code. The shape check is strict, so the
      // normalization is the ONLY thing that lets any of these through.
      final pastes = <(String, String, String)>[
        ('padded with spaces', '  12345678 ', '12345678'),
        (
          'wrapped in a no-break space, a newline and a tab',
          '${_cp(0x00A0)}12345678\n\t',
          '12345678',
        ),
        (
          'wrapped in ideographic spaces and a byte-order mark',
          '${_cp(0x3000)}${_cp(0xFEFF)}12345678${_cp(0x3000)}',
          '12345678',
        ),
        (
          'a trailing zero-width space after 6 digits (the old maxLength: 6 '
              'field silently cut it off; the first version of this fix '
              'refused the whole code)',
          '123456${_cp(0x200B)}',
          '123456',
        ),
        (
          'a zero-width space inside the code',
          '1234${_cp(0x200B)}5678',
          '12345678',
        ),
        ('shown in two groups with a space', '1234 5678', '12345678'),
        (
          'grouped with a narrow no-break space',
          '123${_cp(0x202F)}456',
          '123456',
        ),
      ];

      for (final (label, typed, sent) in pastes) {
        testWidgets('$label -> /verify carries "$sent"', (tester) async {
          await _goToCodeStep(tester);

          await _submitCode(tester, typed);

          final verifies = hits('/auth/v1/verify').toList();
          expect(verifies, hasLength(1));
          expect(bodyOf(verifies.single)['token'], sent);
        });
      }
    });

    group('going back and sending again', () {
      testWidgets('a DIFFERENT address after back: the copy and /verify use '
          'the new one', (tester) async {
        await _goToCodeStep(tester);
        await tester.tap(find.byKey(const ValueKey('auth-header-back')));
        await _pumpSome(tester);
        expect(find.text('SEND CODE'), findsOneWidget,
            reason: 'back returned to the email step');

        await tester.enterText(find.byType(TextField), _otherEmail);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(hits('/auth/v1/recover'), hasLength(2));
        expect(find.text('VERIFY CODE'), findsOneWidget);
        expect(find.textContaining(_otherEmail), findsOneWidget);
        expect(find.textContaining(_email), findsNothing,
            reason: 'the old address must not linger in the copy');

        await _submitCode(tester, '12345678');
        final verifies = hits('/auth/v1/verify').toList();
        expect(verifies, hasLength(1));
        expect(bodyOf(verifies.single)['email'], _otherEmail,
            reason: 'the code was sent to the NEW address, so that is the one '
                'it must be verified against');
      });

      testWidgets('back returns to the email step, keeps the address editable '
          'and drops a code-step error and the typed code', (tester) async {
        await _goToCodeStep(tester);
        await _submitCode(tester, '12345');
        expect(find.text('Enter the code from your email.'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('auth-header-back')));
        await _pumpSome(tester);

        expect(find.text('Reset password'), findsOneWidget);
        expect(find.text('SEND CODE'), findsOneWidget);
        expect(find.text('Enter the code from your email.'), findsNothing,
            reason: 'a code-step error must not follow the user to the email '
                'step');
        expect(_fieldText(tester), _email,
            reason: 'the mistyped address stays editable');

        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(_fieldText(tester), '',
            reason: 'a fresh code step starts with an empty code field');
      });
    });

    group('failures with the sheet still on screen', () {
      testWidgets('a rejected code: GoTrue\'s own wording, the typed code kept, '
          'the button live, and a retry goes out', (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        expect(find.text('VERIFYING…'), findsOneWidget,
            reason: 'in flight, the button says so');

        verifyGate!.complete(http.Response(
            _err(403, 'otp_expired', 'Token has expired or is invalid'), 403,
            headers: _jsonHeaders));
        await _pumpSome(tester);

        expect(find.text('Token has expired or is invalid'), findsOneWidget,
            reason: 'the server\'s wording is the whole point of this branch');
        expect(find.textContaining('Could not verify'), findsNothing,
            reason: 'an AuthException must not fall into the generic branch');
        expect(_fieldText(tester), '12345678',
            reason: 'a server error must not eat what the user typed');
        expect(find.text('VERIFY CODE'), findsOneWidget,
            reason: 'the button is live again');
        expect(find.text('VERIFYING…'), findsNothing);

        verifyGate = null;
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        expect(hits('/auth/v1/verify'), hasLength(2),
            reason: 'a retry after a failure goes out');
        expect(find.text('RESET PLACEHOLDER'), findsOneWidget);
      });

      testWidgets('a rejected send: the message, the address kept, the button '
          'live, and a retry goes out', (tester) async {
        await _openSheet(tester);
        recoverGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(find.text('SENDING…'), findsOneWidget);

        recoverGate!.complete(http.Response(
            _err(429, 'over_email_send_rate_limit', 'Email rate limit exceeded'),
            429,
            headers: _jsonHeaders));
        await _pumpSome(tester);

        expect(find.text('Email rate limit exceeded'), findsOneWidget);
        expect(find.text('SEND CODE'), findsOneWidget,
            reason: 'the button is live again');
        expect(find.text('SENDING…'), findsNothing);
        expect(_fieldText(tester), _email);

        recoverGate = null;
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(hits('/auth/v1/recover'), hasLength(2));
        expect(find.text('VERIFY CODE'), findsOneWidget);
      });

      testWidgets('a locally refused code leaves the button live: a good code '
          'in the same session goes through', (tester) async {
        await _goToCodeStep(tester);
        await _submitCode(tester, '12345');
        expect(hits('/auth/v1/verify'), isEmpty);
        expect(find.text('VERIFY CODE'), findsOneWidget);

        await _submitCode(tester, '12345678');
        expect(hits('/auth/v1/verify'), hasLength(1));
        expect(find.text('RESET PLACEHOLDER'), findsOneWidget);
      });

      testWidgets('a non-Auth failure on /verify: the generic line, the typed '
          'code kept, the button live', (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);

        // A body that is not a session: parsing it throws a plain error, which
        // is not an AuthException and so reaches the generic catch.
        verifyGate!.complete(http.Response('[]', 200, headers: _jsonHeaders));
        await _pumpSome(tester);

        expect(find.textContaining('Could not verify that code'),
            findsOneWidget);
        expect(find.text('VERIFY CODE'), findsOneWidget);
        expect(_fieldText(tester), '12345678');
        expect(AppRouter.isPasswordRecovery, isFalse,
            reason: 'a failed verify must never raise the recovery flag');
      });

      testWidgets('a non-Auth failure on /recover: the generic line, the '
          'address kept, the button live', (tester) async {
        await _openSheet(tester);
        storage.failWritesAfter = Completer<void>();
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(find.text('SENDING…'), findsOneWidget,
            reason: 'precondition: the write is still pending');

        storage.failWritesAfter!.complete();
        await _pumpSome(tester);

        expect(find.textContaining('Could not send the code'), findsOneWidget);
        expect(find.textContaining('link'), findsNothing,
            reason: 'c9e2b7 replaced the emailed link with a typed code; the '
                'failure copy still said "reset link"');
        expect(find.text('SEND CODE'), findsOneWidget);
        expect(_fieldText(tester), _email);
      });

      testWidgets('a missing client names the CODE, never a "link"',
          (tester) async {
        // No client at all: SupabaseService.client throws a non-Auth error (this
        // file never initialises Supabase), which reaches the sheet's generic
        // catch. Tests run with kDebugMode, so the debug string renders.
        SupabaseService.clientOverrideForTest = null;
        await _openSheet(tester);
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);

        expect(find.textContaining('Could not send'), findsOneWidget);
        expect(find.textContaining('link'), findsNothing,
            reason: 'c9e2b7 replaced the emailed link with a typed code; the '
                'failure copy still said "reset link"');
      });
    });

    group('controls while a request is in flight', () {
      testWidgets('two taps on SEND CODE inside one frame send ONE email',
          (tester) async {
        await _openSheet(tester);
        recoverGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await tester.tap(find.text('SEND CODE')); // no pump in between
        await _pumpSome(tester);

        expect(hits('/auth/v1/recover'), hasLength(1),
            reason: 'the button only goes inert on the NEXT build; a second '
                '/recover burns the hosted email quota');
      });

      testWidgets('two taps on VERIFY CODE inside one frame spend the code '
          'ONCE', (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await tester.tap(find.text('VERIFY CODE')); // no pump in between
        await _pumpSome(tester);

        expect(hits('/auth/v1/verify'), hasLength(1),
            reason: 'the code is single-use: a second verifyOTP would fail '
                'and could report a confusing error over a good session');
      });

      testWidgets('a tap on the in-flight SENDING… button sends nothing more',
          (tester) async {
        await _openSheet(tester);
        recoverGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(find.text('SENDING…'), findsOneWidget);

        await tester.tap(find.text('SENDING…'));
        await _pumpSome(tester);

        expect(hits('/auth/v1/recover'), hasLength(1));
      });

      testWidgets('a tap on the in-flight VERIFYING… button sends nothing more',
          (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        expect(find.text('VERIFYING…'), findsOneWidget);

        await tester.tap(find.text('VERIFYING…'));
        await _pumpSome(tester);

        expect(hits('/auth/v1/verify'), hasLength(1));
      });

      testWidgets('Cancel does nothing while a send is in flight',
          (tester) async {
        await _openSheet(tester);
        recoverGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(ForgotPasswordSheet), findsOneWidget);
      });

      testWidgets('Cancel does nothing while a verify is in flight',
          (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(find.byType(ForgotPasswordSheet), findsOneWidget);
      });

      testWidgets('the back arrow is gone while a request is in flight, so the '
          'step cannot flip under it', (tester) async {
        await _openSheet(tester);
        expect(find.byKey(const ValueKey('auth-header-back')), findsOneWidget,
            reason: 'precondition: the arrow exists when nothing is in flight');
        recoverGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(find.text('SENDING…'), findsOneWidget);
        expect(find.byKey(const ValueKey('auth-header-back')), findsNothing);

        recoverGate!.complete(http.Response('{}', 200, headers: _jsonHeaders));
        await _pumpSome(tester);

        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        expect(find.text('VERIFYING…'), findsOneWidget);
        expect(find.byKey(const ValueKey('auth-header-back')), findsNothing,
            reason: 'AuthHeader hides the arrow while onBack is null');
      });
    });

    group('the field the user types into', () {
      testWidgets('the keyboard follows the step: email, then numeric',
          (tester) async {
        await _openSheet(tester);
        await tester.showKeyboard(find.byType(TextField));
        expect(tester.widget<TextField>(find.byType(TextField)).keyboardType,
            TextInputType.emailAddress);
        expect(_platformInputType(tester), 'TextInputType.emailAddress');

        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        await tester.showKeyboard(find.byType(TextField));

        expect(tester.widget<TextField>(find.byType(TextField)).keyboardType,
            TextInputType.number,
            reason: 'a code is typed on a number pad');
        expect(_platformInputType(tester), 'TextInputType.number',
            reason: 'the platform must be told, not just the widget tree');
      });

      testWidgets('the code field takes focus when the code step opens',
          (tester) async {
        await _goToCodeStep(tester);

        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.focusNode.hasFocus, isTrue,
            reason: 'the user is mid-flow: the keyboard must stay up');
      });

      testWidgets('the email field takes focus again after back',
          (tester) async {
        await _goToCodeStep(tester);
        await tester.tap(find.byKey(const ValueKey('auth-header-back')));
        await _pumpSome(tester);

        final editable = tester.widget<EditableText>(find.byType(EditableText));
        expect(editable.focusNode.hasFocus, isTrue);
      });

      testWidgets('each step gets a NEW field element', (tester) async {
        await _openSheet(tester);
        final first = find.byType(TextField).evaluate().single;
        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);

        final second = find.byType(TextField).evaluate().single;

        expect(identical(first, second), isFalse,
            reason: 'one element reused across the steps would keep the old '
                'controller\'s selection and focus state');
      });
    });

    group('the hand-off to /reset', () {
      testWidgets('a good code sets the recovery flag and lands on /reset',
          (tester) async {
        await _goToCodeStep(tester);
        expect(AppRouter.isPasswordRecovery, isFalse);

        await _submitCode(tester, '12345678');

        final verifies = hits('/auth/v1/verify').toList();
        expect(verifies, hasLength(1));
        expect(bodyOf(verifies.single)['token'], '12345678',
            reason: 'with maxLength 6 this flow still ends on /reset, but with '
                'a truncated token; the whole code must be what was verified');
        expect(AppRouter.isPasswordRecovery, isTrue,
            reason: '/reset gates on this flag (reset_password_screen)');
        expect(find.text('RESET PLACEHOLDER'), findsOneWidget,
            reason: 'router.go(/reset) after the sheet pops');
      });

      testWidgets('the hand-off REPLACES the stack and leaves no sheet behind',
          (tester) async {
        await _goToCodeStep(tester);

        await _submitCode(tester, '12345678');
        await tester.pumpAndSettle();

        expect(find.text('RESET PLACEHOLDER'), findsOneWidget);
        expect(_router!.canPop(), isFalse,
            reason: 'go, not push: back from /reset must not return to a '
                'signed-in sign-in page');
        expect(find.byType(ForgotPasswordSheet), findsNothing);
        expect(find.text('VERIFY CODE'), findsNothing);
      });
    });

    group('dismissing the sheet while a request is in flight', () {
      testWidgets('/verify succeeding after the sheet is gone still hands off '
          'to /reset: the code is single-use and the session exists',
          (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();

        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        expect(hits('/auth/v1/verify'), hasLength(1),
            reason: 'precondition: the request is in flight');

        await _tapBarrier(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ForgotPasswordSheet), findsNothing,
            reason: 'precondition: the sheet really is gone');

        verifyGate!
            .complete(http.Response(_sessionJson, 200, headers: _jsonHeaders));
        await _pumpSome(tester);

        expect(AppRouter.isPasswordRecovery, isTrue,
            reason: 'an unmounted-sheet early return used to skip this, '
                'leaving a user with a recovery session who was never asked '
                'for a new password');
        expect(find.text('RESET PLACEHOLDER'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('/verify rejecting the code after the sheet is gone throws '
          'nothing', (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();

        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        await _tapBarrier(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ForgotPasswordSheet), findsNothing);

        verifyGate!.complete(http.Response(
            _err(403, 'otp_expired', 'Token has expired or is invalid'), 403,
            headers: _jsonHeaders));
        await _pumpSome(tester);

        expect(tester.takeException(), isNull,
            reason: 'setState on a disposed State throws');
        expect(AppRouter.isPasswordRecovery, isFalse);
      });

      testWidgets('/verify failing in a non-Auth way after the sheet is gone '
          'throws nothing', (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();

        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        await _tapBarrier(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ForgotPasswordSheet), findsNothing);

        verifyGate!.complete(http.Response('[]', 200, headers: _jsonHeaders));
        await _pumpSome(tester);

        expect(tester.takeException(), isNull);
        expect(AppRouter.isPasswordRecovery, isFalse);
      });

      testWidgets('/recover rejecting the email after the sheet is gone throws '
          'nothing', (tester) async {
        await _openSheet(tester);
        recoverGate = Completer<http.Response>();

        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        expect(hits('/auth/v1/recover'), hasLength(1),
            reason: 'precondition: the request is in flight');
        await _tapBarrier(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ForgotPasswordSheet), findsNothing);

        recoverGate!.complete(http.Response(
            _err(429, 'over_email_send_rate_limit', 'Email rate limit exceeded'),
            429,
            headers: _jsonHeaders));
        await _pumpSome(tester);

        expect(tester.takeException(), isNull,
            reason: 'setState on a disposed State throws');
      });

      testWidgets('/recover failing in a non-Auth way after the sheet is gone '
          'throws nothing', (tester) async {
        await _openSheet(tester);
        storage.failWritesAfter = Completer<void>();

        await tester.enterText(find.byType(TextField), _email);
        await tester.tap(find.text('SEND CODE'));
        await _pumpSome(tester);
        await _tapBarrier(tester);
        await tester.pumpAndSettle();
        expect(find.byType(ForgotPasswordSheet), findsNothing);

        storage.failWritesAfter!.complete();
        await _pumpSome(tester);

        expect(tester.takeException(), isNull);
      });

      // ---- LAST on purpose: see the header comment. ----

      testWidgets('/verify succeeding while the sheet is MID exit animation '
          'hands off to /reset without popping the page underneath',
          (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);
        expect(hits('/auth/v1/verify'), hasLength(1),
            reason: 'precondition: the request is in flight');

        await _tapBarrier(tester);
        await tester.pump(const Duration(milliseconds: 40));
        expect(find.byType(ForgotPasswordSheet), findsOneWidget,
            reason: 'precondition: the State is still MOUNTED while its route '
                'is already popped — `mounted` is not "the sheet is still '
                'ours"');

        verifyGate!
            .complete(http.Response(_sessionJson, 200, headers: _jsonHeaders));
        await _pumpSome(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull,
            reason: 'pop() here takes the only page off the stack: go_router '
                'asserts "You have popped the last page off of the stack"');
        expect(AppRouter.isPasswordRecovery, isTrue);
        expect(find.text('RESET PLACEHOLDER'), findsOneWidget,
            reason: 'the user must still be asked for a new password');
        expect(_router!.routeInformationProvider.value.uri.path, '/reset');
        expect(find.byType(ForgotPasswordSheet), findsNothing);
      });

      testWidgets('/verify rejecting the code while the sheet is MID exit '
          'animation throws nothing and leaves the page intact',
          (tester) async {
        await _goToCodeStep(tester);
        verifyGate = Completer<http.Response>();
        await tester.enterText(find.byType(TextField), '12345678');
        await tester.tap(find.text('VERIFY CODE'));
        await _pumpSome(tester);

        await _tapBarrier(tester);
        await tester.pump(const Duration(milliseconds: 40));

        verifyGate!.complete(http.Response(
            _err(403, 'otp_expired', 'Token has expired or is invalid'), 403,
            headers: _jsonHeaders));
        await _pumpSome(tester);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('RESET PLACEHOLDER'), findsNothing);
        expect(find.byType(Scaffold), findsOneWidget,
            reason: 'the page underneath is intact');
        expect(AppRouter.isPasswordRecovery, isFalse);
      });
    });
  });
}
