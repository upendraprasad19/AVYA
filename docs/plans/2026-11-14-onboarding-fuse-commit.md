# Onboarding: fuse the two commits, drop Muster

Branch `onboarding-fuse-commit`. Tier **L** (touches the router and CLAUDE.md files). Execution mode: **inline**, one worktree, decided at batch start (§4.12.7). Founder decisions 2026-11-14 are in chat: fuse Plan and Induction, button text `I COMMIT →`, drop Muster, write `physique_focus: 'balanced'` at commit, no completeness nudge.

## Problem

New users commit twice and answer one more question after the data commit:

```
Plan  --REPORT FOR DUTY-->  Muster (1 question)  -->  Induction (~220 words, 3 bubbles)  --I COMMIT-->  Home
```

## Target flow

```
Plan (preview + short pledge card + button "I COMMIT →")  -->  Home
```

One tap runs `completeOnboarding()`, which now ends with the commitment stamps (`recordCommitment`, `completeInduction`) and only then `setOnboarded()`; the screen then does `context.go('/home')`.

## Facts verified by reading code (file:line on the branch base c6b1ee48)

| Fact | Where |
|---|---|
| The data commit is `_onReportForDuty`; it navigates to `/coach/muster` (or `/home` if already inducted) at two sites | `plan_screen.dart:554`, `:564`; button label near `:344` |
| `recordCommitment` and `completeInduction` read `userBox['profile']['id']` for their sync call and SKIP the sync silently when it is null. `completeOnboarding`'s profile map has NO `id` key and `saveProfile` replaces the profile verbatim (`profile_write_service.dart:60-75`), so right after commit the id is absent (it is only stamped later by `auth_session_bootstrapper.dart:889`). Review round 1 P0-1, confirmed | `induction_service.dart:61-65`, `completeInduction` body; `onboarding_provider.dart:~470-520` |
| `completeOnboarding` flips the local onboarded flag (`setOnboarded`, `:595`) but the overwrite guard reads the CLOUD `onboarding_completed_at`, which a background `unawaited` sync writes later. A retry seconds after a partial first tap therefore re-runs the whole commit (second profile write, second plan, referral stash already cleared). Round 1 P0-2, confirmed from `:300-345` and `:610-640` | `onboarding_provider.dart` |
| `inductionCompleted` = `coachBox['induction_completed_at'] != null`, false when no Hive session is open | `induction_service.dart:46-49` |
| Router only special-cases `/coach/induction` and `/coach/muster` to bounce already-inducted users home. Nothing forces an onboarded-but-not-inducted user INTO induction | `app_router.dart:677-714`; grep shows no other `go('/coach/...')` caller outside plan_screen and the two screens |
| Muster writes only `body_part_priorities`, bridged to profile `physique_focus` | `induction_service.dart:71-120` |
| `physiqueFocusToBodyFocus('balanced')` returns `[]`, the same as null: no bring-up | `training_history_analyzer.dart` (`default:` branch) |
| Edit Profile already reads a missing `physique_focus` as `'balanced'` | `edit_profile_screen.dart:243` |
| The completeness nudge lists `physique_focus` as Tier 2 | `profile_completeness_provider.dart:8` |
| Push sync maps `physique_focus` from the profile | `sync_service.dart:1446` |
| `/plan-generation` is reached only from the legacy chat screen, not the stepped flow. Leave it | `onboarding_chat_screen.dart:754` |

## Changes

