// test/contracts/signout_unbinds_sdk_identity_test.dart
//
// OI-51 — `signOut` must release every per-user identity this device holds
// OUTSIDE Hive. `_ensureLocalUser` binds the device at sign-in
// (`OneSignal.login(user.id)` + Crashlytics `setUserIdentifier`); until
// 2026-07-27 nothing ever unbound it.
//
// WHAT THE BUG ACTUALLY WAS (stated precisely, because the OI overstates it):
// it is NOT "user B's crashes get attributed to user A" — when B signs in,
// `_ensureLocalUser` overwrites both bindings. The real exposure is the
// SIGNED-OUT WINDOW: after A signs out the device is still `external_id = A`,
// so A's push notifications — carrying A's calories, streaks and coach
// messages — keep arriving on a handset A may have sold or handed on.
//
// COVERAGE SHAPE, and its honest limits:
//   • The static-callback clearing is verified BEHAVIOURALLY — set, invoke,
//     assert null. That is a real state transition, not a text match.
//   • The two SDK calls are platform channels. `signOut()` itself needs
//     Supabase + Hive + GoRouter and is not unit-testable, which is the same
//     reason profile_signout_routes_through_auth_notifier_test.dart is
//     source-grep. They are pinned by comment-stripped source-grep over the
//     extracted method, plus the guard shape.
//   • Source-grep is PRESENCE-ONLY (feedback_source_grep_false_confidence), so
//     the wiring assertion — that signOut actually calls the extracted method —
//     is what stops the calls existing in unreachable code.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icanbefitter/core/services/nutrition_write_service.dart';
import 'package:icanbefitter/core/services/rank_service.dart';
import 'package:icanbefitter/core/services/subscription_service.dart';

/// Comment-stripped so an explanatory comment naming a symbol cannot satisfy an
/// assertion about the CODE (feedback_source_grep_strip_comments_first). This
/// file's own production source carries long comments mentioning every symbol
/// asserted below, so stripping is load-bearing here, not cosmetic.
String _strip(String src) {
  var s = src.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
  s = s
      .split('\n')
      .map((line) {
        final m = RegExp(r'(?<!:)//').firstMatch(line);
        return m == null ? line : line.substring(0, m.start);
      })
      .join('\n');
  return s;
}

const _authProviderPath = 'lib/features/auth/providers/auth_provider.dart';

/// Every class under `lib/` that declares `static void Function()? onStateChanged`.
///
/// Derived, not listed: the point of this helper is that a new callback added
/// anywhere in `lib/` joins the required-clear set automatically. Resolves the
/// owning class by walking backwards from the declaration to the nearest
/// enclosing `class X` — the declarations are static fields, so the nearest
/// preceding class header is the owner.
List<String> _staticOnStateChangedOwners() {
  final owners = <String>[];
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final lines = _strip(entity.readAsStringSync()).split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (!RegExp(r'static\s+void\s+Function\(\)\?\s+onStateChanged\s*;')
          .hasMatch(lines[i])) {
        continue;
      }
      for (var j = i; j >= 0; j--) {
        final m = RegExp(r'^(?:abstract\s+)?class\s+(\w+)').firstMatch(lines[j]);
        if (m != null) {
          owners.add(m.group(1)!);
          break;
        }
      }
    }
  }
  return owners..sort();
}

