---
bug_id: e8f4a1
date: 2026-09-15
batch: Internal-testing observation batch, session 2 (Obs 5 follow-up)
status: fixed
blast_radius: feature
symptom: |
  Raised by the founder as the still-unanswered half of Obs 5 (diagnose
  6c2f91): "whether to also add a 'resume in-progress workout' indicator on
  the Train tab and/or a confirmation before startWorkout() discards live
  progress — the actual mechanism that destroys logged sets once ejected by
  any means." 6c2f91 fixed the specific double-pop navigation bug that
  ejects a user from the active-workout screen, but its own impact_analysis
  found that ejection alone never destroys progress (ActiveWorkoutData
  survives navigating away). The actual data-loss mechanism is that the
  Train/Home START buttons give no indication a session is already live,
  so a user ejected by ANY means (this bug, backgrounding, an accidental
  tap) naturally re-taps START, and `startWorkout()` silently overwrites the
  live session with zero confirmation.
concept: active_workout_resume_guard
sot_registry_entry: |
  Not applicable to docs/sot_registry.yaml — no new Hive key, cloud table,
  or persisted field. `hasInProgressSession` is a pure derived getter over
  three fields the `ActiveWorkoutData` provider already holds in memory
  (workoutDay / isComplete / isSaved); the guard dialog is UI-only
  navigation logic gating an existing writer call. Documented instead as a
  new row in lib/features/train/CLAUDE.md's SoT-concept table (that file's
  own convention already covers session-only, non-Hive-backed concepts —
  e.g. session_detraining_cut, readiness_checkin).
writers:
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "ActiveWorkoutNotifier.startWorkout — unconditional, no-confirmation full reset of ActiveWorkoutData (the writer this fix guards)", line: 1320 }
  - { file: lib/features/train/providers/train_provider.dart, method_or_widget: "ActiveWorkoutData.hasInProgressSession — new derived getter", line: 1242 }
readers:
  - { file: lib/features/train/widgets/readiness_sheet.dart, method_or_widget: "beginWorkoutWithReadiness — reads hasInProgressSession and gates the startWorkout() call behind showResumeOrDiscardGuard", line: 44 }
  - { file: lib/features/train/screens/train/hero_cards.dart, method_or_widget: "_buildWorkoutHeroCard — isResuming flips the WardButton label to RESUME WORKOUT", line: 92 }
  - { file: lib/features/train/screens/train/planned_expansion.dart, method_or_widget: "_buildPlannedExpansion — isResuming flips the WardButton label to RESUME WORKOUT", line: 9 }
  - { file: lib/features/home/screens/home_screen.dart, method_or_widget: "the one real TodayWorkoutCard construction that renders START — passes isInProgress through to _HeroCta", line: 899 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/contracts/active_workout_resume_guard_behavioral_test.dart
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — pure in-session Riverpod provider state (ActiveWorkoutData) plus one Hive delete (ActiveWorkoutPersistence.clearState, already user-scoped by its existing box) on the discard path; no cross-account read introduced."
forbidden_patterns_checked:
  - { pattern: "beginWorkoutWithReadiness calling notifier.startWorkout(day, ...) without first checking hasInProgressSession", absent: true }
proposed_fix: |
  Add ActiveWorkoutData.hasInProgressSession (true whenever a day is
  assigned and neither completeWorkout() nor cancelWorkout() has run
  since). Gate the ONE funnel every START button routes through —
  beginWorkoutWithReadiness — behind it: when a live session exists, show
  a "Workout Already in Progress" dialog (RESUME / DISCARD & START FRESH,
  dismiss-as-RESUME as the safe default) before calling startWorkout(); on
  DISCARD, also clear the AI-coach mid-workout snapshot
  (ActiveWorkoutPersistence, A7 parity with the existing _showCancelDialog/
  _showFinishDialog fire-and-forget pattern) so it doesn't outlive the
  session it describes. Surface the same awareness on all three real START
  surfaces (Train hero card, Train planned-day card, Home today's-workout
  card) by flipping their button label to RESUME/RESUME WORKOUT whenever
  hasInProgressSession is true, so a user is warned before they even tap.
regression_test_planned:
  - test/contracts/active_workout_resume_guard_behavioral_test.dart
impact_analysis: |
  Scoped to the START/RESUME decision point only. beginWorkoutWithReadiness
  is confirmed (by an existing code comment at home_screen.dart calling it
  "the only two startWorkout callsites") to be the single funnel every
  START button in the app routes through, so gating it there covers Train's
  hero card, Train's planned-day expansion, and Home's today's-workout card
  with one change — no other call site invokes ActiveWorkoutNotifier.
  startWorkout directly.

  Not affected: completeWorkout() and cancelWorkout() (the two writers that
  legitimately end a session) — hasInProgressSession is defined in terms of
  their having NOT run, so finishing or cancelling a workout normally still
  clears the flag exactly as before, with no guard shown on the next START.
  The readiness-sheet flow itself (readiness level prompt) is untouched —
  the guard runs strictly before it, and only when a live session exists;
  with PlanEngineFlags.readinessEnabled off or on, the post-guard behavior
  is identical to pre-fix.

  Dismissing the dialog (tapping the barrier) resolves to RESUME, not
  DISCARD — deliberately the safe default, since a stray tap outside the
  dialog must never be read as consent to discard logged sets.

  DISCARD & START FRESH intentionally does still discard the old session's
  in-memory state (that is the whole point of the button) — this fix does
  not add a way to preserve two concurrent sessions, only a confirmation
  step and an explicit choice before the existing silent-overwrite behavior
  fires.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "hasInProgressSession getter + beginWorkoutWithReadiness guard + showResumeOrDiscardGuard dialog + 3 RESUME-label call sites added; flutter analyze lib/ and flutter analyze lib/ test/ both exit 0 (only pre-existing info-level issues, none in touched files)." }
  - { tier: 2, name: "Hive (local state)", status: fixed_in_this_batch, evidence: "Discard branch now clears ActiveWorkoutPersistence's mid-workout snapshot (workoutBox key 'active_session') via unawaited(ActiveWorkoutPersistence.clearState()), matching the pre-existing _showCancelDialog/_showFinishDialog fire-and-forget pattern (A7 parity) — pinned by the contract test's final group via source-grep on the guard block, since the Hive write itself has no public seam to pump through a widget test without hitting the documented real-disk-I/O-in-a-testWidgets-body hang." }
