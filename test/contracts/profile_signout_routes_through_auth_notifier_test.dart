// C-10 (audit-2026-05-11) — regression test that
// `ProfileScreen._performSignOut` delegates to
// `AuthNotifier.signOut()` instead of hand-rolling Supabase signOut +
// `UserRepository.clearAllData()`. Pre-fix the screen-local
// implementation skipped `HiveUserSession.deleteAllFilesForCurrentUser`,
// leaving per-user namespaced box files on disk — re-opening the
// cross-account leak class CLAUDE.md §19 documents as closed.
//
// Source-grep style — the production code touches GoRouter +
// Riverpod + Hive lifecycle, so unit testing the flow is not
// tractable. The contract we pin instead: the signout path on the
// profile screen MUST route through AuthNotifier.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String relPath) => File(relPath).readAsStringSync();

void main() {
  group('C-10 ProfileScreen._performSignOut routes through AuthNotifier', () {
    test(
      '_performSignOut delegates to authNotifierProvider.signOut()',
      () {
        final src = _src('lib/features/profile/screens/profile_screen.dart');
        final idx = src.indexOf('Future<void> _performSignOut() async');
        expect(idx, greaterThan(0));
        // Slice generously — the method body is short; stop at the
        // next sibling method declaration (`\n  /// ` or `\n  Future`).
        final endA = src.indexOf('\n  /// ', idx + 10);
        final endB = src.indexOf('\n  Future<', idx + 10);
        final candidateEnds =
            [endA, endB].where((i) => i > idx).toList()..sort();
        final endIdx = candidateEnds.isEmpty ? src.length : candidateEnds.first;
        final body = src.substring(idx, endIdx);

        expect(
          body,
          contains('ref.read(authNotifierProvider.notifier).signOut()'),
          reason:
              '_performSignOut must route through AuthNotifier.signOut() so '
              'every sign-out gets the canonical teardown — telemetry, '
              'UserRepository.clearAllData, HiveUserSession.deleteAllFilesForCurrentUser, '
              'and state reset. Pre-fix the screen path skipped '
              'deleteAllFilesForCurrentUser and left per-user namespaced '
              'Hive files on disk.',
        );
      },
    );

    test(
      '_performSignOut does NOT call UserRepository.clearAllData directly',
      () {
        final src = _src('lib/features/profile/screens/profile_screen.dart');
        final idx = src.indexOf('Future<void> _performSignOut() async');
        final endA = src.indexOf('\n  /// ', idx + 10);
        final endB = src.indexOf('\n  Future<', idx + 10);
        final candidateEnds =
            [endA, endB].where((i) => i > idx).toList()..sort();
        final endIdx = candidateEnds.isEmpty ? src.length : candidateEnds.first;
        final body = src.substring(idx, endIdx);

        expect(
          body.contains('UserRepository.instance.clearAllData'),
          isFalse,
          reason:
              'Pre-fix this method called clearAllData directly. The '
              'canonical AuthNotifier.signOut() now owns that call '
              '(plus deleteAllFilesForCurrentUser). Duplicating it here '
              'risks drift if AuthNotifier evolves.',
        );
      },
    );

    test(
      'AuthNotifier.signOut still calls deleteAllFilesForCurrentUser',
      () {
        // Belt-and-suspenders — if AuthNotifier.signOut() ever drops the
        // namespaced-file cleanup, the cross-account leak comes back.
        final src = _src('lib/features/auth/providers/auth_provider.dart');
        final idx = src.indexOf('Future<void> signOut() async');
        expect(idx, greaterThan(0));
        final endIdx = src.indexOf('\n  /// Reset back to idle', idx);
        final body = src.substring(idx, endIdx > idx ? endIdx : src.length);

        expect(
          body,
          contains('HiveUserSession.deleteAllFilesForCurrentUser'),
          reason:
              'AuthNotifier.signOut() must delete the per-user namespaced '
              'Hive files. Without this the next sign-in re-opens those '
              'files and Android Auto Backup / legacy migration sweeps '
              'can re-leak the previous user.',
        );
      },
    );
  });
}
