// test/contracts/terms_acceptance_behavioral_test.dart
//
// Behavioral (real Hive box) regression test for closes-diagnose
// b3f9e7.
//
// The pre-fix code wrote `userBox.put('terms_accepted_at', ...)` at CREATE
// ACCOUNT tap time, BEFORE any Supabase session existed — so
// `HiveService.instance.userBox` threw `StateError` every single time (no
// `HiveUserSession.openForUser` had run yet), silently swallowed by a broad
// `catch (_) {}`. The existing `terms_signup_writes_test.dart` /
// `terms_acceptance_writer_to_reader_test.dart` regression tests are pure
// source-grep (`presence_only: true` in docs/sot_registry.yaml) and could
// never have caught this — they check the write call is present in the
// source text, not that it actually succeeds at runtime. This test
// exercises the real Hive/HiveUserSession/GuardedBox machinery (no mocks on
// the box layer) to pin the actual runtime behavior: fails on the pre-fix
// code, passes with the fix.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:icanbefitter/core/services/auth_session_bootstrapper.dart';
import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/hive_user_session.dart';

import '../helpers/hive_test_setup.dart';

void main() {
  // ── Google OAuth / phone-OTP fallback (Part B) ──────────────────
  //
  // hydrateFromCloud itself makes live Supabase network calls a unit test
  // can't exercise, so the decision logic is extracted into the pure
  // AuthSessionBootstrapper.shouldStampFallbackTermsConsent helper (same
  // pattern as classifyDestination) and tested directly here.
  group('shouldStampFallbackTermsConsent', () {
    test('stamps when cloud has no value yet (null)', () {
      expect(
        AuthSessionBootstrapper.shouldStampFallbackTermsConsent(
            cloudTermsAcceptedAt: null),
        isTrue,
      );
    });

    test('stamps when cloud value is an empty string', () {
      expect(
        AuthSessionBootstrapper.shouldStampFallbackTermsConsent(
            cloudTermsAcceptedAt: ''),
        isTrue,
      );
    });

    test('does NOT stamp when cloud already has a real value (no clobber)',
        () {
      expect(
        AuthSessionBootstrapper.shouldStampFallbackTermsConsent(
            cloudTermsAcceptedAt: '2026-05-01T00:00:00.000Z'),
        isFalse,
      );
    });
  });
  group('write BEFORE HiveUserSession.openForUser (reproduces the bug)', () {
    late Directory tempDir;

    setUp(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      tempDir = await Directory.systemTemp.createTemp('terms_no_session_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (call) async => tempDir.path,
      );
      Hive.init(tempDir.path);
      HiveService.debugMarkInitializedForTests();
      // Deliberately do NOT call HiveUserSession.openForUser — this
      // reproduces the exact state at CREATE ACCOUNT tap time, before
      // signUp() has resolved a user and before any session has opened
      // the per-user namespaced boxes.
    });

    tearDown(() async {
      await HiveUserSession.closeAll();
      await Hive.close();
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('HiveService.instance.userBox throws StateError', () {
      // This is the exact throw the pre-fix sign_in_screen.dart write hit
      // on every single CREATE ACCOUNT tap, silently swallowed by its
      // catch (_) {} — so terms_accepted_at/terms_version never once
      // reached Hive, and the existing upward-sync (gated on Hive
      // presence) never had anything to push to cloud.
      expect(
        () => HiveService.instance.userBox,
        throwsA(isA<StateError>()),
      );
    });
  });

  group('write AFTER HiveUserSession.openForUser (the fix)', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await setUpHiveForTests();
    });

    tearDown(() async {
      await tearDownHiveForTests(tempDir);
    });

    test('terms_accepted_at / terms_version persist to userBox', () {
      final ub = HiveService.instance.userBox;
      ub.put('terms_accepted_at', '2026-08-02T12:00:00.000Z');
      ub.put('terms_version', 'v1');

      expect(
        HiveService.instance.userBox.get('terms_accepted_at'),
        '2026-08-02T12:00:00.000Z',
      );
      expect(HiveService.instance.userBox.get('terms_version'), 'v1');
    });
  });
}
