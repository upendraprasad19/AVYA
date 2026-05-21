import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/read_screen_source.dart';

/// Verifies that the 'notification-settings' route is registered in app_router.dart
/// as a child of /profile, making it deep-linkable and state-restorable.
///
/// Previously this screen was pushed via Navigator.push(MaterialPageRoute(...))
/// which bypasses GoRouter's state restoration and deep-linking support.
void main() {
  late String routerSource;

  setUpAll(() {
    final file = File('lib/core/router/app_router.dart');
    expect(file.existsSync(), isTrue, reason: 'app_router.dart must exist');
    routerSource = file.readAsStringSync();
  });

  group('M6 — notification-settings GoRouter route', () {
    test("route path 'notification-settings' is declared", () {
      expect(
        routerSource,
        contains("path: 'notification-settings'"),
        reason: 'notification-settings must be a registered GoRoute path',
      );
    });

    test('NotificationSettingsScreen is imported in app_router.dart', () {
      expect(
        routerSource,
        contains('notification_settings_screen.dart'),
        reason: 'app_router.dart must import notification_settings_screen',
      );
    });

    test('profile_screen uses context.push for notification-settings', () {
      final dir = Directory('lib/features/profile/screens/profile');
      expect(dir.existsSync(), isTrue);
      final profileSource = readScreenSource('profile');
      expect(
        profileSource,
        contains("'/profile/notification-settings'"),
        reason: 'ProfileScreen must navigate via GoRouter push, not MaterialPageRoute',
      );
      expect(
        profileSource,
        isNot(contains('MaterialPageRoute(builder: (_) => NotificationSettingsScreen')),
        reason: 'MaterialPageRoute push to NotificationSettingsScreen must be removed',
      );
    });
  });
}
