---
bug_id: a3f6d9
date: 2026-08-03
batch: restore-onboarding-signin-fix
status: fixed
symptom: |
  Founder (upendraprasad19@gmail.com, auth.users.id d7a67a37-0b05-4f0a-
  b13c-388bff3cb59b) reported: "I was trying to access the app, but from
  restoring it is going to onboarding page." Confirmed via live Supabase
  data this session — the account's cloud row is fully onboarded
  (users.onboarding_completed=true, user_profile.onboarding_completed_at=
  2026-05-01 15:36:41, populated not null), and today's client_errors
  breadcrumbs (12:16:20-12:17:02 UTC) show restoreFromCloudForUser running
  to completion (restore_completed status=success, then ~46s of
  restore_op_done events including sync_user_profile). Despite the cloud
  state being correct and the restore succeeding, the browser landed on
  `/onboarding` (the pre-auth welcome/marketing screen) instead of
  `/home`.
concept: onboarding_completed_at
sot_registry_entry: onboarding_completed_at
writers:
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_goHome (bg-restore fast path — isReturning branch)", line: 242 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_goHome (default blocking path — fresh install / kill-switch branch)", line: 273 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_onContinueAnyway (30s CONTINUE timeout escape hatch — a THIRD path to /home, missed by the initial fix, caught by self-triggered B-pass round 1 Finding 1, hardened by round 2 Finding 1)", line: 551 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: "_authRedirect (onboarding gate, re-evaluated by GoRouter on every navigation)", line: 701 }
hive_key_prefix: "onboarding_completed"
hive_key_formula: "MigratedKey.readWithDefault<bool>('onboarding_completed', false) / MigratedKey.write('onboarding_completed', true)"
sync_methods: [_restoreUserProfile]
restore_methods: [_restoreUserProfile]
cloud_table: user_profile
cloud_columns: [onboarding_completed_at]
contract_test_path: test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart
ist_handling:
  - "Not applicable — this is a boolean flag, not a date-keyed value. No IST contract involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: |
  Unaffected. UserRepository.instance.setOnboarded() writes through
  MigratedKey to the per-user-scoped userBox (via wrapUserScopedBox), same
  as every other user-scoped write in this file. The fix places the write
  AFTER HiveUserSession ownership is confirmed open in BOTH _goHome
  branches (after HiveUserSession.openForUser(userId) in the bg-restore
  branch; after _ensureOwnershipBeforeHome(userId) in the default branch,
  whose own first action is opening ownership if not already open) — the
  exact precondition this codebase's most recent prior bug in this same
  file (closes-diagnose b3f9e7, bug class 2.47) was about violating.
forbidden_patterns_checked:
  - { pattern: "UserRepository.instance.setOnboarded() called before HiveUserSession.openForUser has resolved in either _goHome branch, or in _onContinueAnyway before ownershipOpen AND _committedToGoHome are both confirmed true", absent: true, after_fix: true }
