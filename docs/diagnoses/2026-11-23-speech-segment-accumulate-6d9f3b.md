---
bug_id: 6d9f3b
date: 2026-11-23
batch: oi348-walk-fixes Landing 1b (B5)
status: fixed
tier: full
blast_radius: account
symptom: |
  OI-348 walk A19 (AAB 1.0.0+50, Upendra, 2026-11-22): AI Coach mic, one long spoken sentence; the composer ended with only the last fragment, "or the coming week".
concept: speech_segment_accumulation
sot_registry_entry: speech_segment_accumulation
writers:
  - { file: lib/core/services/speech_input_service.dart, method_or_widget: "engineResultFromPlugin (isSegmentEnd from the raw resultType int), called by PluginSpeechEngine.listen", line: 213 }
  - { file: lib/core/services/speech_input_controller.dart, method_or_widget: "engineResult (feeds every non-final result to the accumulator; a final through onFinal)", line: 404 }
  - { file: lib/core/services/speech_segment_accumulator.dart, method_or_widget: "SpeechSegmentAccumulator.onResult / onFinal (new, pure)", line: 63 }
readers:
  - { file: lib/core/services/speech_input_controller.dart, method_or_widget: "liveText (live bar of the coach composer and the food logger)", line: 154 }
  - { file: lib/core/services/speech_input_controller.dart, method_or_widget: "_finish transcript -> SpeechSessionEnd (CoachComposer._onSpeechEnd, FoodLoggerSection)", line: 404 }
  - { file: lib/features/ai_coach/screens/ai_coach/input_bar.dart, method_or_widget: "_onSpeechEnd", line: 151 }
  - { file: lib/features/nutrition/widgets/food_logger_section.dart, method_or_widget: "live text of the dictation", line: 102 }
hive_key_prefix: "none (no Hive data; the kill switch is configBox['disable_speech_segment_accumulate'])"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: client_errors
cloud_columns: [message]
contract_test_path: test/core/speech_input_controller_behavioral_test.dart
ist_handling: ["n/a: no dates"]
provider_invalidations: ["none: the controller is a ChangeNotifier owned by its host; notifyListeners fires once per real change of the joined text"]
telemetry_op_types:
  success: [speech_segments]
  failure: []
cross_account_guard: "true: no user data stored; the telemetry message carries counts and the mode word only, never a transcript word (test S12)."
forbidden_patterns_checked:
  - { pattern: "a transcript word in telemetry", absent: true }
  - { pattern: "a change to the web path (results are already cumulative there)", absent: true }
  - { pattern: "resultTypeValue (its fromValue throws on an unknown int inside the plugin's result chain)", absent: true }
proposed_fix: |
  Plan docs/plans/oi348-walk-fixes-landing1b.md Unit B5 (v3 FINAL, review 2 rounds, converged). The wrapper now keeps the segment boundary (`isSegmentEnd = r.resultType == ResultType.intermediate.value`). A pure SpeechSegmentAccumulator decides the shape once per session: after a segment end, a repeat of the committed words is ignored; with 3+ committed words, a result with STRICTLY more words matching the committed ones position by position for at least 70% means the recognizer is CUMULATIVE (replace, as before); otherwise SEGMENTED (append). A final that re-sends the whole utterance (2+ committed words, at least as long, 70% positional match) replaces everything; a final repeating the last segment adds nothing; any other final is appended. Empty partials are ignored. Native only (web untouched). One `speech_segments` event per app process after a session with 10+ results (counts only). Kill switch configBox disable_speech_segment_accumulate, read once per session, restores the replace-every-result code verbatim.
regression_test_planned: |
  test/core/speech_segment_accumulator_test.dart (23 tests: S1, S1b x2, S1c, S2-S6, S5b, S5c, S11, S13, S13b, S13c, S14, S14b, S14c, S14d, S15, S16, normaliser, telemetry); test/core/speech_segment_kill_switch_test.dart also pins engineResultFromPlugin (intermediate, partial, final, unknown int); test/core/speech_input_controller_behavioral_test.dart group 'segment accumulation (native)' (S1, S2, S7, S7b, S7c, S13, S9 web, S10 kill switch, S12 telemetry once per process, no words); test/core/speech_segment_kill_switch_test.dart (no box, absent, true, false, override).
