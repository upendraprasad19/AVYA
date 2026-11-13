import 'dart:async';

import 'package:flutter/foundation.dart';

import 'hive_service.dart';
import 'hive_user_session.dart';
import 'sync_service.dart';

/// OI-479 (diagnose 5970aa; plan `docs/plans/2026-11-12-oi479-clear-conversation.md`):
/// the AI Coach "Clear conversation" marker.
///
/// A clear HIDES the chat thread; it never deletes a row (founder decision D1):
/// local and cloud `ai_coach_interactions` rows feed the coach's long-term memory,
/// the weekly report and several server jobs, and a local-only delete would come
/// back on the next restore. The marker is ONE instant, `userBox['coach_chat_cleared_at']`
/// (UTC ISO-8601 with `Z`; `userBox` is opened per user, so it never crosses
/// accounts). A chat row created at or before it is hidden from:
///   * the chat thread (`ChatHistoryNotifier.build`; today's unresolved
///     completion tile is exempt, D3),
///   * the coach's short-term history replay (`recentHistoryExchanges`, D2),
///   * the client dedup scan (`_findRecentDuplicateMessageKey`), so a repeat of a
///     hidden message mints a new, visible row.
/// Nothing else reads it: the daily message count, the first-message flag, the
/// coaching-notes extraction deliberately see every row (the Home coach tip,
/// once a reader here too, was removed by OI-502).
///
/// Monotonic everywhere: [clear] and the restore adoption write `max(stored, new)`,
/// and the cloud copy (`user_preferences.coach_chat_cleared_at`, migration 177) is
/// raised only through `raise_coach_chat_cleared_at` (GREATEST).
class CoachChatClear {
  CoachChatClear._();

  /// The marker's `userBox` key.
  static const String markerKey = 'coach_chat_cleared_at';

  /// `'<marker>|<IST day>'` of the last successful cloud push; bounded by the
  /// IST day so a cloud value lost out of band is re-pushed within a day.
  static const String pushedKey = 'coach_chat_cleared_at_pushed';

  /// The stored marker as a UTC instant, or null (never cleared, unparseable, or
  /// the box could not be read). Fails OPEN: null hides nothing.
  static DateTime? clearedAt() {
    try {
      final raw = HiveService.instance.userBox.get(markerKey);
      if (raw is! String) return null;
      return DateTime.tryParse(raw)?.toUtc();
    } catch (_) {
      return null;
    }
  }

  /// True when [row] (a coachBox chat row) is hidden by [marker].
  ///
  /// Compared as INSTANTS: `created_at` is written both with `Z` (every local
  /// writer) and as whatever the cloud returned (restored rows), so a string
  /// compare would be wrong. A row with no or an unparseable `created_at` is
  /// hidden once a marker exists (every real writer stamps one).
  static bool isHiddenByClear(Map<dynamic, dynamic> row, DateTime? marker) {
    if (marker == null) return false;
    final raw = row['created_at'];
    if (raw is! String) return true;
    final created = DateTime.tryParse(raw);
    if (created == null) return true;
    return !created.isAfter(marker);
  }

  /// The larger of two optional instants (null loses).
  @visibleForTesting
  static DateTime? laterOf(DateTime? a, DateTime? b) {
    if (a == null) return b?.toUtc();
    if (b == null) return a.toUtc();
    return (b.isAfter(a) ? b : a).toUtc();
  }

  /// Raises the stored marker to [at] when [at] is later. The read of the stored
  /// value and the `put` have NO await between them, so this and the restore
  /// adoption cannot interleave and lower the marker. Returns the stored value
  /// after the call (null only when nothing was stored and [at] is null).
  static Future<DateTime?> raiseTo(DateTime at) {
    final current = clearedAt();
    final next = laterOf(current, at);
    if (next == null || (current != null && !next.isAfter(current))) {
      return Future<DateTime?>.value(current);
    }
    return HiveService.instance.userBox
        .put(markerKey, next.toIso8601String())
        .then((_) => next);
  }

  /// Test seam: replaces the fire-and-forget cloud push in [clear] (a widget
  /// test has no stub server). Null in production.
  @visibleForTesting
  static Future<void> Function(String owner)? debugPushOverride;

  /// "Clear conversation": stamp the marker at the device's now and push it.
  ///
  /// Returns false (and writes nothing) when no user owns the Hive session or
  /// the signed-in user changed before the write. The caller invalidates
  /// `chatHistoryProvider` afterwards.
  static Future<bool> clear({DateTime Function()? now}) async {
    final owner = HiveUserSession.currentOwnerFullId;
    if (owner == null) return false;
    final sync = SyncService.instance;
    if (sync.ownerChangedSince(owner)) return false;
    await raiseTo((now ?? DateTime.now)().toUtc());
    unawaited((debugPushOverride ?? sync.pushCoachChatClearedAt)(owner));
    return true;
  }
}
