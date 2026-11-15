---
reviewed_at: 2026-11-03T13:20:00+05:30
staged_against: 2837d1cdbd12
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, guard_without_its_mirror, blast_radius_mismatch, stale_claim_in_comment_or_doc, test_passes_for_the_wrong_reason]
findings_count: 4
verdict: accepted
verdict_note: one fresh Sonnet reviewer on the staged diff of the Working-to-Baseline display change; no P0/P1; every finding fixed or annotated below
---

# Code Review - 2837d1cdbd12 (a lifted deload week is shown as Baseline, platform)

The reviewer saw the first staged diff (hash 6b0af399e1c4); the fixes below changed the staged set, so the hash was recomputed (2837d1cdbd12) after the last edit.

## Finding 1 - P2 - writer_reader_drift (closure ledger)
- **file:line:** docs/audit/train-header-b2.closure.yaml:30-33
- **claim:** row THB-WORKING-WORD stays `blocked_on_user` although this diff is the product call.
- **verification:** read the row; Gate 40 counts every terminal row in `closed_count`.
- **status:** accepted - fixed: the row is closed in place (`closed_in_commit`, verification names the test file); the record commit stamps the SHA. Plan D4 updated (no new closure file: one item).

## Finding 2 - P2 - guard_without_its_mirror (tests)
- **file:line:** test/contracts/train_hero_week_mode_behavioral_test.dart:127
- **claim:** the stamp-less blob fallback with a `working` wave and a padded/upper-case `working` token were not pinned.
- **verification:** read the fixture (`waves` has the four base tokens only).
- **status:** accepted - fixed: added `'  WORKING '` -> Baseline and a stamp-less row in a lifted blob week -> Baseline. Mutation: restoring `'working': 'Working'` in the mapper now reddens 4 tests (2 before); confirmed applied with `grep -c`.

## Finding 3 - P3 - comment style
- **file:line:** lib/core/utils/week_mode_label.dart:5-8
- **claim:** the header comment had one over-long line.
- **status:** accepted - fixed: re-wrapped to the file's width; line count of the file is unchanged.

## Finding 4 - P3 - truth (stored coaching strings)
- **file:line:** lib/core/services/deload_evaluator.dart:211, :265
- **claim:** `overload_notes` and `weight_cue` still say "Working week".
- **verification:** `weight_cue` is read only by dev tools (lib/features/dev/plan_xls.dart:105, simulation_service.dart:677); pinned by deload_eval_behavioral_test.dart:334.
- **status:** false_alarm - these are stored coaching text, not the hero label, and no user-facing screen renders them; recorded in the plan ("Out of scope strings").

## Founder triage notes
Founder call for the label: "baseline" (2026-11-03).

## Tuning entry
- **2026-11-03** - blast-radius platform - 4 findings; 1 false_alarm; tuning: none (the closure-ledger staleness is covered by the existing writer_reader_drift lens; mirror-case pins for a re-labelled token were the P2 class already in the skill).
