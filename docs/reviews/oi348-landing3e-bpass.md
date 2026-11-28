---
reviewed_at: 2026-11-26T17:30:00+05:30
staged_against: 9b3cd284 (three-dot vs 69a3cc4a)
blast_radius: account
reviewer: claude-sonnet-via-skill (2 seats: A lenses read-only, B guard_without_its_mirror by mutation)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror]
findings_count: 11
verdict: accepted
verdict_note: all 11 resolved in this batch (2 fixed in code, 6 by new tests re-mutated red, 3 stated with reasons); founder go to merge still required.
---

# Code Review — OI-348 Landing 3e (dictated words readable in full)

Plan `docs/plans/oi348-landing3e.md`, diagnose `docs/diagnoses/2026-11-26-dictation-field-one-line-c7e3a2.md`.

## Finding A1 — P2 — guard_without_its_mirror
- **file:line:** lib/features/ai_coach/screens/ai_coach/input_bar.dart (composerField), lib/features/nutrition/widgets/food_logger_section.dart (TextField)
- **claim:** With `maxLines: 1` the SDK prepended `FilteringTextInputFormatter.singleLineFormatter` (editable_text.dart:968); a multi-line field does not, so a pasted line break would now reach the coach and `food_text_analysis`. The plan's "pasted newlines are not blocked, as today" was wrong.
- **verification:** `sed -n 960,972p <flutter>/packages/flutter/lib/src/widgets/editable_text.dart`
- **suggested-fix:** pass the formatter on both fields; paste tests.
- **status:** accepted, fixed (both fields pass `singleLineFormatter`; T5b, T8d; formatter-removed mutants red 1 each)

## Finding A2 — P3 — writer_reader_drift (docs)
- **file:line:** lib/core/services/CLAUDE.md (speech_input_lifecycle row); docs/sot_registry.yaml (second `keepBottomAfterChip` call site)
- **claim:** the new shared geometry and the composer's follow-scroll call site were not documented.
- **status:** accepted, fixed (services CLAUDE.md row; `speech_input_session_owner` description; not filed under the measurement-prompt concept, which lists chip mounts)

## Finding B1 — P2 — guard_without_its_mirror
- **file:line:** food_logger_section.dart `_scheduleJumpToEnd` (`_speech.isBusy` guard)
- **claim:** mutant M2 (guard removed) survived; no test ends the session in the frame the last jump was scheduled.
- **status:** accepted, fixed (T6b; M2 re-run red 1)

## Finding B2 — P2 — guard_without_its_mirror
- **file:line:** food_logger_section.dart `hintMaxLines: 1`
- **claim:** M17 survived. The first test written for it (T7b, empty vs typed) ALSO missed it: a hidden hint keeps its layout size (84 dp both ways at 360 dp).
- **status:** accepted, fixed (T7b compares the empty field against ONE line; M17 re-run red 1)

## Finding B3 — P2 — guard_without_its_mirror
- **file:line:** input_bar.dart `SizedBox(width: double.infinity)` around the field
- **claim:** M5 survived.
- **status:** accepted: the SizedBox was redundant (a TextField fills the width; the off-text tap test T4e passed WITH the mutant), so it is removed; T4e kept as the guard of the behaviour

## Finding B4 — P2 — guard_without_its_mirror
- **file:line:** input_bar.dart `_HeightReporter.updateRenderObject`
- **claim:** M8 (no-op) survived; no test rebuilds with a new callback.
- **status:** accepted, fixed (T9b; M8 red 1)

## Finding B5 — P3 — guard_without_its_mirror
- **file:line:** input_bar.dart limit `GestureDetector`
- **claim:** M23 (wrap the TextField, not the 46 dp box) survived.
- **status:** accepted, fixed (T4d asserts the paywall tap area is 46 dp; M23 red 1)

## Finding B6 — P3 — guard_without_its_mirror
- **file:line:** input_bar.dart `_kRowHeight = 46`
- **claim:** M7 (40) survived; the 48 dp bubble minimum hid it.
- **status:** accepted, fixed (T4c asserts the 46 dp tap target; M7 red 2)

## Finding B7 — P3 — guard_without_its_mirror
- **file:line:** input_bar.dart `AlignmentDirectional.centerStart`
- **claim:** M6 (`Alignment.centerLeft`) survived; no RTL test.
- **status:** false_alarm: an EQUIVALENT mutant. Both children are full width (the TextField, and the live words' `SizedBox(width: infinity)`), so only the vertical centring matters, which is identical.

## Finding B8 — P3 — guard_without_its_mirror
- **file:line:** input_bar.dart `if (!attached) return;`
- **claim:** M9 survived.
- **status:** false_alarm (kept as defence): the post-frame callback runs in the same frame as the layout that scheduled it, with no rebuild between, so a detach in between cannot be produced; the guard costs nothing.

## Finding B9 — P3 — guard_without_its_mirror
- **file:line:** food_logger_section.dart `_fieldScroll.dispose()`
- **claim:** M10 survived (a leak, no observable effect in a test).
- **status:** false_alarm (accepted untested; stated in the diagnose doc)

## Clean lenses (seat A)
function_exception_swallow (no `.functions.invoke(`), secrets_in_tree (none), unawaited_no_error_sink (no `unawaited(`), blast_radius_mismatch (account matches `lib/features/ai_coach/**`; no catastrophic path), writer_reader_drift inserted-lines sub-check (every registry cite into the four changed files read against `git show 69a3cc4a:<path>`; all shifted correctly; re-shifted again after the fold's two import lines).

## Founder triage notes
None yet. The founder's go is still required to merge.

## Tuning entry
- **2026-11-26** - blast-radius account - 11 findings; 3 false_alarm (two equivalent / unreachable mutants, one untestable leak); tuning: the mutation seat found 9 survivors the author's own 16-mutant run did not reach, and one of the author's fold tests (T7b) was itself blind on first write (a hidden hint keeps its layout size). Keep re-mutating every fold test before believing it. Seat A's SDK read (an implicit `singleLineFormatter` lost when `maxLines` leaves 1) is a new instance of "a default the old shape gave for free": when a diff changes a widget's mode (maxLines, keyboardType, readOnly), list what the OLD mode added implicitly.
