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
import '../../../core/services/sync_service.dart';

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

  /// The subset of [allKeys] whose notifications only ever fire for a PRO user.
  ///
  /// DISPLAY-ONLY. This is deliberately NOT subtracted from [allKeys] or from
  /// [emissionMap] — the server's rule is ABSENT ⇒ SEND (see the header), so
  /// dropping a key from the emitted snapshot would turn these two PRO-locked
  /// notifications ON for free users, the exact inverse of the intent. The
  /// server PRO-gates them independently; the client's only job is to stop
  /// counting toggles a free user cannot reach (OI-76).
  ///
  /// It is also the source of the `isProFeature` flag on the settings rows, so
  /// the "which keys are PRO?" answer lives in one place instead of being
  /// duplicated as literals at each call site.
  static const Set<String> proOnlyKeys = <String>{
    'protein_alerts',
    'plateau_alert',
  };

  /// The keys a user of the given tier can actually control — the denominator
  /// behind the profile row's "N/M enabled" subtitle.
  ///
  /// A free user is shown 8, not 10: Protein Alerts and Plateau Check are
  /// locked, their server functions PRO-gate anyway, and counting them left the
  /// subtitle permanently reading at least 2/10 "enabled" for notifications
  /// that could never fire.
  /// Both branches return an UNMODIFIABLE list on purpose. Returning `allKeys`
  /// directly (a `const` literal, fully unmodifiable) on one branch and
  /// `.toList(growable: false)` (fixed-length but element-settable) on the
  /// other would hand callers the same type with two different mutability
  /// contracts — a latent trap for whoever first tries to sort or patch the
  /// result. B-pass finding 7.
  static List<String> controllableKeys({required bool isPro}) => isPro
      ? List<String>.unmodifiable(allKeys)
      : List<String>.unmodifiable(
          allKeys.where((k) => !proOnlyKeys.contains(k)));

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

  /// [_legacyAliases] inverted — legacy key -> canonical key.
  ///
  /// Derived rather than hand-written so the two can never disagree: a second
  /// literal map is a rename away from silently disabling alias handling.
  static final Map<String, String> _canonicalByLegacy = <String, String>{
    for (final e in _legacyAliases.entries) e.value: e.key,
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
      // Push the snapshot so the SERVER sees the change today, not at next
      // launch (B-pass P1). Without this the only backstop is checkAndSync's
      // next-login pushSnapshotNow: a user who turns Morning Check-in off at
      // 22:00 and closes the app still gets the 07:00 push, because both the
      // 02:00 generate and the 07:00 deliver read the pre-change snapshot —
      // the exact "my toggle did nothing" failure this batch removes.
      //
      // Fire-and-forget + coalesced, matching every sibling WriteService; the
      // Hive write above is already durable, so a failed push costs a delay,
      // never the setting.
      unawaited(SyncService.instance.pushSnapshot());

      // OI-98 / e4a1b7 — push the NEW home too, so a toggle lands in
      // `user_preferences.notification_preferences` now rather than waiting for
      // the next profile sync. Both pushes run during the cutover window; the
      // snapshot one goes away with the rest of the old path once the server
      // fallback is retired.
      //
      // `.catchError` is NOT decoration. Unlike `pushSnapshot` — whose
      // `pushSnapshotNow` wraps everything including `_ensureSessionOpen` in
      // its own try/catch — this forwarder awaits `_ensureSessionOpen()`
      // OUTSIDE any handler, so a throw there escapes an unawaited future as an
      // unhandled async error. The Hive write above is already durable, so a
      // failed push costs a delay, never the setting.
      unawaited(
        SyncService.instance
            .pushUserPreferencesForSyncDomain()
            .catchError((Object e, StackTrace st) {
          debugPrint('[NotificationPrefs] user_preferences push failed: $e');
          unawaited(ErrorTelemetry.recordNonFatal(e, st,
              reason: 'notification_prefs_push_user_preferences'));
        }),
      );
      return true;
    } catch (e, st) {
      debugPrint('[NotificationPrefs] write failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'notification_prefs_write'));
      return false;
    }
  }

  /// Adopts the cloud copy of the preferences (OI-98 / e4a1b7) — THE restore
  /// leg this concept never had.
  ///
  /// Deliberately NOT [write]: that writer fires
  /// `unawaited(SyncService.instance.pushSnapshot())`, which is right for a
  /// user flipping a switch and wrong here — this runs mid-restore, so it would
  /// publish a snapshot built from half-restored Hive state, and a restore leg
  /// triggering a push is backwards on its face.
  ///
  /// Session-checked through the SAME `_hasSession` gate [read] uses. That
  /// pairing is load-bearing: `read()` short-circuits to `{}` with no session,
  /// so a writer that did not consult the same gate would see a spuriously
  /// empty `local`, degrade the merge to cloud-wins, and adopt over real
  /// preferences. One gate, both sides.
  ///
  /// Returns true only when the box was actually written.
  static Future<bool> adoptFromCloud(dynamic cloudValue) async {
    if (!_hasSession) return false;
    try {
      final cloud = normalize(cloudValue);
      if (cloud.isEmpty) return false;

      final local = read();
      final merged = mergeCloudNotificationPrefs(local: local, cloud: cloud);

      // `merged` starts as a copy of `local` and only ever grows, so an equal
      // length means nothing was adopted. Skip the write rather than churn the
      // box with an identical value.
      if (merged.length == local.length) return false;

      await HiveService.instance.userBox.put(hiveKey, merged);
      return true;
    } catch (e, st) {
      debugPrint('[NotificationPrefs] adoptFromCloud failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'notification_prefs_adopt_from_cloud'));
      return false;
    }
  }
}

