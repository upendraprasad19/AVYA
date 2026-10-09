---
bug_id: c9d2f6
date: 2026-10-06
batch: streak-freeze-restore-ownership (Unit 2 of 2: a stale cloud row stops overwriting the streak-freeze state)
status: fixed
blast_radius: platform
symptom: |
  The founder's Home screen showed streak 16 with 2 freezes. The persisted count was wrong: the streak only holds at 16 because two missed days (2026-10-03 and 2026-10-05) are SIMULATED as covered by two freezes the app never spent, and the chip reads the persisted count. Two defects stack. This document covers the second: every full restore of user_progress copied the cloud row's freeze count, last-refill date and first-PRO flag over the phone's, so a cloud row that lagged the phone (a push that timed out or was dropped) silently refunded spent freezes and re-ran the Monday refill. Live signature on the morning of the report (client_errors, device-measured): streak_freeze_refill_done before=1 after=2 monday=2026-10-05 at 06:46:25, then streak_freeze_refill_check lastRefill=2026-09-28 willRefill=true at 06:46:26, the refill date back at the STALE cloud value 1.6 seconds after the refill stamped it. A second finding in the same function: the sign-in hydrate handed the RAW cloud row (user_id, plan_json, sync_epoch) to the merge, so the whole plan_json blob was spread into userBox['progress'].
concept: progress_restore_freeze_merge
sot_registry_entry: progress_restore_freeze_merge
writers:
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "mergeCloudProgress (pre-fix: cloud-non-null-wins for every key outside monotonicProgressFields, which includes the whole freeze family)", line: 474 }
  - { file: lib/shared/repositories/user_repository.dart, method_or_widget: "_mergeFreezeFamily (post-fix: the order-independent post-pass; delegates to StreakProgressService.mergeFreezeProgress)", line: 663 }
  - { file: lib/core/services/sync/sync_profile.dart, method_or_widget: "_restoreUserProgress (full restore and restoreLightweightAlways on every cold start; post-fix owner guard before the put, then unawaited syncFreezes when the merge kept local ahead)", line: 926 }
  - { file: lib/core/services/auth_session_bootstrapper.dart, method_or_widget: "hydrateFromCloud (sign-in hydrate; the third whole-row merge, passed the RAW cloud row)", line: 758 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method_or_widget: "syncFreezes (post-fix reads _liveUserId so the push is observable under SyncHarness; byte-identical in production)", line: 34 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout (item 8, current_streak_weeks: the ONLY runtime writer, +1 once per streak-week at >= 80% of the planned sessions, gated by the LOCAL-ONLY last_streak_week)", line: 1990 }
  - { file: lib/features/onboarding/providers/onboarding_provider.dart, method_or_widget: "completeOnboarding seeds current_streak_weeks 0 (also :905, and user_repository.dart:835 the default progress map)", line: 590 }
  - { file: lib/features/dev/simulation_service.dart, method_or_widget: "debug-only reset of current_streak_weeks to 0 (the only reset anywhere; kDebugMode)", line: 134 }
readers:
  - "PRODUCTION RESTORE ORDER is user_progress THEN freezes (sync_service.dart restoreFromCloudForUser core, and the single-call path), so _restoreFreezes (sync_restore_completeness.dart) only ever sees the already-clobbered local row and could not repair it. restoreLightweightAlways (every cold start via checkAndSync) and the empty-Hive restoreFromCloud and the sign-in hydrate never run _restoreFreezes at all, so on those paths the clobber was also, by accident, the only cross-device pull of the freeze count."
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "_calculateStreak (reads streak_freezes_available and the used-dates ledger; a refunded count is spent again, a reverted last_refill re-runs the refill)", line: 332 }
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "StreakFreezeNotifier (the chip: shows the PERSISTED available count)", line: 274 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "mergeFreezeProgress (the ONE mutation-proven merge rule; unchanged by this batch)", line: 285 }
  - { file: lib/core/services/badge_service.dart, method_or_widget: "item 8 reader: the 4/8/12-week streak badges read current_streak_weeks", line: 115 }
  - { file: lib/features/ai_coach/services/pattern_detector.dart, method_or_widget: "item 8 reader: _streakRisk fires when weeks > 2 (also ai_snapshot_builder.dart:122-135, the streak-guardian / weekly-report / proactive-coach-promotion / morning-alert Edge Functions)", line: 115 }
