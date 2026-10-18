---
bug_id: d7a3e5
date: 2026-10-18
batch: pro-gap-policy-and-streak (Piece B)
status: fixed
blast_radius: platform
tier: full
symptom: >-
  A PRO user who stopped training and came back saw Home "1 DAY" (a streak the user had not earned), the missed
  weeks never appeared, the freezes were still full, the rank completion rate ignored the break and the coach had no
  way to know the user had been away. Cause: (1) the streak walk skipped a day with NO schedule row while the streak was
  still 0, so it crossed a blank gap and counted the old completed days; (2) the next phase started at
  max(today, plan_end + 1), so a user back after the phase ended got a phase from this Monday and a blank gap instead
  of missed days; (3) a blank gap spends no freeze, so freezes survived any break; (4) completionRateOverWindow skipped
  rowless days, so a long break cost nothing; (5) the coach snapshot carried no lapse fact; (6) the server rank cron (evaluate-rank-promotions, _shared/rank_engine.ts) computed the same completion rate over existing rows only, so it would have promoted on the old rate while the client refused (found by review round 2).
concept: lapse_gap_policy
sot_registry_entry: lapse_gap_policy
writers:
  - { file: lib/core/utils/gap_policy.dart, method: phaseStartAfterGap, line: 44 }
  - { file: lib/core/services/workout_schedule_read_service.dart, method: nextPhaseStartDate, line: 2066 }
  - { file: lib/shared/services/pro_phase_advance.dart, method: _runAdvanceWith and runGraduationPhaseAdvance (freeze zero, only after a committed advance), line: 283 }
  - { file: lib/core/services/streak_progress_service.dart, method: resetFreezesAfterGap, line: 325 }