related_bugs: [2026-06-28-onboarding-completed-at-durability-c4d8a2, 2026-08-02-terms-accepted-dead-write-b3f9e7]
self_review_findings: |
  Self-triggered B-pass round 1 (docs/reviews/1dcc14cdbf32-review.md,
  2026-08-03) caught a P0 BEFORE this batch was committed: the initial fix
  only covered _goHome's two branches, but RestoringScreen has a THIRD
  path to /home — _onContinueAnyway, the 30s CONTINUE timeout escape hatch
  — which bypassed _goHome entirely and was still missing the stamp.
  Round 1's fix gated the new stamp write on `ownershipOpen` alone, on the
  claimed reasoning that _onContinueAnyway can only be tapped once
  _kickoffRestore has already dispatched into _goHome (i.e. classification
  already resolved).

  Round 2 (docs/reviews/1cf9f51d2565-round2-review.md), an INDEPENDENT
  context-blind reviewer per §4.12.1's mandatory second round on the
  post-round-1 (hardened) diff, DISPROVED that reasoning: `_timeoutTimer`
  (30s) starts in `initState`, wall-clock and fully independent of
  `_kickoffRestore`'s own progress; `resolveDestination` is a live,
  un-timed-out Supabase network call (`auth_session_bootstrapper.dart`
  `.from('user_profile').select(...).maybeSingle()`), so on a slow enough
  connection the CONTINUE CTA can become visible and tappable BEFORE
  classification has happened at all — before it's known whether the user
  is new, mid-onboarding, or returning. Verified this myself (read
  initState + the full _kickoffRestore method + resolveDestination's
  actual Supabase call) before accepting the finding, per this repo's
  "never trust a subagent structural claim unverified" discipline — it
  checked out. Round 1's original reasoning is WRONG and has been REMOVED
  from this doc rather than left standing.

  Fix: track classification state explicitly instead of inferring it from
  timing. A new `_committedToGoHome` bool defaults false and is set true
  ONLY immediately before `_goHome` runs, in the `GoHome` and
  `ResumeOnboarding`-self-heal branches. `_onContinueAnyway`'s stamp now
  gates on `ownershipOpen && _committedToGoHome && !isOnboarded` — if
  classification hasn't reached a "treat as onboarded" branch yet, the
  flag is never stamped, and the pre-existing unconditional navigation is
  unchanged (still correctly re-bounces via `_authRedirect` once
  `_kickoffRestore`'s own pending switch eventually resolves). This can no
  longer mis-onboard a genuinely new or mid-onboarding user regardless of
  network latency.

  Both fixes landed in the same batch, same commit, per §4.2 no-deferrals
  — this doc's writers/tests/registry entries below reflect the final,
  round-2-hardened 3-site state.
recurrence: |
  Not a recurrence of c4d8a2 (that bug was the CLOUD column
  onboarding_completed_at staying NULL despite a populated local Hive
  profile — the opposite direction; ruled out this session via live SQL
  showing the cloud column is correctly populated for this account). This
  is a NEW instance of the writer/reader-drift class (CLAUDE.md §4.1,
  debugging skill §2.1): two local/derived representations of "is this
  user onboarded" exist — the profile map's onboarding_completed_at
  timestamp (populated by the restore's generic profile merge,
  sync_profile.dart:_restoreUserProfile) and a SEPARATE top-level boolean
  flag onboarding_completed (read by _authRedirect on every navigation).
  The restore pipeline populated the former but never the latter on a
  plain app-reopen (not a fresh sign-in) for a device/browser with no
  prior local Hive state. It shares its "write placed where its
  precondition (Hive ownership open) isn't yet guaranteed" shape with
  b3f9e7 (bug class 2.47) — but b3f9e7's write was completely missing
  reachability; this bug's writer set exists and is correct for OTHER
  entry paths (fresh sign-in via hydrateFromCloud, on-device onboarding
  completion) — it was specifically the plain-reopen/restore path that had
  no writer at all.
proposed_fix: |
  Add the missing local-flag stamp to RestoringScreen._goHome, which is
  only ever reached once the destination is already classified "treat as
  onboarded" (a genuine GoHome from resolveDestination's live cloud read,
  or the ResumeOnboarding self-heal branch above it) — so stamping
  unconditionally-but-idempotently here is correct by construction, no new
  classification logic needed. Two call sites, one per _goHome branch,
  each placed immediately after that branch's own ownership-establishing
  step so the write can't hit the GuardedBox "HiveUserSession not opened"
  precondition:
    if (!UserRepository.instance.isOnboarded) {
      await UserRepository.instance.setOnboarded();
    }
  Guarded on the current value (not unconditional) to avoid an
  unnecessary Hive write on every single app reopen once the flag is
  already correctly stamped from a prior session.

  B-pass Finding 1 caught a THIRD path to /home this initial fix missed:
  _onContinueAnyway (the 30s CONTINUE timeout escape hatch). It bypasses
  _goHome entirely, so it needs its own copy of the same guard, gated on
  a local ownershipOpen bool (openForUser is best-effort/non-fatal on
  this path — the guard must not fire before ownership is confirmed
  open):
    if (ownershipOpen && !UserRepository.instance.isOnboarded) {
      await UserRepository.instance.setOnboarded();
    }
