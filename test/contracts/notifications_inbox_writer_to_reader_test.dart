// test/contracts/notifications_inbox_writer_to_reader_test.dart
//
// SoT contract for notifications_inbox (audit-fixwave 2026-07-02 / F7).
// Registers the real write path (previously only referenced inside
// restore_completeness). Comment-stripped.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _strip(String s) => s
    .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  final svc = _strip(File(
          'lib/features/profile/services/notification_inbox_service.dart')
      .readAsStringSync());
  final prov = _strip(File(
          'lib/features/profile/providers/notifications_inbox_provider.dart')
      .readAsStringSync());

  group('notifications_inbox writer→reader contract', () {
    test('writer NotificationInboxService.record writes notificationsBox', () {
      expect(svc.contains('record'), isTrue);
      expect(svc.contains('notificationsBox'), isTrue,
          reason: 'inbox entries are written to notificationsBox');
    });
    test('writer syncs the entry to cloud', () {
      expect(svc.contains('syncNotificationsInboxEntry'), isTrue,
          reason: 'each recorded notification syncs to notifications_inbox');
    });
    test('reader provider reads the inbox back', () {
      expect(prov.contains('NotificationInboxService') ||
          prov.contains('notificationsBox'), isTrue,
          reason: 'the inbox provider reads the recorded notifications');
    });
  });
}