1. **`onboarding_provider.dart` `completeOnboarding` owns the whole commit** (round 3 P1-1: a widget-sequenced commit leaves a window where `isOnboarded` is true but nothing is committed, and ADJUST PLAN or an app kill then reaches `/home` through `postSessionRedirect` (`app_router.dart:818-840`) with the commitment lost for good).
   - Hoist `await HiveUserSession.ensureOpenedForCurrentSession()` from `:515` to the top of the method, BEFORE the cloud guard at `:374`. Wrapped in its own try/catch so nothing can escape before the method's `try` at `:382` and leave `isCompleting` stuck (round 5 P2-2). Safe and idempotent (`hive_user_session.dart:123-137`; the guard reads only configBox and Supabase; round 4 P2-2 found no ordering rationale for the old placement). The reason is the uid: after the hoist `HiveUserSession.currentOwnerFullId` is known when the profile map is built (~:470-506). No widget calls it.
   - Add `'physique_focus': 'balanced'` and `'id': HiveUserSession.currentOwnerFullId` to the profile map (~:470-506), omitted when null. NOT `SupabaseService.instance.currentUser`: it returns null whenever Supabase is uninitialised (`supabase_service.dart:90-92`), i.e. in every unit test, while `currentOwnerFullId` honours the test seam (round 4 P1-1). This also closes a latent wipe: `_ensureLocalUser` sets `needsClear = true` when `existingId == null` (`auth_provider.dart:1158`), so today a freshly onboarded profile (no `id`) can be cleared if `_ensureLocalUser` runs before the bootstrapper stamps the id (round 4 P2-3; recorded in the diagnose-doc with its own test). The cloud payload reads the same map (`:~890`) and is built by explicit key with no `id`. Round 2 checked every reader of `profile['id']` (`hive_user_session.dart:257`, `subscription_service.dart:413/444/586`, `auth_provider.dart:1158`): equal-to-owner is benign.
   - New LAST local step, after `saveProgress` (`:586`) and immediately BEFORE `setOnboarded()` (`:595`): `await InductionService.instance.recordCommitment()` when `!hasCommitted`, then `await InductionService.instance.completeInduction()` when `!inductionCompleted`. So `isOnboarded == true` now means profile + plan + progress + commitment are all durable. Extract this tail as `@visibleForTesting static Future<void> finalizeLocalCommit()` (static, so it uses `UserRepository.instance`, not `_userRepo`; `onboarding_provider.dart` gains the `induction_service.dart` import) (stamps, then `setOnboarded`) so a test can drive it without a seeded exercise library (round 3 P1-2), with a `@visibleForTesting static Future<void> Function()? debugAfterStampsForTests` hook called between the stamps and `setOnboarded` so a test can inject a throw there (round 4 P1-2).
   - Retry: a throw anywhere before `setOnboarded` lands in the catch-all (`:663`) with `isOnboarded` still false; the next tap simply re-runs `completeOnboarding` (the cloud guard still reads false because the cloud write happens later in the background; `saveProfile` replaces, the weight seed is idempotent, the referral stash is cleared only after `setOnboarded`). No retry marker exists.
   - The `already_onboarded` early return is unchanged: no stamps (round 2 P1-B: a stamp could overwrite a real cloud `committed_at` before coach memory is restored).
   - Legacy chat onboarding (`onboarding_chat_screen.dart:754`) calls `completeOnboarding` too, so it now also stamps the commitment. Intended: that path never showed an induction either.
2. **`plan_screen.dart`**: pledge card above the button (copy below), button label from `WardroomCopy.onboardingCommitCta` (`I COMMIT →`), drop the "Plan shaped by 14 years..." tagline. `_onReportForDuty` (NOT renamed during execution: a dozen docs, tests and SoT entries cite the name; the class doc says so) calls `completeOnboarding()` and on non-null goes to `/home`; on `already_onboarded` goes to `/home` as today; on other errors shows the banner as today. No direct `InductionService`, `UserRepository` or `HiveUserSession` calls from the widget (round 3 P2-1). `if (!mounted) return;` after the await.
   - Accepted, same as today: on `already_onboarded` with a local `onboarding_completed == false` (only reachable through a routing bug; `restoring_screen.dart:315/346/653` sets the flag on the normal path), `/home` redirects back to `/onboarding` (round 3 P2-2). Pre-change the same user also ended there after Muster and Induction.
