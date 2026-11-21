// lib/core/services/sync_domains/profile_sync_domain.dart
//
// [SyncDomain] wrapper for the user-identity part-file surfaces (audit
// 2026-05-20 / A6 — B5 D7-D8 batch).
//
// Wraps `lib/core/services/sync/sync_profile.dart` via the public
// forwarders on `SyncServiceProfile`.
//
// Sub-surfaces:
//   - user_profile     : _syncUserProfile     ↔ _restoreUserProfile
//   - user_progress    : _syncUserProgress    ↔ _restoreUserProgress
//   - user_preferences : _syncUserPreferences ↔ _restoreUserPreferences
//
// NOT YET WIRED — `SyncFlags.useDomainFor('profile')` defaults FALSE.

import 'package:icanbefitter/core/services/sync_domain.dart';
import 'package:icanbefitter/core/services/sync_service.dart';

class ProfileSyncDomain extends SyncDomainBase {
  ProfileSyncDomain({SyncService? syncService})
      : _syncService = syncService ?? SyncService.instance;

  final SyncService _syncService;

  @override
  String get name => 'profile';

  @override
  Future<void> push() async {
    await Future.wait([
      _syncService.pushUserProfileForSyncDomain(),
      _syncService.pushUserProgressForSyncDomain(),
      _syncService.pushUserPreferencesForSyncDomain(),
    ], eagerError: false);
  }

  @override
  Future<void> restore() async {
    await Future.wait([
      _syncService.restoreUserProfileForSyncDomain(),
      _syncService.restoreUserProgressForSyncDomain(),
      _syncService.restoreUserPreferencesForSyncDomain(),
    ], eagerError: false);
  }
}