readers:
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: _calculateStreak rowless-day branch, line: 397 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: completionRateOverWindow (RankService._qualifies), line: 492 }
  - { file: lib/features/ai_coach/services/ai_snapshot_builder.dart, method_or_widget: _getPlanStatus, line: 1353 }
  - { file: supabase/functions/_shared/rank_engine.ts, method_or_widget: completionRateOverWindow (opt-in countBlankDays) read by evaluate-rank-promotions, line: 173 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: [syncFreezes]
restore_methods: []
cloud_table: user_progress
cloud_columns: [streak_freezes_available, scheduled_workouts.scheduled_date]
contract_test_path: test/contracts/lapse_gap_policy_behavioral_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: [streak_freeze_gap_reset]
  failure: []
cross_account_guard: "All reads and writes go through the signed-in user's Hive boxes (UserRepository, workoutBox); no shared box is written. The kill switch lives in the shared configBox like the other disable_* switches."
forbidden_patterns_checked:
  - "Catch-up chain of all-missed phases (Option A) - REJECTED by the founder 2026-10-18: it inflates effectiveLevel (beginner becomes advanced) and deployments_complete, costs one generation per skipped phase and fills history with 0% phases. Option B (one phase) chosen."
  - "Holding the phase number back - REJECTED by the founder ('let it advance')."
  - "Spending freezes per blank day in the walk - REJECTED: a blank gap of 7+ days holds at least 3 planned days (the smallest plan = the cap of 3) so zeroing equals simulating them, without writing a ledger entry for days that never had a row."
  - "Touching plan_generator.dart - not touched (CLAUDE.md 4.4 rule 14)."
proposed_fix: >-
  New pure lib/core/utils/gap_policy.dart (kill switch disable_lapse_gap_policy, absent = live): phaseStartAfterGap
  starts the next phase at plan_end + 1 when that phase still contains today (days that passed show as missed), else
  at this Monday; the graduation unlock keeps the old rule (gapStart: false). _calculateStreak breaks on a rowless day
  before today that has a LATER schedule row (a mid gap; today tolerated; a trailing gap such as an expired free plan is skipped as
  before), spending no freeze. _runAdvanceWith and the graduation advance call
  StreakProgressService.resetFreezesAfterGap when the new start leaves >= 7 blank days after the old window, and only
  after commitPhaseAdvance returned true (review round 1: an owner swap or a declined commit must not zero freezes).
  completionRateOverWindow counts rowless days after the first schedule row, before the last schedule row and before today as scheduled and missed (client and server).
  _shared/rank_engine.ts completionRateOverWindow gains an opt-in `countBlankDays` (pure blankDaysInWindow, env
  DISABLE_LAPSE_GAP_POLICY=true restores the old rate); only evaluate-rank-promotions opts in. The repo change needs a
  separate founder go to DEPLOY evaluate-rank-promotions (platform tier); until then the cron keeps the old rate.
  AiSnapshotBuilder emits plan_status (null-aware; present while >= 14 idle days, or a blank gap precedes the phase and the user has not trained since it began). The
  ai-proxy prompt rule that teaches the coach to use plan_status is a separate Edge Function change (needs the
  founder's go); until then the key is in the snapshot but the prompt does not mention it.
regression_test_planned:
  - "test/core/gap_policy_test.dart (pure start-date table: gap 0, 3 weeks, day 27, day 28, 6 months, graduation, kill switch, non-Monday end; blankGapDays)"
  - "test/contracts/lapse_gap_policy_behavioral_test.dart (21: streak blank gap / today tolerated / yesterday breaks / no freeze spent / missed rows drain freezes then break; completion rate 11/84 and its kill switch, first-row and today bounds; resetFreezesAfterGap touches only the count; real autoGenerateNextPhaseIfNeeded for 3 weeks late and 10 weeks late incl. both kill-switch cases; plan_status omitted/present/14-day boundary/kill switch; graduation call-site pin)"
  - "test/contracts/lapse_gap_freeze_reset_advance_test.dart (5, real runProPhaseAdvance / runGraduationPhaseAdvance: committed advance zeroes, kill switch keeps, a declined commit keeps, graduation after a blank gap zeroes and starts this Monday, graduation with no gap keeps)"
  - "supabase/functions/_shared/rank_engine_blank_days_test.ts (6 Deno tests: pure blankDaysInWindow, opt-in vs default rate, env kill switch, cron call-site pin)"
  - "test/contracts/phase_unlock_start_date_test.dart (source pin repointed from candidate.isAfter(today) to phaseStartAfterGap)"
mutation_proof: >-
  Dart: 17 mutants applied one at a time (exact-one-match replace, restored in finally, tree diffed clean after): streak break
  removed; today not tolerated; streak ignoring the switch; start always gap / never gap / 27 -> 28; rate blank not
  counted / today counted / before first row counted; freeze zero removed / always / also resetting current_phase;
  plan_status never / always / 14 -> 99; kill switch ignored; graduation gapStart true. First run: 15 red, 2 survived
  (plan_status threshold, graduation call site). Added the 14/13-day boundary test and the call-site pin, re-ran those two
  mutants: both red. 17 of 17 red. Round 1 follow-up: 8 more (reset not tied to the commit, reset removed, gap forced 0, threshold 8 / 1 / ignoring the switch, plan_status ignoring training-in-phase, IST date key): 7 red; the IST-vs-local key mutant is indistinguishable under the IST test zone (equivalent in CI). Server (Deno, before the trailing-gap rule): 7 mutants (t<=end, start ignoring the first row, always / never / switch-ignoring count, cron not opted in, empty present set): 7 of 7 red.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "gap_policy.dart, workout_schedule_read_service.dart, workout_repository.dart, streak_progress_service.dart, pro_phase_advance.dart, ai_snapshot_builder.dart; flutter analyze lib/ clean of errors and warnings; new tests green." }
  - { tier: 2, name: hive, status: verified, evidence: "Writes only userBox progress.streak_freezes_available (existing key, via UserRepository.updateProgress); reads schedule_* rows in workoutBox. Behavioral tests run against real Hive boxes." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change; streak_freezes_available already exists on user_progress." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "App not live, testers only; no data migration." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_deploy, status: fixed_in_this_batch, evidence: "_shared/rank_engine.ts + evaluate-rank-promotions/index.ts changed in the repo (deno check clean, 19 + 6 Deno tests pass); NOT deployed: needs the founder's go (CLAUDE.md 4.3). The plan_status prompt rule is a separate go too." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "evaluate-rank-promotions is the only cron reading the completion rate for promotion; it now opts in to blank days (after deploy). streak-guardian (streak > 2 weeks) simply stops selecting a user whose streak broke; not changed." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy involved." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Freeze zero pushes through the existing syncFreezes; mergeFreezeProgress takes the LOWER available only when last_refill is EQUAL on both sides (streak_progress_service.dart:367), so a strictly newer cloud last_refill with available > 0 and an unlanded push could refund it (disclosed edge, review round 1). Not exercised against the live project." }
impact_analysis: >-
  Affects PRO users who return after a break, and any user whose schedule has rowless days before today (a trailing gap, e.g. a free user whose plan expired, keeps its old streak and is not counted as missed). Ranks already earned are
  never lowered (shouldPromote). Rank gates that read the completion rate (MCPO, officer track) now fail until the
  user retrains after a long break. A mid-week plan_end (redoWeek4 / hold weeks) still snaps the new start back to its own Monday, overlapping the last days of the old window: pre-existing, kept, pinned in gap_policy_test (completed days survive the upsert guard). Open edge reported to the founder: a free user who upgrades after the free plan expired
  goes through the same automatic advance and starts in the past.
  .
  NOT A RECURRENCE of the 2026-10-16 ensure-current bug (d9b3e7); same area (phase advance), different mechanism. Streak
  walk-back history: 5e8a1c (frozen day collapse), f9d2e7 (ledger + single reckon site).
related_bugs:
  - "d9b3e7 (Piece A: the next PRO phase appears on app open)"
  - "5e8a1c, f9d2e7 (streak walk and freeze ledger)"
recurrence: none
---

# 2026-10-18-pro-lapse-gap-streak-start-rank-coach-d7a3e5

The frontmatter is the record. Plan: docs/plans/2026-10-18-pro-gap-policy-and-streak.md.

## Addendum 2026-10-18: free user who upgrades

Founder decision: plans start on a Monday, and a free user who returns and upgrades gets Phase 2 on THIS week's Monday. Fix: `autoGenerateNextPhaseIfNeeded` passes `gapStart: currentPhase > 1` (Phase 1 is the free phase, so leaving it is a fresh start; no PRO-activation date stored, no subscription code touched). Test: `lapse_gap_policy_behavioral_test.dart` "free user leaving Phase 1 3 weeks late: fresh start this Monday"; mutated (rule reverted to `nextPhaseStartDate()`) and it reddened. `phase_unlock_start_date_test.dart` source grep repointed.
