import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Source-of-truth contract: writer/reader pairs for `user_full_name`
/// from docs/sot_registry.yaml.
///
/// Writers: onboarding_provider.completeOnboarding,
///          edit_profile_screen._save (calls syncProfileNow after update)
/// Readers: sync_service._restoreUserProfile (SELECTs from 'users' table),
///          home_provider.userGreetingProvider,
///          ai_coach_repository.buildAiContext (user.name field)
///
/// CRITICAL: full_name lives on users table (not user_profile).
/// _restoreUserProfile MUST SELECT from 'users' table separately.
/// Bug: APK Test #12.8 / Bug #2 — greeting rendered "USER" because
/// _restoreUserProfile only joined user_profile (no full_name column).
///
/// Forbidden: from.*user_profile.*select.*full_name (wrong table)
void main() {
  late String syncSvcSrc;
  late String homeProvSrc;
  late String onboardingProvSrc;

  setUpAll(() {
    final sf = File('lib/core/services/sync_service.dart');
    expect(sf.existsSync(), isTrue, reason: 'sync_service.dart must exist');
    syncSvcSrc = sf.readAsStringSync();

    final hf = File('lib/features/home/providers/home_provider.dart');
    expect(hf.existsSync(), isTrue, reason: 'home_provider.dart must exist');
    homeProvSrc = hf.readAsStringSync();

    final of =
        File('lib/features/onboarding/providers/onboarding_provider.dart');
    expect(of.existsSync(), isTrue,
        reason: 'onboarding_provider.dart must exist (completeOnboarding writer)');
    onboardingProvSrc = of.readAsStringSync();
  });

  group('user_full_name writer↔reader source contract', () {
    test('writer completeOnboarding exists in onboarding_provider', () {
      expect(onboardingProvSrc.contains('completeOnboarding'), isTrue,
          reason: 'onboarding_provider must define completeOnboarding (first full_name writer)');
    });

    test('writer completeOnboarding writes full_name to profile', () {
      expect(onboardingProvSrc.contains('full_name'), isTrue,
          reason:
              'completeOnboarding must write full_name to the profile map '
              'which then syncs to users.full_name cloud column');
    });

    test('reader _restoreUserProfile exists in sync_service', () {
      expect(syncSvcSrc.contains('_restoreUserProfile'), isTrue,
          reason:
              '_restoreUserProfile must exist in sync_service; '
              'reads full_name from \'users\' table on cross-device restore');
    });

    test('reader _restoreUserProfile SELECTs from users table (not just user_profile)', () {
      // APK Test #12.8 bug: restore only read user_profile which has no full_name
      // Fix: _restoreUserProfile must also JOIN/SELECT from 'users' table
      final restoreBody = _methodBody(syncSvcSrc, '_restoreUserProfile');
      expect(
          restoreBody.contains("'users'") || restoreBody.contains('"users"'),
          isTrue,
          reason:
              "_restoreUserProfile must SELECT from 'users' table for full_name + email; "
              "user_profile has no full_name column — this was the 'USER' greeting bug in APK #12.8");
    });

    test('reader userGreetingProvider exists in home_provider', () {
      expect(homeProvSrc.contains('userGreetingProvider'), isTrue,
          reason:
              'home_provider must define userGreetingProvider which reads full_name '
              'from userBox profile map');
    });

    test('edit_profile_screen calls syncProfileNow after save', () {
      final ef =
          File('lib/features/profile/screens/edit_profile_screen.dart');
      if (!ef.existsSync()) return;
      final src = ef.readAsStringSync();
      expect(
          src.contains('syncProfileNow') || src.contains('syncProfile'),
          isTrue,
          reason:
              'edit_profile_screen._save must call syncProfileNow() after updating full_name; '
              'without this, cloud profile stays stale and AI coach loses user name context');
    });

    test('forbidden: _restoreUserProfile does NOT query user_profile for full_name', () {
      // The forbidden anti-pattern: trying to get full_name from user_profile table
      // (it doesn't exist there — APK #12.8 root cause)
      final pattern =
          RegExp(r"from.*user_profile.*select.*full_name", caseSensitive: false);
      expect(pattern.hasMatch(syncSvcSrc), isFalse,
          reason:
              'sync_service._restoreUserProfile must not try to SELECT full_name '
              "from user_profile — full_name is on the 'users' table only");
    });
  });
}

String _methodBody(String src, String methodName) {
  final pattern = RegExp(
      r'Future<void>\s+' + methodName + r'\s*\([^)]*\)\s*async\s*\{');
  final match = pattern.firstMatch(src);
  if (match == null) return '';
  final start = match.end - 1;
  var depth = 1;
  var i = start + 1;
  while (i < src.length && depth > 0) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') depth--;
    i++;
  }
  return src.substring(start, i);
}
