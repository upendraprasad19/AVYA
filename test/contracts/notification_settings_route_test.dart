// test/contracts/notification_settings_route_test.dart
//
// Unit A — bug (b): three Settings rows navigated to a route that does not
// exist.
//
// `settings_screen.dart` used `context.go('/notification-settings')`. The only
// registered path is `notification-settings` NESTED under `/profile`, and the
// router has no errorBuilder or catch-all redirect — so the tap resolved to
// nothing and the user hit GoRouter's error screen.
//
// WHY THIS TEST ASSERTS THE LINK, NOT THE SAVE
// --------------------------------------------
// A save-persistence test passes with the link still broken: the screen works
// fine, nobody can reach it. Round 1 originally diagnosed this as "dead
// toggles" for exactly that reason — the failure is in navigation, one layer
// before any state.
//
// Deliberately a source assertion. Driving GoRouter needs a pumped app with a
// live Hive session and a subscription provider; the defect is a literal string
// in a navigation call, and that is what this pins.
//
// Run: flutter test test/contracts/notification_settings_route_test.dart

import 'dart:io';

import 'package:test/test.dart';

const _settingsScreen =
    'lib/features/profile/screens/settings_screen.dart';
const _router = 'lib/core/router/app_router.dart';
const _workingCaller =
    'lib/features/profile/screens/profile/profile_content.dart';

String _strip(String src) => src
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');

void main() {
  group('bug (b) — the Settings notification rows reach a real route', () {
    test('settings_screen never targets the bare /notification-settings path',
        () {
      final src = _strip(File(_settingsScreen).readAsStringSync());
      expect(src.contains("'/notification-settings'"), isFalse,
          reason: 'That path is not registered. The route is nested under '
              '/profile, and with no errorBuilder the tap lands on GoRouter\'s '
              'error screen.');
    });

    test('it uses the same full path as the working caller', () {
      final settings = _strip(File(_settingsScreen).readAsStringSync());
      final working = _strip(File(_workingCaller).readAsStringSync());
      const path = "'/profile/notification-settings'";
      expect(working.contains(path), isTrue,
          reason: 'sanity — the known-good caller must still use this path, '
              'otherwise this test is pinning the wrong target');
      expect(settings.contains(path), isTrue,
          reason: 'the repaired links must match the caller that works');
    });

    test('the router registers the nested segment', () {
      final src = _strip(File(_router).readAsStringSync());
      expect(src.contains("'notification-settings'"), isTrue,
          reason: 'the nested child route must exist for the full path to '
              'resolve');
    });

    test('the router forwards the paywall callback', () {
      // Without this, a free user tapping a locked PRO row gets a lock icon
      // that does nothing — a smaller version of the same "control that lies"
      // problem this batch exists to remove.
      final src = _strip(File(_router).readAsStringSync());
      expect(src.contains('onProLockedTap'), isTrue);
    });

    test('the router keeps its non-nullable onSave default', () {
      // Round-3 F2: an earlier plan said to DELETE this default. `onSave` is
      // `required` and non-nullable, so removing it fails `flutter analyze`.
      // Recorded as a test so the instruction is not re-derived from the plan.
      final src = _strip(File(_router).readAsStringSync());
      expect(src.contains('onSave'), isTrue);
    });
  });
}
