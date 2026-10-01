---
reviewed_at: 2026-09-06T05:40:00+05:30
staged_against: c22e12c2
blast_radius: platform
reviewer: claude-opus-via-skill (context-blind subagent)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, self_attesting_artifact]
findings_count: 10
verdict: accepted
---

# Code Review (B-pass) — `c22e12c2` (branch `unitb-deload-reason`, platform)

Unit B: fix the stale week-4 deload reason, then flip `enable_deload_reason_line`
→ `disable_deload_reason_line`. Reviewed context-blind against the diff
`12e7906c..c22e12c2`. Every finding below was independently re-verified by the
author against source before action; dispositions are recorded per finding.

**Remediation landed in `23bc109c` and the round-2 follow-up commit.**

⚠ **Reviewer disclosure, kept because it changes how to read this file.** The
review ran while a second reviewer was concurrently mutation-testing the same
worktree (the author dispatched both at once — see the tuning-history note). The
B-pass therefore did **not** run the three claimed mutations, and its
`git status` observations were contaminated. Its one full-contracts run happened
before that window and its P0 was reproduced in isolation on a clean tree, so
that finding stands on its own evidence.

## Finding 1 — P0 — guard_without_its_mirror / rule 20 (deferred test failure)

- **file:line:** `test/contracts/readiness_flag_no_hive_default_test.dart:32-33`
- **claim:** The flip inverted `deloadReasonLineEnabled`'s catch-block default
  from `false` to `true`, but the test pinning that exact default was not
  updated. RED at HEAD: `Expected: false / Actual: <true>`. Its own comment reads
  *"Pinned here so a future flip has to change it deliberately"* — the tripwire
  built for this flip fired into a wall. Blast-radius is platform, so pre-push
  runs the full local suite and CI runs it again; this blocks the push and
  reddens `main`.
- **verification:** `flutter test test/contracts/readiness_flag_no_hive_default_test.dart`
- **status:** accepted — fixed in `23bc109c`. Reproduced independently before
  acting. The comment now records that a getter has two halves living in two
  files: change one, grep for the other.

## Finding 2 — P1 — guard_without_its_mirror (scope overclaim)

- **file:line:** `lib/core/services/workout_schedule_read_service.dart:1133-1140`,
  plus the same claim in `deload_evaluator.dart`, `plan_engine_flags.dart`,
  `docs/sot_registry.yaml` and the diagnose-doc.
- **claim:** The reader validates against the blob, so it can only detect
  staleness introduced by a path that rewrites the blob. **The AI-coach regen
  never touches `current_plan`** — `RegeneratePlanPlanner` produces rows,
  applied via `WorkoutWriteService.upsertScheduled`. So "one seam covers all
  three paths" is false; it covers two.
- **verification:** `grep -c "current_plan\|_planKey\|week_plans" lib/features/ai_coach/services/regenerate_plan_planner.dart lib/core/services/workout_write_service.dart` → 0 and 0
- **status:** accepted with a corrected framing. The fact is confirmed. The
  *consequence* is not what the finding states: because node and line both read
  the blob, that path cannot make them contradict — it leaves both stale
  together. That is a pre-existing phase-arc defect (shipped with flag 3 on
  2026-09-05), **filed as OI-166** with options and a recommendation, since the
  honest repair changes an AI-coach WRITE path. All five overclaiming sites
  corrected.

## Finding 3 — P2 — self_attesting_artifact / §4.12.4

- **file:line:** `docs/ship_dark_pending_review.yaml:165-181`
- **claim:** The flag is still under `pending:` with `flip_reviewed: false` and a
  note calling the defect unfixed — in the commit that flips it. The file's own
  header mandates updating it in the same commit as the flip-on.
- **status:** accepted — moved to `resolved:` in the same commit as the
  plan-review record it points at, so the pointer is never written ahead of its
  target.

## Finding 4 — P2 — writer_reader_drift (auto-loaded doc)

- **file:line:** `lib/shared/repositories/plan_engine/CLAUDE.md:77-88`
- **claim:** This nested `CLAUDE.md` is auto-loaded for the subtree containing
  `plan_engine_flags.dart` and still documents the OLD contract — the key
  stamped "with a pure non-shaming one-liner" (now a map), the reader with no
  mention of validation or the kill-switch rename.
