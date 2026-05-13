---
bug_id: 7bd154
date: 2026-05-12
batch: APK Test #15.4
status: in-progress
symptom: After signing out as Upendra and signing up as sumit1@gmail.com on the same session, Edit Profile rendered Upendra's profile (174 cm / 77.8 kg / DOB 1988-06-30) until the app was force-killed and reopened. The Riverpod cache held the previous user's profile because providers rebuilt on the Supabase auth event before HiveUserSession.openForUser had completed swapping the box owner.
concept: cross_account_riverpod_cache_race
sot_registry_entry: hive_user_session_owner
writers:
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: HiveUserSession.openForUser, line: 123 }
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: HiveUserSession.closeAll, line: 335 }
  - { file: lib/core/services/hive_user_session.dart, method_or_widget: HiveUserSession.deleteAllFilesForCurrentUser, line: 363 }
readers:
  - { file: lib/core/services/hive_session_owner_provider.dart, method_or_widget: hiveSessionOwnerProvider, line: 16 }
  - { file: lib/features/auth/providers/auth_invalidation_provider.dart, method_or_widget: authUserIdTokenProvider, line: 25 }
  - { file: lib/core/services/guarded_box.dart, method_or_widget: wrapUserScopedBox, line: 162 }
hive_key_prefix: "n/a — static singleton state"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/contracts/auth_invalidation_timing_test.dart
ist_handling: []
provider_invalidations:
  - hiveSessionOwnerProvider
  - authUserIdTokenProvider
telemetry_op_types:
  success:
    - hive_session_opened
    - hive_session_closed
  failure:
    - guarded_box_disagreement
cross_account_guard: "Two-layer fix. Layer A — wrapUserScopedBox returns GuardedBox.empty() when Supabase auth.currentUser.id != HiveUserSession.currentOwnerFullId; reads serve null/empty/0/false/true and writes throw StateError. Layer B — HiveUserSession.currentOwnerListenable is a ValueNotifier mutated under _sessionLock from openForUser/closeAll/deleteAllFilesForCurrentUser; hiveSessionOwnerProvider wraps it; authUserIdTokenProvider returns '<anon>' until authUid == hiveOwner."
forbidden_patterns_checked:
  - "user_scoped Hive read while HiveUserSession.currentOwnerFullId is stale"
  - "Riverpod provider rebuild keyed only on Supabase auth event"
proposed_fix: "Add ValueNotifier<String?> currentOwnerListenable to HiveUserSession (mirrors _currentOwnerFullId from 3 locked methods). New hiveSessionOwnerProvider wraps it. Rewire authUserIdTokenProvider to return '<anon>' until Supabase authUid agrees with the listenable. Add disagreement guard at top of wrapUserScopedBox returning GuardedBox.empty(authUid) — a new factory that short-circuits reads to null/empty and throws on writes."
regression_test_planned:
  - { file: test/contracts/auth_invalidation_timing_test.dart, method_or_widget: token_returns_anon_when_authUid_and_hiveOwner_disagree, line: 1 }
  - { file: test/contracts/wrap_user_scoped_box_disagreement_test.dart, method_or_widget: GuardedBox_empty_returns_null_on_get_and_throws_on_put, line: 1 }
---
# Body

## Class

Recurring "writer/reader field drift" — same family as APK Test #6 → #15.3. Sub-class: token-emits-before-async-resource-is-ready. The Riverpod token (`authUserIdTokenProvider`) re-emits the moment `Supabase.auth.onAuthStateChange` fires `signedIn`, but the underlying Hive box owner is swapped asynchronously *after* by `_ensureLocalUser → HiveUserSession.openForUser`. Providers rebuild against the previous owner's namespaced Hive and cache the wrong data under the new token. Cold start works because splash awaits `_ensureLocalUser` before UI mounts; only the live in-session sign-out+sign-up race window is affected.

## Prior fix that didn't fully close it

`c4055a` (APK Test #15.3 / Bug 5) — added `authUserIdTokenProvider` and made 56 user-scoped providers `ref.watch` it. Necessary but not sufficient: it correctly invalidated the Riverpod cache on auth change, but the Hive owner was still wrong at the moment of rebuild.

## Sequence of events

| t | Event | currentOwnerFullId |
|---|---|---|
| t0 | `Supabase.auth.signUp(sumit)` succeeds; SDK fires signedIn(sumit) | upendraId |
| t1 | `authStateProvider` re-emits | upendraId |
| t2 | `authUserIdTokenProvider` re-emits sumitId | upendraId |
| t3 | All 56 providers rebuild → call `getProfile()` → reads from `userBox_<upendraHash>` | upendraId |
| t4 | Providers cache Upendra's profile under sumit token | upendraId |
| t5 | `await _ensureLocalUser(sumit)` runs (lib/features/auth/providers/auth_provider.dart:116) | upendraId |
| t6 | `HiveUserSession.openForUser(sumit)` completes swap | upendraId → sumitId |
| t7 | No further rebuild — providers stuck with Upendra's data | sumitId |

## Fix

Two layers, both required.

**Layer A** (correctness — `lib/core/services/guarded_box.dart`): new `GuardedBox.empty` factory returns a wrapper that short-circuits all reads to null/empty/0/false/true and throws `StateError` on all writes. `wrapUserScopedBox` checks `Supabase.auth.currentUser.id` against `HiveUserSession.currentOwnerFullId` at every call; on disagreement, returns `GuardedBox.empty(authUid)` and emits telemetry `guarded_box_disagreement`. No leak even if Layer B fails.

**Layer B** (liveness — `lib/core/services/hive_user_session.dart` + `lib/core/services/hive_session_owner_provider.dart` + `lib/features/auth/providers/auth_invalidation_provider.dart`): `HiveUserSession` exposes `static final ValueNotifier<String?> currentOwnerListenable`, mutated under `_sessionLock` from the 3 locked methods. `hiveSessionOwnerProvider` is a Riverpod `Provider<String?>` that watches the listenable. `authUserIdTokenProvider` now requires `authUid == hiveOwner` to emit a real userId; otherwise returns `'<anon>'`. Effect: at t1-t5 above, token emits `'<anon>'` (Layer B) → providers render empty (Layer A guarantees no leak even if they didn't); at t6, listenable fires → token re-emits sumit → providers rebuild against correctly-namespaced Hive.

## Regression test

`test/contracts/auth_invalidation_timing_test.dart` — 3 tests: disagreement→`<anon>`, agreement→userId, listenable-flip triggers re-emit.

`test/contracts/wrap_user_scoped_box_disagreement_test.dart` — 1 test (7 assertions) for `GuardedBox.empty` semantics.

The pre-existing `test/contracts/auth_invalidation_contract_test.dart` source-grep test stays — it verifies the *wiring* (each provider watches the token). The new tests verify the *timing* (the token doesn't lie about readiness).

## Files

- NEW: `lib/core/services/hive_session_owner_provider.dart`
- MOD: `lib/core/services/hive_user_session.dart` (+ listenable, mirror writes from 3 locked methods)
- MOD: `lib/core/services/guarded_box.dart` (+ GuardedBox.empty factory + disagreement guard in wrapUserScopedBox)
- MOD: `lib/features/auth/providers/auth_invalidation_provider.dart` (token gates on agreement)

Spec: `docs/superpowers/specs/2026-05-12-cross-account-race-and-muster-bridge-design.md`
Plan: `docs/superpowers/plans/2026-05-12-apk-test-15-4-batch.md`