---

## Summary

Follow-up to Obs 5 (diagnose `6c2f91`). That diagnose-doc's own
`impact_analysis` identified — but deliberately did not fix — a second,
compounding gap: once a user is ejected from the active-workout screen by
any means (that double-pop bug, backgrounding the app, an accidental
back-tap), the Train tab and Home tab give no indication a session is still
live, so the natural next action is re-tapping START. `ActiveWorkoutNotifier.
startWorkout()` performs an unconditional, no-confirmation full reset of
`ActiveWorkoutData` — this is the mechanism that actually destroys logged
sets, not the ejection itself.

Raised back to the agent by the founder in this session ("suggest. and after
your fix what will happen now?"), the agent recommended adding both a resume
indicator and a discard-confirmation guard; the founder approved
("Want me to implement the resume indicator + confirmation guard now: ok").
This diagnose-doc covers that implementation.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "startWorkout", "resume", "active
workout", "discard" — no prior fix touches this decision point. The only
related entry is `6c2f91` itself, whose own `impact_analysis` names this
exact gap and explicitly defers implementing it to a founder decision (which
this doc closes). Not a recurrence of a previously-diagnosed bug.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer:** `ActiveWorkoutNotifier.startWorkout`
(`lib/features/train/providers/train_provider.dart:1320`) unconditionally
sets `state = ActiveWorkoutData(workoutDay: day, exercises: exercises,
elapsedSeconds: 0, checkedSets: {}, ...)` — a full reset — with no check for
whether `state` already represents a live, unfinished session.

**Readers (pre-fix):** every START button —
`lib/features/train/screens/train/hero_cards.dart`,
`lib/features/train/screens/train/planned_expansion.dart`, and
`lib/features/home/widgets/today_workout_card.dart` (via
`lib/features/home/screens/home_screen.dart`) — called
`beginWorkoutWithReadiness` → `notifier.startWorkout(day, ...)` with no
distinction between "no session running" and "a session is already running
with logged sets", and rendered an identical `START WORKOUT`/`START` label
in both cases.

The gap is a missing GUARD at the one funnel every START button shares
(`beginWorkoutWithReadiness`, confirmed the sole call site by an existing
code comment in `home_screen.dart`), not a writer/reader field-name drift —
the writer and readers all agree on the shape of `ActiveWorkoutData`; what's
missing is a check of its CURRENT value before overwriting it.

## Fix

1. **New derived getter** `ActiveWorkoutData.hasInProgressSession`
   (`train_provider.dart:1242`) — true whenever `startWorkout()` has
   assigned a day and neither `completeWorkout()` nor `cancelWorkout()` has
   run since (`workoutDay != null && !isComplete && !isSaved`).
2. **Guard the funnel.** `beginWorkoutWithReadiness`
   (`readiness_sheet.dart:41-67`) now checks `hasInProgressSession` first.
   If true, it awaits `showResumeOrDiscardGuard(context)` — a new
   `AlertDialog` (styled to match the existing `_showCancelDialog`
   precedent in `finish_dialog.dart`: `AppColors.card`/`.line2`, `AppTypography.
   h2`/`.bodySm`/`.mono`) offering **RESUME** or **DISCARD & START FRESH**.
   Any outcome other than an explicit discard choice (including dismissing
   the dialog via the barrier) returns early, leaving the live session
   untouched. Only an explicit `discardAndStartFresh` choice falls through
   to the existing `startWorkout()` call.
3. **A7 parity on discard.** When the user explicitly discards, the
   AI-coach mid-workout snapshot (`ActiveWorkoutPersistence`, a separate
   Hive record of the session being thrown away) is cleared via
   `unawaited(ActiveWorkoutPersistence.clearState())` — matching the
   pre-existing fire-and-forget pattern already used by
   `_showCancelDialog`/`_showFinishDialog` in `finish_dialog.dart`, so the
   snapshot never outlives the session it describes.
4. **Resume awareness before the tap.** All three real START surfaces now
   read `hasInProgressSession` and flip their label to `RESUME WORKOUT`
   (Train hero card, Train planned-day expansion) or `RESUME` (Home
   today's-workout card) whenever a session is already live, so a user sees
   the warning before they even tap, not just after.

## Verification

`test/contracts/active_workout_resume_guard_behavioral_test.dart` — 10
tests:
- 4 pure unit tests on `hasInProgressSession` (fresh/default state, mid-day,
  post-complete, post-save).
- A `beginWorkoutWithReadiness` integration group driving the real function
  against a real `ProviderContainer` + Hive (user-scoped, `disable_readiness`
  set so the readiness sheet doesn't also need mocking): no-live-session
  starts immediately with no dialog; RESUME leaves the old day and its
  checked sets untouched and never starts the new day; dismissing the
  dialog via the barrier resolves as RESUME (the safe default); DISCARD &
  START FRESH starts the new day and drops the old session's checked sets.
- A source-grep test on the discard branch specifically, asserting it
  contains `ActiveWorkoutPersistence.clearState()` — pinning the A7-parity
  call, which has no public seam to pump through a widget test without
  hitting the documented real-disk-I/O-in-`testWidgets` hang
  (`docs/playbook/common-pitfalls.md`).

**Mutated and run** (rule 21), twice:
1. `hasInProgressSession` temporarily replaced with `=> false` — reddened
   5 of 10 tests (the 3 non-fresh-state unit tests plus the 2 integration
   tests whose scenario depends on a live session being detected), leaving
   the fresh-state unit test and the no-live-session integration test green
   as expected. Confirmed the mutation applied via `grep -c`, then restored.
2. The `unawaited(ActiveWorkoutPersistence.clearState());` line deleted
   entirely — reddened exactly 1 of 10 tests, the source-grep test.
   Confirmed via `grep -c` that the line was actually absent (0 occurrences)
   before trusting the red result, then restored.

`flutter analyze lib/` and `flutter analyze lib/ test/` both exit 0 — only
pre-existing info-level issues, none in any file touched by this fix.
Combined regression run across this session's fixes (`exercise_card_weight_
display_format_test.dart`, `submissions_load_timeout_behavioral_test.dart`,
`swap_exercise_logging_type_behavioral_test.dart`, `swap_add_exercise_
double_pop_behavioral_test.dart`, `active_workout_resume_guard_behavioral_
test.dart`) — 27/27 passing, `flutter test` process exit code 0.

## Related

Direct follow-up to `6c2f91` (Obs 5) — see that diagnose-doc's
`impact_analysis` for the original identification of this gap. Not a
recurrence of any other previously-diagnosed bug (see Bug-history lookup
above).
