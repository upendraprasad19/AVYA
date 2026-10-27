---
reviewed_at: 2026-09-18
branch: ai-coach-ux-tool-integrity
staged_against: main...HEAD
reviewer: bpass (context-blind adversarial)
branch_tip: ac83530b
verdict: accepted-with-findings
---

# B-pass review — ai-coach-ux-tool-integrity (2026-09-18)

Whole-branch diff `main...HEAD` read for lib/ + scripts/ + supabase/ (~2,155
lines); tests/docs skimmed; live cloud schema verified via MCP against
`dedsavbjuwgarrhphgnl`; four new test files executed green; one
self-attested mutation claim re-run by the reviewer.

## Findings

### 1. P1 — Server-side rank engine counts moved/dropped/paused rows as scheduled-not-completed; the batch's rank invisibility claim is client-only

- **Where:** `supabase/functions/_shared/rank_engine.ts:186-195` (`completionRate`)
  vs `lib/features/train/repositories/workout_repository.dart:471-472`
  (`completionRateOverWindow`).
- **Why:** C1/C2's thesis is "paused/moved/dropped are invisible to streak and
  rank completion-rate math". That set is implemented on the CLIENT only.
  The server rank cron (`evaluate-rank-promotions` → `rank_engine.ts`) skips
  only `status === 'rest'`; everything else does `scheduled++` and counts
  toward the `completionRateMinimum` promotion gate. This batch (a) makes
  terminal `moved`/`dropped` rows PERSIST and PUSH to cloud — the exact change
  that turns them into permanent scheduled-not-completed rows in the server's
  denominator (pre-batch they were raw-deleted and never reached cloud), and
  (b) removes them from the client's rate. Result: every reschedule move/drop
  permanently deflates the server-side completion rate while the client rank
  UI reads the rate excluding them — client display and server promotion gate
  diverge, and reschedule users get promotion-suppressed. Paused counted
  server-side is pre-existing, but the client side moved and the server did
  not, so the drift is now batch-authored on both statuses.
- **Diagnose c1a9d4:98** claims "the streak walk and the rank rate can never
  drift apart on which statuses are [invisible]" — true client-side only; the
  touched_layers row for the server seam does not cover rank_engine.ts.
- **Fix direction:** mirror `invisibleScheduleStatuses` in
  `rank_engine.ts` (skip `paused`/`moved`/`dropped` exactly as the client
  does), with a Deno test pinning the set parity — same shape as the existing
  `rest` skip. This is the server half of the invariant the batch itself
  declared.

### 2. P2 — `pauseRange` clobbers terminal rows (the 4th writer of the class C3 guarded, missed)

- **Where:** `lib/core/services/workout_schedule_write_service.dart:134-140`
  — skips only `status == 'completed'` before stamping `'paused'`.
- **Why:** The batch's own invariant is "never edit a terminal row" (swap
  guard, auto-complete guard, planner skips, hotel/regeneratePlanBlock/
  scheduleTemplate + TemplateService paused guards — C3). `pauseRange` was
  not added to that set. Terminal rows legitimately exist on FUTURE dates
  (a within-week move of a Friday workout leaves Friday `moved` while today
  is Wednesday), and "pause my plan for 3 days" from the coach covers them:
  the `moved_to`/`moved_at` audit pointer is overwritten by `'paused'`, and
  the pause fans out to cloud, destroying the terminal trail. No streak
  impact (both invisible) — it is the batch's own immutability invariant
  broken by the one write tool nobody guarded.
- **Fix direction:** `if (WorkoutRepository.isTerminalScheduleRow(status))
  continue;` beside the completed skip (terminal rows cannot be "paused" —
  the workout is gone), + a contract test.

### 3. P2 — False OI-174 citation; the cloud exlog residual for moved-out dates is tracked NOWHERE

- **Where:** `lib/core/services/workout_write_service.dart:226-229`
  (moveExerciseLogs doc): *"cloud `exercise_logs` rows for the moved-out
  date are not tombstoned here — that residual is tracked on OI-174"*.
- **Verified false:** `docs/audit/open_issues.md` OI-174 (:3412) is "schedule
  rows written past `plan_end` are never pruned … delay the PRO phase
  advance". Nothing on the board tracks a cloud exlog tombstone for moved
  dates (grep tombstone/moved-out/moveExerciseLogs → only OI-154's unrelated
  profile tombstone).
- **Why it matters:** the residual is real and reachable — `_restoreExerciseLogs`
  (sync_workout.dart:666+) re-creates `exlog_<fromDate>_<hash>` rows from the
  never-tombstoned cloud `workout_log_exercises` and calls
  `addToExlogIndex` (union-only) on the from-date index, so after any move, a
  restore resurrects the from-date logs while the moved copies live at
  `toDate`: double-counted volume across two dates in the AI snapshot's
  `recent_logs`. Attack 1's mid-flight race (restore writes the from-date row
  after `moveExerciseLogs` scanned — restore takes no `exlog_move_*` lock)
  lands the identical state; the additive-restore design makes the race
  one-directional but the terminal state is the same.
