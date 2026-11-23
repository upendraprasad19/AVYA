---
reviewed_at: 2026-11-23T22:45:00+05:30
staged_against: ece4d2c9
blast_radius: account
reviewer: claude-sonnet-via-skill (three seats: A past phases, B dictation, D delta on the fixes)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 10
verdict: accepted
verdict_note: 0 P0/P1 in three seats; every P2/P3 fixed, pinned by a mutant, or stated as a residual; the delta seat's P2 changed the Finding 4 fix from deciding the mode to a one-time replace
---

# Code Review — ece4d2c9 (OI-348 Landing 1b: past-phase display buckets, dictation segments)

Branch `oi348-landing1b`, committed three-dot diff `origin/main...ece4d2c9` (23 files). Two context-blind
Sonnet seats, one per unit, each allowed to mutate only its own source files (copy, mutate, run, copy back,
`cmp`); both reported every file byte-identical afterwards. Neither found a P0 or P1. A third seat reviews
the fix delta.

## Finding 1 — P3 — guard_without_its_mirror (seat A)
- **file:line:** lib/features/train/widgets/week_selector.dart `pastPhaseWeekCount` vs `_PastPhase.hasCompletedDayInWeek` / `entriesForWeek`
- **claim:** the chip count used calendar days, the row-to-chip assignment 7 x 24 h windows; across a DST change a row on calendar day 7k lands on chip k and the last chip can be empty. IST has no DST, so no user sees it today.
- **verification:** `pastPhaseWeekOf` DST-shaped test; "every listed row on exactly one chip" test.
- **suggested-fix:** one calendar-day helper for both.
- **status:** accepted — fixed: `pastPhaseWeekOf` (UTC day difference, floor for dates before the start) used by the count and both assignments. Mutants X1 (floor to truncation) red 1, X2 (entriesForWeek off by one) red 1, X3 (hasCompletedDayInWeek off by one) SURVIVED the first run (no test read a past chip's tick); the hook now returns each chip's tick and statuses and a test pins "tick = a row on this chip is completed" with both values present in the fixture; X3 re-run red 1. All restores cmp-clean.

## Finding 2 — P3 — writer_reader_drift (seat A)
- **file:line:** docs/sot_registry.yaml week_selector.dart cites `38-45`, `35-45`, `137` (pre-existing, not shifted by this diff)
- **claim:** they pointed at comment lines.
- **status:** accepted — repointed to 123-126 (`isPro`), 123-128 (`getPlanStartDate`), 144-149 (the `pastPhaseBlocksForDisplay` call); `check_sot_registry_parity` green.

## Finding 3 — P3 — guard_without_its_mirror (seat A)
- **file:line:** lib/core/services/workout_schedule_read_service.dart `bucketPastRowsForDisplay` noise rule
- **claim:** 3+ consecutive stale rest rows form a spurious segment; a 1-2 rest-row phase is absorbed.
- **status:** false_alarm as a defect (the recorded noise rule; the "<7-day absorb" alternative was rejected in plan review round 1) — stated as a residual in diagnose 5c8e2a.

## Finding 4 — P2 — guard_without_its_mirror (seat B)
- **file:line:** lib/core/services/speech_segment_accumulator.dart `onResult` (`c.length >= 3`) / `onFinal` (`c.length >= 2`)
- **claim:** a cumulative recognizer with a first segment under 3 words and two segment ends kept the duplicate in the FINAL transcript ("two rotis two rotis and dal bhat ..."), worse than the plan's "until the final".
- **verification:** S14, S14b, S14c.
- **status:** accepted — fixed: a one-word committed text needs a strictly longer final for the whole-utterance rule (W5 one-word `>` to `>=` red 1); while undecided, a segment end carrying every committed word in place plus more REPLACES the committed text once without deciding the mode (first shape decided CUMULATIVE; see Finding 8). W1 (rule removed) red 2.

## Finding 5 — P2 — guard_without_its_mirror (seat B)
- **file:line:** speech_segment_accumulator.dart cumulative branch of `onResult`
- **claim:** a segment end in CUMULATIVE mode had no test; removing the branch kept 111 tests green (the live text would blank).
- **status:** accepted — S15; mutant W2 red 1.

## Finding 6 — P2 — writer_reader_drift (seat B)
- **file:line:** lib/core/services/speech_input_service.dart result mapping
- **claim:** the plugin-to-`isSegmentEnd` line had no test.
- **status:** accepted — extracted to the pure `engineResultFromPlugin`, tested with real `SpeechRecognitionResult` values (intermediate, partial, final, unknown int 7); mutant W3 (`isSegmentEnd: false`) red 1.

## Finding 7 — P3 — blast_radius_mismatch / doc accuracy (seat B)
- **claim:** the diagnose doc named a non-existent class; the equal-length cumulative boundary was untested (`>` to `>=` survived); the telemetry is a sample of one session.
- **status:** accepted — doc corrected; S16 pins equal length = segmented, mutant W4 red 1; the sample-of-one is stated in the diagnose residue.

## Delta seat (on the fixes, `git diff HEAD` before the commit)
A fresh seat on the fix delta only, mutating its own copies (4 mutants, all red, all `cmp`-restored). No P0 or P1.

## Finding 8 — P2 — guard_without_its_mirror (delta seat)
- **file:line:** lib/core/services/speech_segment_accumulator.dart segment-end rule (first shape)
- **claim:** deciding CUMULATIVE at a segment end on a 1-word committed text locks a SEGMENTED session when the user re-says a short phrase: end "yes", end "yes I will", end "book it" ended as "book it" (the old code gave "yes yes I will book it"). A word loss is worse than the duplicate the rule removed.
- **status:** accepted — the rule now replaces the committed text once and leaves the mode open; the 3-word rule decides on the next result. S14d pins the sequence ("yes I will book it for monday"); W6 (the lock-the-mode shape re-entered) red 2; W1 red 2.

## Finding 9 — P3 — guard_without_its_mirror (delta seat)
- **claim:** the one-word strictly-longer final is the same weak match: "stop" then final "stop it" gives "stop it" (was "stop stop it").
- **status:** false_alarm as a defect — the same trade as Finding 8's replace: one copy of a re-said word is kept, no word said once is dropped; stated in diagnose 6d9f3b's residue. S5c (equal one-word final = timeout repeat) still pinned by W5.

## Finding 10 — P3 — writer_reader_drift (delta seat)
- **claim:** the registry label for week_selector.dart 340-438 did not name `pastPhaseWeekOf`.
- **status:** accepted — label updated.

## Founder triage notes
Account tier: the verdict is advisory; findings triaged by the author under the founder's standing direction ("build it properly, no shortcuts"; max autonomy, merge a green PR).

## Tuning entry
- **2026-11-23** - blast-radius account - 10 findings; 2 false_alarm; tuning: none (each seat mutating its own files found test-teeth survivors the author's 23-mutant run missed; a test hook that exposes only what the author asserted hides the methods it does not call, so X3 survived until the hook exposed the tick; and the delta seat caught a fix that removed a duplicate by locking a mode, trading a duplicate for a word loss: a fix to a decision rule needs the MIRROR device in its test, here a segmented one).
