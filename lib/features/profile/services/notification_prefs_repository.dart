// lib/features/profile/services/notification_prefs_repository.dart
//
// THE single reader + writer of `notification_preferences` (Unit C, bug (c)).
//
// WHY THIS EXISTS
// ---------------
// The preferences were stored in the SHARED `configBox` (`hive_service.dart`),
// which carries no owner. On a shared device the last saver silently set
// preferences for whoever signed in next — user A turns off streak alerts,
// user B stops receiving them.
//
// WHY NOT `MigratedKey`
// ---------------------
// `MigratedKey` looks like the right tool and is the wrong one here. Both its
// paths fall back to `configBox`:
//   - read  (migrated_key.dart:46-48) — no session, or a userBox miss, returns
//     the SHARED value. That is bug (c) re-created through the helper.
//   - write (migrated_key.dart:93-100) — no session writes to the shared box,
//     seeding the leak for the next signer-in.
// So this repository does its own session check and NEVER touches configBox.
// No session ⇒ read `{}` / write no-op. Silence is correct: the server's rule
// is ABSENT ⇒ SEND (decision N2), so a signed-out read can only fail safe.
//
// CONTRACT (§4.4 r4 — sync_service must not touch Hive directly)
//   - Session check FIRST.
//   - Every Hive call wrapped; NEVER throws. An unhandled throw on the read
//     path would propagate into `compileDailySnapshot` → `pushSnapshotNow`,
//     killing that user's ENTIRE daily snapshot, not just the preferences.
//   - Normalisation happens here, once, so no caller re-derives it.

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/error_telemetry.dart';
import '../../../core/services/hive_service.dart';
import '../../../core/services/hive_user_session.dart';

class NotificationPrefsRepository {
  const NotificationPrefsRepository._();

  /// Hive key, in BOTH boxes historically — read only from `userBox`.
  static const String hiveKey = 'notification_preferences';

  /// The user-controllable notification keys, and THE client-side registry.
  ///
  /// Must stay set-equal to the server's `ProactiveType` vocabulary — pinned by
  /// `test/contracts/notification_prefs_parity_test.dart`. A key present here
  /// but not server-side is a toggle that silently does nothing; a key
  /// server-side but not here never gets emitted, so the server's
  /// absent-means-SEND default applies and the toggle is unreachable.
  static const List<String> allKeys = <String>[
    'morning_checkin',
    'workout_reminders',
    'streak_alerts',
    'weekly_recap',
    'subscription_reminders',
    'protein_alerts',
    'plateau_alert',
    'pr_celebration',
    'rank_promotion',
    're_engagement',
  ];

  /// Legacy key aliases, read-time only.
  ///
  /// The client historically wrote `workout_reminder` (singular) while every
  /// server reader expects the plural. Renaming the stored key outright would
  /// orphan the value → absent → SEND → a user who deliberately turned the
  /// reminder OFF starts getting it again (trap 2). Reading through the alias
  /// preserves their choice; nothing writes the singular form any more.
  static const Map<String, String> _legacyAliases = <String, String>{
    'workout_reminders': 'workout_reminder',
  };

  /// True when a user session owns the Hive boxes.
  ///
  /// Without this, `userBox` is a GuardedBox with no owner and every access
  /// throws — which is why the check comes before the box is touched rather
  /// than relying on the try/catch.
  static bool get _hasSession => HiveUserSession.currentOwnerFullId != null;