2b. **`induction_service.dart`**: `recordCommitment` and `completeInduction` take the uid from `HiveUserSession.currentOwnerFullId` (the same source the class's getters use, `induction_service.dart:46-48`), falling back to `profile['id']`; a `@visibleForTesting static void Function(String uid)? debugOnSyncUidForTests` is called with the uid just before the unawaited sync (the sync itself swallows failure and is unobservable, round 4 P1-1); class docs that describe Muster and the Induction screen are rewritten in the same edit; the sync stays after the Hive puts and never throws into the caller; a telemetry event when neither id exists. No new `StateError` (round 3 P2-3: `coachBox` is already a `GuardedBox` that throws with no session).
3. **Remove Muster**: delete `muster_screen.dart`, the `/coach/muster` screen route and import (the whole `isOnCoachInduction` variable and early return go in 6b). Delete `InductionService.recordMusterAnswer`, `_allowedMusterKeys`, `_bridgeToProfile`. KEEP `backfillMusterToProfileIfNeeded` and the read-only coachBox keys (they heal old tester data once).
4. **Remove the Induction screen and route** once the pledge lives on Plan: delete `induction_screen.dart`, the `/coach/induction` screen route and import (redirects: 6b). Keep `InductionService.recordCommitment`, `completeInduction`, `inductionCompleted`.
5. **Telemetry** (best effort, labelled so: LOW-priority op types are dropped during a client rate-limit cooldown, `error_telemetry.dart:384`, round 4 P2-4; separate commit): one `ErrorTelemetry.logEvent('onboarding_step', message: '<screen>')` per stepped screen on first build (Welcome, Mission Brief, Identity, Goal, Stats, Details, Plan) plus `onboarding_commit` on success. Gives drop-off data we do not have.
6. (dropped) Mission Brief: already trimmed 2026-11-01 (commit 21896289). No change.
6b. **Router**: delete the `isOnCoachInduction` clause and its early return (`app_router.dart:679-681`, `:706-714`), which today lets `/coach/*` skip the auth gates; add route-level `redirect: (_, __) => '/home'` on `/coach/muster` and `/coach/induction`. The global redirect then still sends a signed-out user to `/sign-in` and an un-onboarded user to onboarding.
6c. **Copy constants**: `wardroom_copy.dart:589` `onboardingReportCta` becomes `onboardingCommitCta = 'I COMMIT →'` and the Plan button reads it; `rank_service.dart:339` 'Earned at induction' becomes 'Earned on your commitment' (display only; round 2 confirmed no rank gate reads induction state; grep tests and goldens for the old string).
7. **Docs and tests** (round 1 P1-1 widened this list): `lib/features/onboarding/CLAUDE.md` (flow diagram, SoT row `muster_to_profile_bridge` retired, tests list), `lib/features/ai_coach/CLAUDE.md` (muster/induction sections), `docs/sot_registry.yaml` entry, `docs/architecture/functionality-flow.md` (ONB-09, ONB-12, ONB-13 name REPORT FOR DUTY, the rank grant at induction and `recordMusterAnswer`), `lib/features/auth/CLAUDE.md:38` (muster row), `docs/snapshot_contract.yaml:426-504` prose, stale REPORT FOR DUTY / `_onReportForDuty` comments in `stats_screen.dart:18,381`, `goal_screen.dart:38`, `bmr_calculator.dart:66`, `integration_test/flows/signup_onboarding_traverse_test.dart:5,43-46`, current docs `docs/architecture/{auth-detail,sync,database}.md`, `docs/reference/directory-structure.md`, `docs/qa_checklist_template.md`, `.claude/skills/psychology-pass-fitness/SKILL.md`, `.claude/skills/debugging/bug-classes.md` (historical `docs/superpowers/**`, `docs/reports/**`, dated audits and the frozen tuning history stay as they are), the stale comment at `lib/core/services/sync/sync_coach.dart:821`, and every `docs/sot_registry.yaml` cite of a removed file or symbol (`:5908` reader entry on `induction_screen.dart`, `:7490-7620`, `:10221`, `:11849`; recompute line ranges into `induction_service.dart`). Check `rank_service.dart:339` and `functionality-flow.md:83`: does the SD2 rank gate read `induction_completed_at`? Repoint, never loosen, every source-grep test that names a removed symbol (`grep -rn` over `test/` and docs first, §4.9).

## Copy (draft for the founder)

Pledge card:

> **Recruit {first name}, welcome aboard.**
> I'm your AI Coach. Show up, log honestly, tell me when something hurts. I'll handle the rest.
> **Hold the line: your first rank in the opening weeks, Petty Officer by month three, Lieutenant if you stay on it. That's the contract.**
> Tap below to seal it.

Button: `I COMMIT →`.

## Tests

- Behavioral (new, `test/contracts/onboarding_single_commit_test.dart`, `setUpHiveForTests` from `test/helpers/hive_test_setup.dart`, which opens coachBox and userBox for `kTestUserId`):
  - `finalizeLocalCommit()` writes `committed_at`, `committed_to_lt_cdr`, `induction_completed_at` and `onboarding_completed == true`.
  - ORDER (the load-bearing test): with `debugAfterStampsForTests` throwing, both stamps are present and `onboarding_completed` is still false. Mutant: move `setOnboarded` above the stamps; this test must redden.
  - With an existing `committed_at`, `finalizeLocalCommit()` keeps it (mutant: drop the `!hasCommitted` check).
  - `recordCommitment` with a Hive profile that has no `id` reports `kTestUserId` through `debugOnSyncUidForTests` (mutant: read the uid only from `profile['id']`).
  - The profile saved by `completeOnboarding` in the C1 harness (`onboarding_hive_session_open_before_write_test.dart`, reaches `saveProfile` and dies at `exerciseBox` ~:545) has `id == testUser` (that harness's own constant `b00b1e5e-...`, `:71`; it does not use `setUpHiveForTests`) and `physique_focus == 'balanced'`; `profileCompletenessProvider` does not list Physique Focus. C1 also shows that no stamp lands before plan generation, and nothing more (round 4 P1-2).
  - `_ensureLocalUser`'s clear decision: extract the inline test at `auth_provider.dart:1158` into a pure `static bool shouldClearForProfileId(String? existingId, String userId)` (behaviour unchanged) and table-test it: null id clears, equal id keeps, different id clears. That pins why writing `id` at commit matters (round 5 P2-1).
  - Both test hooks are reset to null in `tearDown` (round 5 P2-3).
  - `already_onboarded`: no seam can force the cloud guard ON (round 4 P2-1), so: the existing pure `shouldRefuseOnboardingOverwrite` table plus a presence-only source pin that the guard's early return precedes `finalizeLocalCommit`.
- Router: `postSessionRedirect` truth table unchanged (existing test) plus a presence-only source pin that `/coach/muster` and `/coach/induction` carry `redirect: ... '/home'` and that `isOnCoachInduction` is gone (go_router 17.2.3 runs the top-level redirect first, so signed-out and un-onboarded users are still gated, `configuration.dart:419-441`).
- Sweep `grep -rn "completeOnboarding\|recordMusterAnswer\|_onReportForDuty" test/` before editing (round 4 P2-5: `onboarding_bodyfat_calc_test`, `boot_onboarding_hive_first_test`, `onboarding_streak_anchor_*`, `user_full_name_*`; `induction_idempotency_test`'s two `recordMusterAnswer` cases are deleted with the method).
- Also repoint: `responsive_picker_host_test.dart:365` (reads `muster_screen.dart`), `boot_onboarding_hive_first_test.dart:76-78` and `plan_screen_targets_match_completeOnboarding_test.dart:79,89` (source-grep `_onReportForDuty` and the "REPORT FOR DUTY" text); grep `restore_coach_memory_test`, `coach_notes_upward_sync_test`, `sync_retry_controller_test` for route or screen references; repoint the stale header of `induction_service_session_guard_test`.
- Repoint or delete: `muster_screen_submit_error_reset_test`, `muster_question_count_test`, `muster_persistence_test`, `muster_profile_bridge_test`, `induction_screen_commit_error_reset_test`, `induction_pledge_test`, `induction_idempotency_test`, `muster_to_profile_bridge_behavioral_test`, `muster_profile_bridge_test`. Keep `muster_bridge_backfill_test`, `induction_service_session_guard_test`.
- Rule 21: mutate each new protection once (move `setOnboarded` before the stamps; remove the `!hasCommitted` check; drop `physique_focus` from the profile map; read the uid only from `profile['id']`) and record how many tests redden in the diagnose-doc.

## Risks the reviewers should attack

1. `completeOnboarding` now writes coach memory (coachBox) inside the onboarding commit; any test or flow that runs `completeOnboarding` without an open session or with an unexpected coachBox state.
2. Re-running `completeOnboarding` after a partial failure (no retry marker): every step before `setOnboarded` must be safe to repeat.
3. The coach snapshot sees `physique_focus: 'balanced'` instead of null (`ai_snapshot_builder.dart:579`); `backfillMusterToProfileIfNeeded` may upgrade `balanced` to an old Muster value once for old testers (accepted).
4. The commitment syncs now fire right after the profile commit instead of minutes later. `coach_memory.user_id` references `public.users(id)` (migration 027), but that row is created at signup by the `on_auth_user_created` trigger (`039_rank_system_and_auth_fk.sql:42-55`), so there is no FK race; the two back-to-back upserts write only the columns present, so the first cannot erase the second (round 5 P2-4). On `already_onboarded` the hoist now opens the Hive session before the refusal; harmless (RestoringScreen and `_ensureLocalUser` open it anyway).
5. Tester accounts mid-sequence: nothing forces induction (`app_router.dart:706-714` is removed; `postSessionRedirect` decides), and app not live (CLAUDE.md §1): no migration.

## Out of scope

Generator, paywall, Welcome, Identity, Goal, Stats, Details, Restoring routing, `/plan-generation`.

## Review plan

Rounds so far: 1 (2 P0, fixed), 2 (1 P0 on the retry marker + 4 P1, fixed), 3 (0 P0, 2 P1: the commit moved into `completeOnboarding`, which removes the retry marker and the widget sequencing; test seam added), 4 (0 P0, design confirmed; 2 P1 on test seams: uid source switched to `HiveUserSession.currentOwnerFullId`, throw-injection hook added). 5 (0 P0; 1 P1, mechanical: the C1 test constant is `testUser`, not `kTestUserId`; 4 P2 applied). Round 5 closes `mechanical_only: true` (§4.12.6). Verdict: converged. converged only when a round finds no P0/P1. Independent context-blind Sonnet rounds (§4.12.1, founder rule: Sonnet only, no Opus). Record at `docs/plan-reviews/onboarding-fuse-commit.md` with `review_rounds: <final count>`, `ground_truth_verified: true`, `verdict: converged`, `bpass: accepted` (platform-tier).
