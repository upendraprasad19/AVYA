---
reviewed_at: 2026-11-04T17:30:00+05:30
staged_against: 467bc1e36a91
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
---

# Code Review — db0dd5d9690f (OI-456 piece B, the exercise count band)

Fresh Sonnet reviewer, read-only, on the staged diff (15 files). It could not run the new test file to completion, so it
reasoned from code; the author ran the targeted tests, the 22-mutant table and the full suite (see the diagnose-doc).

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** test/plan_generator/session_set_budget_gate_test.dart (countExplained); session_set_allocator.dart (force bound)
- **claim:** the allocator's 300 s bound is over the DAY budget, but the gate measured against the user's minutes and added a flat 7 minute allowance, so a 15-minute day could be accepted at about 20+ minutes.
- **verification:** grep -n "maxForcedOverSeconds" lib/shared/repositories/plan_engine/session_set_allocator.dart test/plan_generator/session_set_budget_gate_test.dart
- **status:** accepted. The exemption is now min(forced seconds, 300 s) + the guard lead + the 2-minute display slack, so the flat cap is gone. The 15-minute case is accepted by design (decision D-A and the forcing bound) and stated in the diagnose-doc.

## Finding 2 — P2 — guard_without_its_mirror
- **file:line:** test/plan_generator/session_set_budget_gate_test.dart (countExplained)
- **claim:** a day with one forced slot could carry an unrelated overrun (week-2 gains, titration) up to the same allowance.
- **verification:** read the clause: it subtracted the whole forced seconds, then a separate flat cap.
- **status:** accepted. Same fix as finding 1: the overrun is bounded by the forcing itself, so 100 s of forcing plus 250 s of unrelated overrun now fails.

## Finding 3 — P3 — guard_without_its_mirror
- **file:line:** session_set_allocator.dart (belowCount, read after passes B-D)
- **claim:** the cause was computed after the grow passes spent weekly top, so a day short only because of the forcing bound could read cap_top, and reservation-blocked slots counted as forceable.
- **verification:** read the order of the stats block against pass B.
- **status:** accepted. The verdict is read at the end of pass A2 and skips reservation-blocked slots. The mutant that re-includes them survives and is argued equivalent in the diagnose-doc (a reservation-blocked lead cannot coexist with a week that still has room at that point).

## Finding 4 — P3 — design (force order)
- **claim:** A2 picks the cheapest slot, so a time-refused lead can lose to an accessory.
- **status:** accepted. The force prefers the day's lead lift when the bound allows it (test (p), mutant M21 killed). The related suggestion to force days with an unseated lead first was tried and removed (no fixture killed its mutant).

## Finding 5 — P3 — asserted_fixture_value
- **claim:** with not-budgeted rows at or above the maximum, the guard adds one lead (countMax + 1 rows); no test covered it.
- **status:** accepted. Test (o) pins it (6 timed rows + 1 budgeted slot = 7 rows, forcedDays [0]) and the plan names it.

## Finding 6 — P3 — writer_reader_drift
- **file:line:** docs/sot_registry.yaml (writer semantic text)
- **claim:** the semantic still said the allocator "starts it at baseSets".
- **status:** accepted. Rewritten: seats at 2 up to countMax(level), forces the floor, grows to baseSets.

## Checked and clean (reviewer's list)
Readers of AllocationStats (tests and the gate only); slotsSeen unchanged; belowFloor labels (count_limited only wins when every reason is target); no line-range citations in the registry for the touched files; blast radius platform (no plan_generator.dart, EF, schema or sync); canForce mirrors ledger.fits minus time; target gate vs empty-day guard; copy days; lighter phases; focus groups; unknown level.

## Founder triage notes
All six closed in the same batch (no deferrals).

## Tuning entry
- **2026-11-04** - blast-radius platform - 6 findings (0 P0/P1, 2 P2, 4 P3); 0 false_alarm; tuning: none (lens 6 again earned its place: both P2 were a guard whose bound was measured against a different quantity than the code that enforces it; consider adding "bound measured against the same quantity as its enforcer" to the lens 6 method).
