---
bug_id: c2e9f4
date: 2026-08-10
batch: google-signin-misroute
status: fixed
symptom: |
  Founder (upendraprasad19@gmail.com, auth.users.id d7a67a37-0b05-4f0a-
  b13c-388bff3cb59b) signed in with GOOGLE to an account created by email in
  May, force-closed the app during a slow restore, reopened it, and landed on
  the onboarding MISSION BRIEF screen instead of the dashboard. Identified
  from the screen's founder photo (assets/founder/upendra.jpg,
  mission_brief_screen.dart:76 — hardcoded and unique to that screen), which
  pins the route as /onboarding/mission-brief and therefore the destination as
  StartMissionBrief. Live SQL confirms the account is fully onboarded:
  users.onboarding_completed=true, user_profile.onboarding_completed_at=
  2026-05-01 15:36:41, and all 5 columns resolveDestination selects populated.
  One auth.users row carrying both an `email` and a `google` identity
  (providers: [email, google]) — NOT an account-identity problem. No data was
  lost: user_profile.updated_at is still 2026-05-01 10:05:21, so the funnel
  was never completed.
concept: onboarding_completed_at
sot_registry_entry: onboarding_completed_at
writers:
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "resolveDestination — returns DestinationUnknown instead of StartMissionBrief when the read cannot complete; ensureFreshToken + one hard-refresh retry first", line: 150 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "DestinationUnknown — the new sealed-hierarchy state for 'the read did not answer'", line: 75 }
  - { file: lib/core/services/local_onboarding_evidence.dart, method_or_widget: "hasLocalOnboardedEvidence — shared pure predicate (flag OR all 9 migration-112 fields)", line: 52 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "case StartMissionBrief — now consults local evidence before routing to onboarding (previously consulted nothing)", line: 119 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "case DestinationUnknown — new branch; never routes into onboarding", line: 147 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method_or_widget: "_ensureHiveSessionOpenForEvidence — opens the session BEFORE the evidence read so it is not served GuardedBox.empty", line: 254 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "completeOnboarding — refuses to overwrite an already-onboarded cloud profile", line: 359 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "shouldRefuseOnboardingOverwrite — pure decision, mutation-proven", line: 280 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: "_authRedirect — reads the local onboarding_completed flag on EVERY navigation and redirects to /onboarding when false", line: 707 }
hive_key_prefix: "onboarding_completed"
hive_key_formula: "MigratedKey.readWithDefault<bool>('onboarding_completed', false) / MigratedKey.write('onboarding_completed', true); profile map at userBox['profile']"
sync_methods: [_restoreUserProfile]
restore_methods: [_restoreUserProfile]
cloud_table: user_profile
cloud_columns: [onboarding_completed_at]
contract_test_path: test/contracts/local_onboarding_evidence_behavioral_test.dart
ist_handling:
  - "Not applicable — this is a routing decision over a boolean flag and a nullness check on a timestamptz. No date-key or counter-reset semantics involved."
provider_invalidations: []
telemetry_op_types:
  success: [restoring_missionbrief_overridden_by_local_evidence, resolve_destination_retry_succeeded, onboarding_overwrite_refused]
  failure: [resolve_destination_unknown, restoring_destination_unknown, resolve_destination_token_refresh_failed, restoring_evidence_session_open_failed, restoring_local_evidence_read_failed, onboarding_overwrite_guard_check_failed]
cross_account_guard: |
  Strengthened, not weakened. The new evidence read goes through
  HiveUserSession.ensureOpenedForCurrentSession() FIRST, so it reads the
  correct user's namespaced boxes rather than being served GuardedBox.empty.
  This does not introduce a new ownership transition: openForUser is
  idempotent and _sessionLock-guarded, and both _goHome branches already call
  it moments later — the change only moves the existing call earlier on the
  same path, for the same user id taken from the same live session
  (SupabaseService.currentUser). Reads are performed via MigratedKey /
  HiveService.userBox, i.e. through wrapUserScopedBox, exactly as before.
