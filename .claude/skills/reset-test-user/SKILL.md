---
name: reset-test-user
description: Resets a Supabase-backed QA/test account (test3@gmail.com, etc.) to a genuine brand-new-user state for onboarding E2E testing. Clears local Hive (via sign-out), Supabase user-data rows, AND the users.onboarding_completed flag, in the order that avoids the app's own local-evidence self-heal silently overriding a cloud-only reset. Use when asked to "reset test3/test4/etc. for onboarding", "wipe a test account", "start onboarding from scratch".
type: process
priority: high
self-evolving: true
---

# /reset-test-user — Reset a QA account to brand-new-user state

## When to invoke

Invoke when asked to reset a QA/test account (`test1@gmail.com`..`testN@gmail.com`,
or any account only the founder can sign into) so it replays onboarding for
E2E testing. Do NOT use this for a real user's account.

## Why order matters (founding incident, 2026-09-19 — TWO rounds, both wrong at first)

This app is Hive-first/offline-first: local Hive is primary, Supabase is
backup. `restoring_screen.dart` deliberately trusts local Hive evidence over
a cloud read when they disagree (`_hasLocalOnboardedEvidence()` /
`AuthSessionBootstrapper.resolveDestination`), because a cloud SELECT
returning zero rows is ambiguous - it could mean "genuinely new user" OR
"stale-token / RLS false negative on a real user" (diagnose
`docs/diagnoses/2026-08-10-resolve-destination-failed-read-means-new-user-c2e9f4.md`).
"StartMissionBrief overridden by local evidence" is a real, load-bearing
branch (`lib/features/auth/screens/restoring_screen.dart:129`), not a bug.

**Round 1 mistake:** deleting only Supabase rows while test3 was still signed
in in the test browser let the self-heal fire on the very next screen load,
re-writing a blank stub `user_profile` row back to Supabase and routing to
Home instead of onboarding.

**Round 2 mistake (the one that actually matters - signing out did NOT fix
it):** after signing out (clearing local Hive via `clearAllData()`) AND
deleting the Supabase rows AND verifying 0 residual, signing back in landed
on Home again, byte-for-byte identical. The real, persistent culprit is a
THIRD piece of state, entirely server-side, that earlier attempts did not
cover: **`public.users.onboarding_completed`** (a plain boolean - NOT the
same column as `user_profile.onboarding_completed_at`).
`hasLocalOnboardedEvidence()` (`lib/core/services/local_onboarding_evidence.dart:56`)
is `if (flagOnboarded) return true;` - an unconditional short-circuit checked
BEFORE any Hive-field check. `flagOnboarded` gets set on literally every
sign-in by `AuthSessionBootstrapper.hydrateFromCloud`
(`lib/core/services/auth_session_bootstrapper.dart:697-706`), which reads
`users.onboarding_completed` straight from Postgres and writes it into local
`MigratedKey('onboarding_completed')` if true - regardless of what
`user_profile` or Hive say. **A reset that clears `user_profile` but leaves
`users.onboarding_completed = true` self-heals to Home on every single
login, forever, no matter how clean everything else is.**

**Also note:** `hydrateFromCloud` unconditionally writes a *minimal* Hive
profile stub (`{id, email, created_at}`, no real fields) for any account with
no local Hive profile yet (`auth_session_bootstrapper.dart:724-733`), then
immediately pushes it to Supabase via `_pushProfileToSupabaseIfMissing` if
the cloud has no row - meaning a `user_profile` row will almost always exist
again by the time `resolveDestination` runs, for any RETURNING account (one
whose `auth.users` row predates the reset). Practically: once
`users.onboarding_completed` is correctly false, expect `resolveDestination`
to land on `ResumeOnboarding` routing to `/onboarding/identity` (first
missing field), not literally `StartMissionBrief` - Mission Brief itself may
not be reachable again for an account that has ever signed in before. That's
an acceptable outcome for E2E testing (Identity onward is what matters);
don't chase getting Mission Brief to render for a non-fresh `auth.users` row.

## What this skill does (correct order)

1. **Identify the account.** Get `auth.users.id` for the target email:
   ```sql
   select id, email, created_at, last_sign_in_at from auth.users where email ilike '<email>';
   ```

2. **Sign out FIRST, before touching Supabase.** In whatever browser/device
   currently holds a session for this account, sign out via the app's own
   Profile -> Sign Out. This needs no credentials - the agent may click it
   itself. It runs `UserRepository.clearAllData()`
   (`lib/shared/repositories/user_repository.dart:762`), which clears
   `userBox` / `workoutBox` / `nutritionBox` / `healthBox` / `coachBox` /
   `customBox` / `notificationsBox` / `syncBox` / `configBox` - and
   deliberately preserves `exerciseBox` / `foodBox` (seeded reference data)
   and `migrationBox` (one-shot device flags). Re-check that box list against
   the live file before relying on it - box names can drift.
   - If a session for this account might be open on a device/browser you
     cannot reach (the founder's phone, a friend's laptop), say so explicitly:
     local evidence there is NOT reset by anything below, and that device may
     still self-heal past onboarding on its own next launch.