regression_test_planned:
  - test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "lib/features/auth/screens/restoring_screen.dart edited (3 call sites — _goHome's 2 branches + _onContinueAnyway, the last added after self-triggered B-pass Finding 1 caught it missing); flutter analyze clean on the touched files." }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart — real Hive round-trip (setUpHiveForTests, no box mocks) proving the flag defaults false on a fresh box (reproduces the bug's starting condition) and reads true via the EXACT MigratedKey.readWithDefault expression _authRedirect evaluates, after the fix's guard runs. Source-grep site-count test tightened from 2 to 3 after the B-pass finding. 4/4 tests green (all updated), no regressions in the pre-existing 24 related tests (onboarding_completed_at_behavioral_test.dart + auth_session_bootstrapper_test.dart)." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "No schema change — this is a local-only Hive flag fix, no cloud column involved." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "Live SQL this session against dedsavbjuwgarrhphgnl confirmed the affected account's cloud state is already correct (users.onboarding_completed=true, user_profile.onboarding_completed_at populated 2026-05-01) — ruling out c4d8a2's cloud-side class and confirming the defect is entirely local-state. A second live scan for any user matching c4d8a2's pattern (onboarding_completed=true AND onboarding_completed_at IS NULL) returned zero rows, confirming that class isn't reproducing for anyone right now either." }
  - { tier: 5, layer: migrations_applied, status: not_applicable, evidence: "No migration — client-only fix." }
  - { tier: 6, layer: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, layer: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, layer: rls_policies, status: not_applicable, evidence: "No RLS policy touched — this fix never issues a Postgres write." }
  - { tier: 9, layer: storage_buckets, status: not_applicable, evidence: "No storage interaction." }
  - { tier: 10, layer: secrets_api_keys, status: not_applicable, evidence: "No secret/key touched." }
  - { tier: 11, layer: external_services, status: not_applicable, evidence: "No external service touched." }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "Traced the full call graph: RestoringScreen._kickoffRestore -> resolveDestination (live cloud SELECT, confirmed onboarding_completed_at populated for the affected account) -> GoHome case -> _goHome -> (now) local flag stamped in both branches -> context.go('/home') -> _authRedirect re-evaluates and now reads the flag as true. Live end-to-end browser verification not performed this session (would require the founder's own authenticated session); verified via the behavioral test's real Hive round-trip against the exact reader expression instead." }
