// AUTH_INVALIDATION_EXEMPT: this provider DEFINES authUserIdTokenProvider —
// the very provider every user-scoped consumer is required to watch. It derives
// its token from the LIVE Supabase auth uid + the Hive session owner listenable
// directly; watching itself would be a tautology.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:icanbefitter/core/services/guarded_box.dart'
    show debugAuthUidResolverForTests;
import 'package:icanbefitter/core/services/hive_session_owner_provider.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';
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
/// Reactivity: watches `authStateProvider` (the Supabase auth-state stream) so
/// it re-emits on every sign-in / sign-out / token-refresh, AND
/// `hiveSessionOwnerProvider` so it re-emits when `openForUser` stamps the new
/// owner. The auth uid itself is read LIVE from `SupabaseService.currentUser`
/// on each rebuild — NOT via `currentUserProvider`.
///
/// OBS-6 residual (a7f2e1, 2026-07-02): `currentUserProvider` (auth_provider.dart)
/// is a plain, non-reactive `Provider` that caches `SupabaseService.currentUser`
/// on first read and is NEVER invalidated. On an in-session account switch
/// (sign-out A → sign-in B) it stays cached as A, so the owner-edge rebuild here
/// used to read authUid=A ≠ hiveOwner=B → `'<anon>'` forever → every mixin tab's
/// `isSessionTearingDown` gate stuck on the skeleton (Home/Train/Nutrition/
/// Profile). Reading the LIVE uid — the SAME source `wrapUserScopedBox` uses
/// (guarded_box.dart) so the gate and the box agree — lets the owner-edge rebuild
/// recover. Kill-switch `configBox['disable_live_auth_token_read']` reverts to
/// the verbatim cached-provider read (§4.6). Recurrence of b8e3f1 (OBS-6): that
/// fix repaired the box read + the blank-Home/error-card symptom but did not
/// touch the token source, so the neutral stuck-SKELETON residual survived.
final authUserIdTokenProvider = Provider<String>((ref) {
  // Reactivity: re-emit on auth-state changes AND on the owner-edge
  // (openForUser stamps the owner → hiveSessionOwnerProvider invalidates).
  ref.watch(authStateProvider);
  final hiveOwner = ref.watch(hiveSessionOwnerProvider);

  // Kill-switch (§4.6): global configBox flag, default absent/false ⇒ fix ON.
  // Defensive read — an unopened/throwing box (early boot / pure-VM test) keeps
  // the fix ON. GLOBAL configBox (never user-scoped → no recursion through
  // wrapUserScopedBox). Mirrors guarded_box.dart's disable_null_owner_serve_empty.
  var liveReadDisabled = false;
  try {
    liveReadDisabled =
        Hive.box('configBox').get('disable_live_auth_token_read') == true;
  } catch (_) {
    // configBox unopened → keep the fix ON.
  }

  String? authUid;
  if (liveReadDisabled) {
    // Verbatim pre-fix path (kill-switch engaged): the cached currentUserProvider.
    authUid = ref.watch(currentUserProvider)?.id;
  } else {
    // The fix — LIVE read. `debugAuthUidResolverForTests` (shared with
    // guarded_box) lets pure-VM tests inject a uid without a Supabase singleton.
    try {
      authUid = debugAuthUidResolverForTests?.call() ??
          SupabaseService.instance.currentUser?.id;
    } catch (_) {
      // Supabase singleton not initialised (very early boot / pure-VM test).
      authUid = null;
    }
  }

  // APK Test #15.4 / B1 Layer B — gate on agreement with HiveUserSession.
  // Auth-state-changed alone is not the moment user-scoped Hive becomes safe to
  // read. _ensureLocalUser awaits openForUser AFTER auth fires, so this returns
  // '<anon>' until the listenable confirms the box swap completed for the same
  // user id. The authUid==hiveOwner equality IS the cross-account guard — a
  // mismatch (or either being null) yields '<anon>', so a stale/wrong uid can
  // never serve another account's box.
  if (authUid == null || hiveOwner == null || authUid != hiveOwner) {
    return '<anon>';
  }
  return authUid;
});