- **status:** accepted — rewritten with the value shape, the equality check, the
  kill-switch name, and the new behavioral test.

## Finding 5 — P2 — stale_or_wrong_citation

- **file:line:** `lib/features/train/CLAUDE.md:68` + 9 more sites
- **claim:** The diff moved `deload_evaluator.dart`'s blob rewrite `:231 → :244`
  and its length guard `:228 → :241`; ten live citations still point at the old
  lines, including the row this diff rewrote by hand.
- **status:** accepted — 18 citations repointed across `lib/`, `test/` and the
  SoT registry. Historical records (closure YAMLs, the prior diagnose-doc, the
  prior batch's plan) deliberately left as written.

## Finding 6 — P3 — stale_or_wrong_citation

- **file:line:** `lib/features/train/widgets/phase_arc_strip.dart:61-68`
- **claim:** The comment above the flag gate still says SHIP-DARK.
- **status:** accepted — rewritten; the "flag checked FIRST" sentence kept,
  since it is still true and still load-bearing.

## Finding 7 — P3 — guard_without_its_mirror (normalisation asymmetry)

- **file:line:** `lib/core/services/workout_schedule_read_service.dart:1146`
- **claim:** The guard compared raw tokens while `PhaseArcStrip.labelFor`
  lowercases and trims, so `' deload '` would render `DELOAD` on the node and
  silently suppress the line. Fail-safe direction, but guard and display
  disagreed about sameness.
- **status:** accepted — both sides now normalised. Round 2 found this also
  closed a real hole: `{'week_character':'  '}` against `waves[3]=='  '`
  compared equal RAW and rendered a reason under an em-dash-floored node.

## Finding 8 — P3 — guard_without_its_mirror (comment misstates the mechanism)

- **file:line:** `lib/features/dev/dev_panel_screen.dart:343-345`
- **claim:** The comment credits `deloadReasonProvider` for the rebuild. The flag
  is read in `PhaseArcStrip.build`, non-reactively; what rebuilds is
  `phaseArcProvider` emitting a new `PhaseArcData` identity, which works only
  because that class has no `==` override.
- **status:** accepted — comment now names the real chain and the identity
  dependency it rests on.

## Finding 9 — P3 — asserted_fixture_value (generated-artifact damage)

- **file:line:** the diagnose-doc's `concept:` → `docs/diagnoses/INDEX.md:1133`
- **claim:** `concept:` is specified as a name from `docs/sot_registry.yaml`;
  here it was a three-paragraph block scalar, which `build_bug_index.dart`
  renders verbatim into a markdown table cell, breaking the row and degrading
  concept-grouping — the file §4.1.5 tells every session to grep first.
- **status:** accepted — `concept: deload_decision_reason`; the prose moved into
  the body; index regenerated and the row verified single-line.

## Finding 10 — P3 (informational) — self_attesting_artifact

- **file:line:** `docs/audit/open_issues.md:255-256`
- **claim:** The committed board asserts, present tense, a plan-review record
  that does not exist at that commit.
- **status:** accepted — the record now lands before any merge, and the batch's
  ordering rule is recorded: never commit a pointer ahead of its target.

## Lenses clean

`function_exception_swallow` (0 `functions.invoke` in the diff),
`secrets_in_tree` (0), `unawaited_no_error_sink` (0 added),
`blast_radius_mismatch` (`platform`, matching every claim),
`missing_input` (no new path/asset dependency), and the `writer_reader_drift`
sweep for the String→Map value change — the only writer and only reader were
enumerated, and every `workoutBox` iterator key-filters before type-filtering
except `ai_snapshot_builder.dart`, where the newly-admitted map is inert.

## Founder triage notes

All ten accepted; nine fixed in-batch, one (Finding 2's underlying defect)
filed as OI-166 because it changes a different subsystem. Round 2 subsequently
found a P1 that this pass and plan-review round 1 both missed — a copy branch
made user-visible by the flip that stated a falsehood — recorded as diagnose
`d9e1b4` and as tuning 2/3 in the code-review skill.
