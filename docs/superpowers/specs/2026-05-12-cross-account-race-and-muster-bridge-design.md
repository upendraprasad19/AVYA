# APK Test #15.4 — cross-account cache race + muster→profile bridge

> Date: 2026-05-12
> Origin: APK +23 (1.0.0+23) install — founder reproduced two regressions:
> (1) signOut as Upendra + signUp as sumit1@gmail.com showed Upendra's profile
> in Edit Profile until force-kill+reopen; (2) muster-collected injuries and
> body-part focus never reached `userBox['profile']`.
> Closes-diagnose: TBD on bug-id assignment.

---

## Summary

Two related write/read-drift bugs, fixed together because they touch the same
auth + Hive bootstrap surface.

| Bug | One-line summary |
|-----|------------------|
| **B1** | Riverpod token re-emits the moment Supabase fires `signedIn`, but `HiveUserSession.openForUser(newUid)` hasn't run yet — 56 user-scoped providers rebuild against the previous owner's namespaced Hive and cache wrong data under the new token. Cold start works (splash awaits openForUser before mounting UI), live signOut+signUp does not. |
| **B2** | `MusterScreen` (the 5-question post-onboarding AI chat) writes every answer to `coachBox` only — never bridged to `userBox['profile']`. Result: AI coach sees the muster answers, but Edit Profile and plan generator see defaults (`injuries=['none']`, `physique_focus='balanced'`). |

Class: both are **writer/reader field drift** — the canonical recurring class
captured in `memory/feedback_writer_reader_field_drift_recurring.md`. Test
\#15.3's c4055a fix addressed B1 at the Riverpod *cache-invalidation* layer
but left the Hive *box-owner-swap timing* unaddressed.

---

## Bug 1 — root cause + fix

### Root cause (sequence of events)

On a same-session signOut+signUp:

