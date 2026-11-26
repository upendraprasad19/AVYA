---
bug_id: b3f7d2
date: 2026-11-26
batch: OI-348 Landing 3d (P3)
status: fixed
tier: full
blast_radius: platform
symptom: |
  OI-348 walk P3 (AAB 1.0.0+50, founder, 2026-11-22): a workout missed earlier this week cannot be done later. The day-swap picker (Train ⇅ / drag, Home long-press) shows every past day as PAST, so a missed Wednesday cannot be moved into a free Friday; the freeze spent on Wednesday stays spent. The Home long-press also opened the picker on ANY day (a past or done day) and listed targets the swap would then refuse.
concept: missed_day_rescue
sot_registry_entry: missed_day_rescue
writers:
  - { file: lib/core/services/day_swap/day_swap_rules.dart, method_or_widget: "DaySwapRules.lockOf: `date.compareTo(today) < 0 -> past` (the refusal; unchanged, now bypassed only by rescueLockOf / pairLock)", line: 92 }
  - { file: lib/core/services/swap_service.dart, method_or_widget: "SwapService._firstLock (both dates through lockOf) and _hasLoggedSets (false for every non-today date)", line: 176 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "commitConsume (the only freeze spend writer; nothing ever gave one back)", line: 169 }
readers:
  - { file: lib/core/services/swap_service.dart, method_or_widget: "weekStates / preview / _swapDaysInWeek (locks per date)", line: 199 }
  - { file: lib/features/train/widgets/swap_picker_sheet.dart, method_or_widget: "SwapPickerSheet: per-target d.lock only, no source check", line: 91 }
  - { file: lib/features/train/widgets/day_swap_drag_wrapper.dart, method_or_widget: "isValidTarget = movable && dragging", line: 85 }
  - { file: lib/core/services/streak_progress_service.dart, method_or_widget: "mergeFreezeProgress: same week LOWER available + UNION ledger ('never refund a freeze'), so a plain +1 refund is undone by every restore and push conflict", line: 403 }
  - { file: lib/features/train/repositories/workout_repository.dart, method_or_widget: "_calculateStreak: skips type rest; a used date is covered; a fresh missed day spends a freeze", line: 531 }
hive_key_prefix: "schedule_<date> (row key rescued_into) and userBox['progress'].streak_freeze_used_dates (entry refund:<date>)"
hive_key_formula: "schedule_${formatDateKey(date)}; FreezeLedger.marker(date) = 'refund:' + IST date"
sync_methods: [syncFreezes, pushWorkoutPlanForSyncDomain, syncWorkoutData]
restore_methods: [_restoreFreezes, mergeCloudProgress, _retrySyncFreezesOnceAfterConflict]
cloud_table: user_progress
cloud_columns: [streak_freezes_available, streak_freezes_used_dates, streak_freezes_last_refill, plan_json]
contract_test_path: test/services/day_swap/missed_day_rescue_test.dart
ist_handling:
  - { file: lib/core/services/day_swap/day_swap_rules.dart, line: 59, fn: "mondayOf (string maths on IST dates; the rescue week and the refund's Monday bound)" }
  - { file: lib/core/utils/ist_date.dart, line: 82, fn: istTodayStr }
provider_invalidations: [daySwapWeekProvider, daySwapAllowanceProvider, currentPlanProvider, calendarWeekProvider, streakProvider, streakFreezeProvider, todayWorkoutProvider, allExercisePRsProvider]
telemetry_op_types:
  success: [day_swap_done, streak_freeze_refund_done]
  failure: [day_swap_freeze_refund_threw, day_swap_rescue_reckon_threw, day_rollover_rescue_refund]