- **Fix direction:** file the OI with the correct number (and correct the doc
  citation), or tombstone from-date cloud exlogs in this path. Per §4.2 a
  residual is acceptable only if it is actually tracked where the doc says.

### 4. P3 — scheduleForm composes a date shifted a day back on UTC>+5:30 devices

- **Where:** `lib/features/ai_coach/widgets/compass_form_sheet.dart`
  (`_parseDate(c.value)` → `_targetDate`; compose `istDateStr(_targetDate!)`).
- **Why:** the chip value is an IST date string; `DateTime.tryParse('YYYY-MM-DD')`
  yields device-LOCAL midnight; `istDateStr` re-applies `toUtc()+5:30`
  (ist_date.dart:88), so a local-midnight parse on a device east of IST
  (SGT/JPY/AEST/NZST) maps to the previous IST date. User taps a chip labeled
  TOMORROW; the model receives "Reschedule my Monday workout to <D-1>".
  India (UTC+5:30) round-trips exactly; this is the Test #11.1 double-shift
  trap re-created inside the new form.
- **Fix direction:** keep the chip's raw string (store `_targetDateStr`) and
  compose from it; never round-trip an IST date string through a local
  DateTime.

### 5. P3 — planner vs dispatcher disagree on terminal-row destinations (dead-end move ask)

- **Where:** `lib/features/ai_coach/services/reschedule_week_planner.dart:113`
  (terminal skip runs BEFORE `usedAvailableDays.add`, so a terminal row on an
  AVAILABLE day leaves that day "free") vs `lib/features/ai_coach/services/
  tool_dispatcher.dart:715-721` (terminal destination → error "destination
  was rescheduled elsewhere").
- **Why:** a week holding a terminal row on an available day (normal after a
  prior reschedule) makes the planner plan a move onto that day and the
  dispatcher refuse it — the user's ask fails with a partial error and no
  recovery except re-asking. The planner should mark the day used (or the
  dispatcher should allow superseding a terminal destination written by a
  prior plan whose successor date is intact).
- **Scope note (verified, not assumed):** the planner cannot produce A→B + B→A
  pairs — targets are drawn only from free available days, and an available
  day is always `keep`ed in pass 1 — so the two-phase snapshot in the
  dispatcher is never load-bearing for swaps; the comment at tool_dispatcher
  ~690 is stale but harmless.

### 6. P3 — `is_pr` not rescanned across the move; collision merge can drop a true PR flag

- **Where:** `lib/core/services/workout_write_service.dart` moveExerciseLogs —
  collision merge keeps `existing`'s `is_pr` (moved's dropped); non-collision
  path keeps the moved row's from-date `is_pr` semantics with no
  `_rescanPrFor` pass.
- **Why:** attack 2's double-PR display is NOT reachable (a same-exercise
  collision merges into ONE row, so only one `is_pr` survives; different
  names live on different keys) — but the surviving flag can be WRONG: a
  moved row carrying the true PR merged into an `is_pr:false` existing row
  loses the PR from PR surfaces until the next edit-sheet save rescans.
- **Fix direction:** after the move loop, run the same chronological rescan
  `logExercise`/edit-sheet use for the affected exercise names on `toDate`.

### 7. P3 — double-tap on the capture sheets' confirm can submit duplicate intents

- **Where:** `log_workout_sheet.dart` `_confirm` /
  `swap_exercise_coach_sheet.dart` `_confirm` — no submitted-latch; the
  button is live until the route finishes popping.
- **Why:** ids embed `millisecondsSinceEpoch`, so a second tap lands a NEW id:
  `addIntents`' id-dedup and the dispatcher's `intent_<id>_dispatched_at`
  marker both miss it. log_set double-dispatch is near-idempotent (same
  `exlog_<date>_<hash>` key); swap double-dispatch fails noisily via
  ConcurrentEditException. Chat renders two cards for one action.
- **Fix direction:** a `_submitted` latch set in `_confirm` (or disable the
  button in-flight).

### 8. P4 — defensive date-parse fallbacks pick destructive dates

- **Where:** `tool_dispatcher.dart:761` (`?? destDate` — a failed from-date
  parse writes the TERMINAL row onto the DESTINATION date, clobbering the
  workout just written there) and `:800` (`?? DateTime.now()` — could stamp
  `'dropped'` over today). Unreachable while schedule keys are well-formed
  (the row was just read from `schedule_<fromDate>`), but a parse fallback
  that silently redirects a write is worse than failing the move; the drop
  path's fallback should be a refusal.

### 9. P4 — restore-recreated terminal rows lose their terminal metadata

