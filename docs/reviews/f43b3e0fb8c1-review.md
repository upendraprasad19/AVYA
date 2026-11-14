---
reviewed_at: 2026-11-06T11:20:00+05:30
staged_against: f43b3e0fb8c1
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 8
verdict: accepted
verdict_note: no P0 or P1; the six actionable findings are fixed in this commit, two are stated residue
---

# Code Review (B-pass) — f43b3e0fb8c1

Branch `oi454-quads` (merged up to date with `origin/main` 1118d3b1), diff `origin/main...HEAD` of the fix commit `0c203f77`
plus the sync merge `d7c019cf`; this file's commit carries the review fixes. One fresh context-blind Sonnet reviewer, all
eight lenses, an exhaustive read-only command list (two named test files and `dart analyze` of one file allowed). It reported
no P0 and no P1.

## Finding 1 — P2 — guard_without_its_mirror (root CLAUDE.md 4.6)
- **file:line:** `plan_generator.dart:289`, `split_resolver.dart:1004`, `split_resolver.dart:396`
- **claim:** a plan-engine change shipped always on with no kill switch although the platform tier lists `feature_flag` (4.6).
- **verification:** `git diff origin/main...HEAD -- lib | grep -n "PlanEngineFlags\|configBox"` printed nothing before the fix.
- **suggested-fix:** a `disable_quad_legs_b` switch, or a recorded founder waiver.
- **status:** accepted. Fixed: `PlanEngineFlags.quadLegsBEnabled` (default ON, read once in `generateV4`), `selectV4(quadLegsB:)`,
  the Legs B slot as a conditional, and the credit flag `!(quadLegsB && hasQuadLegsBSplit)`; three tests plus mutants K1 to K4.

## Finding 2 — P2 — asserted_fixture_value: claims the reviewer could not run
- **claim:** the 60 golden hash values, `scorecard_gate_test`, the injury sweeps (`kThinCeilings`) and
  `keep_all_slots_selection_test` (a new slot type with the core-list pool ON) were not run by the reviewer.
- **status:** accepted, proven by running them on the final tree: golden compare on the merged tree passed (7 tests); the
  plan_generator / plan_engine_v4 / allocator / consumers run passed (417, 0 failed) before the review fixes; the full local
  suite on the final tree is run before the merge and named in the PR.

## Finding 3 — P3 — writer_reader_drift: the order of `primary_muscles` is now a contract
- **file:line:** `budget_muscle_groups.dart:71-77`, `docs/reference/exercise-library.md`
- **claim:** nothing pinned the muscle order the rule reads; a library batch that reorders a row silently changes the credit.
- **status:** accepted. Fixed: a census test (the 7 not-quad-first rows and Trap Bar Deadlift are the only known exceptions,
  a new one fails with a message), and the order rule is documented in `exercise-library.md`.

## Finding 4 — P3 — blast_radius_mismatch: dangling plan-review record
- **claim:** the diagnose doc and plan cite `docs/plan-reviews/oi454-quads.md`, which did not exist yet.
- **status:** accepted. The record lands in its own later commit (it is not hash-excluded; SKILL.md section 3).

## Finding 5 — P3 — blast_radius_mismatch: hand-edited context baseline
- **claim:** `backups/context_artifact_sizes.json` carried one hand-typed entry and stamp.
- **status:** accepted. Fixed: re-recorded by `check_context_artifact_budget.dart --record` (every entry, one clock); the
  `OPEN_INDEX.md` entry is retained.

## Finding 6 — P3 — closure rows carry a branch label, not a SHA
- **claim:** `SBF-QUADS-FLOOR` and `FLOOR-CO-GROUP-TIME` named `branch oi454-quads`, dangling once the branch is deleted.
- **status:** accepted. Fixed: both cite the fix commit `0c203f77765c4780b279dfbc44af101aeb1f10e3`, which stays in main's history.

## Finding 7 — P3 — asserted_fixture_value: the `cap_limited` pin did not pin the stated cause
- **claim:** `belowFloor['Quads']` is the allocator's residual label; nothing asserted "both quad compounds at the 5-set maximum".
- **status:** accepted. Fixed: the sweep asserts the two quad compounds of `intermediate|basic_gym|90` equal
  `SessionBudget.maxSetsPerExercise`.

## Finding 8 — P3 — guard_without_its_mirror: untested mirror personas, one cosmetic issue
- **claim:** untested: a repeat phase with pins, 30 / 45 minutes, hip and lower-back injuries, the `glutes_legs` focus; and the
  day focus text still reads "Hamstring + glute focus" on a day that holds a squat.
- **status:** residue, stated in the diagnose doc and the plan: the gate covers 30 and 45 minutes with the core-list pool ON; a
  repeat phase replays a pre-change plan's Legs B until a fresh advance; changing the focus text moves the same 60 golden keys
  and is display copy. Nothing here makes the new code worse than the old for the case, except the stated knee-injured one
  (66 matching library rows, none knee-safe, versus 11 of 12 knee-safe glute isolation rows).

## Founder triage notes
Triaged by the author in session (the founder's standing direction is to continue autonomously); all findings are accepted or
stated. No false alarms.

## Tuning entry
- **2026-11-06** - blast-radius platform - 8 findings; 0 false_alarm; tuning: none (the lens set found the missing kill switch and the unpinned order contract; the reviewer's brief should list the golden, scorecard and sweep tests as runnable, because the VPS excludes the golden tag and a reviewer who cannot run them can only mark them unverified).