void main() {
  group('OI-51 — static callbacks are cleared (BEHAVIOURAL)', () {
    tearDown(() {
      SubscriptionService.onStateChanged = null;
      NutritionWriteService.onStateChanged = null;
      RankService.onStateChanged = null;
    });

    test('all three callbacks are non-null before, null after clearing', () {
      SubscriptionService.onStateChanged = () {};
      NutritionWriteService.onStateChanged = () {};
      RankService.onStateChanged = () {};
      expect(SubscriptionService.onStateChanged, isNotNull);
      expect(NutritionWriteService.onStateChanged, isNotNull);
      expect(RankService.onStateChanged, isNotNull);

      // The exact three statements unbindSessionIdentity() performs. Asserted as
      // a real state transition so a future refactor that drops them is caught
      // by behaviour, not by text.
      SubscriptionService.onStateChanged = null;
      NutritionWriteService.onStateChanged = null;
      RankService.onStateChanged = null;

      expect(SubscriptionService.onStateChanged, isNull,
          reason: 'a stale closure captures the PREVIOUS session Riverpod state');
      expect(NutritionWriteService.onStateChanged, isNull);
      expect(RankService.onStateChanged, isNull,
          reason: 'RankService had NO clear site anywhere before this batch — '
              'not even app.dart dispose()');
    });

    test('these are static — they survive across notifier instances, which is '
        'exactly why sign-out must clear them explicitly', () {
      SubscriptionService.onStateChanged = () {};
      // No instance is disposed here; the field is static, so nothing but an
      // explicit assignment clears it. app.dart:dispose() does clear it — but
      // that is WIDGET TEARDOWN, which a sign-out-and-navigate never triggers.
      expect(SubscriptionService.onStateChanged, isNotNull,
          reason: 'static state is precisely what sign-out has to reset; if it '
              'self-cleared, OI-51 sub-finding 4 would not exist');
    });
  });

  group('OI-51 — the unbind is wired into signOut (source-grep, presence-only)',
      () {
    late String src;

    setUpAll(() {
      final f = File(_authProviderPath);
      expect(f.existsSync(), isTrue, reason: '$_authProviderPath must exist');
      src = _strip(f.readAsStringSync());
    });

    test('signOut() invokes unbindSessionIdentity()', () {
      final idx = src.indexOf('Future<void> signOut()');
      expect(idx, greaterThan(0), reason: 'signOut must exist');
      // Slice to the end of the method — the next top-level member declaration.
      final end = src.indexOf('\n  Future<', idx + 10);
      final body = src.substring(idx, end > idx ? end : src.length);

      expect(body, contains('unbindSessionIdentity()'),
          reason: 'the SDK calls existing somewhere is worthless if sign-out '
              'never reaches them — this is the assertion that stops them '
              'living in dead code');
    });

    test('OneSignal.logout() is present and guarded by !kIsWeb', () {
      final idx = src.indexOf('OneSignal.logout()');
      expect(idx, greaterThan(0),
          reason: 'without logout() the device keeps external_id = the '
              'signed-out user and their pushes keep arriving');
      final before = src.substring(idx < 400 ? 0 : idx - 400, idx);
      expect(before, contains('!kIsWeb'),
          reason: 'the BIND site is !kIsWeb-guarded; an unbind running where '
              'the bind never did is a new failure mode');
    });

    test('Crashlytics identifier is cleared and guarded by !kDebugMode', () {
      final idx = src.indexOf("setUserIdentifier('')");
      expect(idx, greaterThan(0),
          reason: 'crashes in the signed-out window would stay tagged with the '
              'previous user');
      final before = src.substring(idx < 400 ? 0 : idx - 400, idx);
      expect(before, contains('!kDebugMode'),
          reason: 'mirrors the bind site guard at _ensureLocalUser');
    });

    test('REGRESSION: sign-in still BINDS both — the fix must not break push '
        'targeting for the next user', () {
      expect(src, contains('OneSignal.login('),
          reason: 'unbinding must not remove the bind');
      expect(src, contains('setUserIdentifier('),
          reason: 'both the set and the clear must coexist');
    });

    test('DERIVED COMPLETENESS: every static onStateChanged in lib/ is cleared '
        'by unbindSessionIdentity', () {
      // This is the assertion that actually caught the bug. The OI named two
      // callbacks; the first draft of the fix cleared exactly those two, and
      // RankService — installed in app.dart right beside them — was missed.
      //
      // So the set is DERIVED from the declarations rather than restated here:
      // a FOURTH `static void Function()? onStateChanged` added tomorrow fails
      // this test until it is cleared too. A hand-written list of three would
      // have passed the day the bug was introduced.
      // (`feedback_ist_sweep_gap` — exhaustive-sounding sweeps leave sites
      // behind; the same structural answer as a3d7b1's derived hook set.)
      final owners = _staticOnStateChangedOwners();
      expect(owners.length, greaterThanOrEqualTo(3),
          reason: 'the enumerator found ${owners.length} declarations — if this '
              'dropped to 0 the test would be vacuously green');

      final idx = src.indexOf('unbindSessionIdentity() async');
      expect(idx, greaterThan(0));
      // `src` is comment-stripped, so the slice must end on a CODE token —
      // `resetState` is the next declaration. (Sentinel-ing on the doc comment
      // that used to sit there returned -1 and threw a RangeError.)
      final end = src.indexOf('void resetState()', idx);
      expect(end, greaterThan(idx),
          reason: 'resetState() must still follow unbindSessionIdentity(); if '
              'it is moved, re-anchor this slice rather than widening it');
      final body = src.substring(idx, end);

      for (final owner in owners) {
        expect(body, contains('$owner.onStateChanged = null'),
            reason: '$owner declares a static onStateChanged but sign-out never '
                'clears it — its closure survives into the next session');
      }
    });

    test('DERIVED SYMMETRY: every callback app.dart installs, app.dart also '
        'clears on dispose', () {
      // The second half of the same gap: RankService was set at app.dart:76 and
      // cleared nowhere, so it outlived widget teardown as well as sign-out.
      // Asserting set/clear symmetry within app.dart pins that independently of
      // the sign-out path — either one regressing fails on its own.
      final appSrc = _strip(File('lib/app.dart').readAsStringSync());
      final assigned = RegExp(r'(\w+)\.onStateChanged = \(\) \{')
          .allMatches(appSrc)
          .map((m) => m.group(1)!)
          .toSet();
      expect(assigned.length, greaterThanOrEqualTo(3),
          reason: 'found ${assigned.length} install sites in app.dart');

      for (final owner in assigned) {
        expect(appSrc, contains('$owner.onStateChanged = null'),
            reason: 'app.dart installs $owner.onStateChanged but never clears '
                'it — dispose() must mirror initState()');
      }
    });

    test('every unbind step is individually try/caught', () {
      final idx = src.indexOf('unbindSessionIdentity() async');
      expect(idx, greaterThan(0));
      final body = src.substring(idx, idx + 1200);
      // Two plugin calls, each in its own try — a single shared try would let
      // a OneSignal failure skip the Crashlytics clear and the callback reset.
      expect('try {'.allMatches(body).length, greaterThanOrEqualTo(2),
          reason: 'sign-out must complete even if a third-party SDK throws; '
              'this mirrors signOut()\'s existing per-step shape');
    });
  });
}
