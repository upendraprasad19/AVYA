---
bug_id: b7d3e5
date: 2026-10-08
batch: streak-freeze-restore-ownership (addendum A, Slice D: the weekly-streak marker is stamped only when a week counts; founder decision D5 = yes)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  The weekly-streak counter (`current_streak_weeks`) under-counts. With 6 planned workouts the threshold is 5, but the FIRST completed session of a week stamped the marker `last_streak_week` with that week's plan id, so the qualifying fifth session saw "this week already counted" and the week never counted. A week counted only when the qualifying session was also the first completion of its week. Evidence: the founder's `streaks` row for the week of 2026-09-14 is 6 planned, 6 completed, and the counter stayed 4.
concept: weekly_streak_counter
sot_registry_entry: weekly_streak_counter
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout (the only production writer of current_streak_weeks and last_streak_week; pre-fix it wrote last_streak_week unconditionally)", line: 1728 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "weeklyStreakAfterCompletion (post-fix: the pure rule; the marker moves only when the counter increments)", line: 662 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "calendarWeekKey (post-fix: the marker's key, the Monday of the workout's calendar week as days since the epoch)", line: 645 }
readers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "completeWorkout reads last_counted_week_key on the next completion (the only reader of the marker)", line: 2040 }
  - { file: lib/core/services/badge_service.dart, method_or_widget: "checkAll (the 4/8/12-week streak badges read current_streak_weeks)", line: 115 }
  - { file: lib/features/ai_coach/services/pattern_detector.dart, method_or_widget: "_streakRisk (fires when weeks > 2)", line: 115 }
hive_key_prefix: progress
hive_key_formula: "userBox['progress']['current_streak_weeks' | 'last_counted_week_key']  (pre-fix key: 'last_streak_week', a plan week id, now unused)"
sync_methods:
  - syncProgressNow
restore_methods:
  - _restoreUserProgress
cloud_table: user_progress
cloud_columns:
  - current_streak_weeks
contract_test_path: test/contracts/weekly_streak_counter_writer_to_reader_test.dart
ist_handling:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "week ids come from resolveStreakWeekState (unchanged); this fix adds no date arithmetic", line: 559 }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: updateProgress writes the active user's box; no new cross-account path."
forbidden_patterns_checked:
  - { pattern: "last_streak_week stamped unconditionally in completeWorkout", absent: true }
proposed_fix: |
  A pure `weeklyStreakAfterCompletion({streakWeeks, lastCountedWeekKey, weekKey, planned, completedCount}) -> ({int weeks, int marker})` extracted from the inline block. It counts when `planned > 0`, `completedCount >= ceil(0.8 * planned)` and `weekKey != lastCountedWeekKey`, and then returns `weeks + 1` with the marker set to this week; otherwise it returns the counter and the EXISTING marker unchanged. The marker is keyed by the CALENDAR week (`calendarWeekKey`: the Monday as days since the epoch, UTC-built), stored under a NEW local key `last_counted_week_key`; the old `last_streak_week` is no longer written or read. completeWorkout writes `weekly.weeks` and `weekly.marker`. `resolveStreakWeekState` returns the key and `weekIsCurrent` in both arms; the rule counts nothing when `weekIsCurrent` is false (the non-hold arm reads the CLAMPED plan week, which after redoWeek4 or an expired phase is a previous calendar week whose rows still read completed; without the guard the calendar-keyed marker would let each such week count on its first session, an overcount the old stuck marker used to hide). Forward-only: the counter never decreases and nothing is credited retroactively.
regression_test_planned: |
  test/contracts/weekly_streak_counter_writer_to_reader_test.dart (11 behavioural rows on the pure function incl. the B-pass P1 case, 5 rows on calendarWeekKey, plus hold_week_streak_identity_behavioral_test.dart asserting weekKey in both arms; on the pure function: below threshold does not stamp; the qualifying session counts and stamps; the full 6-session sequence counts the week once; a further session does not recount; a restored marker blocks a recount; the next week counts; forward-only; nothing planned; the threshold table; a fresh account) plus a presence pin that the call site uses the function and no longer stamps unconditionally.
