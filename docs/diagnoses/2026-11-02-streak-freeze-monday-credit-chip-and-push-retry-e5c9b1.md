---
bug_id: e5c9b1
date: 2026-11-02
batch: freeze-refill-sync
status: fixed
blast_radius: platform
tier: m_fix
symptom: |
  Founder (account upendra, web 1.0.0+48, PRO yearly), Monday 2026-11-02: the Train header showed
  streak freezes 0/3 (and 0 DAYS) although the Monday credit (+1) is owed after the Saturday miss
  was settled; a full reload still showed 0. Live read-only evidence (client_errors + user_progress):
  at 05:10 UTC the restore, the Saturday consume (1->0), and the refill (0->1) all ran on the device,
  then TWO consecutive `sync_freezes_retry_dropped` events (expected=198, expected=199), and the cloud
  row ended {available 0, last_refill 2026-11-02, used_dates ending 2026-10-31, version 204}.
concept: streaks
sot_registry_entry: |
  streaks: extends the EXISTING streak concept in docs/sot_registry.yaml (behavioral_test_path
  test/contracts/streak_freeze_refill_race_behavioral_test.dart; new additional_tests
  streak_chip_restore_tick_behavioral_test.dart and freeze_push_retry_attempts_behavioral_test.dart).
related_bugs: [9c8958, 9c4a17, f9d2e7, c9d2f6, b4e7a1, e6b9c4, d7a3e5]
recurrence: |
  YES, two classes. (1) 9c8958: a Hive write (refill) with no provider invalidation; 9c8958 fixed only the
  rollover path and Home's background-restore listener. Train and Nutrition read the same chip but only a
  mounted Home refreshed it, so a session opened on /#/train (web deep link) kept the pre-refill value.
  (2) e6b9c4: the version-locked freeze push (`update_streak_progress`) retried ONCE; several freeze pushes
  and the snapshot RPC bump `streak_progress_version` in one launch, so two consecutive bumps lost the
  Monday refill push. Known-good fixes applied (invalidate/rebuild at the source; bounded retry).
writers:
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "commitRefill / refillIfNewWeek (Hive write + unawaited syncFreezes)", line: 62 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "commitConsume (spend; leaves last_refill)", line: 167 }
  - { file: lib/core/services/sync/sync_restore_completeness.dart, method_or_widget: "syncFreezes + _retrySyncFreezesOnceAfterConflict (cloud push via update_streak_progress)", line: 34 }
readers:
  - { file: lib/features/home/providers/home_provider.dart, method_or_widget: "StreakFreezeNotifier.build / StreakNotifier.build (streakFreezeProvider, streakProvider)", line: 270 }
  - { file: lib/features/train/screens/train/plan_header.dart, method_or_widget: "WardStatusStrip ref.watch(streakFreezeProvider)", line: 118 }
  - { file: lib/features/nutrition/screens/nutrition_screen.dart, method_or_widget: "ref.watch(streakFreezeProvider)", line: 150 }
hive_key_prefix: "user_progress (userBox['progress'])"
hive_key_formula: "UserRepository.getProgress()['streak_freezes_available'] / ['streak_freezes_last_refill'] / ['streak_freeze_used_dates'] / ['streak_progress_version']"
sync_methods:
  - "SyncService.syncFreezes -> RPC update_streak_progress (migration 056/090/096, version lock, NULL on mismatch)"
restore_methods:
  - "UserRepository._mergeFreezeFamily / StreakProgressService.mergeFreezeProgress (unchanged)"
cloud_table: user_progress
cloud_columns:
  - streak_freezes_available
  - streak_freezes_last_refill
  - streak_freezes_used_dates
  - streak_progress_version
ist_handling:
  - { file: lib/core/utils/ist_date.dart, method_or_widget: "istTodayStr / setTestClockTo (tests pin the Monday 2026-11-02, never real today)", line: 35 }
provider_invalidations:
  - "restoreCompletedTickProvider (new bridge): streakFreezeProvider and streakProvider watch it"
telemetry_op_types:
  success:
    - streak_freeze_refill_done
  failure:
    - sync_freezes_retry_dropped
cross_account_guard: "HiveUserSession.currentOwnerFullId == userId is now re-checked before EACH fresh Hive read in the retry loop (previously only once, after the RPC)."
forbidden_patterns_checked:
  - { pattern: "a Notifier that reads Hive once per build with no dependency on the restore tick", absent: true }
  - { pattern: "stamping a re-fetched cloud version locally without merging the freeze columns", absent: true }