forbidden_patterns_checked:
  - { pattern: "resolveDestination returning StartMissionBrief from its catch block (an unanswered read presented as the positive fact 'this user has no profile')", absent: true, after_fix: true }
  - { pattern: "a not-onboarded branch in restoring_screen routing to /onboarding without first consulting local evidence", absent: true, after_fix: true }
  - { pattern: "reading userBox['profile'] for the evidence decision before HiveUserSession ownership is open", absent: true, after_fix: true }
  - { pattern: "completeOnboarding writing over a cloud profile whose onboarding_completed_at is already stamped", absent: true, after_fix: true }
related_bugs: [2026-08-03-restoring-screen-local-onboarded-flag-not-stamped-a3f6d9, 2026-05-16-onboarding-triplicate-storage-1bfeed, 2026-06-28-onboarding-completed-at-durability-c4d8a2, 2026-08-02-terms-accepted-dead-write-b3f9e7]
self_review_findings: |
  MUTATION TESTING CHANGED THIS BATCH TWICE — both times because a guard had
  been added without the test that can see it fail.

  Mutation C (revert the catch block to `return const StartMissionBrief()`,
  i.e. re-create this exact bug) initially reddened ZERO tests. Every test
  written to that point covered the predicate and the branch wiring; none
  covered the single line whose wrong value IS the defect. Added a behavioral
  test that drives the real resolveDestination with an unreachable backend and
  asserts DestinationUnknown; that mutation now reddens 1.

  Mutation D (flip the overwrite guard's catch to fail CLOSED) also reddened
  ZERO. The "fail open" test exercised the NO-SESSION path — Supabase is
  uninitialised in unit tests, so `currentUser` is null and the guard returns
  before its network call, never reaching the catch. Rather than claim
  coverage that did not exist, the DECISION was extracted to a pure
  `shouldRefuseOnboardingOverwrite` (the same split as `classifyDestination`
  and `shouldStampFallbackTermsConsent`), which is directly mutation-proven,
  and the catch's fail-open is pinned structurally with the scope limit
  stated in the test file itself.

  This is the `feedback_mistake_guard_without_its_mirror` class, twice in one
  batch. The lesson that generalises: the tests were written from the same
  mental model as the fix, so they asserted what the fix DOES rather than what
  its absence would look like. Only running the mutation exposed that.

  Final mutation table (all run, all reverted):
    A  predicate always returns false ................ 4 tests red
    B  StartMissionBrief skips the evidence gate ..... 1 test  red
    C  unknown collapses back to StartMissionBrief ... 1 test  red (was 0)
    D  overwrite guard fails CLOSED .................. 1 test  red (was 0)
    E  shouldRefuseOnboardingOverwrite always true ... 1 test  red

  Also corrected during the plan's own first review, before any code: the
  count of tests that source-read restoring_screen.dart was carried in from an
  earlier session as "4". It is 17. Every one of them silently reads less than
  it thinks once a function moves to a part file — which is precisely what
  happened: extracting ONE function reddened 3 of them. Fixed durably by
  readLibrarySource(), which parses the head file's own `part` directives
  instead of consulting a hardcoded folder map like the pre-existing
  readScreenSource() does.
recurrence: |
  THIRD instance of the restore→onboarding misroute class, and the first to
  survive its predecessor's fix.

  - 1bfeed (2026-05-16): onboarded users hitting /onboarding/mission-brief on
    fresh install when the cloud column was NULL.
  - a3f6d9 (2026-08-03): SAME founder, SAME account, same landing screen. Root
    cause was the local `onboarding_completed` boolean never being stamped on
    the restore path. Fixed by stamping it at three sites in RestoringScreen.
  - c2e9f4 (this one): a3f6d9's fix IS present in the running build — verified
    by `git merge-base --is-ancestor 6971e267 2470953e` (the fix is an
    ancestor of the 1.0.0+38 version bump) and by telemetry showing
    client_version 1.0.0+38. It did not help, because all three of its stamp
    sites live DOWNSTREAM of a classification that had already gone wrong.

  The through-line across all three is one mistake repeated at different
  layers: a state meaning "we do not know" being represented by a value that
  asserts a positive fact. a3f6d9 fixed the writers; this fixes the
  classifier that decides which writer runs at all.

  NOT a recurrence of c4d8a2 (cloud column NULL despite a populated local
  profile — the opposite direction; ruled out by live SQL showing the column
  correctly populated for this account). Shares with b3f9e7 the property that
  Google OAuth does not traverse hydrateFromCloud, so no writer on that path
  could have healed the flag either.
proposed_fix: |
  Stop conflating "could not read" with "has no profile", then stop trusting
  either one alone.

  1. `DestinationUnknown` joins the sealed PostSignInDestination hierarchy.
     `resolveDestination` calls `ensureFreshToken()` before its SELECT (the
     precaution `callFunction` has always taken — CLAUDE.md §4.4 rule 9), and
     on a throw retries once behind a hard `refreshSession()`; only then does
     it return DestinationUnknown. Because the hierarchy is `sealed`, adding
     the state makes RestoringScreen's switch non-exhaustive and FAILS TO
     COMPILE until the branch is handled — the compiler enforces the pairing.
     Kill-switch `disable_resolve_destination_unknown` restores the verbatim
     pre-fix path.

  2. The local-evidence predicate moves out of the ResumeOnboarding branch
     into `local_onboarding_evidence.dart` and is consulted by all THREE
     not-onboarded branches. Its read is preceded by
     `ensureOpenedForCurrentSession()`, because under owner-null
     wrapUserScopedBox serves GuardedBox.empty (guarded_box.dart:333) and the
     read silently returns "no evidence" — the loud StateError at :335 fires
     only when UNAUTHENTICATED, which never applies here. The pre-fix code
     relied on the parallel restoreFromCloudForUser having opened the session,
     but that call (sync_service.dart:454) is fire-and-forget, so whether
     ownership was open came down to a race. A genuinely new user has neither
     signal, so their routing is unchanged. Kill-switch
     `disable_local_onboarded_evidence`.

  3. `completeOnboarding` refuses to overwrite a cloud profile that already
     carries `onboarding_completed_at`, at the method's ENTRY so both the Hive
     stamp and the sync fan-out it triggers are prevented. Fails OPEN on any
     error or when signed out: a false negative costs a returning user one
     wrong screen, a false positive would block every new signup. Kill-switch
     `disable_onboarding_overwrite_guard`.

  Why 3 exists at all: three routing bugs have now put an onboarded user in
  front of onboarding, and a fourth route is always possible. What made all
  three survivable was luck — the founder never tapped through. The guard
  turns that luck into a property.
regression_test_planned:
  - test/contracts/local_onboarding_evidence_behavioral_test.dart
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "auth_session_bootstrapper.dart, local_onboarding_evidence.dart (new), restoring_screen.dart + 2 new part files, onboarding_provider.dart. flutter analyze on lib/: 0 errors, 0 warnings (44 pre-existing info lints, none in touched files)." }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "test/contracts/local_onboarding_evidence_behavioral_test.dart — real Hive round-trip via setUpHiveForTests (no box mocks): a restored profile map is seen as evidence, a fresh box is not, and a stamped flag round-trips. 22/22 green; 5 mutations each redden >=1 test." }
  - { tier: 3, layer: postgres_schema, status: not_applicable, evidence: "No schema change — client-only fix. The 9-field list mirrors migration 112's existing trigger; nothing altered server-side." }
  - { tier: 4, layer: postgres_data, status: verified, evidence: "Live SQL against dedsavbjuwgarrhphgnl: users.onboarding_completed=true, user_profile.onboarding_completed_at=2026-05-01 15:36:41, all 5 selected columns populated, user_profile.updated_at still 2026-05-01 10:05:21 (proving the funnel was never re-run and no data was overwritten)." }
  - { tier: 5, layer: migrations_applied, status: not_applicable, evidence: "No migration in this batch." }
  - { tier: 6, layer: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, layer: cron_jobs, status: not_applicable, evidence: "No cron touched." }
  - { tier: 8, layer: rls_policies, status: verified, evidence: "pg_policy on public.user_profile: user_profile_select_own is ((SELECT auth.uid()) = user_id), own-row-only, SELECT. This is WHY a stale/unattached token yields HTTP 200 with zero rows rather than an error — the mechanism behind leg 2 of the ambiguity. Policy unchanged by this batch." }
  - { tier: 9, layer: storage_buckets, status: not_applicable, evidence: "No storage interaction." }
  - { tier: 10, layer: secrets_api_keys, status: not_applicable, evidence: "No secret or key touched." }
  - { tier: 11, layer: external_services, status: not_applicable, evidence: "Google OAuth provider config unchanged; the identity linking is correct and was verified (one auth.users row, two auth.identities)." }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "Traced end-to-end: splash -> /restoring -> resolveDestination (ensureFreshToken -> SELECT -> retry -> DestinationUnknown) -> RestoringScreen branch -> evidence check (after ensureOpenedForCurrentSession) -> _goHome -> setOnboarded stamp -> context.go('/home') -> _authRedirect reads the flag as true. Device-level end-to-end verification (sign out, Google sign-in, airplane-mode mid-restore) is listed in the batch plan and NOT yet performed — the mechanism is a live-network race no unit test reproduces, so that step is genuinely owed before this can be called verified in the field." }