mutation_proof: |
  Rule 21, scratch-copy protocol (backup, mutate, run the new file plus hold_week_streak_identity_behavioral_test.dart, restore from the backup, hash identical). 14 mutants on train_provider.dart, all APPLIED and all genuinely RED (a mutant that failed to COMPILE does not count and was redone): always stamp the marker, drop the already-counted guard, ceil to floor, drop the planned guard, do not stamp on count, write the old key at the call site, key the non-hold arm by the plan id, key the hold arm by the plan id, no Monday normalisation, wrong unit, the rule ignoring weekIsCurrent, the call site hard-coding it true, the non-hold arm always current, the hold arm never current. Two mutants SURVIVED the first test set (the call-site wiring of weekIsCurrent had no behavioural cover; the hold arm's true was unasserted): the decision was moved into the pure function and the hold assertion added, then both went red. The file was byte-identical afterwards.
impact_analysis: |
  Only `completeWorkout` writes these keys. After the fix a week counts once its qualifying session lands (5 of 6 planned). Not retroactive: the founder's 2026-09-14 week stays uncounted unless the founder asks for a one-off production write (its own go). One accepted edge: an account whose marker was already stamped to the CURRENT week by an earlier completion this week (the old behaviour) will not count THIS week; the next week counts normally. The counter is monotonic on restore and push (migration 156), so a restored count is never lowered.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "train_provider.dart (weeklyStreakAfterCompletion, completeWorkout call site); flutter analyze clean; 10 new tests plus hold_week_streak_identity_behavioral_test green." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Same two userBox['progress'] keys with the same names; only the moment the marker moves changed." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema change; current_streak_weeks is the existing column, last_streak_week is local-only." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "No data read or written." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not cron-dispatched." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "No cloud access added." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "The pushed counter is unchanged in shape; it can only be higher than before, and migration 156's GREATEST keeps it from going back. A device check (complete 5 of 6 planned sessions in a week and see the counter step once) is owed under CLAUDE.md section 5." }
recurrence: "Not a recurrence of a fixed class: the stamp-on-every-completion has stood since the original commit b9dfb2bc (March 2026). Adjacent: a3f8d1 (the week id under hold weeks, unchanged here) and c9d2f6 / 47de4f (the counter's restore and push rules)."
related_bugs: [a3f8d1, c9d2f6, 47de4f]
---

# b7d3e5 - the weekly-streak marker was stamped on every completion

## What happened

The weekly counter advances once per week, at 80% of the planned sessions. The marker that says "this week is already counted" was written after every completion, not only after the one that counted. So the first session of a week wrote the marker, and the session that reached 80% was then refused as a repeat.

## The fix

One pure function decides both numbers, and the marker moves only when the counter does. Tested as a function because `completeWorkout` needs full workout state; the call site is pinned by a presence test.

## Not covered

No retroactive credit. The week marker is still local-only; moving it to the cloud is Slice C2, which needs its own review round and a second migration.

## B-pass (one Sonnet seat, 2026-10-08)

P1 (REAL, fixed in this batch): the first draft keyed the marker by the plan week id. The non-hold arm clamps that id to 1..4 and it restarts every phase, so after counting a week with id 4, a later qualifying week that also carries id 4 (three non-qualifying weeks in between) would never count. Verified against `resolveStreakWeekState` and `getCurrentWeekNumber`. Fix: the marker is the calendar week (`calendarWeekKey`) under a new key; a test pins the scenario (non-qualifying weeks never block a later week). Everything else clean: the extracted condition equals the old one, the marker has one reader and one writer, the simulation reset is harmless. P3 (a restore brings the counter but no marker, so a reinstall can re-count the current week once) is the documented Slice C2 half.

## B-pass round 2 (one Sonnet seat) and the coordinator's follow-up

No P0/P1/P2. calendarWeekKey is correct (UTC build, no DST drift; two completions in one calendar week always share a key; plan start is normalised to Monday so a plan week cannot straddle two keys). P3 upgrade edge, ACCEPTED and bounded to one week: the old marker is ignored and the new key reads -1, so a week that was ALREADY counted before the upgrade can count a second time if another qualifying session lands in that same week (the counter is monotonic, next week is normal; seeding from the old marker would suppress the legitimate count for everyone with any completion that week, which is the worse error). P3 test hygiene: the DST row was vacuous (local DateTimes in an IST run) and was replaced by a leap-day row. The reviewer's "possible overcount" (clamped week-4 rows after the window rolls on) was VERIFIED real by reading redoWeek4 (it copies the rows forward as planned but leaves the originals completed) and fixed with `weekIsCurrent`, covered by the redoWeek4 regression row in hold_week_streak_identity_behavioral_test.dart. Doc drift fixed: docs/architecture/services-detail.md named the old key. Gate 19 (hive map field drift) gained the new key in its allowlist (it is a userBox['progress'] key read in a file that also reads exlog_ maps).
