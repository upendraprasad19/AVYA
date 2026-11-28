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
        // Dart 3 class modifiers (sdk: ^3.11.1) — `sealed`, `base`, `final`,
        // `interface`, `mixin`, and `abstract base` are all valid prefixes. The
        // first version matched only `abstract`, so an owner declared with any
        // other modifier would fail to match and the backward walk would
        // silently misattribute the field to an EARLIER plain `class`. Not
        // triggered today (all three owners are plain `class`), which is
        // exactly why it needed catching by reading rather than by a red test.
        final m = RegExp(
          r'^(?:(?:abstract|base|final|interface|sealed|mixin)\s+)*class\s+(\w+)',
        ).firstMatch(lines[j]);
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

    test('BEHAVIOURAL: a cleared callback stays cleared — nothing re-arms it, '
        'which is why sign-out must not clear it', () {
      // This is the P0 from review round 1, expressed as a state transition
      // rather than as prose. `app.dart` initState is the only installer and it
      // runs ONCE per process, so "cleared" is terminal for the app's lifetime.
      SubscriptionService.onStateChanged = () {};
      NutritionWriteService.onStateChanged = () {};
      RankService.onStateChanged = () {};

      // Simulate what the first version of unbindSessionIdentity() did.
      SubscriptionService.onStateChanged = null;
      NutritionWriteService.onStateChanged = null;
      RankService.onStateChanged = null;

      // Simulate a subsequent sign-in: _ensureLocalUser runs, nothing else.
      // (Verified: `grep -rn "onStateChanged = " lib/` finds installs ONLY in
      // app.dart initState — never in the auth provider.)
      expect(SubscriptionService.onStateChanged, isNull,
          reason: 'a sign-in does NOT restore it, so a PRO write after the '
              'second sign-in would not invalidate subscriptionInfoProvider '
              '(APK Test #12.2 — PRO pill stuck showing FREE)');
      expect(NutritionWriteService.onStateChanged, isNull,
          reason: 'APK Test #12.4 — "I logged breakfast, it showed meal saved, '
              'but nothing got updated in UI"');
      expect(RankService.onStateChanged, isNull,
          reason: 'OI-37 — rank promotion writes cloud but UI shows stale rank');
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

    test('the sign-out path reaches unbindSessionIdentity()', () {
      // UPDATED 2026-08-09 (diagnose b7e4c1, B-pass finding 1): signOut() is
      // now a join-or-start dispatcher and the teardown lives in _teardown(),
      // so the old "slice to the next `\n  Future<`" span stops at
      // _performSignOut and can no longer see the call. It failed on a MOVE,
      // not a regression.
      //
      // The invariant is unchanged and is what this still pins: sign-out must
      // REACH the unbind. Asserting the chain link-by-link keeps that true —
      // a call sitting in a method nobody invokes is exactly the dead code
      // this test exists to prevent.
      final signOutIdx = src.indexOf('Future<void> signOut()');
      expect(signOutIdx, greaterThan(0), reason: 'signOut must exist');
      final performIdx = src.indexOf('Future<void> _performSignOut()');
      expect(performIdx, greaterThan(0),
          reason: 'signOut delegates to _performSignOut');
      final teardownIdx = src.indexOf('Future<void> _teardown()');
      expect(teardownIdx, greaterThan(0),
          reason: '_performSignOut delegates to _teardown');

      expect(src.substring(signOutIdx, performIdx), contains('_performSignOut()'),
          reason: 'signOut() must actually invoke _performSignOut');
      expect(src.substring(performIdx, teardownIdx), contains('_teardown()'),
          reason: '_performSignOut must actually invoke _teardown');

      final end = src.indexOf('\n  Future<', teardownIdx + 10);
      final teardown =
          src.substring(teardownIdx, end > teardownIdx ? end : src.length);
      expect(teardown, contains('unbindSessionIdentity()'),
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

    test('REGRESSION GUARD: sign-out must NOT clear the static callbacks', () {
      // The inverse of what this test originally asserted, because the original
      // assertion was WRONG and shipped a P0. Review round 1 (2026-07-27):
      //
      //   `app.dart:45/59/76` (initState) is the ONLY install site in lib/, and
      //   ICanBeFitterApp is constructed once per process, so initState runs
      //   ONCE for the app's lifetime. `_ensureLocalUser` never re-installs.
      //   Nulling the callbacks on sign-out therefore kills provider
      //   invalidation permanently for every later sign-in in the same process
      //   — silently, because every call site uses `onStateChanged?.call()`.
      //   That reintroduces APK #12.2, #12.4 and OI-37.
      //
      // OI-51's sub-finding 4 asks for this clear on the premise that the
      // closure "captures Riverpod state". It captures the ConsumerState `ref`,
      // bound to the process-lived ProviderScope, not to a user — so there is
      // no cross-account leak to close and the correct number of clears on the
      // sign-out path is ZERO.
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
        expect(body, isNot(contains('$owner.onStateChanged = null')),
            reason: 'sign-out clears $owner.onStateChanged, but nothing '
                're-installs it — app.dart initState runs once per PROCESS. '
                'Every subsequent sign-in in this session loses that provider '
                'invalidation silently. Clear it in app.dart dispose() instead.');
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

    test('DERIVED: every .auth.signOut( call site in lib/ reaches '
        'releaseDeviceSessionIdentity()', () {
      // Round 2 found this list was WRONG in the most embarrassing way: the
      // previous version of this test hard-coded TWO paths (main.dart and
      // delete_account_screen). `grep "\.auth\.signOut("` finds FIVE. A
      // closed list written by the same person who missed the sites is not a
      // check -- so the set is now computed from the tree.
      //
      // The five: AuthNotifier.signOut, _ensureLocalUser's cross-account-guard
      // force-signout, reset_password_screen, delete_account_screen, and
      // perform_sign_out's defensive fallback (which runs precisely BECAUSE the
      // notifier path failed, possibly before reaching the unbind).
      final sites = <String, List<int>>{};
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final lines = _strip(f.readAsStringSync()).split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (RegExp(r'\.auth\s*\.?\s*$').hasMatch(lines[i]) ||
              lines[i].contains('.auth.signOut(') ||
              (lines[i].contains('.signOut(') && lines[i].contains('auth'))) {
            sites.putIfAbsent(f.path, () => []).add(i + 1);
          }
        }
      }

      expect(sites.length, greaterThanOrEqualTo(4),
          reason: 'found sign-out sites in only ${sites.length} files — the '
              'enumerator is probably broken, not the tree');

      final missing = <String>[];
      sites.forEach((path, lineNos) {
        final src = _strip(File(path).readAsStringSync());
        // The auth provider DEFINES the release function, so it trivially
        // contains the name; require an actual invocation instead.
        final invocations =
            RegExp(r'await releaseDeviceSessionIdentity\(\)').allMatches(src).length;
        if (invocations == 0) missing.add('$path (sign-out at $lineNos)');
      });

      expect(missing, isEmpty,
          reason: 'these files end a session but never release the device '
              'identity: ${missing.join(", ")}');
    });

    test('every unbind step is individually try/caught', () {
      // The two plugin calls now live in the top-level
      // releaseDeviceSessionIdentity(), which is what the extra session-ending
      // paths call — so that is where the per-step guarding has to hold. It is
      // invoked from a zone handler (main.dart), where an escaping throw would
      // be especially bad.
      final idx = src.indexOf('Future<void> releaseDeviceSessionIdentity()');
      expect(idx, greaterThan(0),
          reason: 'the extracted top-level release function must exist');
      final body = src.substring(idx, idx + 1200);
      // Two plugin calls, each in its own try — a single shared try would let
      // a OneSignal failure skip the Crashlytics clear and the callback reset.
      expect('try {'.allMatches(body).length, greaterThanOrEqualTo(2),
          reason: 'sign-out must complete even if a third-party SDK throws; '
              'this mirrors signOut()\'s existing per-step shape');
    });
  });
}
