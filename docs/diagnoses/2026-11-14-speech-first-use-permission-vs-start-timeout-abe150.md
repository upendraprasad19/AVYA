---
bug_id: abe150
date: 2026-11-14
batch: voice-input-unified
status: fixed
blast_radius: account
symptom: >-
  On a fresh Android install the first mic tap opens the system microphone
  dialog while the 4 s native start timeout is already running. A user who
  takes longer than 4 s to tap Allow sees "Could not hear you. Please try
  again." behind the dialog, a spurious speech_input_error:start_timeout
  telemetry row, and after Allow nothing starts (the session was already
  abandoned), so the first dictation of a new user is lost and they must tap
  the mic a second time. Found by all three context-blind B-pass reviewers of
  PR 273 independently (b55bc328); never reproduced on a device (the build is
  not out yet), established by reading the controller, the service and the
  plugin's Android Kotlin.
concept: speech_input_session_owner
recurrence: >-
  NOT a recurrence. docs/diagnoses/INDEX.md and a grep of docs/diagnoses for
  start_timeout, speech_to_text and "permission dialog" found only the
  unrelated Telegram note (b9d3f1). The class of the bug (a timer armed at a
  gesture that also covers an OS prompt the same call chain raises) is new;
  bug-class 2.157 now carries the first-use shape. The old coach avoided it
  only by accident: it called initialize at screen mount, with no timer.
related_bugs: []
sot_registry_entry: speech_input_session_owner (ranges recomputed; description now states the first-use budget)
writers:
  - { file: lib/core/services/speech_input_controller.dart, method: _start (armed the start timeout and the one-restart window at the tap), line: 210 }
  - { file: lib/core/services/speech_input_controller.dart, method: _armStartTimeout / _prelistenBudget / _onListenIssuing (the fix), line: 251 }
  - { file: lib/core/services/speech_input_service.dart, method: begin (awaited _ensureReady with no bound; now bounded and calls onListenIssuing right before engine.listen), line: 443 }
  - { file: lib/core/services/speech_input_service.dart, method: _initializeEngine (records isInitialized), line: 407 }
readers:
  - { file: lib/features/ai_coach/screens/ai_coach/input_bar.dart, method_or_widget: _CoachComposerState._onSpeechEnd (shows the engine-failure message), line: 151 }
  - { file: lib/features/nutrition/widgets/food_logger_section.dart, method_or_widget: _onSpeechEnd (shows the engine-failure message), line: 106 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/core/speech_input_controller_behavioral_test.dart
ist_handling:
  - { file: lib/core/services/speech_input_controller.dart, line: 251, fn: "n/a, monotonic durations only; no date key" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [speech_input_session_error, speech_input_on_busy]
cross_account_guard: n/a
forbidden_patterns_checked:
  - { pattern: "a start timer armed at the tap and not re-armed at the listen", absent_after_fix: true }
  - { pattern: "an await of the plugin's initialize inside the serial slot with no timeout", absent_after_fix: true }
  - { pattern: "Permission.microphone / permission_handler (nothing else asks for RECORD_AUDIO)", absent_after_fix: true }
proposed_fix: >-
  Three budgets instead of one. Before the listen is issued the session waits
  startTimeoutFirstUse (45 s) until the engine is initialised, the 4 s native
  budget afterwards, 15 s on web (initialize prompts nothing there, the listen
  does). The service calls onListenIssuing synchronously right before
  engine.listen and the controller re-arms the listen budget AND opens the
  one-restart window there, so neither counts the dialog, the quiesce or the
  settle. The plugin's initialize is bounded by initializeTimeout (60 s) while
  it holds the serial slot (the memo stays, a late Allow completes it). Also
  closed from the same review (see the batch ledger for every finding): the
  retry now nulls the grace timers it cancels, a second host preempts a
  session still waiting in the slot, the host busy callback cannot break a
  session, a Stop commit asks for the keyboard before the screen is told the
  mic is off, a hidden tab or a preemption never takes the keyboard, the Log
  sheet shows its messages inline (a snackbar is drawn behind a modal sheet),
  and the fake engine now follows the plugin's own done filter.

touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "flutter analyze (whole project) 0 warnings, 0 errors; 209 targeted tests green; engine mutants M1 M2 M3b M4a M4b M4c M5 M6 M7 M8 M9 and host mutants H1 H2 H3 H4 H5a H5b H6 H7 H8 each reddened a named test (M3 was an equivalent mutant: the listen hook re-opens the window anyway)" }
  - { tier: 2_hive, status: not_applicable, evidence: "speech state is session-only; nothing is stored" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no cloud write" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched; the food text call is unchanged" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no Storage object" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: verified, evidence: "speech_to_text 7.4.0 Android Kotlin read: initializeIfPermitted requests RECORD_AUDIO and completeInitialize runs only from onRequestPermissionsResult (SpeechToTextPlugin.kt:503-520, 711-720); the Dart plugin swallows done while the latest result is partial (speech_to_text.dart:722-745). Device check T8 step 7 (slow Allow on a fresh install) is the founder's, OI-348 A19" }
  - { tier: 12_client_server_contract, status: verified, evidence: "no server contract changed; the nutrition Send path still calls the existing food_text_analysis through aiBreakdownProvider (food_logger_send_test)" }
impact_analysis: >-
  Account tier: the microphone input of the AI Coach composer and the nutrition
  Log sheet (a feature not yet released). Behaviour users will notice: the
  first-ever mic tap on a phone survives a slow answer to the system dialog;
  the Log sheet shows its messages under the field instead of out of sight.
  Rollback: revert the batch; nothing is persisted.
regression_test_planned:
  - test/core/speech_input_controller_behavioral_test.dart (group "first use: the permission dialog is not part of the listen budget"; retry grace tests; the busy-callback test; the pure speechEndWantsFocus table)
  - test/core/speech_input_options_test.dart (first-use and initialize relations)
  - test/ai_coach/coach_composer_speech_test.dart (typed prefix Send, focus before busy:false, hidden no focus)
  - test/widgets/food_logger_speech_test.dart (Scaffold-free harness: inline notice, notice clears, hidden no focus, Stop focus)
  - test/contracts/speech_privacy_copy_test.dart (no on-device claim in the three stale comment files either)
---

# First-use permission dialog vs the start timeout (abe150)

## Observation

PR 273's three B-pass reviewers each found the same P1 without seeing each
other's work: `SpeechInputController._start` armed `startTimeoutNative` (4 s)
and the 1.5 s restart window at the tap, then awaited `SpeechInputService.begin`,
whose first step is the plugin's `initialize`. On Android that call is where
RECORD_AUDIO is requested (nothing else in `lib/` or `pubspec.yaml` asks), and
its Future completes only when the user answers the dialog.

## Writers and readers

Writers: the controller's two arming sites and the service's `begin`. Readers:
both hosts' `_onSpeechEnd`, which show the "Could not hear you" copy for the
engine failure the timer produced.

## Why it survived

The plan reserved the long budget for web only ("the browser's permission
prompt"), the tests gated `listen`, never `initialize`, past 4 s, and the old
coach asked for the permission at screen mount with no timer, so nobody had
seen the new ordering fail.

## Fix and proof

See `proposed_fix`. Regression: the first-use group in
`test/core/speech_input_controller_behavioral_test.dart`. Mutation proof (rule
21): each fix's mutant reddened a named test (list in `touched_layers_checked`
tier 1). Honest limits: nothing was run on a device; whether the Android
activity is recreated under the dialog (the case `initializeTimeout` bounds) is
a hypothesis the code defends against, not an observation.
