---
reviewed_at: 2026-11-03T04:30:00+05:30
staged_against: 00ac3fa65cf7
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 9
verdict: accepted
verdict_note: two fresh Sonnet reviewers (lib+docs, test+fixtures); no P0/P1; every finding fixed, accepted or annotated below
---

# Code Review - 00ac3fa65cf7 (set-budget-flip, platform)

Two context-blind reviewers ran the lenses over the staged diff (A: lib/, scripts, registry, docs; B: test/, golden and baseline fixtures). Both returned the lens-by-lens "checked clean" lists; the findings are below, with the author's triage.

## Finding 1 - P2 - writer_reader_drift
- **file:line:** docs/sot_registry.yaml (physique-focus concept, reader entry for `periodization_engine.dart`, ~11176)
- **claim:** The entry still described `PeriodizationEngine.apply (bodyFocus +1 set)` as an unchanged mechanism; the flip deleted it.
- **verification:** `git show :lib/shared/repositories/plan_engine/periodization_engine.dart | sed -n 60,75p` (no `bodyFocus` parameter).
- **status:** accepted - fixed: the reader entry now names `generateV4` (`BudgetMuscleGroups.of(effectiveBodyFocus)` into the allocator's focus pass) and says the post-hoc +1 is deleted.

## Finding 2 - P2 - blast_radius_mismatch
- **file:line:** docs/ship_dark_pending_review.yaml (`resolved:` entry), closure yaml, registry prose
- **claim:** They cite `docs/plan-reviews/set-budget-flip.md`, which is not in the index of this commit.
- **verification:** `git ls-files docs/plan-reviews | grep set-budget-flip`
- **status:** accepted - by design: the plan-review record cannot be in the same commit as the review file it cites (it would move this hash). It lands in the next commit of the same branch, together with the SHA stamps; `check_plan_review_record_exists.dart` only needs it by the merge commit.

## Finding 3 - P3 - writer_reader_drift (stale prose)
- **file:line:** volume_titration.dart:4,151,185,204; training_history_analyzer.dart:193-205; plan_generator.dart (~317, ~454)
- **claim:** Comments still described the deleted unbudgeted path, the [8,20] clamp, `budgetOn`, and a garbled "PeriodizationEngine.set budget's" phrase.
- **verification:** `git grep -n -i -E "unbudgeted|budgetOn|\[8, ?20\]|under the flag" -- lib` (now only the plan_engine CLAUDE.md history sentence and a rationale comment in muscle_groups.dart).
- **status:** accepted - fixed (comments only).

## Finding 4 - P3 - missing_input
- **file:line:** edit_profile_screen.dart:~1983 (reschedule dialog `fmt`)
- **claim:** The chips read "Up to N min" but the change summary still reads "Session: 60 min -> 90 min".
- **verification:** `git show :lib/features/profile/screens/edit_profile_screen.dart | sed -n 1983,1986p`
- **status:** false_alarm - plan decision D4 (reviewed in both plan rounds) keeps the summary line unchanged; it describes the stored value, and the test pins it.

## Finding 5 - P2 - guard_without_its_mirror
- **file:line:** test/helpers/injury_floor_sweep_lib.dart (`kThinCeilings`, `expectNoThin`)
- **claim:** The ceilings were one-sided: a measured count far below its ceiling would pass, so "a ceiling only moves down" was not enforced.
- **verification:** re-ran the five sweep files after the fix: `flutter test test/plan_generator/injury_sweep_{a..e}_*_test.dart` (all 20 blocks pass with exact equality).
- **status:** accepted - fixed: `expectNoThin` now also fails when a count falls below its ceiling and names the value to lower it to; every recorded value was confirmed exact.

## Finding 6 - P3 - writer_reader_drift (vacuous anchor)
- **file:line:** test/contracts/session_duration_chip_wording_test.dart:19-24
- **claim:** The end marker was a comment that the same test strips, so the picker slice ran to the end of the file.
- **verification:** `grep -n "Physique Focus" lib/features/profile/screens/edit_profile_screen.dart` (a `//` line).
- **status:** accepted - fixed: the slice ends at the next `Widget _build...(` code token and a length bound pins it; mutating the chip label to `'$min min'` turns the test red.

## Finding 7 - P3 - asserted_fixture_value
- **file:line:** test/contracts/session_set_budget_consumers_test.dart; test/plan_engine_v4/shared_contracts_test.dart
- **claim:** One consumers test duplicated the first test of its group after `bodyFocus` was deleted; the phase-1 vs phase-5 test was near-tautological with stale multiplier comments; a group name still said keepAllSlots.
- **verification:** `grep -rn cycleMultiplier lib` (empty).
- **status:** accepted - fixed: the duplicate is deleted (focus is proved by `physique_focus_bringup_test.dart`), the phase test now asserts equality and says the multiplier is gone, the group is renamed.

## Finding 8 - P3 - guard_without_its_mirror
- **file:line:** test/plan_generator/baseline/baseline_scorecard.json
- **claim:** The re-freeze raises the tolerated fallback picks (1679 to 2009) and balance/volume fell; the gate checks only the mean overall score, unsafe, equipment and fallback count.
- **verification:** `git diff --cached -U0 -- test/plan_generator/baseline/baseline_scorecard.json`
- **status:** accepted - founder awareness only (closure SBF-SCORECARD-BASELINE records it; unsafe and equipment violations stay 0); listed in the PR.

## Finding 9 - P3 - guard_without_its_mirror
- **file:line:** test/contracts/injury_recheck_v14_contract_test.dart (~224)
- **claim:** The generator-level reach row for Bicycle Crunch / lower_back was dropped.
- **verification:** `grep -n "Bicycle Crunch" test/contracts/injury_recheck_v14_contract_test.dart` (line 156 keeps the `queryV4` filter proof).
- **status:** accepted - no persona in the search space reaches the row after the flip; the filter-level proof stays and the test's comment says why.

## Checked clean
- Every reader of the deleted symbols (`enable_session_set_budget`, `sessionSetBudgetEnabled`, `cycleMultiplier`, `keepAllSlots`, `_titrateWeek`) in lib, test, scripts, supabase, integration_test and the registry: none left.
- The three display fallbacks share one function and keep their numbers; template and custom days keep the 300 s warm-up; `PeriodizationEngine.apply` weeks 1-4 verified by reading the whole function.
- No secrets in the diff; `dart analyze` clean on every staged lib and test file; registry line ranges for the shifted files re-opened.
- Reviewer B could not finish the injury sweeps inside its time limit; the author ran them (exit 0, 177 tests with the scorecard gate and two contract files) after the fix.

## Founder triage notes
Finding 8 and the open founder calls are in the PR body.

## Tuning entry
- **2026-11-03** - blast-radius platform - 9 findings; 1 false_alarm; tuning: none (the guard_without_its_mirror lens found the one-sided ratchet again; a reviewer that cannot finish a long sweep should be told to read the helper's printed counts instead).
