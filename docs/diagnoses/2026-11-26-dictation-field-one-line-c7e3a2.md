---
bug_id: c7e3a2
date: 2026-11-26
batch: OI-348 Landing 3e (V1)
status: fixed
tier: full
blast_radius: account
symptom: |
  OI-348 walk A19 (AAB 1.0.0+50, founder, 2026-11-25): a long dictated sentence cannot be read in full before it is sent. The coach composer showed one line (the newest words while listening, the tail after Stop); the nutrition Log Food field likewise one line.
concept: speech_input_session_owner
sot_registry_entry: speech_input_session_owner
writers:
  - { file: lib/core/services/speech_input_controller.dart, method_or_widget: "SpeechInputController._liveText (engineResult) and _finish(userSend, _liveText): the words, unchanged by this fix", line: 117 }
readers:
  - { file: lib/features/ai_coach/screens/ai_coach/input_bar.dart, method_or_widget: "_LiveWords (live words while listening; was maxLines 1 in a horizontal reversed scroll)", line: 616 }
  - { file: lib/features/ai_coach/screens/ai_coach/input_bar.dart, method_or_widget: "_buildIdleRow composerField (after Stop; was one line)", line: 338 }
  - { file: lib/features/ai_coach/screens/ai_coach/input_bar.dart, method_or_widget: "_onSpeechEnd -> _writeField (the words into the controller)", line: 170 }
  - { file: lib/features/nutrition/widgets/food_logger_section.dart, method_or_widget: "FoodLoggerSection TextField (live and after Stop; was one line) + _onSpeechChanged / _scheduleJumpToEnd", line: 316 }