  /// Normalises a stored value into `{key: {enabled: bool, ...}}`.
  ///
  /// Pure and total — every input maps to a value, nothing throws. Hive
  /// returns nested maps as `Map<dynamic, dynamic>`, so a naive
  /// `Map<String, dynamic>.from(...)` cast on the INNER map throws; that is
  /// the trap this function exists to absorb.
  ///
  /// Shape rules (decision N2 — absent or unreadable must mean SEND):
  ///   - non-Map entry            ⇒ `{'enabled': true}`
  ///   - Map without `enabled`    ⇒ `enabled: true` added, siblings kept
  ///   - `enabled` not a bool     ⇒ coerced; only a literal `false` disables
  ///
  /// The last rule is deliberate: a corrupted or half-written value must not
  /// silently darken a notification for a user who never turned it off.
  static Map<String, Map<String, dynamic>> normalize(dynamic stored) {
    final out = <String, Map<String, dynamic>>{};
    if (stored is! Map) return out;

    stored.forEach((k, v) {
      final key = k?.toString();
      if (key == null || key.isEmpty) return;

      if (v is! Map) {
        out[key] = <String, dynamic>{'enabled': true};
        return;
      }

      final entry = <String, dynamic>{};
      v.forEach((ik, iv) {
        final innerKey = ik?.toString();
        if (innerKey != null && innerKey.isNotEmpty) entry[innerKey] = iv;
      });

      final raw = entry['enabled'];
      entry['enabled'] = raw is bool ? raw : true;
      out[key] = entry;
    });

    return out;
  }

  /// Current preferences for the signed-in user. `{}` when absent, malformed,
  /// or no session. Never throws.
  static Map<String, Map<String, dynamic>> read() {
    if (!_hasSession) return <String, Map<String, dynamic>>{};
    try {
      // gate16-exempt: [hiveKey] is a fixed SINGLETON key, not a row id. Gate 16
      // guards collections keyed by entity id (exercise logs, meals), where the
      // Hive key IS the id and downstream consumers — edit sheets, receipts,
      // sync — need it injected back into the map. This box entry holds one
      // settings blob for the signed-in user; there is no per-row identity to
      // restore, and the returned map is keyed by notification NAME. Injecting
      // an 'id' here would fabricate an eleventh pseudo-preference that the
      // emission map would then publish to the server.
      return normalize(HiveService.instance.userBox.get(hiveKey));
    } catch (e, st) {
      debugPrint('[NotificationPrefs] read failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'notification_prefs_read'));
      return <String, Map<String, dynamic>>{};
    }
  }

  /// The map emitted into the daily snapshot (Unit D).
  ///
  /// EVERY key in [allKeys] is present, always. A key the user has never
  /// touched emits `{'enabled': true}` rather than being omitted — the server
  /// tests `=== false`, so an omitted key already means send, but emitting it
  /// explicitly makes the snapshot self-describing and lets a server-side
  /// audit tell "user left it on" apart from "client never emitted it".
  ///
  /// Never throws: [read] already swallows storage errors and returns `{}`,
  /// which degrades to all-enabled. An exception escaping here would propagate
  /// through `compileDailySnapshot` into `pushSnapshotNow` and kill that
  /// user's ENTIRE daily snapshot — not just their preferences.
  static Map<String, Map<String, dynamic>> emissionMap() {
    final stored = read();
    final out = <String, Map<String, dynamic>>{};
    for (final key in allKeys) {
      final direct = stored[key];
      final alias = _legacyAliases[key];
      final value = direct ?? (alias == null ? null : stored[alias]);
      out[key] = value ?? <String, dynamic>{'enabled': true};
    }
    return out;
  }

  /// THE writer. Returns false when it did not persist (no session, or the
  /// box threw) so a caller can surface that rather than assume success.
  ///
  /// Normalises before storing, so a malformed value can never be written in
  /// the first place — the read path's normalisation is then a belt for
  /// values written before this repository existed.
  static Future<bool> write(Map<String, dynamic> prefs) async {
    if (!_hasSession) {
      debugPrint('[NotificationPrefs] write skipped — no session. '
          'Writing to the shared configBox here is what caused bug (c).');
      return false;
    }
    try {
      await HiveService.instance.userBox.put(hiveKey, normalize(prefs));
      return true;
    } catch (e, st) {
      debugPrint('[NotificationPrefs] write failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'notification_prefs_write'));
      return false;
    }
  }
}
