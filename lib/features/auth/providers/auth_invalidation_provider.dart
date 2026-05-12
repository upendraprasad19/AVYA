import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final user = ref.watch(currentUserProvider);
  return user?.id ?? '<anon>';
});