hive_key_prefix: progress
hive_key_formula: "userBox['progress'][streak_freezes_available | streak_freeze_used_dates (singular, local) | streak_freezes_last_refill | streak_freezes_first_pro_grant_done | streak_progress_version]; the cloud column for the used-dates ledger is plural (streak_freezes_used_dates)"
sync_methods:
  - syncFreezes
restore_methods:
  - _restoreUserProgress
  - _restoreFreezes
  - restoreLightweightAlways
  - hydrateFromCloud
contract_test_path: test/contracts/progress_restore_freeze_merge_behavioral_test.dart
cloud_table: user_progress
cloud_columns:
  - current_streak_weeks
  - streak_freezes_available
  - streak_freezes_used_dates
  - streak_freezes_last_refill
  - streak_freezes_first_pro_grant_done
  - streak_progress_version
ist_handling:
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "mergeFreezeProgress compares last_refill Monday date strings (IST) with plain string ordering; this batch adds no date arithmetic", line: 285 }
provider_invalidations: []
telemetry_op_types:
  success:
    - progress_restore_freeze_merge_engaged
  failure: []
cross_account_guard: "_restoreUserProgress now returns before the put and before the push when ownerChangedSince(userId) (the e5c2d1 class: it had no sink-side guard, and the new push would otherwise send account B's box, merged with A's row, to B's cloud row). The sign-in hydrate is for the current user and needs none. Pinned by Group C of the behavioral test."
forbidden_patterns_checked:
  - { pattern: "a map literal with the key streak_freezes_available in user_repository.dart (the sole-writer contract streak_progress_service_concurrency_test.dart greps raw source, comments included; the post-pass writes by index assignment only). B-pass reviewer A F3: that test now ALSO flags index assignment, so user_repository.dart (a restore projection) and streak_freeze_clamp_migrator.dart (a one-shot repair) are allowlisted BY NAME and the next index writer is caught", absent: true }
  - { pattern: "a second freeze merge rule next to mergeFreezeProgress", absent: true }
  - { pattern: "the throwing 'as num?' cast on cloud row values in the post-pass (is-tests only)", absent: true }
  - { pattern: "a symmetric first-PRO grant carry (local flag true, cloud not): _restoreFreezes and the conflict retry merge with the plain rule and would undo it", absent: true }
  - { pattern: "the plural cloud key streak_freezes_used_dates copied into the local map", absent: true }