hive_key_prefix: "none (display only; nothing stored)"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: ""
cloud_columns: []
contract_test_path: test/ai_coach/coach_composer_speech_test.dart
ist_handling: ["n/a: no dates"]
provider_invalidations: ["none: layout only"]
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "true: no user data stored or read; the change is the size of two text fields."
forbidden_patterns_checked:
  - { pattern: "TextInputType.multiline on either field (would turn the action key into a newline and stop Enter from sending / analysing)", absent: true }
  - { pattern: "a TextPainter measured with the late-loading DM Sans font (the cap is measured with a forced strut, font-independent)", absent: true }
  - { pattern: "a multi-line field without singleLineFormatter (a pasted line break would reach the coach / food_text_analysis; maxLines 1 used to strip it)", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-landing3e.md (3 review rounds, converged; build notes B1-B3). Shared in speech_input_lifecycle.dart: kDictationFieldMaxLines = 6, kDictationStrut (fontSize 14, height 1.4, forced) and dictationMaxHeight (TextPainter.preferredLineHeight with the strut x 6, the number RenderEditable uses). Coach: the bubble is minHeight 48 (no fixed height); every button sits in a 46 dp slot (the M3 IconButton keeps today's 46 dp tap target, one line stays 48); the idle field is minLines 1 / maxLines 6 / keyboardType text / the strut / hintMaxLines 1, centred in a 46 dp box; both rows align to `end`; _LiveWords wraps in a vertical reversed scroll capped at dictationMaxHeight; a _HeightReporter reports growth once per frame and the screen passes keepBottomAfterChip so a chat at its bottom stays there. Nutrition: the same field settings plus _fieldScroll, jumped to its end after each live write (an unfocused field does not follow its caret), one jump per frame, guarded by mounted, isBusy and hasClients. No kill switch (layout only, outside the CLAUDE.md 4.6 classes); rollback is a revert.
regression_test_planned: |
  test/ai_coach/coach_composer_speech_test.dart group 'OI-348 Landing 3e' (T3, T3b, T3c, T4, T4b, T5, T9 x2 tiers, T9c, the screen wiring pin) plus T1 / T2 x2 scales in 'the bar' (they replace the old horizontal-overflow test); test/widgets/food_logger_speech_test.dart group 'OI-348 Landing 3e' (T6, T7, T8, T8b, T8c). Coach file 34 passed, nutrition file 26 passed (TZ=Asia/Kolkata).
mutation_proof: |
  Rule 21. scratchpad m3e/run.sh + run2.sh: each mutant applied by a node script that refuses unless the pattern matches EXACTLY once, the host's test file run (TZ=Asia/Kolkata), the source restored by cp from a snapshot and cmp-identical after every mutant (never git checkout); final cmp of both files clean. 16 of 16 red (failing tests in brackets):
  coach (34 tests): M1 field maxLines 1 [6]; M2 live words maxLines 1 [6]; M3 reverse removed [2]; M4 cap removed [3]; M5 live-words strut dropped [1]; M7 coach keyboardType removed [1]; M9 _kRowHeight 48 [1]; M10 field box without the centring Align [1]; M11 dot+clock box without its height [1]; M12 reporter never calls [2]; M13 first layout reported [3]; M14 _lastHeight updated only on growth [2]; M15 coach field strut dropped [3].
  nutrition (26 tests): M6 jump-to-end removed [1]; M8 keyboardType removed [1]; M16 field strut dropped [1].
  A first run left 9 mutants NOT applied (the patterns assumed CRLF; the files are LF): reported as not-applied by the exact-once guard, never counted, re-run with LF patterns.
  B-pass (review docs/reviews/oi348-landing3e-bpass.md): seat B ran 30 more mutants, 9 survived. Tests added and each survivor re-mutated (run3.sh, same protocol): M2 jump without the isBusy guard red 1 (T6b); M7 _kRowHeight 40 red 2 (T4c); M8 updateRenderObject no-op red 1 (T9b); M23 paywall GestureDetector on the TextField red 1 (T4d); M17 nutrition hintMaxLines removed SURVIVED T7b's first form (empty vs typed: a hidden hint keeps its layout size, both 84 dp), T7b rewritten against one line, re-run red 1. M5 (full-width SizedBox removed) survived because a TextField already fills the width: the SizedBox was redundant and is removed; T4e (off-text tap focuses) stays. New guard F1/F2 (singleLineFormatter on each field) red 1 each (T5b, T8d). Stated, no test: M6 AlignmentDirectional vs Alignment.centerLeft (equivalent: full-width children), M9 the `attached` check (unreachable within one frame), M10 the _fieldScroll dispose (no observable effect).
impact_analysis: |
  Both dictation hosts show up to six lines of the words while listening (coach: the live words; nutrition: the field itself) and after Stop, then scroll with the newest in view. Enter / the keyboard action still sends (coach) and analyses (nutrition); nothing about the words, the send path, the usage gate or the speech engine changed. The coach bubble is 48 dp for one line as before; the chat list follows a taller composer when it was at its bottom.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "input_bar.dart, screen.dart (onHeightGrew), food_logger_section.dart, speech_input_lifecycle.dart; flutter analyze clean on the touched files (2 pre-existing infos); the two test files green." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "Nothing read or written." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "None." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "None." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "None." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: verified, evidence: "Flutter SDK source read: EditableText picks TextInputAction.newline only for TextInputType.multiline (so `text` keeps done); an unfocused EditableText does not scroll to its caret on a value change; RenderEditable height = preferredLineHeight * maxLines; getLocalRectForCaret is in text coordinates. The web Enter key is checked live after the merge (Vercel deploys main)." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No payload changed: Send still sends SpeechInputController._finish's whole transcript." }
recurrence: "Not a recurrence: 6d9f3b LOST words (a dropped segment boundary); here no word was ever lost, only the display was one line (a deliberate voice-input-unified D4 choice, now reversed by the founder)."
related_bugs: [6d9f3b]
---

# c7e3a2 - dictation-field-one-line

## What happened
voice-input-unified D4 drew the coach's live words on ONE line in a reversed horizontal scroll (newest visible), and both hosts' text fields had no `maxLines` (one line). Send always sent the whole transcript, so nothing was lost, but a long sentence could not be read before sending.

## PROVEN
- From the code: `_LiveWords` had `maxLines: 1`, `softWrap: false` in a horizontal reversed scroll; both `TextField`s had no `maxLines`.
- From the build (T3c, the cross-check): the engine rounds a line's height (19.6 lays out as 20), so a cap computed as `scale(14) * 1.4 * 6` was 2.4 dp short of the field's own six lines; the cap is now measured with `TextPainter.preferredLineHeight`.
- From the build (T4): an M3 `IconButton` pads its tap target to 48 dp under loose constraints; the old fixed 48 dp bubble squeezed it to 46. The 46 dp slots keep that tap target and the 48 dp one-line bubble.

## Residue, stated
- Devanagari words from the speech engine drawn in a fallback font may be clipped at the first and last line by the forced strut; checked on the device (A19 step 8).
- A six-line composer on a small phone with the keyboard open takes a large share of the chat; checked on the device (A19 step 8).
- Two growths less than 200 ms apart can end the chat's follow short by the second step (accepted; the next reply runs `_scrollToBottom`).
- After a Stop that does not take focus (a hidden tab, a preemption) a long text shows its FIRST six lines; scrolling shows the rest.
- In a multi-line field the buttons sit level with the last line's slot, a few dp off the last line's own centre (one line is exactly centred).
- The web Enter key (sends / analyses) is read from the SDK and checked live after the merge.
