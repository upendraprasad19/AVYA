import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import '../services/notification_inbox_service.dart';

/// Inbox contents for the Notifications screen.
///
/// Reads from `HiveService.instance.notificationsBox` via
/// [NotificationInboxService.readAll] each build. Mutations (new push
/// arrives, MARK READ tapped) call `ref.invalidateSelf()` explicitly
/// — Hive doesn't stream, so the notifier is the canonical refresh
/// point. Cheap to rebuild (cap 200 entries, simple list traversal).
class NotificationInboxNotifier extends Notifier<List<AppNotification>> {
  @override
  List<AppNotification> build() {
    return NotificationInboxService.instance.readAll();
  }

  /// Re-read the Hive box and rebuild. Call after:
  /// * OneSignal push arrives (service already saved; provider needs refresh)
  /// * user taps MARK READ
  /// * user manually dismisses a row
  void refresh() {
    state = NotificationInboxService.instance.readAll();
  }

  /// Mark every entry read. Delegates to the service for the write;
  /// updates `state` in-place to avoid a second Hive read.
  Future<void> markAllRead() async {
    await NotificationInboxService.instance.markAllRead();
    state = state.map((n) => n.copyWith(read: true)).toList();
  }
}

final notificationsInboxProvider =
    NotifierProvider<NotificationInboxNotifier, List<AppNotification>>(
        NotificationInboxNotifier.new);
