# OI-348 walk fixes — Landing 1b: B3/B7 (past-phase history) + B5 (dictation)

Status: v3 FINAL (2026-11-23). Round 1 (seat A on B3: 2 P1 + 5 P2; seat B on B5: 3 P1 + 4 P2; both
`not_converged`) → v2. Round 2 on v2 (fresh seats): B3 `converged` (0 P1, 6 P2), B5 `converged`
(0 P1, 4 P2); every round-2 P2 folded in place (v3). Resolutions are listed at the end.
Branch `oi348-landing1b`, base `main` `70add5cf`. Supersedes the B3/B7 and B5 text in
`docs/plans/oi348-walk-fixes-landing1.md` (history). Execution mode (§4.12.7): **inline**, one
worktree, two independent units, one PR. If a round reopens only one unit, that unit splits off
(§4.12.1) and the converged one ships first.

Tier: M for both units (`lib/core/services/**` is outside the S filter). No server, schema or
migration.

---

## Unit B3/B7 — past-phase history drops days; phase ranges look wrong

### Symptom (founder, OI-348 walk A5 part 1, 2026-11-22)
Train week strip, a past group's week 2 sheet lists only Sun + Mon while the cloud has Tue-Fri
completed (Oct 1 "PULL + CORE"). Phase chips read "Phase II from Apr 27", "Phase III ends Jun 28",
"Phase IV from Oct 12".

### Evidence (live, read-only, `user_progress.plan_json.schedules`, account d7a67a37…, 2026-11-23)
`current_phase = 5`, `plan_start = 2026-11-09`. Past rows, date:stamp (`-` = no stamp):
Apr 27-May 24 `2`; May 25-31 `-`; Jun 1-Jul 5 `3` (unstamped: Jun 2, 5, 6, 7, 14, 21, 28, Jul 5);
Jul 17-23 `-`; Aug 19-22 `-`; Aug 23-25 `2`; Sep 14-19 `3`; Sep 20 `1` (rest); Sep 21-23 `3`;
Sep 24 `-`; Sep 25 `3`; Sep 26 `-`; Sep 27 `1` (rest); Sep 28 `-`; Sep 29-Oct 3 `3`; Oct 4 `1` (rest);
Oct 5-10 `3`; Oct 11 `1` (rest); Oct 12-Nov 8 `4`. The four `1` rows are Sunday REST rows with the
correct `week` 1..4. The test fixture is this list, row for row (status/type as queried).

### Reader (the defect)
`WorkoutScheduleReadService.bucketPastRows` (`workout_schedule_read_service.dart:2020-2082`) groups
ALL past rows by carried stamp into ONE block per stamp NUMBER, ignoring dates. On the evidence:
phase 1 = {Sep 20, Sep 27, Sep 28 (carried), Oct 4, Oct 11}; phase 2 = Apr 27-Aug 25; phase 3 =
Jun 1-Oct 10; phase 4 = Oct 12-Nov 8; blocks interleave by date. `_toPastPhases`
(`week_selector.dart:335-368`) shows the last `currentPhase-1` blocks numbered up to
`currentPhase-1`; `_PastPhase.entriesForWeek` (`:411-419`) cuts weeks from the block's `startDate`
and `_PastPhaseGroup` draws exactly 4 chips (`:461`). So "Phase I" week 2 (Sep 27-Oct 3) holds only
Sun 27 + Mon 28: the founder's symptom exactly; and every row of a block past its day 28 is on no
chip. Reader #2: `phaseForDate` (`:2092-2109`) labels a past receipt by the index of the STRICT
`pastPhaseBlocks()` block (callers `workout_receipt_card.dart:555`, `completion_sheet.dart:133`).

