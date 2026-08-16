import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:icanbefitter/core/services/hive_service.dart';
import 'package:icanbefitter/core/services/sync_service.dart';
import '../models/app_notification.dart';

/// Captures OneSignal push events into `HiveService.instance.notificationsBox`
/// so the in-app Notifications screen has real data to render.
///
/// Wired up from `splash_screen.dart` after `OneSignal.initialize` so
/// the listener registration lasts the full session. Two hooks:
///
/// * [OneSignal.Notifications.addForegroundWillDisplayListener] —
///   fires when a push arrives while the app is foregrounded. We save
///   it to the inbox AND call `event.preventDefault()` is intentionally
///   NOT used: we still want the OS banner to show. Writes happen in
///   parallel with native display.
/// * [OneSignal.Notifications.addClickListener] — fires when the user
///   taps a background push to open the app. We save it + mark it
///   read since the user has clearly seen it.
///
/// Notifications received while the app is fully killed (neither
/// foreground nor clicked) are NOT captured — that requires a server-
/// side inbox source of truth (e.g. Supabase `user_notifications`
/// table), which is tracked as a future enhancement but out of AG.5
/// scope. This gap is documented in the UI via the default "ALL · 0"
/// empty state and a welcome seed on first launch.
class NotificationInboxService {
  NotificationInboxService._();
  static final NotificationInboxService instance =
      NotificationInboxService._();

  /// Maximum entries retained in the box. Rolling window — oldest are
  /// pruned when a new entry pushes past the cap. 200 covers several
  /// months of typical usage (a heavy user gets ~3 pushes/day).
  static const int _maxEntries = 200;

  bool _wired = false;

  /// Attach OneSignal listeners + seed welcome entry on first launch.
  /// Safe to call multiple times — attachment happens exactly once.
  void init() {
    if (_wired || kIsWeb) return;
    try {
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        final n = event.notification;
        _ingestFromOsNotification(n, markRead: false);
      });
      OneSignal.Notifications.addClickListener((event) {
        _ingestFromOsNotification(event.notification, markRead: true);
      });
      _wired = true;
    } catch (e) {
      // Binding not ready or plugin missing (tests / web); safe to skip.
      debugPrint('[NotificationInbox] listener wire failed: $e');
    }

    // Seed a welcome entry on first launch — gives the inbox a visible
    // "YOUR JOURNEY BEGINS" row so new users don't land on an empty
    // screen before any push has arrived.
    _seedWelcomeIfFirstLaunch();
  }

  /// Save an entry directly from the app (e.g. on-device PR detection,
  /// streak freeze event). Callers outside OneSignal use this path.
  Future<void> record(AppNotification notification) async {
    final box = HiveService.instance.notificationsBox;
    await box.put(notification.id, notification.toJson());
    await _pruneIfOverCap();
    // Push to cloud so inbox survives reinstall (migration 048).
    unawaited(SyncService.instance.syncNotificationsInboxEntry(notification.toJson()));
  }

  /// Pull all rows, newest first. Returns empty list if box hasn't
  /// been opened yet (shouldn't happen after HiveService.init but
  /// guarded for hot-reload safety).
  List<AppNotification> readAll() {
    try {
      final box = HiveService.instance.notificationsBox;
      final items = <AppNotification>[];
      for (final raw in box.values) {
        if (raw is Map) {
          final parsed = AppNotification.fromJson(raw);
          if (parsed != null) items.add(parsed);
        }
      }
      items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return items;
    } catch (_) {
      return const <AppNotification>[];
    }
  }

  /// "MARK READ" tap handler from the Notifications screen header —
  /// flips every entry to read=true and rewrites to the box. Cheap
  /// enough to do serially since we cap at 200 entries.
  Future<void> markAllRead() async {
    final box = HiveService.instance.notificationsBox;
    for (final key in box.keys.toList()) {
      final raw = box.get(key);
      if (raw is Map) {
        final parsed = AppNotification.fromJson(raw);
        if (parsed != null && !parsed.read) {
          await box.put(key, parsed.copyWith(read: true).toJson());
        }
      }
    }
  }

  // ── Internals ──────────────────────────────────────────────────

  void _ingestFromOsNotification(OSNotification osn,
      {required bool markRead}) {
    final additional = osn.additionalData ?? const <String, dynamic>{};
    final categoryRaw =
        (additional['category'] as String?)?.toLowerCase() ?? 'system';
    final priorityRaw =
        (additional['priority'] as String?)?.toLowerCase() ?? '';

    final category = AppNotification.fromJson({
      // Round-trip through fromJson to reuse its category parser.
      'category': categoryRaw,
    })?.category ??
        AppNotificationCategory.system;

    final priority = (priorityRaw == 'gold' ||
            category == AppNotificationCategory.pr)
        ? AppNotificationPriority.gold
        : AppNotificationPriority.normal;

    final notification = AppNotification(
      id: osn.notificationId.isNotEmpty
          ? osn.notificationId
          : 'os-${DateTime.now().microsecondsSinceEpoch}',
      category: category,
      title: osn.title ?? '(no title)',
      body: osn.body ?? '',
      createdAt: DateTime.now(),
      priority: priority,
      read: markRead,
    );

    // Fire-and-forget; errors here would only hurt the inbox, not the
    // native banner, so we don't await callers.
    record(notification);
  }

  Future<void> _pruneIfOverCap() async {
    final box = HiveService.instance.notificationsBox;
    if (box.length <= _maxEntries) return;

    // Sort keys by their entry's createdAt; drop oldest.
    final entries = <MapEntry<dynamic, DateTime>>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is Map) {
        final createdAtStr = raw['created_at'] as String? ?? '';
        final createdAt =
            DateTime.tryParse(createdAtStr) ?? DateTime(1970);
        entries.add(MapEntry(key, createdAt));
      }
    }
    entries.sort((a, b) => a.value.compareTo(b.value));
    final toDelete = entries.length - _maxEntries;
    for (var i = 0; i < toDelete; i++) {
      await box.delete(entries[i].key);
    }
  }

  /// Mints the id for a LOCALLY-created notification.
  ///
  /// A REAL uuid, not the old `'local-welcome-<micros>'` (diagnose a4f1c8).
  /// `notifications_inbox.id` is a uuid column and this id is forwarded
  /// verbatim by `syncNotificationsInboxEntry`, so the old format made every
  /// sync of the welcome row fail 22P02 "invalid input syntax for type uuid" —
  /// permanently, on every retry, for every install.
  ///
  /// Extracted and `@visibleForTesting` so the regression test asserts THIS
  /// function's output. The first version of that test minted its own uuid and
  /// checked that, which was circular: reverting this line to the legacy format
  /// left all four cases green (round-1 review, P1-4).
  @visibleForTesting
  static String newLocalNotificationId() => const Uuid().v4();

  Future<void> _seedWelcomeIfFirstLaunch() async {
    try {
      final cfg = HiveService.instance.configBox;
      const key = 'notifications_inbox_seeded_v1';
      if (cfg.get(key) == true) return;

      final now = DateTime.now();
      final welcome = AppNotification(
        id: newLocalNotificationId(),
        category: AppNotificationCategory.system,
        title: 'Welcome aboard',
        body:
            'Your inbox will collect coach nudges, PRs, and weekly reports here. '
            'OS-level pushes show up as notifications; this is where you see them again.',
        createdAt: now,
        priority: AppNotificationPriority.normal,
        read: false,
      );
      await record(welcome);
      await cfg.put(key, true);
    } catch (e) {
      debugPrint('[NotificationInbox] seed failed: $e');
    }
  }
}
