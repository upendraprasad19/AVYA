---
bug_id: b8e3f1
date: 2026-06-21
batch: fix-session-open-race
status: fixed
blast_radius: platform
symptom: >
  Full-charter web E2E (2026-06-21, OBS-6): in-session sign-out → sign-in as a
  DIFFERENT user → blank Home (and a cold-boot deep-link to /coach/induction
  showed "Something went wrong"). Root cause: during the sign-out → sign-in gap,
  HiveUserSession owner is cleared to null before openForUser for the new user
  runs, WHILE every user-scoped Riverpod provider rebuilds on the
  authUserIdTokenProvider='<anon>' signal and reads user-scoped Hive. The
  Layer-A disagreement guard in wrapUserScopedBox only serves GuardedBox.empty
  when the Hive owner is NON-null and disagrees; the owner-NULL-but-authenticated
  transient fell through to `throw StateError('HiveUserSession not opened …')`
  → the provider rebuild threw → blank Home. It is a provider-rebuild race, NOT
  a routing bug.
concept: auth_hive_owner_agreement
sot_registry_entry: auth_hive_owner_agreement
contract_test_path: test/contracts/wrap_user_scoped_box_null_owner_authenticated_test.dart
writers: >
  Part A — lib/core/services/guarded_box.dart `wrapUserScopedBox`: the
  owner-null branch now serves `GuardedBox<T>.empty(authUid)` (with telemetry
  `guarded_box_null_owner_authenticated`) WHEN a Supabase session is
  authenticated, mirroring the existing :253 disagreement-empty branch; the loud
  `throw StateError` is kept ONLY when UNAUTHENTICATED (a genuine
  read-before-openForUser ordering bug). Part B — lib/core/router/app_router.dart
  `_authRedirect` routes an authenticated-but-owner-null navigation to /restoring
  (via the pure `AppRouter.shouldGateOnSessionOpen` predicate, onboarding-exempt)
  so the empty-serve never mis-routes an onboarded user to /onboarding;
  lib/features/auth/screens/restoring_screen.dart `_onContinueAnyway` now awaits
  `HiveUserSession.openForUser` before navigating so the guard cannot infinite-loop.
readers: >
  Every Hive-touching Riverpod provider + WriteService reads user-scoped boxes
  through `wrapUserScopedBox` (e.g. home_provider TodayWorkoutNotifier,
  nutrition/health/subscription providers). Layer B
  (HiveUserSession.currentOwnerListenable → authUserIdTokenProvider) re-invalidates
  every watcher once openForUser stamps the new owner, so they rebuild with real
  data. `_authRedirect` reads onboarding_completed via MigratedKey (user-scoped).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: "not_applicable"
ist_handling: not_applicable
provider_invalidations:
  - "authUserIdTokenProvider (Layer B) — unchanged; relied upon to re-invalidate every user-scoped watcher once openForUser sets the owner, so the empty-served window self-heals."
telemetry_op_types:
  success: []
  failure:
    - "guarded_box_null_owner_authenticated — emitted (unawaited) when wrapUserScopedBox serves empty during the owner-null-but-authenticated window; sibling of guarded_box_disagreement / guarded_box_auto_open_fallback so a non-race masking stays measurable."
cross_account_guard: true
forbidden_patterns_checked:
  - "wrapUserScopedBox owner-null path no longer throws unconditionally — serves GuardedBox.empty only when AUTHENTICATED; UNAUTHENTICATED owner-null still throws loud. Pinned by wrap_user_scoped_box_null_owner_authenticated_test.dart (both branches)."
  - "GuardedBox.empty WRITES still throw (guarded_box.dart put/putAll/delete/clear) — an inflight fire-and-forget sync can NOT silently leak into the wrong box during the race. Pinned by the same test (put → throwsA StateError)."
  - "Box namespacing (hive_user_session.namespacedBoxName) unchanged — empty-serve returns an empty stub, never another user's box. No cross-account read leak."
proposed_fix: >
  Two-layer. Part A (the headline): extend wrapUserScopedBox's owner-null branch
  to serve GuardedBox.empty when authenticated (reads → null/empty, writes →
  throw-loud) instead of throwing, so the provider-rebuild race renders an empty
  state that Layer B immediately re-invalidates; keep the throw for the
  unauthenticated ordering-bug case. Part B (cold-boot / mis-route defense):
  _authRedirect routes authenticated-owner-null navigations through /restoring
  (onboarding-exempt) and _onContinueAnyway opens the session before navigating
  so the guard cannot trap on the reinstall ~36s-restore CONTINUE path. A
  debugAuthUidResolverForTests seam lets a pure-VM unit test drive the owner-null
  path behaviorally (the production Supabase.instance read can't be initialised
  in a unit test); the seam preserves the inline Supabase string the auto-open
  source-grep test asserts.
