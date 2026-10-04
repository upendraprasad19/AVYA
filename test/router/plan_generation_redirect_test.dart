import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

/// Verifies that the _authRedirect logic in app_router.dart includes
/// '/plan-generation' in the onboarding-bypass set.
///
/// Without this, a not-yet-onboarded user navigating to /plan-generation
/// would be immediately redirected back to /onboarding by the auth guard,
/// breaking the graduation → plan-generation flow.
void main() {
  late String routerSource;

  setUpAll(() {
    final file = File('lib/core/router/app_router.dart');
    expect(file.existsSync(), isTrue, reason: 'app_router.dart must exist');
    routerSource = file.readAsStringSync();
  });

  group('AN-1 — /plan-generation auth redirect', () {
    test('isOnOnboarding check includes /plan-generation', () {
      expect(
        routerSource,
        contains("startsWith('/plan-generation')"),
        reason:
            '_authRedirect must include /plan-generation in the onboarding bypass',
      );
    });

    test('/plan-generation route is still declared', () {
      expect(
        routerSource,
        contains("path: '/plan-generation'"),
        reason: '/plan-generation route must remain registered',
      );
    });
  });
}
