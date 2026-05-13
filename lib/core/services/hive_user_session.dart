import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:synchronized/synchronized.dart';

import 'error_telemetry.dart';
import 'hive_service.dart';
import 'supabase_service.dart';

/// Owns the per-user Hive box lifecycle. Opens namespaced boxes
/// (`<box>_<8hex>`) when the user signs in; closes them on sign-out.
///
/// User-scoped boxes — userBox / workoutBox / nutritionBox / healthBox /
/// coachBox / customBox / notificationsBox — are physically separate
/// Hive box files per user. Cross-account leaks become impossible at
/// the storage layer: Avyaansh's sign-in opens `coachBox_94368fd4`,
/// which has no relationship to Upendra's `coachBox_5f0a13b2`.
///
/// Shared boxes — exerciseBox / foodBox / configBox / syncBox — are
/// owned by `HiveService` directly and stay open across the app
/// lifetime; they are NOT touched by this class.
///
/// Bootstrap order (cold start):
///   1. main.dart runs `HiveService.instance.init()` — opens shared
///      boxes only.
///   2. Auth resolves → `_ensureLocalUser` → on success
///      `HiveUserSession.openForUser(user.id)` opens the 7
///      user-scoped boxes.
///   3. UI mounts. Reads through `HiveService.instance.userBox` etc.
///      transparently route to the namespaced box via
///      `currentOwnerHash`.
class HiveUserSession {
  HiveUserSession._();

  /// APK Test #15.4 / B1 Layer B — observable mirror of
  /// [_currentOwnerFullId]. Flutter `ValueNotifier` so Riverpod's
  /// `hiveSessionOwnerProvider` can watch it without polling.
  ///
  /// Mutated under [_sessionLock] from [_openForUserLocked],
  /// [_closeAllLocked], and [_deleteAllFilesForCurrentUserLocked].
  /// Always reflects the latest value of [_currentOwnerFullId].
  ///
  /// Test code may NOT mutate this directly — go through the three
  /// locked methods so the lock invariant is preserved.
  static final ValueNotifier<String?> currentOwnerListenable =
      ValueNotifier<String?>(null);

  /// 8-hex prefix of the currently signed-in user.id. Null when no
  /// user-scoped boxes are open (cold start before sign-in,
  /// post-sign-out before the next sign-in).
  static String? _currentOwnerHash;

  /// Full user.id of the current owner. Stored alongside the hash so
  /// guards can compare full ids without depending on prefix collisions.
  static String? _currentOwnerFullId;

  /// APK Test #15.1 / Bug C — serialization lock around the three
  /// methods that mutate `_currentOwnerHash` / `_currentOwnerFullId`:
  /// `openForUser`, `closeAll`, `deleteAllFilesForCurrentUser`.
  ///
  /// Pre-fix the three methods could interleave on the Dart event loop
  /// during signOut → signUp transitions. Founder's sumit1 leak
  /// (2026-05-11): signOut started `clearAllData` (slow), signUp's
  /// `openForUser` yielded into the middle of it, both paths mutated
  /// the static state before either finished. Telemetry captured
  /// `hive_session_opened userId=428cd70c` BEFORE
  /// `hive_session_closed userId=d7a67a37` plus a follow-on
  /// `hive_session_reopen_noop` — a clear race signature.
  ///
  /// With the lock, the second caller blocks until the first finishes,
  /// so static-state observers always see a consistent view.
  ///
  /// closes-diagnose: 2026-05-12-cross-account-mutex-c7d4f6
  static final Lock _sessionLock = Lock();

  static String? get currentOwnerHash => _currentOwnerHash;
  static String? get currentOwnerFullId => _currentOwnerFullId;

  /// The 7 user-scoped box roots. Each gets `_<hash>` appended at open.
  static const List<String> userScopedBoxRoots = <String>[
    HiveService.userBoxName,
    HiveService.workoutBoxName,
    HiveService.nutritionBoxName,
    HiveService.healthBoxName,
    HiveService.coachBoxName,
    HiveService.customBoxName,
    HiveService.notificationsBoxName,
  ];

  /// Compute the namespaced box name for a given root + user.id.
  /// `userBox` + `5f0a13b2-...` → `userBox_5f0a13b2`.
  static String namespacedBoxName(String root, String userId) {
    final hash = userId.replaceAll('-', '').substring(0, 8);
    return '${root}_$hash';
  }

