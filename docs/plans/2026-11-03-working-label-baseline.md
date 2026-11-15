# Plan: a lifted deload week shows the word `Baseline` (not `Working`)

Date 2026-11-03. Branch `working-label-baseline`. Tier M, blast radius `account` for the mapper (`lib/core/utils/`), `platform` for the diff because one comment in `plan_engine_flags.dart` is corrected. Execution mode: INLINE (one worktree, one writer), decided at start.
Founder decision 2026-11-03: "working label : baseline" (closure row `THB-WORKING-WORD` in `docs/audit/train-header-b2.closure.yaml`, `blocked_on_user` until now).

## Problem
After `deload_evaluator.dart` lifts a deload week, the week's rows carry `week_character: 'working'`. The Train hero and the Home card print that as `Working`, a fifth word beside the four the founder named (Baseline, Overreach, Peak, Deload). The founder chose to show such a week as `Baseline`.

## Writer / reader
- Writer of the stamp (UNCHANGED): `lib/core/services/deload_evaluator.dart:187` (`newRow['week_character'] = 'working'`) and `:209` (blob `wp['week_character']`). The stored token stays `working`: guard 6 (`deload_evaluator.dart:91`) and `plan_week_for_date`, the day-swap engine and rules all key on the stored token, so changing it would break the lifted-week detection.
- Reader / display (CHANGED): `weekModeLabel` in `lib/core/utils/week_mode_label.dart` (`'working': 'Working'` becomes `'working': 'Baseline'`). The only callers: `WorkoutScheduleReadService.weekModeForRow` (`lib/core/services/workout_schedule_read_service.dart:1517`), which feeds Train's hero (`hero_cards.dart`) and Home's today card (`home_screen.dart`). Both call the same resolver, so they cannot disagree.

## Decision
D1. Change only the display word in `weekModeLabel`. Any other token and the unknown-token fallback are untouched.
D2. Update the tests that pin the old word: `test/contracts/train_hero_week_mode_behavioral_test.dart` lines 68 (mapper) and 127 (service resolver through `weekModeForRow`). The deload-evaluator tests assert the STORED token `working` and stay as they are (they prove the stamp is unchanged).
D3. Correct every comment/doc that names the old label (grep sweep, CLAUDE.md 4.9): `week_mode_label.dart` header, `home_screen.dart`, `hero_cards.dart`, `plan_engine_flags.dart:213`, `lib/features/train/CLAUDE.md` (the `week_character_display` row), and `docs/naming_conventions.md:300` (the `week mode` glossary row; found by review round 1, the sweep now covers all of `docs/` except history files).
D4. Close `THB-WORKING-WORD` IN PLACE in `docs/audit/train-header-b2.closure.yaml` (a `blocked_on_user` row left stale would be false; `closed_count` already counts every terminal row, so it stays 6) and add the plan-review record `docs/plan-reviews/working-label-baseline.md`. No new closure file: one item. (B-pass P2-1.)
D5. Two mirror pins added by the B-pass (P2-2): a padded upper-case `'  WORKING '` token, and a stamp-less row in a lifted blob week (`week_plans[3].week_character == 'working'`) reads `Baseline` through the fallback path.

## Mutation check (CLAUDE.md 4.4 rule 21)
Restore `'working': 'Working'` in the mapper: the two pins in `train_hero_week_mode_behavioral_test.dart` must go red (measured 2026-11-03: 27 passed, 2 failed). Confirmed the mutant applied with `grep -c`.

## Value-semantics sweep (4.1.5 point 3)
`grep -rn "Working" lib test supabase/functions docs` (history files excluded: docs/plans, docs/reviews, docs/plan-reviews, closure ledgers, diagnoses, bug-classes): no Edge Function, no other lib reader and no widget test prints the label; `sot_registry.yaml:10486/10516` describe the stored token `working`, not the display word (no change). Nothing outside Dart reads the display word.

## Out of scope strings (review round 1)
`deload_evaluator.dart:211` (`overload_notes`: 'Working week - recovered...') and `:265` (`weight_cue`: 'Working week - full sets and reps') are stored coaching strings, not the hero label; only dev tools (`lib/features/dev/plan_xls.dart:105`, `simulation_service.dart:677`) read `weight_cue`. They stay, and `deload_eval_behavioral_test.dart:334` pins one of them.

## Risks
- Both cards show `Baseline` for a lifted week 4 although the sets are the reduced-deload-lifted ones: intended by the founder.
- A future reader that compares the displayed string with `'Working'` would silently miss: none exists (sweep above).

## Out of scope
Changing the stored token, adding a sixth word, or touching `deload_evaluator.dart`.
