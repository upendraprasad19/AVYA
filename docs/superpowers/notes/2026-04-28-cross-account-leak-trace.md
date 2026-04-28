# Cross-account leak trace — +3 APK (APK Test #4 ship)

**Date:** 2026-04-28
**Branch under audit:** `feat/apk-test-5-batch` (off `main` post-`feat/apk-test-1-batch`; **does not contain RestoringScreen**)
**Affected accounts:** `upendra.prasad@thinkingcode.com`, `avyaaanshfit@gmail.com`
**Symptom (OBS-5):** Sign out as Upendra → sign in as Avyaansh → AI coach screen shows Upendra's 13 chat messages locally even though cloud `ai_coach_interactions` is correctly scoped (Avyaansh = 2 rows, Upendra = 13 rows, separate `user_id`).

---

## Sign-out paths (all callers of `clearAllData`)

`grep -rn "clearAllData" lib/` — five hits across four files:

| # | File | Line | Caller | Notes |
|---|---|---|---|---|
| 1 | `lib/features/auth/providers/auth_provider.dart` | 293 | `AuthNotifier.signOut()` — primary path | Atomic-logout marker → Supabase signOut → `clearAllData()` → clear marker |
| 2 | `lib/features/auth/providers/auth_provider.dart` | 338 | `_ensureLocalUser` mismatch branch | Fires on next sign-in if stored `profile.id != user.id` |
| 3 | `lib/features/auth/screens/splash_screen.dart` | 123 | `_runDeferredInit` cross-account guard | Belt-and-suspenders; fires after `Supabase.initialize()` |
| 4 | `lib/features/profile/screens/profile_screen.dart` | 2037 | `_performSignOut()` — Profile screen sign-out | Independent of `AuthNotifier` |
| 5 | `lib/features/profile/screens/profile_screen.dart` | 2108 | `_showDeleteAccountDialog` | Account-delete flow |
| 6 | `lib/main.dart` | 62 | Atomic-logout recovery | Resumes interrupted `clearAllData` on cold start if `logout_in_progress` is `true` |

### Path 1: `auth_provider.dart::signOut` (lines 272-301)

```dart
Future<void> signOut() async {
  state = state.copyWith(status: AuthStatus.loading, errorMessage: null);
  final hive = HiveService.instance;
  try {
    await hive.configBox.put('logout_in_progress', true);  // F16 marker
  } catch (_) {}
  // 1. Terminate session.
  try {
    await _supabase.client.auth.signOut(scope: SignOutScope.global);
  } catch (_) {
    try { await _supabase.client.auth.signOut(scope: SignOutScope.local); } catch (_) {}
  }
  // 2. Clear all user data after session is gone.
  await UserRepository.instance.clearAllData();
  // 3. Atomic logout complete.
  try { await hive.configBox.delete('logout_in_progress'); } catch (_) {}
  state = const AuthState2(status: AuthStatus.idle);
}
```

Findings:
- Calls `clearAllData`? **Yes**, unconditional, after Supabase signOut.
- Calls `Hive.close()`? **No.** Boxes stay open across the wipe and the next sign-in — `_ensureLocalUser` writes into boxes that are still open.
- Order: sign-out first, then `clearAllData`. Reasonable: session is gone before local wipe begins.
- **`AuthNotifier.signOut` is NOT actually wired to the visible "SIGN OUT" button** — `ProfileScreen._performSignOut` (lines 2020-2045) is its own function that does `auth.signOut()` + `clearAllData()` directly. It does NOT set the `logout_in_progress` marker.

### Path 2: `splash_screen.dart` line 123 (lines 109-128)

```dart
try {
  final profile = HiveService.instance.userBox.get('profile');
  final localId = (profile is Map) ? profile['id'] as String? : null;
  final sessionId = SupabaseService.instance.currentUser?.id;
  if (localId != null && sessionId != null && localId != sessionId) {
    debugPrint('[splash] Hive/session id mismatch — local=$localId session=$sessionId. Clearing.');
    await UserRepository.instance.clearAllData();
    await SupabaseService.instance.client.auth.signOut();
  }
} catch (e) {
  debugPrint('[splash] profile-id mismatch check failed (non-fatal): $e');
}
```

