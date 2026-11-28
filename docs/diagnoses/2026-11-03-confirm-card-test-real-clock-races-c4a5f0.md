---
bug_id: c4a5f0
date: 2026-11-03
batch: oi-450-flaky-confirm-card (test-only; no lib/ change)
status: fixed
tier: s_fix
blast_radius: feature
symptom: |
  `test/ai_coach/workout_log_confirm_card_saved_signal_test.dart` failed intermittently in loaded full-suite runs (OI-450: "a timed set with a bad duration saves, the day mark fails") and passed alone 52/52. Reproduced by looping the whole file under CPU load: 6 distinct failing sites across the loops (the OI's own test at the long-hold midpoint, "skipped leftover" at the same midpoint, "a completed status with no wlog_" and "header ... slot is empty" asserting the saved card, "(f) ... ignores CONFIRM for its first moment", and "auth flip on a retry" throwing UnmountedRefException after the test completed). Not a race in the save path: every site is a test assertion against a real clock.
concept: coach_workout_card_saved_state
sot_registry_entry: coach_workout_card_saved_state
writers:
  - { file: lib/features/ai_coach/providers/ai_coach_provider.dart, method_or_widget: "WorkoutDraftNotifier.markSaved (starts the REAL hold Timer; 150/500 ms in the old test setUp)", line: 1943 }
  - { file: lib/features/ai_coach/services/conversational_log_handler.dart, method_or_widget: "submitWorkoutDraft finally -> notifier.endSubmit (runs after the test's container was disposed when the draft was null and the helper stopped waiting)", line: 446 }
  - { file: lib/features/ai_coach/widgets/workout_log_confirm_card.dart, method_or_widget: "_submit tap guard: Stopwatch _sinceMount vs kHeldCardTapGuard (500 ms real time)", line: 94 }
readers:
  - { file: test/ai_coach/workout_log_confirm_card_saved_signal_test.dart, method_or_widget: "every `expect(s.draft...)` on the saved card, the two long-hold midpoint checks, untilIdle/openGate, and test (f)", line: 1 }
hive_key_prefix: none
hive_key_formula: "not applicable: no stored value changes meaning"
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/ai_coach/workout_log_confirm_card_saved_signal_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "unchanged: no lib/ change."
forbidden_patterns_checked:
  - { pattern: "a wall-clock 'still present at time T' assertion against a real Timer in a widget test", absent: true }
proposed_fix: |
  Test-only. (1) The saved-card hold is `kNeverFires` (1 h) in setUp, so assertions on the saved card cannot race it; tests that watch the card clear call `useFiringHold()` and assert only the END state (a stall delays the clear, never undoes it). (2) The two "long hold" midpoint timing checks became `expect(holdAsked, [true])` (the argument the notifier passes), plus a pin of the shipped durations 1500/4000 ms. (3) The first saved test was split: assertions vs "the slot is empty after the hold". (4) Test (a), whose subject is the hold ending, uses one explicit 1500 ms hold. (5) `openGate` waits an extra 400 ms when the draft is null (after an auth flip `untilIdle` sees nothing to wait for). (6) Test (f) starts its own Stopwatch before the card mounts and asserts "the immediate tap is ignored" only while that stopwatch is under 480 ms (it never under-counts the guard's elapsed time); after a longer stall the guard has legitimately expired and the test ends early.
regression_test_planned: |
  The file itself is the regression test: 20 consecutive runs under 4 CPU burners on 4 cores passed (OI-450 done-when). Widening the margins alone (150/500 to 1000/3000 ms) was tried first and still failed once in 10 runs at 8 burners, which is why the design moved to a never-firing hold.
mutation_proof: |
  Rule 21, scratch-copy protocol (backup, mutate, run, restore, diff --stat clean). Mutant 1: `final hasNote = !dayMarked || skipped.isNotEmpty;` to `final hasNote = false;` in markSaved: APPLIED (grep -c 1), exactly the two long-hold tests went RED (2 failed). Mutant 2: remove the `_sinceMount.elapsed < kHeldCardTapGuard` guard line in workout_log_confirm_card.dart: APPLIED (grep -c 1), exactly test (f) went RED (1 failed). Mutant 3 (earlier design): shrinking the wide hold to 200 ms reddened both midpoint tests. Residual: a run that stalls past 480 ms before the tap skips test (f)'s one assertion (the guard goes unchecked in that run, never wrongly red).
impact_analysis: |
  Test file only. No production behavior, no writer/reader contract, no registry range moves.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "Writers/readers named above read at the cited lines; lib/ diff is empty (git diff --stat -- lib); the test file passes 54/54 unloaded and 20/20 under load." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive contract changed." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "Not involved." }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "Not involved." }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function changed." }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "Not involved." }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "Not involved." }
  - { tier: 9, name: "Storage buckets", status: not_applicable, evidence: "Not involved." }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "Not involved." }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "Not involved." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No client/server contract touched." }
recurrence: "Not a recurrence of a fixed product bug class. Same family as the memory notes on tests that pass for the wrong reason and on a test clock equal to the authoring day: a wall-clock assertion that only holds on an idle machine."
related_bugs: []
---

# c4a5f0 - the confirm-card test raced real clocks

## What happened

The saved workout card clears itself after a real `Timer` (1.5 s, 4 s with a day line in production; 150/500 ms in the test). The test asserted the card was still there some hundreds of milliseconds later. On an idle machine that holds; when the machine stalls for longer than the margin the timer fires first and the assertion sees a null draft.

## The fix

Remove the race instead of widening the margin: the timer never fires in tests that look at the saved card, and tests that watch it clear assert only the final state.

## Not covered

- Test (f) skips its one "tap inside the guard window is ignored" assertion in a run that stalls past 480 ms; a lib seam (injectable guard clock) would make it deterministic and was declined by the founder (option A, 2026-11-03).
- `openGate`'s 400 ms settle after an auth flip is still a wall-clock wait (about 20 times the old 20 ms); a debug hook on `submitWorkoutDraft` completion would remove it.
