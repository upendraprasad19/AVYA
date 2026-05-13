import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:icanbefitter/core/services/hive_session_owner_provider.dart';
import 'package:icanbefitter/features/auth/providers/auth_provider.dart';

/// Token provider whose identity changes on every auth state change.
///
/// **Every user-scoped Notifier/Provider MUST `ref.watch(authUserIdTokenProvider)`
/// in its `build()` body.** When the user signs in / out / up, this provider
/// re-emits, triggering a rebuild of every downstream consumer → the rebuild
/// re-reads from now-correctly-namespaced Hive boxes (via
/// `HiveUserSession.openForUser`) and produces fresh state for the new user.
///
/// Closes APK Test #15.3 / Bug 5 (closes-diagnose: c4055a). The contract is
/// pinned by `test/contracts/auth_invalidation_contract_test.dart` — any new
/// provider file in `lib/features/*/providers/` that reads user-scoped data
/// MUST also watch this token, or the source-grep test fails.
///
/// Anonymous sessions resolve to the sentinel `'<anon>'` so providers also
/// re-emit on sign-out (token transitions from `<id>` → `<anon>`).
///
/// This provider watches `authStateProvider` (the Supabase auth state stream)
/// so it actually re-emits on auth changes. `currentUserProvider` reads
/// synchronously from `SupabaseService.instance.currentUser` and does not
/// itself subscribe to the auth stream; watching it alone would not produce
/// the re-emit we need.
final authUserIdTokenProvider = Provider<String>((ref) {
  // Subscribe to the auth state stream so this provider rebuilds on every
  // sign-in / sign-out / token refresh.
  ref.watch(authStateProvider);
  final authUid = ref.watch(currentUserProvider)?.id;

  // APK Test #15.4 / B1 Layer B — gate on agreement with HiveUserSession.
  // Auth-state-changed alone is not the moment user-scoped Hive becomes
  // safe to read. _ensureLocalUser awaits openForUser AFTER auth fires,
  // so this provider returns '<anon>' until the listenable confirms the
  // box swap completed for the same user id.
  //
  // Cold start: hiveOwner is set by splash bootstrap before UI mounts →
  // agreement on first read → token = authUid.
  // Live signOut+signUp: hiveOwner lags auth by a tick → token = '<anon>'
  // → 56 user-scoped providers render empty for ~100ms → listenable
  // fires when openForUser completes → token = authUid → providers
  // re-render with correctly-namespaced data.
  final hiveOwner = ref.watch(hiveSessionOwnerProvider);
  if (authUid == null || hiveOwner == null || authUid != hiveOwner) {
    return '<anon>';
  }
  return authUid;
});