proposed_fix: |
  1. UserRepository.mergeCloudProgress skips the freeze family (and the control-plane keys user_id, plan_json, sync_epoch) in its cloud-copy loop and runs an order-independent post-pass, _mergeFreezeFamily, which calls the existing static pure StreakProgressService.mergeFreezeProgress UNCHANGED (same-week LOWER available, cloud-newer wins, local-newer kept and pushed, used-dates union, clamp 0..3). Inputs use is-tests; a cloud row whose count is absent or non-numeric skips the post-pass and leaves local verbatim.
  2. ASYMMETRIC first-PRO grant carry: cloud flag true and local flag not true lifts the local count to the cloud's before the rule, so a free-cap local 1 is not clamped onto a granted 3. B-pass reviewer A F2 refined it twice: (a) the carried count is the cloud's MINUS every local used date the cloud ledger has not seen (so {0,W,flag F,used [d1]} against cloud {3,W,flag T} is 2, not a refund to 3; with no ledger evidence it stays 3, equal to pre-fix); (b) when the local week stamp is NEWER than the cloud's, the cloud's OLDER stamp is adopted, so the next refillIfNewWeek (which runs after the restore, under the real PRO cap) still tops the week up exactly as the pre-fix whole-row copy allowed; keeping the newer stamp silently dropped that week's +1. There is NO symmetric carry (round-4 review showed _restoreFreezes and the retry would undo it). The flag is written back as local OR cloud, matching _restoreFreezes's own documented intent, EXCEPT for an EATEN grant: B-pass reviewer A F1 (P2, verified) showed that a local grant {3,W,flag T} meeting a stale cloud {1,W,flag F} (the grant push in flight or failed) was clamped to 1 by the plain same-week rule while the flag was written TRUE, which blocks grantFirstProFreezes (idempotent on the flag; it runs on every PRO boot) for good and pushed the lost count over a cloud that might already hold the landed grant. An eaten grant (local flag true, cloud not, merged count below the local one) now leaves the flag at the cloud's false (pre-fix outcome, self-healing at the next PRO boot) and does not schedule a push for the flag; a surviving grant is claimed and pushed as before.
  3. ProgressMergeResult.scheduleFreezeSyncUp: true when the merged state differs from the ORIGINAL cloud row (available, last_refill, used_dates compared AS A SET, or the grant flag local-true/cloud-not). Both whole-row callers then fire unawaited(syncFreezes()) after their put. A steady state (identical sides) never pushes; after a landed push cloud equals local, so there is no loop.
  4. Owner guard in _restoreUserProgress before the put and the push (the e5c2d1 class, closed in the same place).
  5. syncFreezes, the core restore and the single-call guard read _liveUserId instead of _supabase.currentUser?.id (identical in production, where the resolver is null) so the whole restore, including the push, runs and is observable under SyncHarness.
  6. Kill switch configBox['disable_progress_freeze_merge'] (with the box unopened the fix stays ON, like disable_streak_reckon_user_gate). The OI-83 switch disable_progress_restore_monotonic_merge stays the WIDER rollback: when either is set the freeze and control-plane keys take the pre-fix cloud-non-null-wins branch verbatim. One best-effort LOW event, progress_restore_freeze_merge_engaged (per-process latch), when a push is scheduled; its ABSENCE proves nothing (LOW events drop under client cooldown).
  7. Field doc at user_repository.dart (the freeze family is merged by ONE rule) corrected; it used to claim that while the loop overwrote it. B-pass: the stale line-number citations in that comment and in the new tests are replaced by symbol names.
  8. current_streak_weeks joins monotonicProgressFields (local-max-wins, the existing OI-83 switch is its rollback): a stale cloud row can no longer lower the weeks counter on a reinstall, a second device or a sign-in hydrate (a phone at 6 with the cloud at 5 used to restore to 5). Founder decision A, 2026-10-06. The doc on monotonicProgressFields records the one rule a future reset feature must follow (remove the field from the list in the same change).
  9. B-pass reviewer A F3: the sole-writer contract (streak_progress_service_concurrency_test.dart) now also flags INDEX assignment of streak_freezes_available; it used to match only a map-literal key, so the pre-fix `merged[entry.key] = ...` writers (and this unit's post-pass) were invisible to it. The two legitimate index writers are allowlisted with their reasons.
  10. B-pass reviewer A F6: the sign-in hydrate (hydrateFromCloud) is driven behaviorally through SyncHarness (a stale cloud row leaves local and pushes it; an equal row pushes nothing); the Group D pin stays as a labelled presence check.
regression_test_planned: |
  test/contracts/progress_restore_monotonic_behavioral_test.dart, edited for item 8: the every-monotonic-field test now carries weeks (6 local x 5 cloud) and expects 4 declined fields; the old assertion that weeks takes cloud including a genuine 0 is REPLACED (it encoded the superseded OI-83 premise; the daily streak keeps that assertion), and a new group of 7 tests (the file now holds 50) pins weeks (lower cloud refused, with the pre-fix control reproducing the demotion; higher cloud wins; a fresh reinstall adopts cloud including 0; the daily streak is still free to fall; a malformed cloud value keeps local and reports; the OI-83 kill switch restores cloud-wins; a Hive round-trip). Plus test/contracts/progress_restore_freeze_merge_behavioral_test.dart (41 tests, all new: 32 from the first pass plus 9 from the B-pass). Group A pure merge: the stale-cloud row (local {2,P} x cloud {1,earlier}) keeps local 2 and schedules a push (FAILS pre-fix); the asymmetric grant carry rows; the boot-seeded row; the carry refinements (an unseen local consume comes off the carried count: {0,W,F,used=[d1]} x {3,W,T} -> 2; two and more-than-cloud rows; the already-seen mirror; the no-ledger-evidence row {0,W,F} x {3,W,T} -> 3 equal to pre-fix; the older cloud stamp is adopted: {1,W,F} x {3,P,T} -> {3,P}, no push); the local grant the cloud has not seen (an eaten grant {3,W,T} x {1,W,F} -> {1, flag F}, no push, with the pre-fix control reproducing the cloud flag; with a local-only used date it still pushes the ledger; the surviving-grant and local-newer mirrors); the F4 mirror (phantom local grant x cloud 1 same week -> 1); flag-only divergence pushes; used-dates union into the singular key; plural key not copied; non-numeric count does not throw; control-plane keys dropped (F7); steady state (identical, set-equal, flag on both sides) never pushes. Group B: kill switches, key by key, in both directions (each switch alone restores cloud-wins for freeze AND control-plane keys; neither set is the control; the getter fails closed with the box unopened). Group C real code through SyncHarness: the lightweight shape and the PRODUCTION ORDER (_restoreUserProgress then _restoreFreezes against the same stale pre-fetched row leaves local {2,P} and sends exactly ONE update_streak_progress RPC; two consecutive runs send zero extra), and the owner guard (a restore captured for another account writes nothing and pushes nothing). The sign-in hydrate behavioral tests in Group C (a stale cloud row pushes; an equal row does not). Group D presence pins (labelled presence-only; the behaviour is Group C). Mirror rows that already pass pre-fix by design are labelled in the test.
mutation_proof: |
  Rule 21, scratch-copy protocol (copy, mutate with sed, confirm the hash CHANGED, run, restore from the copy, confirm the hash identical; no compile error in any run). Run against the new test file only (32 tests in the first pass, 41 after the B-pass): M1 post-pass off (freeze family and control-plane keys back to the loop copy) 12 red; M2 asymmetric carry removed 4 red; M3 flag-only push clause removed 1 red; M4 owner guard removed 2 red; M5 used-dates push clause removed 1 red; M6 the unawaited(syncFreezes()) call removed 1 red; M7 syncFreezes back to _supabase.currentUser?.id 2 red. Item 8 (weeks): K1 removing current_streak_weeks from monotonicProgressFields reddens 4 of the 50 tests in progress_restore_monotonic_behavioral_test.dart (lower cloud refused, malformed keeps local, the Hive round-trip, every-field-guarded). B-pass, against the 41-test file: MC1 the eaten grant claimed (flag written local OR cloud) 2 red; MC2 the push scheduled for an eaten grant 1 red; MC3 the unseen-consume subtraction removed 2 red; MC4 the cloud's older refill stamp not adopted 3 red; MC5 the hydrate push removed 2 red (the behavioral hydrate test and the Group D pin); and against streak_progress_service_concurrency_test.dart (5 tests): MC6 a second index-assignment writer added to an unrelated lib file 1 red. Every mutation reddened a distinct, expected set. Each protection has at least one test that fails only for it.
impact_analysis: |
  Founder account only is CONFIRMED affected (live read-only SELECT, project dedsavbjuwgarrhphgnl, 2026-10-06 06:50 IST): user_progress streak_freezes_available=2, used_dates {2026-09-16, 2026-09-25}, last_refill 2026-10-05, streak_progress_version 121; two missed days (10-03, 10-05) planned with no workout_logs row. Telemetry shows the same revert on 2026-10-01 (refill_check lastRefill=2026-09-21 after the 09-28 refill, a second Monday refill, +1 freeze) and cloud-lagging-local drops (sync_freezes_retry_dropped, sync_user_progress_retry_dropped on 09-26, 09-28/29/30 and 10-02), so the exposure is any user whose freeze push times out. BEHAVIOUR CHANGES, accepted: (1) a restore that previously refunded a spent freeze by taking the cloud's higher count now keeps the lower local count and pushes it (the same-week LOWER rule), which is the intent of mergeFreezeProgress; (2) a boot-seeded {1, thisMonday} against a cloud {3, lastMonday} now takes the rule's local-newer branch (3 and a push when the cloud flag is true, else 1 and a push) that the clobber used to pre-empt; reviewers could not construct a reachable production sequence; (3) a first-PRO grant whose push was dropped followed by a restore loses its extra freezes exactly as before (no symmetric carry) AND, since the B-pass, leaves the grant flag at the cloud's false exactly as before, so the idempotent grantFirstProFreezes (it runs on every PRO boot, not only on the transition, as this document used to claim) re-grants at the next boot; the first-pass version wrote the flag TRUE next to the lost count and would have blocked that re-grant for good. NOT FIXED here, with terminal states in docs/audit/streak-freeze-restore-ownership.closure.yaml (the push RPC is still a bare COALESCE for current_streak_weeks and last_streak_week is local-only, so a reinstall re-counts the current week once; both need a migration and the founder's apply go: blocked_on_user): the founder's own ledger is one freeze short (a prod UPDATE needing the founder's explicit word, applied to the cloud row AND the phone because a cloud-only +1 is reverted by the same-week LOWER rule); current_streak_weeks WAS overwritten by the whole-row restore (item 8 of the fix: founder decision A, 2026-10-06, makes it local-max-wins like current_phase; it is a lifetime count of good weeks because its only RUNTIME writer increments it (train_provider.dart completeWorkout); onboarding and the default progress map seed 0 and the debug-only dev simulation resets it, and nothing resets it in production; OI-83 had excluded it on a premise the code contradicts). Not changed: when it goes UP (+1 per week at 80% of the planned sessions) and that no runtime path resets it; a reset-when-the-daily-streak-breaks feature would have to REMOVE it from the monotonic list again and is filed on the open-issues board at commit time, not built here.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "user_repository.dart (mergeCloudProgress, _mergeFreezeFamily with the carry refinements and the eaten-grant rule, ProgressMergeResult.scheduleFreezeSyncUp, kill switch, engaged event), sync_profile.dart (_restoreUserProgress owner guard + push, restoreFreezesForTest seam), auth_session_bootstrapper.dart (push), sync_restore_completeness.dart (_liveUserId), sync_service.dart (core restore and single-call guard read _liveUserId). flutter analyze (whole project, --no-fatal-infos): 0 errors and 0 warnings (356 infos, none a warning). Full suite on the final tree (TZ=Asia/Kolkata flutter test test/ --exclude-tags golden, 2026-10-06, 40 min): 7854 passed, 9 skipped, 0 failed, exit 0." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Group C drives the real writers over a real Hive userBox through SyncHarness and reads userBox['progress'] back after the production-order restore; Group A pins the merge result for every row in the grid." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "user_progress columns used here (streak_freezes_available INTEGER NOT NULL CHECK 0..3, streak_freezes_used_dates, streak_freezes_last_refill, streak_freezes_first_pro_grant_done, streak_progress_version) read from the live row; NOT NULL comes from migration 048 and the CHECK 0..3 from migration 072 (056/090/096 are the update_streak_progress RPC); no schema change." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "Read-only SELECTs on 2026-10-06 against the founder's user_progress, scheduled_workouts and subscriptions rows (values in the impact analysis); no write." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function touched; the restore-user-snapshot function was read from the REPO only (no deployed-version comparison) to confirm what the single-call path returns." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "No cron involvement." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No policy change; the push is the existing update_streak_progress RPC under the user's own session." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "No secret read or written." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "Group C counts requests to /rest/v1/rpc/update_streak_progress under a stub server: exactly one for a stale cloud row, zero for a steady state and for a second consecutive run. The RPC call shape is unchanged (cross_device_progress_optimistic_lock_wiring_test passes). Real-device confirmation (cold start with a lagging cloud row) is the founder's check and is NOT done." }