3. **Reset the `users` row's onboarding flag** (separate from `user_profile`):
   ```sql
   update users set onboarding_completed = false where id = '<user_id>';
   ```
   This is the step both earlier rounds missed. Skipping it means every future
   login self-heals to Home regardless of anything else you clear.

4. **Enumerate every table with a `user_id` FK, count rows for this user,
   and show the founder the exact list before deleting anything:**
   ```sql
   select table_name from information_schema.columns
   where table_schema='public' and column_name='user_id' order by table_name;
   -- then one UNION ALL count(*) per table for the target user_id
   ```
   This is a destructive, irreversible action on production data - even
   though it's a test account, confirm the footprint before deleting.

5. **Delete those rows** (delete `user_profile` last, though FK order barely
   matters here since almost everything keys off `user_id` directly). **Never
   touch `auth.users`** - the account's login must keep working. Verify 0
   residual with the same count query.

6. **Sign back in** (the account holder does this - never enter a password
   yourself). Screenshot the landing screen:
   - **Genuine reset:** lands on `/onboarding/mission-brief` or, for a
     RETURNING `auth.users` row, `/onboarding/identity` (see note above -
     this is still a correct reset, not a failure).
   - **Still lands on Home / shows an existing profile:** the reset did NOT
     take. Don't conclude onboarding routing is broken - first re-check
     ALL THREE pieces of state (local Hive via sign-out having actually run,
     `user_profile` rows, AND `users.onboarding_completed`) before assuming
     anything about the app itself.

## Red flags

| Thought | Reality |
|---|---|
| "I'll just delete the Supabase rows, that's the source of truth" | Hive is primary here, not Supabase (root CLAUDE.md §2, §4.4 rule 1). A cloud-only delete is not a reset. |
| "I cleared user_profile, that's the onboarding flag" | `users.onboarding_completed` is a SEPARATE column on a SEPARATE table from `user_profile.onboarding_completed_at`. Both must be reset. Confirmed by reproducing this exact bug twice in one session. |
| "Signing out and clearing Hive fixed it, cloud must be clean now" | Verify DB state independently - don't infer cloud correctness from a client-side action. `hydrateFromCloud` reads `users.onboarding_completed` on every login and re-derives local state from it. |
| "Let's clear IndexedDB directly with JS, it's faster than clicking Sign Out" | `e2e-sim-testing` skill's own anti-pattern list flags hard-clearing IndexedDB as risky on a DEBUG build's Hive init race. Sign-out exercises the app's own tested clear path instead of reinventing box names. |
| "Delete while still logged in, then sign out after" | A live session can self-heal / background-sync a stub row back before you finish, or immediately after. Sign out ALWAYS comes first. |
| Landing on Home right after a "reset" | The reset didn't take. Re-run ALL THREE state checks (Hive, user_profile, users.onboarding_completed) before doing anything else - don't start debugging onboarding routing on a false premise. |
| "It's just a test account, no need to show the delete list first" | Still real production data in the shared Supabase project. Show the footprint, then delete. |

## Self-evolution

When a reset produces an unexpected landing screen for a reason not covered
above (a second device holding a session, a PWA/service-worker cache, a
different self-heal branch, another flag this skill doesn't yet know about),
add a new red-flag row and a changelog entry citing the concrete symptom.
Treat a second unexplained recurrence as a sign there is a FOURTH piece of
state still missing, not as "the app is just flaky."

## Changelog

- 2026-09-19: Founding incident, two rounds. Round 1: reset `test3@gmail.com`
  by deleting Supabase rows while the account was still signed in - local
  Hive self-heal (diagnose `c2e9f4`) overrode it and re-wrote a stub
  `user_profile` row. Round 2: signed out first (clearing Hive) and deleted
  Supabase rows again with 0 residual verified - STILL landed on Home,
  identically. Root cause was `public.users.onboarding_completed = true`,
  never reset by either round, unconditionally trusted by
  `hasLocalOnboardedEvidence()`. Fixed by adding the explicit
  `users.onboarding_completed = false` step. Skill written same-day as the
  first mistake and was ITSELF incomplete until this second round - see
  `feedback_mistake_cloud_only_reset_ignores_local_hive.md` in the harness
  memory dir for the full incident writeup.