| t | Event | State of `HiveUserSession.currentOwnerFullId` |
|---|---|---|
| t0 | `Supabase.auth.signUp(sumit)` succeeds; SDK internally fires `signedIn(sumit)` on its auth stream | upendraId |
| t1 | `authStateProvider` (StreamProvider straight off Supabase's stream — `auth_provider.dart:24-30`) re-emits | upendraId |
| t2 | `authUserIdTokenProvider` (watches authStateProvider + currentUserProvider) re-emits `sumitId` | upendraId |
| t3 | All 56 user-scoped Riverpod providers rebuild. They call e.g. `UserRepository.getProfile()` → `_hive.userBox.get('profile')` → `wrapUserScopedBox` → reads from `userBox_<upendraHash>` because `currentOwnerFullId` is still upendraId | upendraId |
| t4 | Providers cache Upendra's profile data under the new sumit token | upendraId |
| t5 | The signUp call returns in our `signUpWithEmail` handler; we `await _ensureLocalUser(sumit)` | upendraId |
| t6 | `_ensureLocalUser` awaits `HiveUserSession.openForUser(sumitId)` | upendraId → sumitId |
| t7 | Owner swap complete. **No further Riverpod rebuild triggered** because nothing watches `HiveUserSession`. | sumitId |

On **cold start (force-kill + reopen)** the order is the opposite: splash
explicitly awaits `_ensureLocalUser` (→ `openForUser`) *before* `runApp` /
provider build, so by t1 the owner is already sumitId. That's why the
diagnostic test (kill+reopen → correct data) passed.

c4055a (this morning) added `authUserIdTokenProvider` and made 56 providers
`ref.watch` it so the cache invalidates on auth change. That's *necessary*
but not *sufficient* — it triggers a rebuild at t2 when the underlying Hive
owner is still wrong. The fix completes one half of the loop.

### Fix design (two-layer)

**Layer A — Read-side disagreement guard at `wrapUserScopedBox`** (single
point per founder direction Q1A; replaces sweeping 56 build bodies):

```dart
GuardedBox<T> wrapUserScopedBox<T>(String root) {
  final fullId = HiveUserSession.currentOwnerFullId;
  final hash = HiveUserSession.currentOwnerHash;

  String? authUid;
  try {
    authUid = Supabase.instance.client.auth.currentUser?.id;
  } catch (_) {}

  // NEW (B1 / Layer A) — race-window guard.
  // Hive is open for someone, but Supabase auth has changed to a different
  // user and openForUser hasn't caught up yet. Refuse to serve stale data.
  // This window is short (~50–500ms during signOut+signUp transitions) and
  // a brief "empty state" render is preferable to leaking the prior user's
  // data into the new user's session.
  if (authUid != null && fullId != null && authUid != fullId) {
    unawaited(ErrorTelemetry.logEvent(
      'guarded_box_disagreement',
      message: 'root=$root authUid=${authUid.substring(0, 8)} '
          'hiveOwner=${fullId.substring(0, 8)}',
    ));
    return GuardedBox<T>.empty(authUid);
  }

  // ... existing cold-start fallback + normal path unchanged
}
```

`GuardedBox.empty(authUid)` is a new factory that returns a wrapper whose
`get`/`getAll`/`values`/`keys` return null/empty without touching disk, and
whose `put`/`delete` throw `StateError("HiveUserSession not ready")` so
inflight writes fail loudly instead of silently writing to the wrong box.

**Layer B — Event-side rebuild trigger via observable HiveUserSession**:

1. **Add a static `ValueNotifier` to `HiveUserSession`:**

   ```dart
   class HiveUserSession {
     static final ValueNotifier<String?> currentOwnerListenable =
         ValueNotifier<String?>(null);
     // ... existing fields
   }
   ```

   Mutate it from the three locked methods after the static field flip:
   - `_openForUserLocked` → `currentOwnerListenable.value = userId;` (last
     line, after the cross-account guard).
   - `_closeAllLocked` → `currentOwnerListenable.value = null;` (after
     `_currentOwnerFullId = null`).
   - `_deleteAllFilesForCurrentUserLocked` → `currentOwnerListenable.value =
     null;` (after the field flip).

   All three already hold `_sessionLock`, so the listenable always mirrors
   the static field under the lock.

2. **New Riverpod wrapper `hiveSessionOwnerProvider`:**

   ```dart
   // lib/core/services/hive_session_owner_provider.dart
   final hiveSessionOwnerProvider = Provider<String?>((ref) {
     final notifier = HiveUserSession.currentOwnerListenable;
     void listener() => ref.invalidateSelf();
     notifier.addListener(listener);
     ref.onDispose(() => notifier.removeListener(listener));
     return notifier.value;
   });
   ```

3. **Rewire `authUserIdTokenProvider` to gate on agreement** (`auth_invalidation_provider.dart`):

   ```dart
   final authUserIdTokenProvider = Provider<String>((ref) {
     ref.watch(authStateProvider);
     final authUid = ref.watch(currentUserProvider)?.id;
     final hiveOwner = ref.watch(hiveSessionOwnerProvider);
     if (authUid == null || hiveOwner == null || authUid != hiveOwner) {
       return '<anon>';
     }
     return authUid;
   });
   ```

   **Effect on the timeline:**
   - t1 (Supabase fires): token sees authUid=sumit, hiveOwner=upendra →
     disagree → token = `<anon>`. Providers rebuild against `<anon>` →
     read via `wrapUserScopedBox` → Layer A guard fires → return empty.
     UI renders an empty/loading state for ~100ms.
   - t6 (`openForUser` completes): listenable fires →
     `hiveSessionOwnerProvider` invalidates → `authUserIdTokenProvider`
     recomputes: agree on sumit → emits `sumitId`. Providers rebuild
     against the now-correctly-namespaced Hive. UI shows Sumit's data.

The two layers are intentionally redundant: Layer A is the *correctness*
net (even if Layer B fails, no data leaks); Layer B is the *liveness* net
(without it, providers stay at empty forever).

### Files touched (B1)

- **NEW** `lib/core/services/hive_session_owner_provider.dart` — Riverpod
  wrapper around the listenable.
- **MOD** `lib/core/services/hive_user_session.dart` — add listenable, set
  it from 3 locked methods.
- **MOD** `lib/core/services/guarded_box.dart` — add `GuardedBox.empty`
  factory + disagreement guard in `wrapUserScopedBox`.
- **MOD** `lib/features/auth/providers/auth_invalidation_provider.dart` —
  add `hiveSessionOwnerProvider` watch + agreement gate.

No other file changes for B1. The 56 user-scoped providers already
`ref.watch(authUserIdTokenProvider)` from c4055a — they automatically
benefit from the new gating logic.

### Contract tests (B1)

- **`test/contracts/auth_invalidation_timing_test.dart`** — simulate the
  exact race: set `HiveUserSession.currentOwnerFullId` to upendraId,
  flip Supabase's mocked currentUser to sumit, pump providers, assert
  `authUserIdTokenProvider` value is `'<anon>'`. Then call
  `HiveUserSession.openForUser(sumitId)`, pump, assert token flips to
  `sumitId`.
- **`test/contracts/wrap_user_scoped_box_disagreement_test.dart`** —
  set up disagreement state, call `wrapUserScopedBox('userBox')`, assert
  returned `GuardedBox.get(any)` returns null and `.put` throws.

---

## Bug 2 — muster→profile bridge

### Scope (3 sub-changes, shipped together)

| # | Change | Why |
|---|---|---|
| 2a | Drop `MusterScreen` Q1 (`why_now`) and Q2 (`definition_of_winning`) | Founder direction — "stupid questions"; low signal for AI context, high user friction |
| 2b | Bridge muster answers into `userBox['profile']` (two writes per answer, atomic per Option B) | Closes the SoT drift — Edit Profile + plan generator need these values |
| 2c | Add new `preferred_workout_time` profile field (Hive + cloud migration + Edit Profile UI) | Q4 collects this; nowhere for it to land today |
| 2d | Change Q5 from 8-chip multi-select to 4-chip single-select matching the `physique_focus` enum | Enables identity 1:1 bridge (no fuzzy mapping) |

### 2a — Remove Q1 + Q2 from MusterScreen

File: `lib/features/ai_coach/screens/muster_screen.dart`

- Delete `_whyNowCtrl`, `_winningCtrl` + their `dispose()` calls.
- Delete `_onSubmitQ1`, `_onSubmitQ2`, `_buildQ1`, `_buildQ2`.
- Renumber: old Q3 (injuries) → new Q1; old Q4 (wake/workout) → new Q2;
  old Q5 (body parts) → new Q3.
- Update `_buildCurrentQ` switch to dispatch 0→`_buildQ3`, 1→`_buildQ4`,
  2→`_buildQ5` (preserving the existing widget method names since they
  still write to the same coachBox keys).
- Update `_buildProgress` from `List.generate(5, ...)` to
  `List.generate(3, ...)`.
- Initial `_showTypingThen(0)` unchanged — first question is now Q3
  (injuries).

Keep `InductionService._allowedMusterKeys` including `why_now` and
`definition_of_winning` so legacy data still round-trips on read without
error. The cloud `coach_memory` columns are not dropped.

### 2b — Bridge inside `InductionService.recordMusterAnswer`

File: `lib/features/ai_coach/services/induction_service.dart`

After the existing `coachBox.put(key, value)` line:

```dart
Future<void> recordMusterAnswer(String key, dynamic value) async {
  if (!_allowedMusterKeys.contains(key)) {
    throw ArgumentError('Unknown muster key: $key');
  }
  await HiveService.instance.coachBox.put(key, value);

  // NEW (B2b) — bridge into userBox['profile'] so Edit Profile and
  // plan generator see these values. Per CLAUDE.md §15 "Source of Truth
  // Rules" + memory/feedback_writer_reader_field_drift_recurring.md.
  await _bridgeToProfile(key, value);
}

Future<void> _bridgeToProfile(String musterKey, dynamic value) async {
  final Map<String, dynamic> fields;
  switch (musterKey) {
    case 'known_injuries':
      // value is List<String>; profile.injuries is List<String>.
      fields = {'injuries': (value as List).cast<String>()};
    case 'typical_wake_time':
      // value is "HH:MM"; profile.wake_up_time is "HH:MM".
      fields = {'wake_up_time': value as String};
    case 'preferred_workout_time':
      // value is "HH:MM"; profile.preferred_workout_time (new field).
      fields = {'preferred_workout_time': value as String};
    case 'body_part_priorities':
      // After B2d, value is a 1-element List<String> whose element is a
      // valid physique_focus enum value. Length>1 means a pre-B2d row;
      // skip the bridge in that case to stay safe.
      final v = (value as List).cast<String>();
      if (v.length != 1) return;
      fields = {'physique_focus': v.first};
    default:
      // why_now / definition_of_winning — no profile mapping. Skip.
      return;
  }

  await UserRepository.instance.updateProfileFields(fields);

  final uid = SupabaseService.instance.currentUser?.id;
  if (uid != null) {
    unawaited(SyncService.instance.syncProfileNow(uid));
    unawaited(SyncService.instance.pushSnapshot());
  }
}
```

The bridge is **atomic from the caller's POV** — every
`recordMusterAnswer` either writes both coachBox AND profile, or throws.
Profile sync fan-out is fire-and-forget per CLAUDE.md §15.

### 2c — New `preferred_workout_time` profile field

**Migration 062** — `supabase/migrations/062_add_preferred_workout_time.sql`:

```sql
-- APK Test #15.4 / Bug 2c — new profile column to capture muster
-- Q4's preferred_workout_time answer. Stored as "HH:MM" text matching
-- the existing wake_up_time column shape.
ALTER TABLE user_profile
  ADD COLUMN IF NOT EXISTS preferred_workout_time TEXT;
```

Apply via Supabase MCP `apply_migration`. Record in
`backups/applied_migrations.json` in the same commit per
`memory/feedback_migration_apply_record_pair.md`.

**Sync projection** — `lib/core/services/sync_service.dart`,
`_syncProfile` method: add `preferred_workout_time` to the projected
field list (mirror the existing `wake_up_time` pattern).

**Edit Profile UI** — `lib/features/profile/screens/edit_profile_screen.dart`:

- Add `TimeOfDay? _preferredWorkoutTime` state.
- Initialize from `profile['preferred_workout_time']` in `initState`
  (parse "HH:MM").
- Add a `_buildPreferredWorkoutTimeTile` widget mirroring the existing
  wake-up-time row layout. Place it directly below the wake-up-time row.
- Include in the `_save` field map.

### 2d — Q5 single-select matching physique_focus enum

File: `lib/features/ai_coach/screens/muster_screen.dart`

Current Q5 offers 8 body parts (`Back / Chest / Shoulders / Arms / Legs /
Glutes / Core / None`) as multi-select chips. After B2d:

```dart
static const _physiqueFocusOptions = <(String, String)>[
  ('balanced', 'Balanced — all-round'),
  ('glutes_legs', 'Glutes & Legs'),
  ('chest_shoulders_arms', 'Chest, Shoulders & Arms'),
  ('strength', 'Strength — heavy compounds'),
];

String? _physiqueFocus;  // replaces Set<String> _bodyParts
```

- `_setPhysiqueFocus(String key)` (replaces `_toggleBodyPart`):
  `setState(() => _physiqueFocus = key);`
- Bubble copy update: *"Where do you want to put extra emphasis? Pick
  one — your plan will weight that area."*
- `_onSubmitQ5` writes `[_physiqueFocus!]` (a 1-element List<String>) to
  coachBox key `body_part_priorities`. The List shape is preserved for
  the AI context reader at
  `ai_coach_repository.dart:212-213` which casts to `List` — no consumer
  changes needed.
- `COMPLETE MUSTER` button enabled only when `_physiqueFocus != null`.

The 4 enum keys ARE the chip values — no translation table needed
inside the bridge. `_bridgeToProfile('body_part_priorities', [key])` just
reads `[0]` and writes `profile.physique_focus = key`.

### Files touched (B2)

- **MOD** `lib/features/ai_coach/screens/muster_screen.dart` — drop Q1+Q2;
  Q5 single-select.
- **MOD** `lib/features/ai_coach/services/induction_service.dart` — add
  `_bridgeToProfile` method.
- **MOD** `lib/core/services/sync_service.dart` — add
  `preferred_workout_time` to `_syncProfile` projection.
- **MOD** `lib/features/profile/screens/edit_profile_screen.dart` — add
  `preferred_workout_time` picker tile + state.
- **NEW** `supabase/migrations/062_add_preferred_workout_time.sql`
- **MOD** `backups/applied_migrations.json` — record 062.

### Contract tests (B2)

- **`test/contracts/muster_profile_bridge_test.dart`** — for each of the
  4 bridged muster keys (`known_injuries`, `typical_wake_time`,
  `preferred_workout_time`, `body_part_priorities`), call
  `recordMusterAnswer(key, value)`. Assert BOTH
  `coachBox.get(key) == value` AND the mapped
  `userBox['profile'][profileField] == expectedMapped`.
- **`test/contracts/muster_question_count_test.dart`** — pump
  MusterScreen; assert progress bar renders exactly 3 dots; tap through
  in sequence and assert the captain bubble copies match Q3/Q4/Q5
  prompts.

---

## Backfill for existing users (Q1B locked = YES)

Existing users who completed muster before this batch have answers in
`coachBox` but `profile.injuries` and `profile.physique_focus` still at
defaults. **One-shot backfill** on next `_ensureLocalUser`, gated by a
`migrationBox` flag so it runs at most once per device:

**Location:** `lib/features/auth/providers/auth_provider.dart`,
`_ensureLocalUser`, after `HiveUserSession.openForUser` succeeds and
before the existing migrators.

```dart
await _backfillMusterToProfileIfNeeded();
```

**Implementation** (new private method on `AuthNotifier` or a free
function in `induction_service.dart`):

```dart
static const String _backfillFlagKey = 'muster_bridge_backfill_v1_done';

Future<void> _backfillMusterToProfileIfNeeded() async {
  try {
    final mig = HiveService.instance.migrationBox;
    if (mig.get(_backfillFlagKey) == true) return;

    final coach = HiveService.instance.coachBox;
    final updates = <String, dynamic>{};

    final injuries = coach.get('known_injuries');
    final profile = UserRepository.instance.getProfile() ?? {};
    if (injuries is List && injuries.isNotEmpty) {
      final existing = profile['injuries'];
      final isDefault = existing == null ||
          (existing is List && (existing.isEmpty ||
              (existing.length == 1 && existing.first == 'none')));
      if (isDefault) updates['injuries'] = injuries.cast<String>();
    }

    final wake = coach.get('typical_wake_time');
    if (wake is String && wake.isNotEmpty &&
        (profile['wake_up_time'] == null ||
            (profile['wake_up_time'] as String).isEmpty)) {
      updates['wake_up_time'] = wake;
    }

    final preferredWorkout = coach.get('preferred_workout_time');
    if (preferredWorkout is String && preferredWorkout.isNotEmpty &&
        profile['preferred_workout_time'] == null) {
      updates['preferred_workout_time'] = preferredWorkout;
    }

    final bodyParts = coach.get('body_part_priorities');
    if (bodyParts is List && bodyParts.length == 1) {
      final v = bodyParts.first as String;
      final validEnum = const {
        'balanced', 'glutes_legs', 'chest_shoulders_arms', 'strength',
      }.contains(v);
      final currentDefault = (profile['physique_focus'] as String?) == 'balanced';
      if (validEnum && currentDefault && v != 'balanced') {
        updates['physique_focus'] = v;
      }
    }

    if (updates.isNotEmpty) {
      await UserRepository.instance.updateProfileFields(updates);
      final uid = SupabaseService.instance.currentUser?.id;
      if (uid != null) {
        unawaited(SyncService.instance.syncProfileNow(uid));
        unawaited(SyncService.instance.pushSnapshot());
      }
    }

    await mig.put(_backfillFlagKey, true);
  } catch (e, st) {
    debugPrint('[muster bridge backfill] failed: $e');
    unawaited(ErrorTelemetry.recordNonFatal(e, st,
        reason: 'muster_bridge_backfill'));
    // Do NOT set the flag on failure — let it retry next launch.
  }
}
```

**Idempotency contract:** backfill only writes to a profile field if
that field is currently at its default value. So if the user has already
manually edited (e.g.) `injuries` post-muster, the backfill won't
clobber the edit. `body_part_priorities` legacy data may be multi-select
(>1 element); we skip those — user can re-pick on Edit Profile if they
care.

For the legacy multi-select case where `bodyParts.length > 1` the
backfill skips by design (no fuzzy mapping). The user's existing
coachBox data isn't touched.

**One-line contract test** verifies the flag stops re-runs.

---

## Migration ordering (deploy / build sequence)

1. Apply migration 062 to prod via Supabase MCP `apply_migration`.
2. Update `backups/applied_migrations.json` in the same commit.
3. Land code + tests in one PR on `feat/apk-test-15-4-batch`.
4. Merge `--no-ff` to main after green CI + manual smoke.
5. `/build-apk` — pre-flight Gate 14 will verify the migrations record
   matches schema. Skill refuses build if dirty / on feature branch
   per `memory/feedback_main_is_source_of_truth.md`.

---

## Out of scope (explicit)

- Removing `why_now` / `definition_of_winning` columns from cloud
  `coach_memory` — preserve existing rows. If we add the questions back
  later (different copy), no migration needed.
- Validating `preferred_workout_time > typical_wake_time` — defer.
- Re-running muster for users with multi-select legacy
  `body_part_priorities` — they keep their old answer in coachBox; Edit
  Profile picks up the default. They can re-pick via Edit Profile.
- Cleaning up the unused 4 unused chip options (Back / Core /
  Glutes / Arms standalone) — they're gone from muster Q5; no library to
  prune.

---

## CLAUDE.md updates (post-merge)

- **§19 Common Bugs** — new entries for B1 ("Live signOut+signUp leaks
  prior user's profile until force-kill") and B2 ("Muster answers don't
  reach Edit Profile / plan generator — writer/reader drift between
  coachBox and userBox['profile']"). Reference closes-diagnose IDs.
- **§15 Source of Truth Rules** — add the muster→profile bridge as a
  named writer chain: "muster answers (`InductionService.recordMusterAnswer`)
  write coachBox AND mirror specific fields into `userBox['profile']`
  via `_bridgeToProfile`. Single-writer guarantee: never write
  `coachBox['known_injuries']` etc. from anywhere else."
- **`docs/sot_registry.yaml`** — add entries for the 4 bridged keys with
  writer = `InductionService.recordMusterAnswer`, readers = profile
  consumers + AI context builders.

---

## Test plan summary

| New test | Asserts |
|---|---|
| `auth_invalidation_timing_test.dart` | Token returns `<anon>` during authUid ≠ hiveOwner disagreement; flips to userId after openForUser completes |
| `wrap_user_scoped_box_disagreement_test.dart` | `wrapUserScopedBox` returns empty GuardedBox when Supabase user ≠ `currentOwnerFullId`; `.put` throws |
| `muster_profile_bridge_test.dart` | Every muster `recordMusterAnswer` for the 4 mapped keys writes BOTH buckets atomically |
| `muster_question_count_test.dart` | MusterScreen renders exactly 3 questions; progress bar 3 dots |
| `muster_bridge_backfill_test.dart` | One-shot backfill copies coachBox values into profile defaults; flag prevents re-run; existing non-default values not clobbered |

Plus the existing `auth_invalidation_contract_test.dart` source-grep
test stays in place — it verified the *wiring* (each provider watches
the token). The new `auth_invalidation_timing_test.dart` verifies the
*timing* (the token doesn't lie about readiness).

---

## Risk + rollback

- **B1 Layer A blast radius:** Every user-scoped Hive read now passes
  through the disagreement guard. If the guard misfires (e.g. Supabase
  briefly returns null currentUser during token refresh), reads return
  empty for ~1 frame. Mitigation: guard only fires when *both*
  `authUid != null` AND `fullId != null` AND `authUid != fullId` — a
  transient null on either side skips the guard.
- **B1 Layer B blast radius:** Token now goes `<anon>` more often (any
  disagreement window). UI must tolerate `<anon>` → typically renders
  empty state for ~100ms. Verify on splash + restore screen with
  manual smoke before merge.
- **B2 bridge blast radius:** New `_bridgeToProfile` write can throw if
  `UserRepository.updateProfileFields` fails (e.g. Hive corruption). The
  throw propagates up and the muster screen catches via the existing
  `try/catch` around `recordMusterAnswer`. The user sees a toast and can
  retry. coachBox write already succeeded — bridge re-runs on next
  attempt.
- **Rollback:** revert single commit on `feat/apk-test-15-4-batch`. The
  migration 062 column stays (no rollback migration needed — unused
  columns are harmless). Backfill flag stays set so it doesn't re-fire.

---

## Open questions for plan phase

None. All design decisions locked:

- Q1A: single-point guard at `wrapUserScopedBox` (✓ + Layer B unavoidable
  for liveness).
- Q1B: backfill yes.
- Q2A: Option B (two writes, atomic).
- Q2B: add `preferred_workout_time` profile field.
- Q2C: muster Q5 → single-select matching enum (B3).
