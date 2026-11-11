---
reviewed_at: 2026-11-11T10:40:00+05:30
staged_against: 71f07c62 (branch coach-workout-parity-server, staged diff, 34 files)
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh context-blind seats, S1 and S2)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
verdict: accepted
verdict_note: no P0 or P1; two P2 fixed with mutation-proven tests, three P2 closed with evidence (one is the recorded U2 deploy gate).
---

# Code Review: coach workout parity 2 (server)

Scope: OI-492 server landing. S1 counts distinct completed IST days in the rank job, weekly-recalc, `getPromotionStatus` and the i-see-you Saturday gate (diagnose f9bf1c). S2 is the partial-day 8 pm / 9 pm reminder (diagnose c97729). The two seats split by slice. Each was given the staged diff, the 8 lenses, an exhaustive command list (read-only git, file reads, `deno check` / `deno test` on the staged files, mutation under a backup / sha256 restore protocol) and a ban on scripts, the `supabase` CLI, network tools and any database statement.

Before dispatch, the gate loop was green:
- whole-project `flutter analyze --no-fatal-infos`: 0 warnings;
- full Flutter suite: 13,923 passed;
- pre-commit loop: green;
- `deno check` / `deno test`: green.

Step 0 and step 0b were clean (no `MM`/`AM`; HEAD...origin/main = 0 0).

## Finding 1 — P2 — guard_without_its_mirror (seat S1)
- **file:line:** supabase/functions/weekly-recalc/index.ts:280-300 (the completed-days read, third member of the `Promise.all`)
- **claim:** The new all-users `workout_logs` read only feeds a floor that can RAISE a monotonic total, yet its failure failed the whole weekly tick, including every user's `detected_experience_level`. The old code had no such veto.
- **verification:** `sed -n 280,300p supabase/functions/weekly-recalc/index.ts`
- **suggested-fix:** Catch that one read: log it, use an empty map, keep every stored total, and still write the levels.
- **status:** accepted, fixed. The read now has a `.catch` that logs `completed-days read failed` and returns `[]`. `mergeMonotonicTotal(0, existing)` keeps every stored total. The handler test "a failed workout_logs read does NOT fail the tick" replaces the old fail-the-tick test. It covers two users with stored totals 2 and 7, where u1 has 3 completed days that a successful read would count: the response is 200, both upserts happen, the totals are 2 and 7, and the level is a string. Mutant B1 removes the `.catch`: index_test.ts goes 16 pass / 1 fail.

## Finding 2 — P2 — asserted_fixture_value (seat S1)
- **file:line:** supabase/functions/i-see-you-callout/streak_gate_test.ts:11, supabase/functions/_shared/tools/__tests__/getPromotionStatus_test.ts:44 (both clocks fixed at 10:00Z)
- **claim:** At 10:00Z the UTC date and the IST date agree, so a UTC-bucketing regression would pass every test.
- **verification:** `grep -n "T10:00:00Z\|T19:" supabase/functions/i-see-you-callout/streak_gate_test.ts supabase/functions/_shared/tools/__tests__/getPromotionStatus_test.ts`
- **suggested-fix:** One case per helper at 19:00Z, with literal expected dates.
- **status:** accepted, fixed. New tests at `2026-11-07T19:00:00Z` use literal dates as an independent oracle: IST today is 2026-11-08 and the window starts 2026-10-12, so 2026-10-11 is outside.
  - Mutant B2 (`readDeepStreak` window from the UTC date): streak_gate_test.ts 7 pass / 1 fail. The pre-existing 10:00Z tests stay green, which confirms the gap was real.
  - Mutant B3 (`recent28Dates` from the UTC date): getPromotionStatus_test.ts 8 pass / 1 fail.

