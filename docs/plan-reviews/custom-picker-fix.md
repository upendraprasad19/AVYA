# Plan review record — custom-picker-fix

branch: custom-picker-fix
reviewed_at: 2026-09-17
review_rounds: 2
blast_radius: platform
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/75d765030e86-review.md
hermes: n/a

## Scope

Custom exercises invisible in all three exercise pickers (swap / +Add /
template builder): the creation sheet hardcodes `equipment_needed: []` and
`primary_muscles: []`; the OI-89 capability predicate fails CLOSED on an
unparseable requirement; the three pickers applied it to the custom list.
Founder-approved plan: reader-side exemption (Option A) + muscle capture +
edit mode; Option B (equipment field + data backfill) filed as OI-211;
custom-food search gap filed as OI-212.

## Ground truth verified

Every file:line claim in the plan was read from source by both reviewers and
the main thread before implementation: `equipment_capability.dart:31-35`
(fail-closed), `create_custom_exercise_sheet.dart:83-84` (hardcoded empty
lists), `exercise_swap_sheet.dart:90-98`, `exercise_picker_sheet.dart:39-47`,
`template_builder_screen.dart:518-553`, `workout_repository.dart:1325`
(AI writer already captures muscles), `workout_write_service.dart:995-1035`
(canonical upsert writer), `sync_community.dart` restore shape
(custom rows carry NO `is_custom` field), `exercise_selector.dart:963`
(supplement gate).

## Round 1 (context-blind, qa-agent)

Stanza captured. Verdict: material-issues-found.
- P0: per-row `is_custom == true` discriminator misses RESTORED custom rows
  (cloud table `user_custom_exercises` has no `is_custom` column; restore
  stamps only `type: 'exercise'`) — would have failed for the reported
  exercise itself, which arrived via restore. RESOLVED: filter-then-merge,
  provenance from list membership, no per-row discriminator anywhere.
- P1: edit mode must route through the canonical SoT writer
  (`upsertCustomExercise`) + registry update. RESOLVED.
- P1: muscle vocabulary map is private. RESOLVED: additive
  `canonicalMuscleTokens` getter.
- P1: L2-append behavior change unflagged. RESOLVED: disclosed in
  diagnose-doc + `_eligibleCustomExercises` comment.

## Round 2 (context-blind, qa-agent, on the hardened plan)

Verified clean: order preservation, bypass scope (only empty requirements
bypass), `source` re-stamp safety (zero readers branch on it for custom
exercise rows), id + cloud round-trip on onConflict 'id', restored rows in
the custom list, onCreated nullability across 4 call sites, seam-gate counts
unchanged, all 16 UI tokens canonical. Findings (plan-text gaps, no
architecture changes):
- P1-1: edit mode must NOT re-stamp equipment_needed / approved_for_library.
  RESOLVED: buildEditPayload preserves both; behaviorally pinned.
- P1-2: edit prefill must union pre-existing unmapped muscle tokens through
  save. RESOLVED: resolveMuscles + behavioral pin.
- P2-1..P2-7 (chip overflow → scrollable body; onCreated?.call; seam-lib
  reason strings; registry note rewrite; cap==null skip preserved;
  null-safe prefill; edit arm in the existing behavioral harness). All
  implemented.

## Verdict

Two independent context-blind rounds converged. Round 2's remaining findings
were mechanical plan-text gaps with encoded fixes, not new mechanisms; per
§4.12 the unit was already the smallest converged piece (the visibility bug
and the muscle field share the one writer). Both rounds' blockers resolved
and mutation-proven (5 mutations; M3 initially zero-red → fictional-fixture
trap found and corrected).