Findings:
- Fires on EVERY cold start during `_runDeferredInit`, immediately after `SupabaseService.instance.initialize()`.
- Condition: BOTH `localId != null` AND `sessionId != null` AND they differ.
- **Critical gap (likely the OBS-5 root cause):** if `localId == null` (e.g. an older Hive write with no `'id'` field — the bootstrap stub at `auth_provider.dart:533-537` only sets id during `_ensureLocalUser`, not during onboarding's first profile write), the guard is skipped entirely, and stale `coachBox` / `workoutBox` survives untouched.
- Also skipped if `sessionId == null` (offline cold start before Supabase restores the session token).
- Race condition: this runs AFTER auth state is restored. If the user is hot-launching directly into AI coach screen via deep link, `coachBox` has already been read into Riverpod providers before this guard runs.

### Path 3: `profile_screen.dart::_performSignOut` (lines 2020-2045)

This is the **actual user-visible sign-out**. It does:
1. `supabase.auth.signOut(scope: SignOutScope.global)` (with local fallback).
2. `UserRepository.instance.clearAllData()`.
3. `context.go('/sign-in')`.

Findings:
- Does NOT set `logout_in_progress` marker → if killed mid-`clearAllData`, `main.dart`'s recovery path won't fire.
- Does NOT close Hive boxes — same as Path 1.
- No invalidation of Riverpod providers that hold cached data (e.g. `aiCoachConversationProvider`). On the very next `ref.read` inside the same engine session, providers may serve a cached old-user value — but normally the navigation to `/sign-in` rebuilds the tree.

### Path 4: `auth_provider.dart::_ensureLocalUser` mismatch branch (lines 335-340)

```dart
if (existing != null) {
  final existingId = (existing as Map<dynamic, dynamic>?)?['id'] as String?;
  if (existingId == null || existingId != user.id) {
    await UserRepository.instance.clearAllData();
  }
}
```

Findings:
- **Tightly defines what counts as "different user"**: missing id OR id mismatch → wipe. This is the SAME logic the splash guard uses, except it fires on next sign-in.
- IF `_ensureLocalUser` is called on the new sign-in (Path A: `signInWithEmail` → `_ensureLocalUser`), the wipe fires before any Hive read. Verified path covers OBS-5 *if* `_ensureLocalUser` fires.
- **CRITICAL: `ProfileScreen._performSignOut` does not call `_ensureLocalUser`** — it just `signOut()` + `clearAllData()` then routes to `/sign-in`. The router redirect logic itself doesn't invoke `_ensureLocalUser`. So the next sign-in screen MUST go through `AuthNotifier.signInWithEmail`/`signInWithGoogle`/`verifyOtp`, ALL of which call `_ensureLocalUser`. This appears solid IF the user signs in normally.

### Path 5: `main.dart` line 62 (atomic-logout recovery)

Reads `configBox['logout_in_progress']` on cold start. If `true`, runs `clearAllData()` again. Only set by `AuthNotifier.signOut` — NOT by `ProfileScreen._performSignOut`. So this is dead code for the actual sign-out path users hit from the UI.

---

## `UserRepository.clearAllData()` — what gets wiped (lines 200-210)

```dart
Future<void> clearAllData() async {
  await _hive.userBox.clear();
  await _hive.workoutBox.clear();
  await _hive.nutritionBox.clear();
  await _hive.healthBox.clear();
  await _hive.coachBox.clear();
  await _hive.syncBox.clear();
  await _hive.configBox.clear();
  await _hive.customBox.clear();
  // Keep exerciseBox and foodBox (seeded data, no need to re-downloaded)
}
```

Boxes registered in `HiveService` (line 50, 97, 188): **`notificationsBox`** is opened, but **NOT cleared in `clearAllData()`**. Verified by inspection — only 8 of 10 user-scoped boxes are wiped (`exerciseBox` + `foodBox` deliberately preserved as seeded reference data).

This is **a confirmed leak surface** for in-app notification history (OneSignal payloads stored locally), but `coachBox` (the source of OBS-5's 13 chat messages) IS in the wipe list. So `notificationsBox` is a real gap but probably not the OBS-5 cause.

---

## RestoringScreen ownership check

`grep -rn "_ensureOwnershipBeforeHome\|hiveOwner\|lastAuthenticatedUserIdKey" lib/` — **zero matches.**

`ls lib/features/auth/screens/` shows only:
- `sign_in_screen.dart`
- `splash_screen.dart`

**There is NO `restoring_screen.dart` in this branch.** The `RestoringScreen` + `_ensureOwnershipBeforeHome` + `lastAuthenticatedUserIdKey` infrastructure described in the prior-work notes (the "B1-B5 layers from Test #4") **does not exist on `feat/apk-test-5-batch`**. The branch was cut from `main` whose tip post-dates `feat/apk-test-1-batch` but pre-dates `feat/apk-test-2-batch` — so APK Test #2's Q1 RestoringScreen was never merged into the lineage this branch sits on.

This is the dominant fact of the investigation: **OBS-5 was reproduced on a build that has NO ownership guard**. The prior-investigation note ("on paper, B1-B5 should have prevented OBS-5") was based on a different branch.

---

## restoreFromCloudForUser filter audit

[deferred to Task A-3]

---

## Auto Backup XML

[deferred to Task A-4]

---

## Hypothesis — actual leak path

**Primary suspect: H4 + a corollary.**

H4 as stated (RestoringScreen ownership guard didn't fire because `lastAuthenticatedUserIdKey` was never stamped) is technically vacuous on this branch — there's no RestoringScreen to fire at all. The mechanism is the same in spirit: **there is no per-session ownership stamp, and the splash-line-123 guard is the ONLY belt-and-suspenders defense**, which has at least one bypass:

- If the prior session never persisted `userBox['profile']['id']` (e.g. Hive was first written by an old onboarding path before id-stamping was added, or `_ensureLocalUser` wrote a partial profile without the id, or a corrupted write), `localId == null` → guard skipped → stale `coachBox`/`workoutBox` survive.
- After `ProfileScreen._performSignOut`, `clearAllData` IS called — so on a clean sign-out + re-sign-in, OBS-5 should NOT reproduce. The fact that it does reproduce means one of:
  1. The user did NOT sign out via the UI; they used Supabase's session-expiry path or app-data-clear → only the splash guard runs → the `localId == null` window opens.
  2. Sign-out completed but the **next sign-in path that landed bypassed `_ensureLocalUser`** (e.g. session was already restored from token cache when the app launched; `_ensureLocalUser` only fires from `signInWith*` / `verifyOtp`, NOT from passive session restore on cold start).
  3. The UI fired sign-out, but `clearAllData` partially failed (one box `clear()` threw silently) and the next sign-in saw the `profile.id` matched (because userBox was successfully cleared) but `coachBox` was not cleared.

**Strongest suspect: #2 — passive session restore on cold start does NOT call `_ensureLocalUser`.** Sequence:
1. User signs in as Upendra → `_ensureLocalUser` writes Upendra's profile + populates Hive via syncs → `coachBox` fills with 13 messages.
2. User signs out via Profile screen → Supabase signOut + `clearAllData` (8 boxes wiped, notificationsBox NOT — but coachBox IS). After this, Hive should be empty.
3. User signs in as Avyaansh → `_ensureLocalUser` fires → writes new profile with `id=avyaansh_uuid`. Hive starts fresh.
4. **Somewhere in here, OBS-5 reproduces.** Either: (a) the sign-in for Avyaansh used a flow that didn't call `_ensureLocalUser`, OR (b) the Test #4 build the user was running has an earlier `clearAllData` that did NOT include `coachBox` and Avyaansh inherited it.

To verify which, A-3 must check whether `restoreFromCloudForUser` (or `restoreLightweightAlways`) re-pulls `ai_coach_interactions` from cloud and overwrites `coachBox` keyed by user_id, OR whether it merges into a single conversation list keyed by date (allowing Upendra's local messages to coexist with Avyaansh's cloud-pulled messages).

### Evidence supporting H4-corollary

- No RestoringScreen / ownership guard exists on this branch.
- `_ensureLocalUser`'s wipe condition is correct but only fires from explicit sign-in actions, not passive session restore.
- `clearAllData` does not include `notificationsBox` — proves the maintainer can forget a box; same class of bug could have existed for `coachBox` in an older build (verifiable by `git log -p` on `user_repository.dart`).
- `splash_screen.dart:123` guard requires `localId != null` AND a session — fragile.
- No box is closed/reopened across sign-out → potential for in-memory cache (Hive's lazy-box value cache) to serve stale values immediately after a `.clear()` call if the next read happens before the on-disk truncation is flushed.

---

## Recommendation for Layer 2 design

[1-paragraph summary feeding into Task A-5 design — TBD after A-3/A-4]