## Finding 3 — P2 — writer_reader_drift (seat S1)
- **file:line:** supabase/functions/weekly-recalc/index.ts:280-300 against the old tombstone-filtered exercise-row floor
- **claim:** `workout_logs` has no tombstone. If a deleted day left its cloud row, the monotonic floor could count it permanently.
- **verification:** `grep -rn "\.delete(" lib/core/services/workout_write_service.dart lib/core/services/sync/sync_workout.dart lib/features/train --include=*.dart`
- **status:** no_change_needed. A `workout_logs` / `wlog_` day is never deleted on the client. The only cloud writer is the upsert at `sync_workout.dart:187`. Every Hive `.delete(` in the workout writers targets other keys:
  - schedule keys: `swapScheduledDays` at `workout_write_service.dart:895`/`:908`;
  - exlog keys: the move and rekey at `:973`/`:1169`, `deleteLog` at `:1490`/`:1497`;
  - template keys: `sync_workout.dart:2131`;
  - the active-session key: `active_workout_persistence.dart`.

  A completed day is permanent on both sides, so the floor counts the same set as the client's `completedWorkoutDayCount` (`workout_read_service.dart:61`). The rank job's head count had the same exposure before this change.

## Finding 4 — P2 — missing_input (seat S2)
- **file:line:** supabase/functions/_shared/partial_day_loader.ts:106 (`today_row:plan_json->schedules->schedule_${todayIST}`)
- **claim:** No other select in the repo uses a JSON-arrow path with a hyphenated key. If PostgREST rejects it, the loader catches the error and every user gets the old line: safe, but the feature is silently off.
- **verification:** `grep -rnE 'select\(.*->' supabase/functions lib --include=*.ts --include=*.dart`
- **status:** accepted as the recorded hard gate U2 (plan B4-F8, diagnose c97729 "Hard precondition U2"). The exact select string is checked live, read-only, before the S2 deploy go: the primary read is compared with the fallback read for the same rows. A rejection switches `planRead` to the fallback (chunk 10) before the deploy. No deploy runs without that record.

## Finding 5 — P2 — guard_without_its_mirror (seat S2)
- **file:line:** supabase/functions/_shared/partial_day_count.ts:98-101 (stale-plan guard)
- **claim:** One off-plan logged name makes the whole count null, so a partial day plus an off-plan exercise keeps the old line.
- **verification:** `sed -n 85,105p supabase/functions/_shared/partial_day_count.ts`
- **status:** false_alarm (accepted residual R4 in the plan). An off-plan name is indistinguishable from a stale cloud plan copy, and a wrong count is worse than the old line. The seat itself rated it "no worse than before".

## Observation (seat S2)
A user can receive both the 8 pm and the 9 pm push with partial copy. This is documented as accepted. The two crons use different dedup types.

## Clean lenses (summary of both seats)
- **writer_reader_drift:**
  - the client writes `plan_json.schedules.schedule_<date>` at `sync_workout.dart:1463-1505`, and the server reads the same key;
  - names are lower-cased and trimmed on both sides;
  - `swapped_from` is matched;
  - the `workout_log_id` v5 is the same on both sides;
  - the converted server readers are listed per seat, and the non-count readers were checked and left as they are.
- **IST:** `todayIST` is computed once per run. `istDatesEnding` goes through `istDateStr`.
- **Truncation:** a truncated read throws per user (rank, streak gate) or per tool call (`getPromotionStatus`). The per-user catch keeps the rest of the job.
- **Monotonic total:** the only writer is `mergeMonotonicTotal`.
- **Handler/deps seam:** auth and telemetry are still direct calls. `import.meta.main` serve is the same pattern as 15 deployed functions.
- **Kill switch:** on only for the exact lowercase string `"true"`. When on, the old line and `/ai_coach` are byte-identical.
- **secrets_in_tree, function_exception_swallow, unawaited_no_error_sink:** no hits in scope.

## Mutants run by the seats
Seat S1 ran 14 mutants and seat S2 ran 6, across every production file in scope. Each turned at least one test red, and each file was restored by sha256.

## Founder triage notes
Coordinator triage 2026-11-11 (platform tier, verdict advisory): F1 and F2 fixed in this batch, F3 no change (evidence above), F4 = the U2 deploy gate, F5 false alarm (accepted residual R4).

## Tuning entry
- **2026-11-11** - blast-radius platform - 5 findings; 1 false_alarm; tuning: none. Splitting the seats by slice (S1 day counting, S2 reminder) kept each brief narrow. Both seats ran mutants under the sha256 restore protocol and left the index clean. The one real test gap (a fixed 10:00Z clock that cannot see UTC-vs-IST) is the clock-dependent-tests class; a seat brief that names the 18:30-24:00 UTC window by default would have found it without prompting.