  /// C-7 (audit-2026-05-11) — shared helper any startup/background
  /// service can call to ensure the user-scoped Hive boxes are open
  /// for the *current* Supabase session before reading them.
  ///
  /// Returns the auth uid on success, or `null` if there's no live
  /// session (caller should short-circuit). Idempotent — when the
  /// session is already open for the same uid this is a fast no-op.
  ///
  /// Lifted from the pre-existing `SyncService._ensureSessionOpen` so
  /// `RankService`, `SubscriptionService`, splash startup mutations,
  /// migrators, etc. all gate on the same signal without duplicating
  /// the helper. `SyncService._ensureSessionOpen` now delegates here.
  static Future<String?> ensureOpenedForCurrentSession() async {
    final userId = SupabaseService.instance.currentUser?.id;
    if (userId == null) return null;
    if (_currentOwnerFullId == userId) return userId;
    try {
      await openForUser(userId);
    } catch (e, st) {
      debugPrint(
          '[HiveUserSession.ensureOpenedForCurrentSession] openForUser failed: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'ensure_session_open'));
      // Fall through — return the uid even on failure so callers can
      // attempt their work and surface a more specific error.
    }
    return userId;
  }

  /// Open the 7 user-scoped boxes for [userId]. Idempotent — calling
  /// twice with the same id is a no-op. Calling with a different id
  /// closes the previous user's boxes first.
  ///
  /// Throws [HiveError] if a box file is corrupted; caller should
  /// surface this as a fatal error and force the user to reinstall.
  ///
  /// APK Test #15.1 / Bug C — wrapped in [_sessionLock] so concurrent
  /// signOut/signUp callers can't interleave + race the static state.
  static Future<void> openForUser(String userId) async {
    await _sessionLock.synchronized(() => _openForUserLocked(userId));
  }

  /// Body of [openForUser] — runs while the [_sessionLock] is held.
  /// Internal callers that already hold the lock invoke this directly
  /// (no inner re-entry — `synchronized` is non-reentrant).
  static Future<void> _openForUserLocked(String userId) async {
    if (_currentOwnerFullId == userId) {
      // APK Test #12.8 — surface the no-op so we can see how often
      // SyncService.restoreFromCloudForUser's defensive ensure (Test
      // #12.6) actually saves us. High no-op rate = boxes already open
      // (good). Low or zero = the defensive call is the only path
      // opening boxes (bug elsewhere).
      unawaited(ErrorTelemetry.logEvent('hive_session_reopen_noop',
          message: 'userId=${userId.substring(0, 8)}'));
      return;
    }
    if (_currentOwnerFullId != null) {
      // Already holding _sessionLock — call the inner variant directly.
      await _closeAllLocked();
    }

    // One-shot migration — copies pre-namespacing shared box contents
    // into the namespaced box on first sign-in after upgrade.
    await _migrateLegacySharedBoxes(userId);

    final hash = userId.replaceAll('-', '').substring(0, 8);
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, userId);
      try {
        await Hive.openBox(boxName);
      } catch (e, st) {
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[HiveUserSession] failed to open $boxName: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'hive_user_session_open_box_corrupt'));
        await Hive.deleteBoxFromDisk(boxName);
        await Hive.openBox(boxName);
      }
    }

    _currentOwnerHash = hash;
    _currentOwnerFullId = userId;
    // APK Test #15.4 / B1 Layer B — mirror static field into listenable
    // so Riverpod providers re-emit. Mutated under _sessionLock.
    currentOwnerListenable.value = userId;

    // C-6 (audit-2026-05-11) — Cross-account guard, lifted from
    // splash_screen.dart where the `try/catch` swallowed the
    // `HiveUserSession not opened` throw on first launch and made the
    // guard a no-op. Now the check runs inside `openForUser` itself, so
    // every caller (auth_provider._ensureLocalUser, RestoringScreen,
    // SyncService defensive ensure) gets it for free.
    //
    // After opening the namespaced boxes for [userId], inspect the
    // user-scoped profile. If profile.id is present and mismatches
    // [userId], the namespaced files were populated by another account
    // (Android Auto Backup restore, dev-build copy, legacy migration
    // race). Clear all 7 boxes in place so the caller's downstream
    // restoreFromCloudForUser path starts from a clean slate.
    //
    // The heavier `auth_provider._ensureLocalUser` ClearResult check +
    // force-signOut path stays in place as a second layer for partial
    // failures.
    try {
      final userBoxName =
          namespacedBoxName(HiveService.userBoxName, userId);
      final box = Hive.box(userBoxName);
      final profile = box.get('profile');
      if (profile is Map) {
        final existingId = profile['id'] as String?;
        if (existingId != null && existingId != userId) {
          debugPrint(
              '[HiveUserSession] Cross-account guard fired: namespaced box for $hash contains profile.id=$existingId. Clearing all 7 boxes.');
          for (final root in userScopedBoxRoots) {
            final boxName = namespacedBoxName(root, userId);
            if (Hive.isBoxOpen(boxName)) {
              try {
                await Hive.box(boxName).clear();
              } catch (e, st) {
                // audit-2026-05-11 H-42 — telemetry pair.
                debugPrint(
                    '[HiveUserSession] cross-account clear $boxName failed: $e');
                unawaited(ErrorTelemetry.recordNonFatal(e, st,
                    reason: 'hive_user_session_cross_account_clear'));
              }
            }
          }
          final foundPrefix = existingId.length >= 8
              ? existingId.substring(0, 8)
              : existingId;
          unawaited(ErrorTelemetry.logEvent(
              'hive_cross_account_guard_fired',
              message: 'expected=$hash found=$foundPrefix'));
        }
      }
    } catch (e, st) {
      // Guard must never throw — log and continue so the session is
      // usable. The auth_provider second-layer check will catch any
      // mismatch we missed.
      debugPrint('[HiveUserSession] cross-account guard error: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'hive_cross_account_guard_error'));
    }

    debugPrint('[HiveUserSession] opened 7 boxes for user $hash');
    // APK Test #12.8 — successful open event so we can verify the
    // bootstrap order: every cold start should produce auth_user_ensured
    // → hive_session_opened → restore_started.
    unawaited(ErrorTelemetry.logEvent('hive_session_opened',
        message: 'userId=$hash boxes=${userScopedBoxRoots.length}'));
  }

  /// Test #10.1 — `migrationBox` flag key for the one-shot legacy
  /// box migration. Stored in `migrationBox` (NEVER cleared) so the
  /// migration can't re-run and re-leak data from a stale legacy
  /// shared `userBox`/`workoutBox`/etc. into a fresh user's
  /// namespaced box.
  static const String _legacyMigrationFlagKey =
      'legacy_shared_box_migration_v1_done';

  /// One-shot migration: if a pre-namespacing shared box exists for any
  /// user-scoped root AND the per-user namespaced box for [userId]
  /// doesn't already have data, copy contents over and delete the
  /// shared box.
  ///
  /// Test #10.1 — Now gated by a `migrationBox` flag so it runs at most
  /// ONCE per device lifetime. Previously ran on every `openForUser`
  /// call; if the legacy box ever survived (silent delete failure),
  /// every subsequent fresh-user signup would re-copy that legacy data
  /// into the new user's namespaced box → cross-account leak.
  ///
  /// Skipped silently if the shared box is empty or fails to open.
  static Future<void> _migrateLegacySharedBoxes(String userId) async {
    // Gate on migrationBox so the flag survives clearAllData()
    // (which clears configBox but NOT migrationBox).
    try {
      final migBox = HiveService.instance.migrationBox;
      if (migBox.get(_legacyMigrationFlagKey) == true) {
        return;
      }
    } catch (e, st) {
      // migrationBox not yet initialised (very early cold start).
      // Fall through and let the migration run; it'll set the flag
      // at the end if migrationBox is available by then.
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[HiveUserSession] migrationBox unavailable: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'hive_user_session_migration_box_unavailable'));
    }

    for (final root in userScopedBoxRoots) {
      final namespaced = namespacedBoxName(root, userId);
      try {
        // If namespaced already has any keys, migration already ran for
        // this user OR they signed in fresh post-namespacing. Skip.
        if (Hive.isBoxOpen(namespaced)) {
          if (Hive.box(namespaced).keys.isNotEmpty) continue;
        }

        // Try to open the legacy shared box. If it doesn't exist on
        // disk, openBox creates an empty one — check keys count and
        // delete-empty if so.
        final legacy = await Hive.openBox(root);
        if (legacy.keys.isEmpty) {
          await legacy.close();
          await Hive.deleteBoxFromDisk(root);
          continue;
        }

        // Open namespaced (creates if needed), copy every key/value,
        // close + delete legacy.
        final dest = Hive.isBoxOpen(namespaced)
            ? Hive.box(namespaced)
            : await Hive.openBox(namespaced);
        for (final key in legacy.keys) {
          await dest.put(key, legacy.get(key));
        }
        await legacy.close();
        await Hive.deleteBoxFromDisk(root);
        debugPrint(
          '[HiveUserSession] migrated $root → $namespaced (${dest.keys.length} keys)',
        );
      } catch (e, st) {
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[HiveUserSession] migration $root failed: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'hive_user_session_migrate_legacy_box'));
        // Non-fatal — fresh start, cloud has the data anyway.
      }
    }

    // Test #10.1 — set the run-once flag so this never runs again on
    // this device, even after sign-out / cross-account guard / etc.
    // Stored in `migrationBox` which is NEVER cleared by clearAllData.
    try {
      await HiveService.instance.migrationBox
          .put(_legacyMigrationFlagKey, true);
    } catch (e, st) {
      // audit-2026-05-11 H-42 — telemetry pair.
      debugPrint('[HiveUserSession] failed to set legacy migration flag: $e');
      unawaited(ErrorTelemetry.recordNonFatal(e, st,
          reason: 'hive_user_session_set_legacy_migration_flag'));
      // If we can't set the flag, the migration may re-run next time.
      // The migration body itself is idempotent for already-migrated
      // users (the `if (legacy.keys.isEmpty) … delete + continue` arm
      // handles the no-op path), so re-running is safe — just wasteful.
    }
  }

  /// Close + clear references to all user-scoped boxes. Files remain
  /// on disk (use `clearAllDataForCurrentUser` to delete contents).
  ///
  /// APK Test #15.1 / Bug C — public API serializes via [_sessionLock].
  static Future<void> closeAll() async {
    await _sessionLock.synchronized(_closeAllLocked);
  }

  static Future<void> _closeAllLocked() async {
    if (_currentOwnerFullId == null) return;
    final id = _currentOwnerFullId!;
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, id);
      if (Hive.isBoxOpen(boxName)) {
        await Hive.box(boxName).close();
      }
    }
    final closedHash = _currentOwnerHash;
    _currentOwnerHash = null;
    _currentOwnerFullId = null;
    // APK Test #15.4 / B1 Layer B — mirror cleared state.
    currentOwnerListenable.value = null;
    debugPrint('[HiveUserSession] closed all user-scoped boxes');
    // APK Test #12.8 — close event so we can detect close-races
    // (close fires while a sync is inflight → GuardedBox auto-open
    // fallback fires; we want to see the close timing).
    unawaited(ErrorTelemetry.logEvent('hive_session_closed',
        message: 'userId=${closedHash ?? "?"}'));
  }

  /// Delete every user-scoped box file for the **current** user.
  /// Used by signOut so leftover bytes can't surface on next sign-in.
  ///
  /// APK Test #15.1 / Bug C — public API serializes via [_sessionLock].
  static Future<void> deleteAllFilesForCurrentUser() async {
    await _sessionLock
        .synchronized(_deleteAllFilesForCurrentUserLocked);
  }

  static Future<void> _deleteAllFilesForCurrentUserLocked() async {
    if (_currentOwnerFullId == null) return;
    final id = _currentOwnerFullId!;
    for (final root in userScopedBoxRoots) {
      final boxName = namespacedBoxName(root, id);
      try {
        if (Hive.isBoxOpen(boxName)) {
          await Hive.box(boxName).close();
        }
        await Hive.deleteBoxFromDisk(boxName);
      } catch (e, st) {
        // audit-2026-05-11 H-42 — telemetry pair.
        debugPrint('[HiveUserSession] failed to delete $boxName: $e');
        unawaited(ErrorTelemetry.recordNonFatal(e, st,
            reason: 'hive_user_session_delete_box_file'));
      }
    }
    _currentOwnerHash = null;
    _currentOwnerFullId = null;
    // APK Test #15.4 / B1 Layer B — mirror cleared state.
    currentOwnerListenable.value = null;
  }
}