regression_test_planned: >
  test/contracts/wrap_user_scoped_box_null_owner_authenticated_test.dart
  (behavioral, RED→GREEN: owner-null+authenticated serves empty + reads null +
  writes throw; owner-null+unauthenticated still throws) and
  test/contracts/auth_redirect_session_open_guard_test.dart (truth table for
  AppRouter.shouldGateOnSessionOpen incl. the onboarding-exempt no-trap case).
  Sibling guards verified still green: guarded_box_auto_open_test (source-grep
  strings preserved), wrap_user_scoped_box_disagreement_test,
  auth_hive_owner_agreement_behavioral_test (Layer B liveness).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "guarded_box.dart Part A + app_router.dart Part B + restoring_screen.dart _onContinueAnyway; flutter analyze (3 files) clean; 2 new tests + 3 sibling guard tests green" }
  - { tier: 2, layer: hive_local_state, status: verified, evidence: "GuardedBox.empty reads return null/empty (guarded_box.dart:96), writes throw StateError (:101-129) — pinned by the new behavioral test; namespacing isolates per-user boxes" }
  - { tier: 12, layer: client_server_contract, status: verified, evidence: "sign-out→sign-in + cold-boot deep-link auth flows traced; Layer A (serve-empty) + Layer B (currentOwnerListenable re-invalidation) both intact; no RLS/cloud change" }
impact_analysis: >
  Platform-class by consequence (the cross-account isolation primitive): the
  symptom was an app-unusable blank Home on every in-session account switch — the
  exact path that, mis-handled, leaks one user's data into another's session.
  The fix preserves isolation: empty-serve returns an empty stub (never another
  user's box), writes still throw-loud, and namespacing is unchanged — so there
  is no cross-account read OR write leak, only a transient empty state that Layer
  B heals within the same frame-loop. No migration, no cloud, no Edge Function.
---

# Session-open race: blank Home on in-session account switch (b8e3f1)

## What happened
On a live sign-out → sign-in as a different user, Supabase auth flipped and every
user-scoped Riverpod provider rebuilt on `authUserIdTokenProvider='<anon>'`,
reading user-scoped Hive through `wrapUserScopedBox` during the gap before
`HiveUserSession.openForUser(newUser)` ran. The Layer-A disagreement guard only
serves an empty box when the Hive owner is non-null and disagrees; the
**owner-null-but-authenticated** transient fell through to the
`throw StateError('HiveUserSession not opened …')` at `guarded_box.dart:292` →
the rebuild threw → blank Home (OBS-6). The same throw class produced the
cold-boot `/coach/induction` "Something went wrong" before the dedicated
`inductionCompleted` null-guard landed.

## Why it was mis-diagnosed (rounds 1–3 → R4)
Rounds 1–3 read it as a routing bug and proposed a router guard, which does NOT
fix symptom (a) — there is no route change during the provider race. R4's deep
trace pinned it to the provider rebuild vs the `:292` throw. The fix is therefore
**two-layer**: Part A (serve-empty in the guard) for the race; Part B (router
guard + continue-override) for cold-boot deep-links and to stop Part A's
empty-serve from mis-routing an onboarded user to `/onboarding`.

## Fix
- **Part A** — `wrapUserScopedBox` serves `GuardedBox.empty(authUid)` on
  owner-null **when authenticated**; keeps the loud throw when unauthenticated.
- **Part B** — `_authRedirect` routes authenticated-owner-null → `/restoring`
  (onboarding-exempt, via the testable `shouldGateOnSessionOpen` predicate);
  `_onContinueAnyway` opens the session before navigating (no infinite trap).

## Why it's safe (not "masking the bug")
The existing Layer A/B design already intends "race → empty box → Layer B
rebuild" — this only closes the null-owner gap the disagreement branch missed.
`GuardedBox.empty` reads serve empty but **writes throw**, so an inflight sync
can't leak into the wrong box; namespacing means empty ≠ another user's data.

## OBS-4 sibling — logout "Failed to load profile" flash (folded into this fix)
The full-charter live re-walk re-confirmed OBS-4 (P3): during sign-out the
Profile screen briefly flashed "Failed to load profile / Tap to retry". Cause:
`auth_provider.signOut()` clears Hive data + owner (`clearAllData` →
`deleteAllFilesForCurrentUser`) BEFORE `Supabase.auth.signOut()` and BEFORE the
router redirect, so the still-mounted tab screen rebuilds, reads an empty box
(`authUserIdTokenProvider` is already `'<anon>'` the moment the owner clears),
its `_buildContent` throws, and the per-screen `catch → ErrorState` shows the
error card. The same flash can hit any of the 4 tab screens (home/train/
nutrition/profile — all on `HiveTabScaffoldMixin`) during the FIX-1 account
swap. **Fix:** a shared `HiveTabScaffoldMixin.isSessionTearingDown` getter
(`ref.watch(authUserIdTokenProvider) == '<anon>'`); each tab screen ORs it into
its `isLoading` branch → renders the neutral skeleton during a teardown/pre-open
window instead of the error card. Pre-existing (observed pre-FIX-1, P3);
cosmetic; no isolation impact. Pinned by
`test/contracts/session_teardown_skeleton_guard_test.dart`.

## See also
- lib/core/services/guarded_box.dart (Part A + the debugAuthUidResolverForTests seam)
- lib/core/router/app_router.dart (Part B guard + shouldGateOnSessionOpen)
- lib/features/auth/screens/restoring_screen.dart (_onContinueAnyway openForUser)
- lib/shared/mixins/hive_tab_scaffold.dart (OBS-4 isSessionTearingDown guard) + the 4 tab screens
- test/contracts/wrap_user_scoped_box_null_owner_authenticated_test.dart
- test/contracts/auth_redirect_session_open_guard_test.dart
- test/contracts/session_teardown_skeleton_guard_test.dart (OBS-4)
- docs/diagnoses/2026-05-30-induction-redirect-session-race-*.md (the redirect-read sibling)