mutation_proof: |
  Rule 21. scratchpad/mut_b5.sh: sed applied to the live file, grep -c of the mutated text = 1 for every mutant, the three test files run, all three source files restored by cp and cmp-identical after every mutant (never git checkout). 13 of 13 red:
  V1 a segment end does not commit red 17; V2 cumulative threshold 0 red 1; V2b no "strictly more words" red 1; V3 never cumulative red 3; V4 no whole-utterance final rule red 1; V5 no repeat rule red 1; V5b no final-repeat rule red 1; V6 `_start` keeps the accumulator red 1; V7 no isWeb gate red 1; V8 kill switch inverted red 1; V9 normaliser without \p{M} red 1; V11 telemetry threshold 0 red 1.
  V10 (empty partial not ignored) SURVIVED the first run: S13 fed the empty partial in segmented mode, where the old code does not blank either. S13b (an empty partial after a segment end must not decide the mode) and S13c (an empty partial in cumulative mode keeps the words) were added; V10 re-run red 2, restored cmp-clean.
  B-pass (2 seats, review `docs/reviews/oi348-landing1b-bpass.md`) found three survivors and one wrong outcome, all fixed in this batch and each mutated once (scratchpad/mut_bpass.sh, cp restore + cmp): the mapping line had no test (it is now the pure `engineResultFromPlugin`, tested with real `SpeechRecognitionResult` values incl. an unknown type int; W3 `isSegmentEnd: false`); a segment end in CUMULATIVE mode had no test (S15; W2 cumulative branch removed); the equal-length boundary of the cumulative decision had no test (S16; W4 `>` to `>=`); and a cumulative recognizer whose first segment had fewer than 3 words kept the duplicate PAST the final after a second segment end (S14/S14b; fixed by a strictly-longer whole final for a one-word committed text, W5 one-word `>` to `>=` red 1, and a commit-time rule). The first commit-time rule DECIDED cumulative; the delta seat showed it locks a SEGMENTED session when the user re-says a short phrase ("yes", "yes I will", "book it" ended as "book it"), losing words. Final shape: while undecided, such a segment end REPLACES the committed text once and leaves the mode open (S14d); W1 (rule removed) red 2, W6 (the lock-the-mode shape re-entered) red 2, restores cmp-clean. Results in the B-pass review file.
impact_analysis: |
  Native dictation (coach composer, food logger) keeps every word of a long utterance on a recognizer that restarts its partials after a segment end. A recognizer that never sends a segment end, or one that is cumulative, behaves as before. Web unchanged.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "speech_input_service.dart (isSegmentEnd, switch getter), speech_input_controller.dart (accumulate, telemetry), new speech_segment_accumulator.dart; flutter analyze clean." }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "Only the configBox kill switch is read (try/catch, unreadable = enabled); speech_segment_kill_switch_test.dart reads it from a real temp box." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "None." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "None (the transcript is not stored by this code)." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "None." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "None; the event goes through the existing log-client-error path." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "None." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "None." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "None." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "None." }
  - { tier: 11, name: "External services", status: verified, evidence: "speech_to_text 7.4.0 source read: Android updateResults (SpeechToTextPlugin.kt:442-465) turns a non-final bundle with final_result=true into ResultType.intermediate with no accumulation; Dart _checkAggregates joins only recognizedPhrases, which Android never fills; web results are cumulative (speech_to_text_web.dart:221-247)." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No server payload changed (one new LOW telemetry event of counts)." }
recurrence: "Not a recurrence: abe150 is the first-use start timeout and the session-owner fixes are about lifecycle, not result content. New class: a platform segment boundary dropped at a wrapper."
related_bugs: [abe150]
---

# 6d9f3b - speech-segment-accumulate

## What happened
`SpeechToTextEngine.listen` mapped each plugin result to `SpeechEngineResult(words, isFinal)` and dropped the result type. `SpeechInputController.engineResult` replaced its text with every result.

## PROVEN
From the speech_to_text 7.4.0 source: on Android a finished segment arrives as `ResultType.intermediate` (`finalResult == false`) and the plugin adds no accumulation, so a long utterance reached the controller as segments, and each replaced the last.

## INFERENCE
The founder's recognizer restarts its partials after a segment end (SEGMENTED). This fits the walk exactly ("or the coming week" is the last segment) but is not provable from source. The `speech_segments` event (mode, segment_ends) answers it on the next walk; both shapes are handled.

## Residue, stated
- A device that never sends a segment end keeps today's behaviour.
- A final rescored with different numerals after segment ends is appended rather than replacing.
- A cumulative recognizer whose first segment had fewer than 3 words shows those words twice on screen until its next segment end or its final, which then replace them (B-pass fix, S14/S14b); a Stop or Send before that keeps the duplicate; one whose first post-end partial revises a 3-word segment below 70% is taken as segmented and keeps the duplicate.
- The `speech_segments` event samples ONE session per app process (the first with 10+ results): `segment_ends=0` there can mean that session had no pause, not that the device never sends one; read several walks before concluding.
- On a segmented device, a next segment that starts with the committed words and is longer is taken as cumulative and drops the committed words (today's loss).
- A genuinely repeated segment ("yes" ... "yes") is kept once; likewise a short first segment that the user re-says at the start of a longer one ("yes" ... "yes I will", or a final "stop it" after "stop") keeps one copy. That is the price of removing a cumulative recognizer's duplicate; it never drops a word the user said only once.
- The kill switch is removed after the device re-check (OI on the board).
