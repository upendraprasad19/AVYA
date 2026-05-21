part of 'screen.dart';

extension _PerformSignOut on _ProfileScreenState {

  /// Sign out Supabase -> clear Hive -> route to auth screen.
  ///
  /// C-10 (audit-2026-05-11) — routed through
  /// `AuthNotifier.signOut()` so we get the canonical teardown:
  /// telemetry → `UserRepository.clearAllData()` →
  /// `HiveUserSession.deleteAllFilesForCurrentUser()` (DELETES the
  /// per-user namespaced box files, not just clears the contents) →
  /// `_supabase.client.auth.signOut()` → state reset to idle.
  ///
  /// Pre-fix this method bypassed `AuthNotifier.signOut()` entirely and
  /// skipped `deleteAllFilesForCurrentUser`. Per-user namespaced Hive
  /// files survived on disk — re-opening the cross-account leak class
  /// CLAUDE.md believes closed by namespacing. Same class as the
  /// splash-time guard bug fixed in C-6.
  Future<void> _performSignOut() async {
    try {
      await ref.read(authNotifierProvider.notifier).signOut();
    } catch (e) {
      debugPrint('[ProfileScreen._performSignOut] AuthNotifier.signOut: $e');
      // Defensive fallback — if the notifier path fails partway, still
      // try a raw supabase signOut so the auth state is at least
      // partially terminated before we route.
      try {
        await SupabaseService.instance.client.auth
            .signOut(scope: SignOutScope.local);
      } catch (e) {
        debugPrint('[ProfileScreen._performSignOut] fallback signOut: $e');
      }
    }

    if (mounted) {
      context.go('/sign-in');
    }
  }

// _showDeleteAccountDialog removed — Task H1 (APK Test #11).
// Hard-delete replaced with 2-step confirm screen at /profile/delete-account.
// The old soft-flag helper in UserRepository is now @Deprecated (no callers here).

  String _formatGoal(String goal) {
    switch (goal) {
      case 'build_muscle':
        return 'Building Muscle';
      case 'lose_fat':
        return 'Losing Fat';
      case 'general_fitness':
        return 'General Fitness';
      case 'strength':
        return 'Building Strength';
      default:
        return goal.isNotEmpty
            ? goal[0].toUpperCase() +
                goal.substring(1).replaceAll('_', ' ')
            : 'Building Foundation';
    }
  }
}