/// Rewrites legacy keys to their canonical form. Pure and total.
///
/// An explicit canonical entry OUTRANKS a legacy one, mirroring
/// [NotificationPrefsRepository.emissionMap]'s `direct ?? alias` — otherwise
/// the two would disagree about which value is authoritative for the same
/// notification, which is how a user's choice gets read one way and written
/// another.
Map<String, Map<String, dynamic>> canonicalizeNotificationPrefs(
    Map<String, Map<String, dynamic>> input) {
  final out = <String, Map<String, dynamic>>{};
  // Pass 1 — anything already in canonical form.
  input.forEach((k, v) {
    if (!NotificationPrefsRepository._canonicalByLegacy.containsKey(k)) {
      out[k] = v;
    }
  });
  // Pass 2 — legacy keys, only where the canonical form is absent.
  input.forEach((k, v) {
    final canonical = NotificationPrefsRepository._canonicalByLegacy[k];
    if (canonical != null && !out.containsKey(canonical)) out[canonical] = v;
  });
  return out;
}

/// Merges a cloud preference map into a local one. PER-KEY LOCAL-WINS.
///
/// Extracted as a pure top-level function (the shape `paywallLetterheadTitle`
/// already uses in this repo) so production and its test call the SAME code. A
/// test that re-implements the merge inline proves nothing about the merge that
/// actually runs — replacing this body with cloud-wins would leave such a test
/// green.
///
/// TWO RULES, both learned the hard way:
///
/// 1. **Local wins per key, not all-or-nothing.** `RestoringScreen` surfaces a
///    CONTINUE escape at 30s while the restore keeps writing in the background,
///    so a reinstalling user really can flip one switch before this runs. An
///    all-or-nothing guard would let that single toggle discard every other
///    preference the cloud still held. Per-key is what ADR-0014's
///    additive/local-wins actually means.
///
/// 2. **Containment is tested in CANONICAL space, but the result is written in
///    LOCAL's own key space.** A box holding the legacy singular
///    `workout_reminder` has no canonical `workout_reminders` key; a naive
///    `local.containsKey(canonical)` test would therefore adopt the cloud's
///    canonical entry, and `emissionMap`'s `direct ?? alias` would then prefer
///    that adopted value forever — flipping a deliberate OFF back ON, on every
///    sign-in. Comparing canonically stops that. Writing in local's own shape
///    stops the mirror error: silently migrating the box would strip the legacy
///    key that other readers still resolve through.
Map<String, Map<String, dynamic>> mergeCloudNotificationPrefs({
  required Map<String, Map<String, dynamic>> local,
  required Map<String, Map<String, dynamic>> cloud,
}) {
  final localCanonical = canonicalizeNotificationPrefs(local);
  final out = <String, Map<String, dynamic>>{...local};
  canonicalizeNotificationPrefs(cloud).forEach((key, value) {
    if (!localCanonical.containsKey(key)) out[key] = value;
  });
  return out;
}