impact_analysis: |
  Blast radius: account (docs/blast_radius.yaml — lib/features/auth/** :188,
  lib/core/services/** :267, lib/core/** :271). Confirm with
  scripts/blast_radius_from_diff.dart before merging rather than assuming.

  Changes are additive and each is kill-switched (§4.6 — auth is a named
  category). Nothing is removed from the existing decision tree: GoHome and
  ResumeOnboarding behave exactly as before, and StartMissionBrief still
  routes to Mission Brief for anyone without local evidence, which is every
  genuinely new user. The compiler-enforced sealed switch guarantees no
  caller silently ignores the new state.

  The highest-risk edit is moving HiveUserSession.openForUser earlier on the
  boot path (via ensureOpenedForCurrentSession) so the evidence read is not
  served an empty box. It is idempotent, _sessionLock-guarded, uses the same
  user id from the same live session, and both _goHome branches already call
  it — but it is an ordering change on the cross-account-critical path and is
  the thing the independent review round should scrutinise hardest.

  Also folded in: restoring_screen.dart was 791 lines against Gate 43's
  800-line ceiling, so this batch could not add code to it without tripping
  the gate. Two functions were extracted to sibling `part` files (768 lines
  now), which also completes the extraction half of OI-88.
blast_radius: account
---

# A cloud read that fails is not a user who doesn't exist

## Symptom

Google sign-in to a five-month-old, fully-onboarded account landed on the
onboarding **Mission Brief** screen instead of `/home`.

The founder identified the screen as "my pic with message". That photo is
`assets/founder/upendra.jpg`, hardcoded at
`mission_brief_screen.dart:76` and rendered on no other screen — which fixes
the route as `/onboarding/mission-brief`, and therefore the destination as
`StartMissionBrief`.

## Investigation

Live SQL against `dedsavbjuwgarrhphgnl`:

```sql
select u.onboarding_completed, p.onboarding_completed_at, p.updated_at
from public.users u
join public.user_profile p on p.user_id = u.id
where u.email = 'upendraprasad19@gmail.com';
-- true | 2026-05-01 15:36:41 | 2026-05-01 10:05:21
```

The cloud state is correct, so `classifyDestination` given a real row returns
`GoHome`. Landing on Mission Brief therefore means the row never reached it.

The account itself is fine: one `auth.users` row (`d7a67a37…`) carrying two
`auth.identities` (`email` from 2026-05-01, `google` from 2026-08-10 07:09:08).
Supabase linked the OAuth identity to the existing confirmed email, so the user
id — and every FK, PRO entitlement, streak and Hive namespace hanging off it —
is unchanged.

Telemetry could not close the gap: there are **no** `client_errors` rows at all
between 06:50 and 07:13 UTC, and `log-client-error` was returning **503**
cold-start retries at 07:17. That window is a hole, not a clean bill of health,
and saying so is the point — the fix below is deliberately built to be correct
without knowing which of the two entrances fired.

## Root cause

`resolveDestination` collapsed three outcomes into two:

| outcome | returned | correct? |
|---|---|---|
| row present, `onboarding_completed_at` set | `GoHome` | ✅ |
| row genuinely absent | `StartMissionBrief` | ✅ |
| **read failed / returned nothing** | `StartMissionBrief` | ❌ |

The third case had two entrances, indistinguishable at the call site:

1. **the SELECT throws** — the catch returned `StartMissionBrief`, commented as
   "the conservative fallback". It is conservative for a brand-new user, and
   the single most destructive answer available for an existing one.
2. **the SELECT returns zero rows** — `user_profile` RLS is own-row-only
   (`user_profile_select_own`, verified via `pg_policy`), so a request whose
   token is stale or not yet attached is filtered to zero rows and returns
   **HTTP 200**. `.maybeSingle()` yields `null`, byte-identical to "no such
   user". No exception, no telemetry, nothing to see.

`resolveDestination` also never refreshed its token, unlike
`SupabaseService.callFunction`, which has always called `ensureFreshToken()`
for exactly this reason (§4.4 rule 9) — despite this being the single read that
decides where every returning user lands.

Then the screen compounded it. Of `RestoringScreen`'s two "not onboarded"
branches, only one consulted local state:

* `ResumeOnboarding` self-healed from a populated Hive profile.
* `StartMissionBrief` — the branch every failed read lands on — consulted
  **nothing**.

And the self-heal that did exist was itself unreliable: it read
`HiveService.instance.userBox` on a path where ownership may not be open, and
under owner-null `wrapUserScopedBox` serves `GuardedBox.empty`, so the read
returns null and the heal concludes "no evidence". Whether ownership happened
to be open depended on a race with the fire-and-forget
`ensureOpenedForCurrentSession()` inside `restoreFromCloudForUser`
(`sync_service.dart:454`). That is the most likely reason a3f6d9's fix passed
its tests and still let this through in the field.

## Fix

See `proposed_fix` in the frontmatter for the three units and their
kill-switches. The shape of the fix is one idea: **a state meaning "we do not
know" must be represented by a value that says so** — never by a value that
asserts a positive fact, and least of all by the one whose consequence is
destructive.

## Verification

```
flutter test test/contracts/local_onboarding_evidence_behavioral_test.dart   # 22/22
flutter analyze lib/                                                          # 0 errors, 0 warnings
dart run scripts/check_god_screen_max_lines.dart                              # OK, no new allow-list entry
```

Mutation results are tabulated in `self_review_findings` above. Two of the five
mutations initially reddened nothing; both gaps are closed, and the sequence is
recorded rather than smoothed over, because "we ran mutations" is worth nothing
next to "here is what they caught".

## Owed, and not yet done

Device-level end-to-end verification: sign out, sign in with Google, confirm
`/home`; then repeat with airplane mode toggled mid-restore to force the
failed-read path and confirm it does not land on Mission Brief. The mechanism
is a live-network race that no unit test reproduces, so this is a genuine gap
in the evidence, not a formality.
