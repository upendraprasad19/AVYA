---
reviewed_at: 2026-11-04T12:00:00+05:30
staged_against: 927757c6 (code), e4e4851a5dcb (docs delta)
blast_radius: platform
reviewer: claude-sonnet-via-skill (two fresh context-blind reviewers: A on the first build, B on the post-fix tree)
lens_set: [writer_reader_drift, guard_without_its_mirror, asserted_fixture_value, blast_radius_mismatch, missing_input]
findings_count: 12
verdict: accepted
verdict_note: reviewer A's findings were closed in 1b339225 and reviewer B's in 927757c6 plus this docs commit; no P0 or P1 from either
---

# Code Review — OI-456 piece A (rest by exercise type)

Diff reviewed: `origin/main..exercise-count-band` (plan_engine allocator, budget, periodization, swap_service, nested
CLAUDE.md, tests, registry, diagnose d3b7f1). Reviewers were context-blind and read-only. Reviewer A's findings were
triaged in the earlier part of this batch and fixed in 1b339225 (the main one: a swap across archetypes must re-derive
the rest from the incoming exercise, on the RESOLVED logging type). This file records reviewer B's report on the
post-fix tree: no P0, no P1, five P2 and seven P3. Every item is closed in this batch.

## Reviewer B

### Finding 1 — P2 — asserted_fixture_value
- **claim:** the mutation evidence was stale: the raw log showed M11 passing and the re-run with its fixture fix was not recorded.
- **status:** accepted, fixed: the whole table was re-run on the final tree (23 mutants incl. the new swap, rotation-stat and 38 s mutants), all killed; red counts are in the diagnose-doc.

### Finding 2 — P2 — missing_input
- **claim:** a timed / cardio row swapped in for a REP-BASED slot inherited that slot's 150 / 120 / 75 s rest.
- **status:** accepted, fixed in swap_service.dart: library default rest else the B rest (60); timed replacing timed keeps the slot's rest. Tests N1-N4 mutants killed.

### Finding 3 — P2 — guard_without_its_mirror
- **claim:** the plateau-rotation invariance test had been weakened to a per-day delta [0, 1].
- **status:** accepted, fixed: the allocator records `AllocationStats.slotsSeen` (test-only) and the test asserts ON equals OFF exactly at the selector stage; mutant S1 killed.

### Finding 4 — P2 — asserted_fixture_value
- **claim:** the thin-day ceiling rise (bodyweight pairs 30 to 32) rested on a hypothesis, and the prose said both "only down" and "one rose".
- **status:** accepted, fixed: two probes measured it (old base sets with the new rests gives 30; new base sets with the old rests gives 32), so the cause is the 3 base sets. Counts restated as 18 fell, 1 equal, 1 rose.

### Finding 5 — P2 — blast_radius_mismatch
- **claim:** the plan-review record was still a draft with a placeholder review path.
- **status:** accepted, fixed: the record is written after this file, citing it, with the honest convergence note.

### Findings 6-12 — P3
- 6. report writer could write a partial report: now writes only when all 9 cells ran. fixed.
- 7. nested CLAUDE.md said 45 minutes holds 4: now "30 min holds 3, 45 min 4 to 5". fixed.
- 8. no test of the allocator's price at 30 minutes: test (h), six distinct-group isolations seat 3. fixed.
- 9. stale comment in session_set_budget_consumers_test.dart: reworded. fixed.
- 10. no test for a library row without logging_type: added; it follows the stored type. fixed.
- 11. numbers the docs cite were not asserted: (f) now asserts all nine report cells. fixed.
- 12. sweep timeout 8 minutes was tight: 12 minutes. fixed.

## Founder triage notes
Not applicable before merge; the open product decision (D-A, the 30-minute floor) belongs to piece B.

## Tuning entry
- **2026-11-04** - blast-radius platform - 12 findings; 0 false_alarm; tuning: none (a probe-before-record habit and a re-run of the full mutant table on the final tree both caught items here; both are already in memory feedback files).