recurrence: "Recurrence of a8f3d1 (restore merge vs concurrent consume), 9c4a17 (Monday refill vs restore race) and e9d4b7 (cloud streak stale after decay): the same freeze keys, a third whole-row writer that bypassed the merge rule. user_repository.dart's own field doc said 'two merge rules over one field is how writer/reader drift starts' and left a second rule live. Same class as the OI-83 monotonic-field demotion (d1f6b3)."
related_bugs: [a8f3d1, 9c4a17, e9d4b7, f9d2e7, d1f6b3, e6b9c4]
---

# c9d2f6 — a whole-row restore overwrote the streak-freeze state with a stale cloud row

## What happened

`UserRepository.mergeCloudProgress` (introduced for OI-83 so the lifetime counters could not be demoted) was local-max-wins for three fields and cloud-non-null-wins for everything else. The freeze family (`streak_freezes_available`, `streak_freezes_last_refill`, `streak_freezes_first_pro_grant_done`) shares key names between the local map and the cloud row, so it fell into "everything else". A cloud row that lagged the phone therefore replaced the phone's newer freeze state on every restore. Its own doc comment said the family was "already merged by `StreakProgressService.mergeFreezeProgress`" while the loop below it overwrote it.

The production restore runs `_restoreUserProgress` and then `_restoreFreezes`. `_restoreFreezes` applies the right rule, but it only sees the local row the first step already replaced, so it could not repair anything. `restoreLightweightAlways` (every cold start) and the sign-in hydrate never call `_restoreFreezes`. On the morning of the report the log shows the refill stamping `last_refill` at 06:46:25 and a `refill_check` reading the stale `2026-09-28` 1.6 seconds later.

