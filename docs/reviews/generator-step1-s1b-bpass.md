---
reviewed_at: 2026-11-09T10:30:00+05:30
staged_against: generator-step1-s1b staged tree (25 files) vs origin/main e7625c00
blast_radius: platform
reviewer: fresh-context-blind-sonnet-agent (adversarial B-pass)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value, off_identity]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — Library Batch S1b-1, gym Hip / Glutes slots and Goblet Squat (`generator-step1-s1b`)

A fresh, context-blind Sonnet agent reviewed the staged diff (25 files) read-only, with the importer and scope `--check`
runs and five named contract tests. In parallel the plan-review seat (one round, ship-dark build tier) found the same P2
independently.

**Verdict: accepted after the P2 fix.** One P2, three P3; all resolved.

## Finding 1 — P2 — guard_without_its_mirror (the Glutes slot is the Hip slot's mirror)
- **file:line:** lib/shared/repositories/plan_engine/core_list_selector.dart:395-416 with assets/data/exercise_library.json (E107)
- **claim:** with E107 core at beginner, a full_gym beginner Glutes / hip_isolation pool has no like-for-like row (E109 core only from intermediate, E110 lists "Glutes (medius)"), so it stays {E107, E110, E257, G0168, G3667}; E107 ties E257 on every key and wins on id, so the machine takes the Glutes slot. The plan said "gym Glutes slots are unchanged".
- **verification:** node pool simulation HEAD vs staged library; is_foundational / priority_tier of the rows; matches the audit (E107 in 64 full_gym beginner plans vs G0168 in 3 basic_gym beginner plans).
- **status:** fixed. E109 Glute Kickback (Cable) gains `beginner`, so every gym Glutes isolation slot reduces to E109; the gate zero now covers the Glutes slot and fails a Glutes pick whose first muscle is not Glutes; like-for-like cells recorded; plan, diagnose, docs corrected.

## Finding 2 — P3 — basic_gym Hip slot is a one-row pool
- **claim:** G0168 every time, both variants; not an abduction row; "B repeats A" +2.2 points.
- **status:** accepted and stated in the plan (no cables abduction row in the library; one Hip slot per day in the splits, so same-day dedup cannot reach bodyweight today).

## Finding 3 — P3 — the gate zero has no mirror for excluded kit
- **claim:** a persona excluding cables or machines would fall back to bodyweight by design and false-red the zero.
- **status:** fixed: the zero skips personas whose exclusions remove cables or machines, with the reason in a comment.

## Finding 4 — P3 — ledger `commit:` placeholders; record pending
- **status:** fixed by the stamp commit after the fix commit (as S1a did); the record is set accepted in this commit.

## Clean lenses (reviewer's evidence, abridged)
- **writer_reader_drift:** registry seed_service 160-160 (x3) land on `_exerciseLibraryVersion = 22`; 259-300 spans retiredLibraryIds to the _seedExercises catch; core_list_selector 259 is the `equipment_tier` read (the old 196 cite was already stale).
- **missing_input:** importer `--check` byte-identical (862 rows); scope `--check` C1-C6 OK.
- **asserted_fixture_value:** totals, Table A, like-for-like cells and the v21 levels in the seed test computed from the data and matching.
- **namesMuscle mirrors:** exact match only; home / bodyweight users unaffected (improvised rows never like-for-like, E107 / G0168 fail the tier filter); injured personas filtered upstream (E107, G0168 carry `hip`); compound Adductors rows blocked by the isolation checks.
- **OFF identity:** `namesMuscle` is called only from rankedPool, reached only behind `enable_core_list_pool`; no Edge Function reads core_levels.

## Founder triage notes
Triaged by the coordinating session. The E109 change answers the question put to the founder about the gym beginner
Glutes slot; it is reported to the founder with the merge.

## Tuning entry
- **2026-11-09** - blast-radius platform - 4 findings; 0 false_alarm; tuning: none (the P2 is the guard_without_its_mirror lens working as written: the Hip slot's sibling hip_isolation slot, Glutes, was the mirror; both seats found it from the brief's "mirror cases" line).