### Writer of the stray stamps (§4.1)
Every generator writes all days of its window with ONE stamp (`generateAndSchedule` `:283-350`,
`generateAndScheduleFromDate` `:544-629`, coach regen `regenerate_plan_planner.dart:357-406`). A
stamp older than its neighbours survives on a REST row because the restore/boot merge keeps a local
rest row wholesale, stamp included (`PlanIntegrityReconciler.mergeScheduleEntry`,
`plan_integrity_reconciler.dart:131-136`, L1 guard, `10b2b76b` 2026-09-28) while the neighbouring
workout rows take the incoming content. Completed rows restored from `scheduled_workouts` carry no
stamp (that table has no phase column). The FIRST writer of the `1`s is not identifiable from current
code: the only `?? 1` fallbacks (`train_provider.dart:802`, `auth_session_bootstrapper.dart:983-986`,
`edit_profile_screen.dart:2336`) fire only with no local progress, where 1 is right; the dev
simulation resets to 1 by design (`simulation_service.dart:148-155`). The L1 guard is NOT changed:
making it adopt the incoming stamp has an unresolvable mirror (when the LOCAL stamp is the fresh one,
adopting the incoming one makes it stale). So the reader must not trust one stamp over the sequence.

**Strict-count residual (stated, not changed).** `PhaseProgressReconciler`
(`phase_progress_reconciler.dart:131`, monotonic `reconciledPhase` `:49-60`) and
`pro_phase_advance.dart:725` count `pastPhaseBlocks()`, which groups by stamp NUMBER. A stale lower
stamp adds a block there only when NO real past row carries that number (a stale `1` on an account
that has real phase-1 rows merges into them). For an account whose history began at phase 1 every
lower number has real rows, so it cannot fire; on the founder's account (no real phase-1 rows) strict
gives 4 blocks and `current_phase` is already 5, so it is a no-op. It is a monotonic counter risk only
for an account whose early rows were deleted; it is recorded in the diagnose-doc with that condition.

### Bug history (§4.1.5)
Related, not the same defect: `7d2e6b` (28-day calendar windows split one long phase, over-count; fix
F-B = group by stamp), `c9e4b7` / `b7f1c8` (display recovery when the strict set is empty). F-B must
hold for clean data: one logical phase stays ONE block whatever its span.

### Fix (DISPLAY ONLY; strict `pastPhaseBlocks()` untouched)
New pure `bucketPastRowsForDisplay(rows)` (static, `@visibleForTesting`, next to `bucketPastRows`):
1. S = rows whose `phase` is an int, date-sorted. S empty → return `bucketPastRows(rows)` (legacy).
2. RUNS over S only (unstamped rows never join or break a run): maximal consecutive members of S
   with equal stamp.
3. NOISE: a run of ≤ 2 rows that are ALL rest rows (`type` rest or `status` rest — the only rows the
   L1 merge keeps with a stale stamp, the proven mechanism above) is noise, unless EVERY run is noise
   (then none is). A run with any workout row, or of 3+ rows, is never noise. Drop noise runs, then
   merge runs that became adjacent with equal stamp → SEGMENTS, each with a stamp, `first` = its
   earliest stamped date and `last` = its latest stamped date.
4. ASSIGN every row (stamped, noise, unstamped) to a segment by date: the last segment with
   `first <= date`; a row before every segment → the first segment. Edge rule: a row that is NOT a
   member of a non-noise run (unstamped or noise), lies AFTER the previous segment's `last`, and lies
   in the same Mon-Sun calendar week as the NEXT segment's `first` (and before it) → that next segment
   (an unstamped completed Monday of a new window joins its window; an old window that ended mid-week
   keeps its own rows up to its last stamped day).