cross_account_guard: "true: the rescue reads and writes only the signed-in user's own user-scoped boxes, through the same engine and write lock as every swap; the refund goes through the existing owner-checked syncFreezes push."
forbidden_patterns_checked:
  - { pattern: "a refund keyed on the row SHAPE (rest + is_swapped) alone: reachable without a rescue (a swap from another device restored after this device spent)", absent: true }
  - { pattern: "a plain +1 to streak_freezes_available with no ledger marker (the same-week LOWER merge undoes it)", absent: true }
  - { pattern: "a merge raise on a side whose ledger never held the date (double refund)", absent: true }
  - { pattern: "a rescue offered to DaySwapOrigin.coach (its lookahead never shows a past day)", absent: true }
  - { pattern: "a status: missed value (missed stays derived: past + planned + no logs)", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-landing3d.md (3 review rounds; split after round 2 under CLAUDE.md 4.12.1; converged). Founder calls 2026-11-26: partner = today only when today is a rest day, same week; the old day shows MOVED and counts as rest; a freeze spent on it is refunded; the rescue spends the weekly swap.
  Rules (pure, day_swap_rules.dart): isRescueHost (type AND status rest), isMissed, rescueLockOf, pairLock (a past date pairs only with today). Engine (swap_service.dart): _lockFor/_firstLock/weekStates use them (a day before the user's anchor, WorkoutRepository.earliestUserAnchorKey, stays past: B-pass F2) when the kill switch is off and the origin is not coach (preview takes the origin too); one datesWithExerciseLogs pass + wlog_ for "no logs"; the past landed row gets rescued_into (a markerKeys member); after the write, settleRescueRefunds then reckonStreakDecayAndPersist, neither can fail the swap. Refund (streak_progress_service.dart): FreezeLedger, the refund:<date> marker next to the kept plain date, the derived idempotent settleRescueRefunds (current IST week, tier cap, keys on rescued_into + type rest, NOT is_swapped: B-pass F1, a rescue sending earlier-swapped content home lands without the swap markers; a marker only for the dates actually paid, B-pass F6a), also run from the day rollover; mergeFreezeProgress raises a side +1 per marker the other side has, it lacks, on a date it holds, on/after its last_refill; prune by the marker's date; the grant carry in UserRepository._mergeFreezeFamily counts net spends. UI: picker per-target pairLock (a target refused because the SOURCE is a missed day says TODAY ONLY, B-pass F5), a locked SOURCE shows "<Day> has already passed. It stays put." and no rows (the pre-existing Home bug), the rescue footer, the refund toast line; drag target follows pairLock; the controller refreshes streakFreezeProvider. Kill switch configBox['disable_missed_day_rescue'] (default ON).
  Not changed (OI-532): the per-row schedule restore that can undo ANY unpushed swap; the rescue has exactly an ordinary swap's exposure.
regression_test_planned: |
  test/services/day_swap/missed_day_rescue_test.dart (30: rule T1-T6 incl. T1c anchor, T-P, T-K, T-W, refund T7-T7i incl. T7e3/T7e4, streak T8/T8b), test/core/streak_freeze_refund_merge_test.dart (13: M1-M8, M-cap, every two-device interleaving MS1-MS3), test/widgets/swap_picker_rescue_test.dart (8: pairLock table, picker from today / Wed / Sat, locked source, kill switch, refund toast), test/features/train/day_swap_provider_test.dart (+1: the freeze chip refreshes). Related suites (283 tests: engine, rules, provider, picker, row trailing, drag, allowance line, coach card, freeze merges, rollover invalidation, restore merge invariants) green on Windows.
mutation_proof: |
  Rule 21. scratchpad mut3d.py: each mutant applied by an EXACT-ONCE replace (refused otherwise), the named test file run, the source restored by copy and compared byte-for-byte after every mutant, md5 of all five mutated files equal before and after the run (never git checkout). 17 of 17 red, none a compile error (the nine single-red mutants re-run with output kept: each reddened exactly its intended test):
  a isMissed ignores logs [3, engine]; b pairLock always null [2, engine] and [3, widget]; c refund skips the +1 [6]; d merge drops the "holds D" condition [3, merge: M3/M4]; e prune treats markers as plain strings [1: M7]; f rescue ignores the kill switch [1: T-K]; g host accepts a rest hybrid [1: T2b]; h no-logs check ignores wlog_ [2: T4w + T-W]; j coach origin allowed [2: T3b, T-P]; k refund drops the Monday bound [1: T7f]; l refund keys on the row shape [1: T7g]; m refund drops the is_swapped check [1: T7h]; o grant carry counts a refunded date [1: M8]; p controller does not refresh streakFreezeProvider [1: provider test]; q rescued_into never written [9]; r no reckon after a rescue [1: T8].
  B-pass folds (B-pass review docs/reviews/oi348-landing3d-bpass.md), same protocol, exact-once sed, `grep -c` confirmed, restore by copy + cmp: re-add the is_swapped check [2: T7i, T7e4]; drop the anchor guard [1: T1c]; mark every owed date [1: T7e4]; drop the TODAY ONLY chip [1: picker]; drop the given<=0 early return [0: equivalent, the same values are written]. Mutation m above (the is_swapped check) is retired with the check.
  B-pass seat B (mutation lens, 54 mutants on 666760a0, 13 survived): each survivor re-run after the new tests: M03 drag pairLock argument order, M31 drag kill switch, M30 settle kill switch, M07 Monday bound, M11 type rest, M13 same-week into, M46 notice decrement, M44 host status, M39 rollover settle call (runRolloverNow behavioural test) all red; M14 (a count above the cap) and M42 (_weekHostsRescue same week) green, both equivalent (reasons in docs/reviews/oi348-landing3d-bpass.md).
  Dropped from the plan: mutation n (the coach card's origin), because the card never shows the preview's refusal (build note B1).
impact_analysis: |
  A free or PRO user who missed a workout this week can move it into today when today is a rest day (Train ⇅ or drag, Home long-press); it spends the week's swap. The past day shows MOVED and counts as rest for the streak and the completion rate; a Streak Freeze spent on it comes back, also across devices and restores (the ledger marker); a chain the missed day broke counts again. Nothing changes for future days, for the coach, or with the kill switch set. The Home long-press on a day that cannot move now says why.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "day_swap_rules.dart, swap_service.dart, streak_progress_service.dart, day_rollover_service.dart, user_repository.dart, day_swap_copy.dart, day_swap_result.dart, missed_day_rescue_flag.dart, the picker / drag / confirm sheet / coach card / controller; flutter analyze lib/ no warnings." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "schedule_<date>.rescued_into and the refund:<date> ledger entry; behavioral tests on real Hive (missed_day_rescue_test.dart)." }
  - { tier: 3, name: "Postgres schema", status: verified, evidence: "user_progress.streak_freezes_used_dates is text[] with no CHECK; streak_freezes_available BETWEEN 0 AND 3 (migration 072) holds (refund capped by tier); update_streak_progress (migration 115) stores the array verbatim. No migration." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data repair; markers appear only after a rescue." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "consume-day-swap is date-blind (unchanged); restore-user-snapshot passes streak_freezes_used_dates through (restore_reads.ts:119); no EF change." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "None." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The freeze push sends the ledger array as before (a marker is one more string); the rank engine and the AI snapshot do not read the ledger; the coach lookahead (today..+6) never shows a past day." }
recurrence: "Not a recurrence of a bug: a past day was locked by design (day-swapper spec decision 4, amended here by the founder's 2026-11-26 calls). The freeze half touches the 'never refund' merge rule of a8f3d1 / c9d2f6 / f9d2e7 deliberately: a refund is now a recorded, mergeable event instead of a count change the merge would undo."
related_bugs: [a8f3d1, c9d2f6, f9d2e7, e2b9d4, d5a1e7]
---

# b3f7d2 - a missed workout cannot be rescued into today

## What happened
The day-swap engine refuses any date before today (`DaySwapRules.lockOf`, decision 4 of the day-swapper spec). A missed day is not stored; it is a planned row whose date has passed. So a user who missed Wednesday and is free on Friday could not move the workout, and the freeze the streak walk spent on Wednesday stayed spent.

## PROVEN
- From the code: `lockOf` returns `past` before any other check for a date before today, and `_firstLock` runs it on both dates; `_hasLoggedSets` answers false for every date but today.
- From the code: `mergeFreezeProgress` takes the LOWER `available` within a week and unions the ledger, so a plain +1 is lost on the next restore or push conflict (routine: the snapshot RPC bumps `streak_progress_version`). Hence the `refund:<date>` marker.
- From the tests: every interleaving of a two-device spend / rescue / sync sequence settles at the true count (MS1-MS3); the old rule's results are unchanged when no marker exists (M6, MS3).
- From review: the per-row restore of `scheduled_workouts` (`_restoreScheduledWorkouts`) can undo an unpushed swap (cloud status wins, no cloud timestamp). It applies to every swap, so it is OI-532, not this fix.

## Residue, stated
- OI-532: a restore before a swap's push lands can undo the swap; after a rescue the refund then stays (the kept plain date stops a second spend, T8b).
- An old build (+50) merging a marker keeps it but takes the lower count until a new build pushes (testing accounts only).
- A Monday credit landing before another device's refund of a last-week day is merged: under-refund only.
- The coach cannot rescue (its card reads only the allowance and the warning from `preview`, so the coach origin there changes nothing visible; the apply refuses `past`).
- Device check on the next build: OI-348 row (Landing 3d); the kill switch goes after it.