proposed_fix: |
  T1 (chip): `restoreCompletedTickProvider` bridges `SyncService.restoreCompletedTick` (bumped LAST after
  the background restore + heals) into Riverpod; `StreakFreezeNotifier` and `StreakNotifier` watch it, so
  every completed restore rebuilds the chip from Hive on every tab, whichever is mounted.
  T2 (push): `_retrySyncFreezesOnceAfterConflict` becomes a bounded loop of up to
  `SyncFlags.freezePushRetryAttempts` (3) rounds, each re-fetching the cloud row, re-reading Hive fresh and
  re-checking ownership; the local version is stamped ONLY on a successful RPC (a dropped round never
  restamps it); the drop event fires once after the last round. Kill switch `disable_freeze_push_attempts`
  (default new path ON) restores the single retry verbatim. 3 is a bounded improvement, NOT proven
  sufficient: `syncFreezes` is not coalesced, so N racing pushes can each lose to N-1 winners; the next
  write or restore self-heals as before.
  NOT FIXED HERE (honest scope): the writer that left the cloud at {0, 2026-11-02} was NOT reproduced
  (T0 replay: the logged sequence yields cloud {0, 10-26} + local {1, 11-02}, which a reload heals).
  See the closure ledger: blocked_on_user. The first-PRO grant firing on every web cold start was split
  out (OI filed) per CLAUDE.md 4.12.1 and is NOT causal for the observed chain.
contract_test_path: test/contracts/streak_chip_restore_tick_behavioral_test.dart
regression_test_planned: |
  - test/contracts/streak_chip_restore_tick_behavioral_test.dart (4 tests, behavioral): real Hive + real
    refill + real tick bump, no screen mounted (the Train-first case). Mutants run: removing the freeze
    watch (red), removing the streak watch (red, counted through a subclass), bridge never listening (red),
    listener not removed on dispose (red once the dispose test asserted hasListeners is false from the
    start; the first version of that test compared to a baseline the mutant itself polluted: survived).
  - test/contracts/freeze_push_retry_attempts_behavioral_test.dart (6 tests): stub applies migration 096's
    lock verbatim; asserts the p_expected_version of EVERY request IN ORDER ([190,196,197,198]); bounded
    1+3 requests with one drop event; kill switch restores [190,196]; row-absent returns without a drop
    event; a same-device write during the retry is folded in; presence pin for the per-round ownership
    guard. Mutants run: attempts 3->1, 3->2, ownership guard removed (only the presence pin reddens: no
    behavioral ownership test), kill switch ignored, no break on success, captured args instead of a fresh
    read, drop event on the first miss, stale version reused: all 8 reddened >=1 test, each confirmed
    applied (grep -c) and not a compile error.
impact_analysis: |
  Scoped to the Home/Train/Nutrition streak chip providers (rebuilt on a completed restore) and the freeze
  push retry. No change to the refill/consume rules, the merge rule (same-week LOWER, ledger union), the
  RPC, any migration or Edge Function. Existing pins (29 test files that grep or exercise these paths,
  389 tests) pass unchanged. Value semantics of streak_freezes_available / first_pro_grant_done are NOT
  changed (4.1.5 point 3: grep of test/ and supabase/functions/ found only the restore-user-snapshot
  column projection outside lib/).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "home_provider.dart (bridge + 2 watches), sync_restore_completeness.dart (bounded loop), sync_flags.dart (switch). 12 mutants killed, see regression_test_planned." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "T0 replay (throwaway, deleted) printed local Hive after every step of the 2026-11-02 timeline." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "pg_get_functiondef(update_streak_progress) read live 2026-11-02: FOR UPDATE, version lock, NULL on mismatch, COALESCE on update; no schema change." }
  - { tier: 4, name: "Postgres data", status: verified, evidence: "user_progress for upendra read-only: available 0, last_refill 2026-11-02, flag true, version 204, used_dates ending 2026-10-31, current_phase 4, last_workout_date 2026-10-21. client_errors event timeline 05:09-05:34 UTC, all platform web." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No policy or grant touched; the RPC is SECURITY DEFINER with its own auth.uid() check." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The stub in freeze_push_retry_attempts_behavioral_test.dart reproduces migration 096's contract; the request bodies are asserted." }
---

# Monday streak-freeze credit lost: chip not rebuilt after a restore, push dropped after one retry

## What the founder saw
Train header `0 DAYS` / freezes `0/3` on Monday 2026-11-02, still 0 after a reload.

## What was proven (and what was not)
- The restore, the Saturday consume (1->0) and the refill (0->1) all ran on the device within ~45 s. The chip
  providers read Hive once per build and only a mounted Home invalidated them after a restore (9c8958 class).
- The freeze pushes lost the version race twice (expected 198 then 199) after one retry each (e6b9c4).
- T0 (throwaway replay with a stub that bumps the version between the retry's fetch and RPC): the logged
  sequence leaves cloud {0, 2026-10-26, version 199} while local holds {1, 2026-11-02}; a reload heals it.
- NOT reproduced: the cloud ended {0, 2026-11-02}. A second debit after the refill (a second consume, or
  `resetFreezesAfterGap`) would produce it, but prod shows no new used date after 10-31, no phase/gap event,
  one device only (web). The same-week LOWER rule then keeps the 0 on every reload. Ledger:
  `blocked_on_user` (needs the device's local Hive or a log of the next occurrence).

## Fix
See `proposed_fix`. Tier: platform (sync path); plan `docs/plans/2026-11-02-freeze-refill-sync.md`, 3 plan-review
rounds (rounds 1 and 2 not converged; the unit was shrunk per 4.12.1; round 3 converged).