5. Blocks = segments in date order; rows date-sorted; `startDate`/`endDate` = first/last row.
Properties: (a) blocks never interleave by date; (b) equal to `bucketPastRows` (same blocks, same
row order) when stamps are non-decreasing, each stamp's rows are contiguous in date, every phase has
≥ 3 stamped rows, and no unstamped row sits in the calendar week of a later phase's first stamped
row before it (today's carry-forward puts such a row in the EARLIER block; the edge rule moves it to
its own window); (c) F-B for clean data: one stamp spanning any length (holds, lapses, gaps) is one
block; (d) non-adjacent runs with the same stamp are SEPARATE blocks (a restart), where
`bucketPastRows` merges them.
On the evidence: noise = the four single `1` runs; segments 2 (Apr 27), 3 (Jun 1), 2 (Aug 23),
3 (Sep 14), 4 (Oct 12); blocks Apr 27-May 31, Jun 1-Jul 23, Aug 19-25 (Aug 19-22 are unstamped and
share Aug 23's Mon-Sun week, so the edge rule puts them there), Sep 14-Oct 11 (Oct 11 is in Oct 5-11,
not Oct 12's week), Oct 12-Nov 8 → shown (last 4) as PHASE I = Jun 1-Jul 23 (8 chips), II = Aug 19-25,
III = Sep 14-Oct 11, IV = Oct 12-Nov 8. Phase III week 3 = Sep 28-Oct 4 lists all seven days. (The
short Phase II is that account's real history: a regeneration wrote Aug 23-25 stamped 2.)

Kill switch `configBox['disable_past_phase_display_runs'] == true` → today's code verbatim. Read by a
service getter `pastPhaseDisplayRunsEnabled` (try/catch around the box; unreadable → enabled):
- `pastPhaseBlocksForDisplay` (`:1981-2006`) reads it per call; both branches use
  `bucketPastRowsForDisplay` when enabled (strict-non-empty branch: rows before `plan_start`;
  recovery branch: all rows, newest block dropped, as today). The strict `pastPhaseBlocks()` stays
  the gate for which branch runs.
- `phaseForDate` (`:2092`) keeps its short-circuit FIRST: read `planStart`, return `currentPhase` for
  a date in/after the window before any block walk (a current-window receipt never walks the box and
  never reaches the strict-empty tripwire). For a past date it reads the switch; enabled → blocks from
  `pastPhaseBlocksForDisplay(currentPhase)` and the NEW pure `phaseForDateDisplay(currentPhase,
  planStart, date, blockStarts)`: in/after window → `currentPhase`; else `i` = index of the last
  block with start ≤ date; `showCount = clamp(currentPhase-1, 0, n)`, `first = n - showCount`;
  `i >= first` → `currentPhase - showCount + (i - first)`; `i < first` or before every block → 1
  (a date before the shown blocks matches no chip: stated). `phaseForDatePure` stays, unchanged
  (pinned by `receipt_phase_for_date_test`), and runs when the switch is on.
- `WeekSelector.build` (`week_selector.dart:145`) reads the getter ONCE through
  `workoutScheduleReadServiceProvider` and passes it to `_toPastPhases(blocks, currentPhase,
  extendWeeks: enabled)`. `_toPastPhases` keeps its own numbering code (deliberately NOT shared with
  `phaseForDateDisplay`, so the test below compares two implementations). New `_PastPhase.weekCount`
  = enabled ? `max(4, d ~/ 7 + 1)` : 4, `d` = the day difference of `startDate`/`endDate` taken as
  UTC calendar dates (DST-proof); `_PastPhaseGroup` loops to
  `weekCount` (`:461`). Past hold weeks show as W5+ (history, read-only; the current phase's H chips
  are unchanged). `_toPastPhases` and `_PastPhase` become `@visibleForTesting` public names
  (`pastPhaseGroups`, `PastPhaseGroupData`) for the test; the source-order pin of the first
  `_phaseRoman(widget.currentPhase)` after the past loop (`week_selector_past_phases_test`,
  `week_selector_reads_current_phase_test`) is kept.
Cost, stated: a receipt for a PAST date walks the box twice (strict gate, then display rows), the
same cost class as the chip strip. Behaviour change, stated: in the recovery branch a past-date
receipt used to read 1 (empty strict starts); it now reads the chip number (intended).
Threshold note: the noise rule is tied to the mechanism (rest-only, ≤ 2 rows), not fitted to the
evidence. On the evidence Aug 23-25 (two workout rows + one rest) is a real regen block and stays a
phase; it takes one of the four shown slots, and the Apr 27 block is the hidden oldest (honest: those
are the rows that exist).

### Tests
- NEW `test/contracts/past_phase_display_runs_behavioral_test.dart` (pure):
  T1 the evidence fixture → the 5 blocks above (incl. Aug 19-22 in the Aug block, Oct 11 in the Sep
     block); Sep 28-Oct 4 all in one block; no date in two blocks.
  T2 clean 1/2/3 history (each phase ≥ 3 stamped rows, a leading unstamped run) → equal to
     `bucketPastRows` (dates + row identity, in order).
  T3 one stamp, 9 weeks, a 3-week gap, unstamped completed rows inside → one block (F-B / 7d2e6b).
  T4 five-week held phase (hold rows same stamp) → one block, 5 weeks.
  T5 restart: 3 ×28 days then 1 ×14 days → two blocks; and non-adjacent equal stamps (2, 3, 2) →
     three blocks.
  T6 noise mirrors: (3, [4 ×1], 3) → one block; (3 long, [4 ×2], [5 ×2], 3 long) → one block
     (consecutive noise); (3, [4 ×3 rows], 5) → three blocks (3 rows is not noise); every run noise
     ((2 ×2), (3 ×1)) → two blocks.
  T7 seat-A P1-1 shape: phase 3 window with every Mon-Sat row unstamped + completed and every Sunday
     stamped 1, after a stamped phase-2 window → two blocks with the window's own bounds.
  T8 edge rule: an unstamped completed Monday before a stamped Tuesday of a new window → the new
     block; an unstamped Sunday after the old window's last stamped Saturday → the old block.
  T8b mirror: the old window ends mid-week (last stamped Wed), the new window's first stamped row is
     Thu of the same week, unstamped completed Mon-Tue → stay OLD; unstamped Wed-after-last? none;
     an unstamped Fri before a stamped Sat of the new window, after the old last → new.
  T9 no stamps → equals the legacy fallback.
  T10 noise boundaries: a rest-only run of 2 rows → noise; of 3 → a block; a 1-row WORKOUT run → a
     block (not noise); a 2-row run of 1 workout + 1 rest → a block.
  T11 `phaseForDate` for a current-window date does no block walk (a counting fake/spy on the row
     walk, or the tripwire seam stays silent in the recovery branch).
- NEW widget-level test `test/features/train/week_selector_past_runs_test.dart`: evidence fixture in
  Hive + `current_phase 5` → labels PHASE I..IV with the bounds above; Phase I shows `weekCount` 8
  chips; the Phase III chip W3 sheet lists 7 days; PER ROW: for every entry of every shown group
  (`pastPhaseGroups` output, independent code), `phaseForDate(entry.date)` equals that group's
  number; gap dates (Jul 24-Aug 18, Aug 26-Sep 13) resolve to the PRECEDING block's number; a date in
  the hidden Apr 27 block reads 1, which collides with Phase I by design (stated in the test); switch
  on → 4 chips and the strict-index receipt number.
- Kill switch (service): on → `pastPhaseBlocksForDisplay` / `phaseForDate` equal today's values on
  the evidence fixture (both branches: strict-non-empty and recovery).
- Run and repoint (never loosen): `past_phase_bucketing_test`,
  `past_phase_display_recovery_behavioral_test` (its test D, wrapper == strict on clean data, must
  stay green; it does so because its `writeBlock` writes 28 stamped rows per phase: the fixture is
  load-bearing and must not be thinned), `receipt_phase_for_date_test`, `week_selector_past_phases_test`,
  `week_selector_reads_current_phase_test`, `coach_regen_phase_stamp_behavioral_test`,
  `week_selector_hold_marker_test`.
- Mutations (each must redden ≥ 1 named test): M1 group by stamp number → T1; M2 noise threshold 0
  → T1; M3 runs include unstamped rows (carry-forward) → T7; M4 no adjacent-merge after dropping
  noise → T6 consecutive case; M5 drop the edge rule → T8; M6 `phaseForDateDisplay` returns the raw
  index → widget agreement check; M7 weekCount fixed at 4 → widget chip count; M8 switch inverted →
  kill-switch test.

---

## Unit B5 — dictation keeps only the last fragment of a long sentence

### Symptom (founder, A19)
Coach mic, one long sentence: the field ends with only "or the coming week".

### Writer (the defect)
`SpeechInputController.engineResult` (`speech_input_controller.dart:388-400`) REPLACES `_liveText`
with every partial (`:397-398`); a final ends the session with the final's words only (`:393`). The
wrapper `listen` (`speech_input_service.dart:255-266`) maps each plugin result to
`SpeechEngineResult(r.recognizedWords, isFinal: r.finalResult)` and DROPS the result type.
PROVEN from speech_to_text 7.4.0 source: Android `updateResults` (`SpeechToTextPlugin.kt:442-465`)
turns a non-final bundle whose `final_result` extra is true into `ResultType.intermediate`, with no
accumulation; Dart `_checkAggregates` (`speech_to_text.dart:653-668`) joins only
`recognizedPhrases`, which Android does not fill; an intermediate has `finalResult == false`, so
today it is replaced like any partial. INFERENCE (consistent with the walk, not provable from the
source): the founder's recognizer sends `final_result` at a segment end and restarts its partials.
Telemetry below answers it. Web (`speech_to_text_web.dart:221-247`): every result is `partial` and
cumulative across `results[]` — web is not affected and is left exactly as it is.
Readers: `liveText` (`:142`) → live bar (`input_bar.dart:453`, `food_logger_section.dart:102`);
`_finish(..., _liveText)` (`:185, 191, 206, 407, 414, 424, 438`) → `SpeechSessionEnd.transcript` →
`CoachComposer._onSpeechEnd` and `FoodLoggerSection`; `_canRetry` (`:344`).

### Recurrence
Not a recurrence (`abe150` is the first-use start timeout; `speech_input_session_owner` class).

### Fix (native only; `service.isWeb` → today's code, untouched)
- `SpeechEngineResult` gains `final bool isSegmentEnd` (default false), with the const-constructor
  assert `!(isFinal && isSegmentEnd)`. The real engine sets it from the raw int
  `r.resultType == ResultType.intermediate.value` (NOT `resultTypeValue`, whose `fromValue` throws on
  an unknown int inside the plugin's result chain). `FakeSpeechEngine.emitResult` gains
  `isSegmentEnd`.
- `_accumulate = !_service.isWeb && _service.segmentAccumulateEnabled`, computed once in `_start`;
  every rule below and the telemetry run only when it is true.
- A non-final result whose `trim()` is empty is IGNORED while accumulating (`_afterEnd` untouched);
  today's code would blank the field (web and the fake can send one; Android filters them).
- Controller state (reset in `_start` and `_retry`): `_committed` (finished segments joined by one
  space), `_segment` (current), `_lastCommitted`, `_mode` ∈ {undecided, segmented, cumulative},
  `_afterEnd` (true right after a segment end until the next non-empty result). `_liveText` is ALWAYS
  the joined value `join(_committed, _segment)` (or `_segment` in cumulative mode), recomputed on
  every change; the existing early return compares the NEW joined value with `_liveText`, so
  `notifyListeners` fires once per real change.
- `norm(s)` = lowercase, U+2019 → `'`, remove `[^\p{L}\p{M}\p{N}\s']` (`unicode: true`, keeps
  Devanagari vowel signs), split on whitespace. `prefixMatch(c, r)` = share of `norm(c)` words equal
  to the word at the same position in `norm(r)`; evaluated only after the length checks below (which
  guarantee `norm(r)` is at least as long), and 0 when `norm(c)` is empty (no division by zero).
- Non-final result `r` (non-empty), in this order:
  a. `_mode == cumulative` → `_segment = r` (today's replace; a segment end commits nothing). Stop.
  b. `_afterEnd` (the first non-empty result after a segment end):
     - `norm(r) == norm(_lastCommitted)` → ignore it (a repeat, no new word yet; `_afterEnd` stays
       true). Stop. (Checked FIRST: a cumulative recognizer's first partial can equal the committed
       text, and that alone must not decide the mode.)
     - `_mode == undecided` and `norm(_committed)` has ≥ 3 words and `norm(r)` has STRICTLY more and
       `prefixMatch(_committed, r) >= 0.7` → `_mode = cumulative`, `_committed = ''`,
       `_lastCommitted = ''`, `_segment = r`, `_afterEnd = false`. Stop.
     - `_mode == undecided` and `norm(_committed)` has ≥ 3 words → `_mode = segmented`. Continue.
  c. `r.isSegmentEnd` → `_committed = join(_committed, r)`, `_lastCommitted = r`, `_segment = ''`,
     `_afterEnd = true`.
  d. otherwise `_segment = r` (growth or revision inside the segment), `_afterEnd = false`.
- Final `r` (`isFinal`, non-empty; an empty final stays a no-op as today, `:391`): if `_committed`
  is empty or cumulative mode → `_finish(auto, r)` (today). Else: WHOLE-UTTERANCE final iff
  `norm(_committed)` has ≥ 2 words, `norm(r)` has at least as many, and
  `prefixMatch(_committed, r) >= 0.7` → `_finish(auto, r)`; else if `_segment` is empty and
  `norm(r) == norm(_lastCommitted)` → `_finish(auto, _committed)` (the plugin's `_onFinalTimeout`
  re-sends the last result as final, `speech_to_text.dart:670-676`); else
  `_finish(auto, join(_committed, r))`.
- Without any segment end the controller behaves exactly as today (no heuristic fold: round 1 showed
  a word-overlap fold duplicates on numerals and contractions). Residue, stated: a device that sends
  no intermediate keeps today's behaviour; a final rescored with different numerals after segment
  ends appends instead of replacing; a cumulative recognizer whose first segment had < 3 words, or
  whose first post-end partial revises enough of a 3-word committed text to fall under 0.7, can
  duplicate those words until the final; on a segmented device, a next segment that starts with the
  committed words and is longer (≥ 0.7 positional match) is taken as cumulative and drops the
  committed text, which is the same loss as today; a genuinely repeated segment ("yes" ... "yes") is
  swallowed by the repeat rule, as today. Telemetry measures which shape a device has.
- Telemetry: at most ONE `ErrorTelemetry.logEvent('speech_segments', message: 'partials=N
  segment_ends=N finals=N mode=<m> repeats=N whole_finals=N')` per app PROCESS (a static flag with a
  `@visibleForTesting` reset), emitted in `_finish` before the `disposed` early return, at the end of
  the first accumulating (native) session with ≥ 10 results: a SAMPLE of one session. Counts and the
  mode word only, never words. New op type is LOW (`error_telemetry.dart:165` priority list
  unchanged); Gate 22 (advisory, map-literal PII keys only) passes a string of counts.
- Kill switch `configBox['disable_speech_segment_accumulate'] == true` → today's code verbatim. Read
  through a new `SpeechInputService.segmentAccumulateEnabled` getter (`HiveService.instance.configBox`
  read in try/catch, the `plate_flags.dart:67` pattern; unreadable → enabled; a constructor override
  for tests, so the five existing `SpeechInputService(` construction sites stay Hive-free), once per
  session in `_start` (`_retry` keeps the session's value). No host change.

### Tests (extend `test/core/speech_input_controller_behavioral_test.dart`, fake engine)
- S1 segmented: partials "I want a plan", "I want a plan for next week", segment end same,
  partials "or the coming", "or the coming week", final "or the coming week" → "I want a plan for
  next week or the coming week".
- S2 cumulative: segment end "I want a plan", partials "I want a plan for", "I want a plan for next
  week", final "I want a plan for next week" → that text once.
- S3 no segment end (growing partials, final) → identical to today (and to the switch-on result).
- S4 whole-utterance final with a revised prefix: segment end "I want a plant for", partial "next
  week", final "I want a plan for next week" → the final alone.
- S5 repeat: segment end "A B C", final "A B C" (synthetic final) → "A B C" once; segment end "A B C",
  partial "A B C" (ignored) then "D" → mode segmented, "A B C D"; segment end "A B C", partial
  "A B C" (ignored) then "A B C D" → mode cumulative, "A B C D".
- S6 the user repeats a short phrase: segment end "yes", partials "yes", "yes I will" (committed has
  1 word → no cumulative decision) → "yes yes I will" (stated: short-prefix duplicate preferred over
  loss), and segment end "next week please do it", partial "next", "next week" → segmented, both kept.
- S7 Stop / Send / hidden after a segment end → committed + segment.
- S8 retry path and a new session start empty; `_canRetry` sees the joined text.
- S9 web session → unchanged (segment-end flag never set; rules gated off by `isWeb`).
- S10 kill switch on → the walk input yields "or the coming week" (today).
- S11 Hindi: segment end "मुझे एक प्लान चाहिए", partial "अगले हफ्ते के लिए" → both kept; `norm` keeps
  vowel signs (two words differing only in a matra are not equal).
- S1b segmented device whose first post-end partial is LONGER than the committed text with different
  words ("I want a plan" end, partial "and then maybe something else later") → segmented, both kept;
  same-words case (end "I want a plan for next week", partial "I want a plan for the weekend and
  more") → cumulative, the stated residue.
- S7b `done` right after a segment end (no partial) → the session ends with the committed words.
- S12 telemetry: one event per process (seam `ErrorTelemetry.debugOnLogEventForTests`, set and
  reset; the static flag reset in `setUp`), none before 10 results, message contains no transcript
  word.
- S13 an empty/whitespace partial after a segment end → ignored, the field keeps the words.
- Mutations: V1 step c does not commit → S1; V2 cumulative threshold 0 → S1b; V2b drop the
  "strictly more words" check → S1b;
  V3 no cumulative detection → S2; V4 drop the whole-utterance final rule → S4; V5 drop the repeat
  rule → S5; V6 `_start` keeps `_committed` → S8; V7 drop the `isWeb` gate → S9 (a web segment end
  injected by the fake); V8 switch inverted → S10; V9 `norm` without `\p{M}` → S11; V10 empty partial
  not ignored → S13.

---

## Ledger and docs (same batch)
- Diagnose-docs: `docs/diagnoses/2026-11-23-past-phase-display-runs-<id>.md` (B3, FULL template,
  `related_bugs: 7d2e6b, c9e4b7, b7f1c8`, the strict-count residual with its condition) and
  `docs/diagnoses/2026-11-23-speech-segment-accumulate-<id>.md` (B5, PROVEN vs INFERENCE split,
  residue). Each with the mutation table (§4.4 r21).
- SoT registry: new concepts `past_phase_display_buckets` and `speech_segment_accumulation` with
  `behavioral_test_path`; the `speech_input_session_owner` entry and its `behavioral_test_path`, and
  the `week_completion_check` / `workout_receipt_rendering` entries reopened by hand, and the two
  registry texts naming the renamed symbols (`docs/sot_registry.yaml` `_PastPhase blocks`,
  `+ _toPastPhases`); shifted line ranges re-checked; `scripts/check_hive_map_field_drift.dart` run on
  the new code (it allowlists `current_phase` at `:353`).
- Naming: both kill switches and both concepts added to `docs/naming_conventions.md`.
- Kill switches (2): ONE OI minted via `scripts/mint_oi.sh` for removing both after the device walk
  (§4.6.4). OI-348 walk rows A5 part 1 / A19: "fix landed, re-check".
- Nested docs: `lib/features/train/CLAUDE.md` (`week_completion_check` text, which now says
  `bucketPastRows` for display: corrected; past-phase pitfall row), `lib/core/services/CLAUDE.md`
  (`speech_input_session_owner` row: segments).
- `.claude/skills/debugging/bug-classes.md`: "write-time stamp trusted over the date sequence" (B3),
  "platform segment boundary dropped at a wrapper" (B5).
- Closure ledger `docs/audit/oi348-landing1b.closure.yaml`; plan-review record; B-pass before merge.
- Runtime check (§5): next device walk: A5 part 1, A19, and the `speech_segments` event.

---

## Round 1 resolutions (v1 → v2)
| Finding | Resolution |
|---|---|
| A P1-1 carry-forward lets a stray stamp swallow unstamped rows | runs over stamped rows only; rows assigned by date to segments (steps 2-4); T7 |
| A P1-2 consecutive short runs defeat the absorb rule | noise = runs ≤ 2 rows, dropped before merging; adjacent equal segments merge; T6 |
| A P2-1 T8 circular | numbering not shared; widget test compares `phaseForDate` with the rendered groups |
| A P2-2 kill switch read point | service getter; per call in the service; once per build in the widget |
| A P2-3 spurious W5 | edge rule (calendar week of the next segment) + weekCount from first/last row; T8 |
| A P2-4 strict over-count | stated residual with the condition under which it can fire |
| A P2-5 property (b) overstated | stated precisely, non-adjacent equal stamps tested (T5) |
| B P1-A re-emission wipes committed words | no prefix wipe per result; ONE mode decision needing ≥ 3 committed words; S6 |
| B P1-B rescored whole final duplicates | whole-utterance final rule with positional match ≥ 0.7; S4 |
| B P1-C fallback fold duplicates on numerals/contractions | fallback removed; no segment end = today's behaviour; residue stated |
| B P2 `\p{M}` | kept, `unicode: true`; S11 |
| B P2 kill switch seam | `SpeechInputService.segmentAccumulateEnabled`, no host change |
| B P2 telemetry flood | one event per process after ≥ 10 results |
| B P2 rule order / empty final / early return | specified above |
| B P3 web gating, `_onFinalTimeout`, fake mirror, SoT paths | gated; repeat rule covers the synthetic final; assert; cited |
