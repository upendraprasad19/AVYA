// Source-grep contract for the onesignal_player_id write path.
//
// Originally landed as T-7 of `audit_2026_05_11_t1_t11_contracts_test.dart`.
// Split per concept per tech-debt audit 2026-05-20 T12.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  // Audit 2026-05-20 / A1: onesignal_player_id write logic relocated from
  // auth_provider.dart into AuthSessionBootstrapper.pushOneSignalPlayerId
  // (lib/core/services/auth_session_bootstrapper.dart). Source-grep
  // checks both files for the canonical writer. Per
  // `feedback_source_grep_false_confidence.md`, this is presence-only;
  // behavioral test lives at
  // `test/contracts/auth_session_bootstrapper_test.dart`.
  group('T-7 onesignal_player_id write contract', () {
    test('auth-stack writes pushSubscription.id to user_progress', () {
      final authSrc =
          _src('lib/features/auth/providers/auth_provider.dart');
      final bootstrapperSrc = _src(
          'lib/core/services/auth_session_bootstrapper.dart');
      final hasPushId = authSrc.contains('OneSignal.User.pushSubscription.id') ||
          authSrc.contains('pushSubscription.id') ||
          bootstrapperSrc.contains('OneSignal.User.pushSubscription.id') ||
          bootstrapperSrc.contains('pushSubscription.id');
      expect(hasPushId, isTrue,
          reason:
              'auth_provider OR auth_session_bootstrapper must read '
              'OneSignal.User.pushSubscription.id after OneSignal.login() and '
              'upsert to user_progress.onesignal_player_id. Without this, '
              'delete-account.push-unsub has no player_id to act on.');

      final hasColumn = authSrc.contains('onesignal_player_id') ||
          bootstrapperSrc.contains('onesignal_player_id');
      expect(hasColumn, isTrue,
          reason:
              'auth_provider OR auth_session_bootstrapper must reference '
              'onesignal_player_id column.');
    });
  });
}