- **Where:** push payload (sync_workout.dart:1634) sends `status` but not
  `moved_to`/`moved_via`/`moved_at`/`dropped_*`; the restore merge spreads
  `...existingMap` (local metadata survives) but a row that exists ONLY in
  cloud (fresh device) restores as `status='moved'` with NO `moved_to`.
  Invisibility semantics survive; the audit pointer does not. Fold into
  finding 3's residual or extend the payload.

## Verified-clean notes (attack list)

1. **Restore-day exlog move:** rows matched on the row's own `date` field;
   restore-shaped rows DO carry `'date'` (sync_workout.dart ~:755) → they move
   correctly. Mid-flight race terminal state = finding 3 (untracked residual),
   not a lost/duplicated row inside the move itself. Move lock
   `exlog_move_<fromDate>` held across scan+write; restore does not take it,
   but additive-restore bounds the damage to the finding-3 state.
2. **Double-PR:** no — collision merges into one row (single `is_pr`);
   non-collision rows are name-distinct. Residual = wrong-flag, finding 6.
3. **pauseRange past-date refusal vs terminal writers:** inconsistent —
   pauseRange refuses >1-day-past dates and completed, but OVERWRITES
   terminal rows (finding 2). The terminal writers' `_utcDateFromIstDateStr
   ?? fallback` (finding 8) never lands on a pause-refusable past date in
   practice (moves are within the current week, planner-validated).
4. **Captain suffix vs manual rules:** clean. Promotion ceremony text is
   server-templated in `_shared/ceremony_text.ts` and injected into chat
   history (captain_manual.ts:193-196) — the model never renders it, so the
   100-word cap cannot truncate a ceremony. TONE SCALING registers' examples
   all fit ≤100 words; "point to /LOG, /SWAP" references chips that still
   exist post-removal of /PR and /TARGET. No instruction induces refusing a
   format the client expects. Leak check: nothing secrets- or
   injection-shaped in the suffix.
5. **ToolIntent ids / dedup:** same-ms ids are unique via the `_i` suffix;
   id-dedup + `dispatched_at` markers hold for identical ids; distinct-id
   double-tap residue = finding 7. Dedup ring buffer (chat 60s + ai-proxy
   placeholder dedup) does not interact with sheet intents (they never pass
   through ai-proxy).
6. **scheduleForm compose string → planner:** the ask is model-interpreted,
   not regex-parsed — the model supplies `daysAvailable`/`weekStart`, the
   planner computes moves from the cache; no parser to break. Residue: the
   form only offers today..+6 as source AND target, so cross-week moves are
   out of its reach (planner plans the current week) — a UX scope note, not a
   defect. Verified the planner never emits same-day/no-op or swap pairs.
7. **Gate weakening:** none. `check_hive_map_field_drift.dart` +5 fields
   matches exactly what the two new writers stamp (verified against
   `_executeRescheduleWeek`'s moved/dropped maps);
   `exercise_seam_lib.dart` allowlist entry count (2) matches the sheet's two
   `ExerciseRepository` reads, and the claimed justification (picker
   pre-filtered by the same `canOfferInPicker` + `resolveCapabilityFromProfile`
   predicate swap_service.dart:262-264 enforces) verified on both sides.

Additional verified-clean:
- Cloud `scheduled_workouts.status` is plain `text`, NO CHECK constraint
  (queried live `pg_constraint` on dedsavbjuwgarrhphgnl — zero CHECK/NOT-VALID
  constraints) → terminal statuses push cleanly; C2's cloud fan-out claim holds.
- Restore merge: local-terminal + cloud-planned arm keeps terminal status and
  metadata; local-planned + cloud-moved falls to the cloud-authoritative
  default (terminal applied) — both directions of the double-count killed
  client-side (test/sync/restore_terminal_row_merge_test.dart green, run by
  reviewer).
- Mutation claim on the planner re-verified by the reviewer: mutating BOTH
  skips reddens exactly 2 tests; mutating the FIRST skip alone reddens zero
  (absorbed by the second-pass sibling — the known zero-red class; the
  doc's claim as worded is accurate). File restored after the check.
- C5 mutex: `_coachMemoryLock` chains completions correctly (no lost-wake,
  complete-in-finally); the only other `coach_memory` writers are
  sync/restore paths with different fields (restore-vs-append race
  pre-existing, narrower than the fixed one).
- C4: `aiTextLogRemainingProvider` exists (nutrition_provider.dart:1548) and
  is invalidated in the same batch-invalidator the manual path uses.
- Sheets' paused=pending consistency (R2-B2): log sheet and swap sheet both
  admit `planned`+`paused` and block terminal/completed, matching the
  dispatcher's terminal-only guards. log sheet parse-validity guard (R1
  finding 9) verified: garbage disables confirm rather than coercing.
- Terminal-row contract test (12), streak test, display read-path test,
  mutex test: all executed green in-session.

## Verdict

accepted-with-findings — no P0; findings 1-3 should be fixed before or in the
batch that next touches rank/sync-restore; 4-9 are bounded follow-ups with
named fix directions.