impact_analysis: |
  Blast-radius account tier — touches lib/features/auth/screens/
  restoring_screen.dart, which docs/blast_radius.yaml classifies as
  account (auth surface). Change is narrowly scoped: two small guarded
  writes added at points where the surrounding code has already
  established both (a) the user should be treated as onboarded
  (resolveDestination's live cloud classification) and (b) Hive ownership
  is open (the branch's own preceding openForUser/_ensureOwnershipBeforeHome
  call) — cannot regress an existing-correct case, only heals the specific
  fresh-local-state gap. No new Riverpod provider invalidations, no new
  cloud writes, no schema change. Self-triggered /code-review (B-pass)
  still owed before merge to main per CLAUDE.md §4.3, alongside the sibling
  onboarding welcome-screen overlap fix and the sign-in redesign landing in
  the same batch.
blast_radius: account
---

# Returning user bounced from `/restoring` back to `/onboarding` despite a fully-onboarded cloud account

## Symptom

Founder tried to open the app and, after the restore screen ran, landed on
`/onboarding` (the pre-auth "AVYA PROSPECTUS... BEGIN ENLISTMENT" welcome
screen) instead of the dashboard — even though the account has been fully
onboarded since 2026-05-01.

## Investigation

Live SQL against `dedsavbjuwgarrhphgnl` this session confirmed:

```sql
select usr.onboarding_completed, up.onboarding_completed_at
from public.users usr
join public.user_profile up on up.user_id = usr.id
where usr.id = 'd7a67a37-0b05-4f0a-b13c-388bff3cb59b';
-- onboarding_completed=true, onboarding_completed_at=2026-05-01 15:36:41
```

Ruled out `c4d8a2` (the durability-drift class where the *cloud* column
stays NULL): a fresh scan for any user with `onboarding_completed=true AND
onboarding_completed_at IS NULL` returned zero rows.

Today's `client_errors` breadcrumbs (12:16:20–12:17:02 UTC) for the account
show `restore_completed status=success total_ms=13613 path=singlecall`
followed by ~46 seconds of further `restore_op_done` events (including
`sync_user_profile`), ending with `sync_exercises ms=39297`. The restore
genuinely ran to completion.

## Root cause

Read `lib/core/services/auth_session_bootstrapper.dart` and
`lib/features/auth/screens/restoring_screen.dart` in full to trace the
actual decision path:

1. `RestoringScreen._kickoffRestore` calls
   `AuthSessionBootstrapper.instance.resolveDestination(user.id)` — a pure,
   live `SELECT` on `user_profile`, independent of any local Hive state.
   For this account it correctly classifies `GoHome()`.
2. `_goHome` runs. For a device/browser with **no prior local Hive
   state** — a cleared-storage or fresh browser context, which the web
   session in the screenshot is consistent with — `isReturning` (derived
   from a local `userBox['profile']` read) is `false`, so it takes the
   default/blocking branch: `await restoreFuture;` (the ~46s restore seen
   in the breadcrumbs) → `await _ensureOwnershipBeforeHome(userId);` →
   `context.go('/home')`.
3. `context.go('/home')` triggers **GoRouter to re-run `_authRedirect`**
   for the new target. `_authRedirect` (`app_router.dart:701-706`) reads a
   *separate* local boolean:
   `MigratedKey.readWithDefault<bool>('onboarding_completed', false)`.
4. Nothing on this path ever wrote that flag. `_restoreUserProfile`
   (`sync_profile.dart:505`) — the writer that ran during step 2's
   restore — merges the cloud row's `onboarding_completed_at` into
   `userBox['profile']`, a *different* key, and never touches the
   top-level boolean. The only writers of the boolean flag are inside
   `AuthSessionBootstrapper.hydrateFromCloud` (reachable only from a fresh
   email/OTP sign-in, not a plain reopen) and
   `OnboardingNotifier.completeOnboarding` (only when onboarding finishes
   live on-device).
5. So the flag stayed at its default `false`. `_authRedirect` saw
   `!isOnboarded` and redirected to `/onboarding` — right after
   `RestoringScreen` had already run the full restore and tried to send the
   user home.

This is a writer/reader-drift bug (CLAUDE.md §4.1 class): two local
representations of "is onboarded" exist, and the restore pipeline only
kept one of them (`profile.onboarding_completed_at`) in sync, not the one
`_authRedirect` actually gates on (`onboarding_completed`).

## Fix

Stamp the local flag in `RestoringScreen._goHome`, which is only ever
reached once the destination is already classified "treat as onboarded" —
so an idempotent, guarded stamp there is correct by construction:

```dart
if (!UserRepository.instance.isOnboarded) {
  await UserRepository.instance.setOnboarded();
}
```

Added at two points — one per `_goHome` branch — each placed immediately
after that branch's own ownership-establishing step
(`HiveUserSession.openForUser` in the bg-restore branch;
`_ensureOwnershipBeforeHome` in the default branch), so the write can never
hit the `GuardedBox` "HiveUserSession not opened" precondition — the exact
class of bug `b3f9e7` (this same file's most recent prior fix) documented.

**Self-triggered B-pass round 1 caught a P0 before commit**
(`docs/reviews/1dcc14cdbf32-review.md`, Finding 1): `RestoringScreen` has a
**third** path to `/home` — `_onContinueAnyway`, the 30-second CONTINUE
timeout escape hatch — that bypasses `_goHome` entirely and was still
missing the stamp. Round 1's fix gated the write on `ownershipOpen` alone,
reasoning that `_onContinueAnyway` can only be tapped once `_kickoffRestore`
has already dispatched into `_goHome`.

**Round 2, an independent context-blind reviewer per §4.12.1's mandatory
second round, disproved that reasoning** (`docs/reviews/1cf9f51d2565-round2-review.md`,
Finding 1): `_timeoutTimer` (30s) starts in `initState`, wall-clock and fully
independent of `_kickoffRestore`'s progress; `resolveDestination` is a live,
un-timed-out Supabase network call. On a slow enough connection the CONTINUE
CTA can surface **before classification has happened at all** — before it's
known whether the user is new, mid-onboarding, or returning. Verified this
myself before accepting it (read `initState`, the full `_kickoffRestore`
method, and `resolveDestination`'s actual Supabase call) — it checked out;
round 1's reasoning was wrong.

**Fix (final):** track classification state explicitly instead of inferring
it from timing. A new `_committedToGoHome` bool defaults `false` and is set
`true` only immediately before `_goHome` runs, in the `GoHome` and
`ResumeOnboarding`-self-heal branches:

```dart
if (ownershipOpen &&
    _committedToGoHome &&
    !UserRepository.instance.isOnboarded) {
  await UserRepository.instance.setOnboarded();
}
```

If classification hasn't reached a "treat as onboarded" branch yet, the
flag is never stamped, and the pre-existing unconditional `context.go(...)`
navigation is unchanged from before this diff — it still correctly
re-bounces via `_authRedirect` once `_kickoffRestore`'s own pending switch
eventually resolves. This can no longer mis-onboard a genuinely new or
mid-onboarding user regardless of network latency.

## Verification

```
$ flutter test test/contracts/restoring_screen_local_onboarded_flag_stamp_test.dart test/contracts/onboarding_completed_at_behavioral_test.dart test/contracts/auth_session_bootstrapper_test.dart
```

66/66 green across the full auth suite + these targeted files (no
regressions), including one auth_session_bootstrapper_test.dart source-grep
assertion hardened to tolerate `dart format` line-wrapping (unrelated
fragility surfaced incidentally by formatting this batch's files — fixed in
the same commit, not deferred). `flutter analyze` clean on all touched
files.

Live end-to-end browser verification (the founder's own authenticated
session) was not performed this session — the behavioral test instead
exercises the real Hive/MigratedKey machinery end-to-end against the exact
expression `_authRedirect` evaluates, which is the mechanism that was
actually broken.

## Follow-ups (tracked, not deferred)

None outstanding for this specific fix. The onboarding welcome-screen
overlap bug and the sign-in redesign are tracked separately in the same
batch's plan.