## Writer / reader map

Writers of the three keys: the freeze service (`commitRefill`, `commitConsume`, `grantFirstProFreezes`, `resetToFreeCapOnLapse`), `_restoreFreezes`, the conflict retry, `StreakFreezeClampMigrator`, the version stamp in `sync_service.dart`, and the two whole-row merges (`sync_profile.dart` `_restoreUserProgress`, `auth_session_bootstrapper.dart` `hydrateFromCloud`) via `UserRepository.mergeCloudProgress`. No third cloud-row merge exists (every `put('progress'` and `saveProgress` site was grepped in the plan). Readers: `_calculateStreak`, `StreakFreezeNotifier`, `refillIfNewWeek`, `syncFreezes`.

## Fix and what it deliberately does not do

See `proposed_fix`. The merge rule itself is untouched: the batch reuses the mutation-proven `mergeFreezeProgress` rather than adding a second one. The symmetric grant carry was designed, reviewed and DROPPED in plan round 4 because `_restoreFreezes` and the conflict retry would undo it at two more merge sites; the asymmetric carry survives because after the post-pass local already equals the cloud value there.

## Mutation table

| Mutation (scratch copy, hash confirmed changed and restored) | Tests red (of 32; B-pass rows of 41) |
|---|---|
| M1 post-pass off | 12 |
| M2 asymmetric carry removed | 4 |
| M3 flag-only push clause removed | 1 |
| M4 owner guard removed | 2 |
| M5 used-dates push clause removed | 1 |
| M6 `unawaited(syncFreezes())` removed | 1 |
| M7 `syncFreezes` back to `_supabase.currentUser?.id` | 2 |
| K1 `current_streak_weeks` removed from `monotonicProgressFields` (item 8; of 50 tests in the monotonic file) | 4 |
| MC1 eaten grant claimed (flag local OR cloud, B-pass; of 41) | 2 |
| MC2 push scheduled for an eaten grant | 1 |
| MC3 unseen-consume subtraction removed | 2 |
| MC4 cloud older refill stamp not adopted | 3 |
| MC5 hydrate push removed | 2 |
| MC6 second index writer (of the 5-test sole-writer file) | 1 |

No run was a compile error. The reviewer-prescribed reductions (no symmetric carry, no leaf extraction) are why the mutation set is this small.

## Limits

The founder's own ledger is one freeze short because of the 2026-09-17 spurious debit (see b4e7a1). Repairing it would be a production write; the founder decided on 2026-10-06 to leave it as it is, so no write was made. This fix keeps a cloud row that is ahead from clobbering the phone but cannot invent a freeze that was lost earlier.
