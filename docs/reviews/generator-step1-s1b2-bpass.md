---
reviewed_at: 2026-11-09T23:45:00+05:30
staged_against: generator-step1-s1b2 staged tree (staging hash a37cd37a2a40, 59 files) vs origin/main 5d64d1a9
blast_radius: platform
reviewer: two fresh context-blind Sonnet seats (adversarial B-pass; seat A the rule, seat B the data and cloud path)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value, universal_pool, lowercase_sets, l6_consequence, v22_install]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — Library Batch S1b-2, nine loaded versions and the same-movement rule (`generator-step1-s1b2`)

Two fresh, context-blind Sonnet seats reviewed the staged diff read-only (allowed commands listed exhaustively; no
`dart run scripts/*`, no database statement). Seat A ran the three same-movement test files (14 pass; gate OFF 4,441
member-days / 5 placements / 0 shared, ON 3,184 / 977 / 0). Seat B regenerated migration 174 into a temp dir (byte-
identical to the staged file) and ran four contract files (51 pass).

**Verdict: accepted.** No P0, P1 or P2; five P3, all fixed in this batch.

## Finding 1 — P3 — missing_input / hollow guard (seat B)
- **file:line:** scripts/seed_exercise_library.js (kept-row loop)
- **claim:** the generator checked each kept-row record's `after` against the library but never its `before`, which is
  what the inline rollback restores; only a contract test compared `before` with migration 173. The real values were
  right (E010 [Beginner, Intermediate], E045 [Intermediate, Advanced]). A record naming a batch-new row was not refused.
- **verification:** `node scripts/seed_exercise_library.js 999_x.sql --out <tmp>` with a record whose E010 before is [Beginner].
- **status:** fixed. `tupleOf` extracted; the row rebuilt with `before` must equal its tuple in the previous seed
  migration (a missing file or line is a hard stop), and a record naming a `BATCH.newRowIds` row is refused. Three new
  refusals in `exercise_library_cloud_seeded_test.dart`; mutant `if (false && tupleOf(...))` reddens it (1 test).

## Finding 2 — P3 — header comment drift (seat B)
- **file:line:** scripts/seed_exercise_library.js header "JSON-only fields" (copied into 174 lines 14-20)
- **claim:** the list omitted `slot_pattern` and `same_movement_as`, both bundled-only.
- **status:** fixed; 174 regenerated (that comment line is its only change; the rehearsal SQL is unchanged).

## Finding 3 — P3 — asserted_fixture_value (seat B)
- **file:line:** test/contracts/library_seed_v23_upgrade_behavioral_test.dart (`_putV22Box`)
- **claim:** the "v22" box is built from the v23 bundle, so "every other row unchanged" compares v23 with v23 and cannot
  see a v23 edit to another row (the data itself was checked clean: 9 added, 2 changed, 0 removed).
- **status:** fixed. A pin: the v23 bundle minus the nine rows with E010 / E045 back at v22 must hash to the sha256 of
  the shipped v22 bundle (`7a37c26c…`, Dart `jsonEncode`, recorded from 5d64d1a9). Mutant: one row's
  `default_rest_secs` 90 -> 91 reddens it.

## Finding 4 — P3 — weak non-vacuity floor (seat A)
- **file:line:** test/plan_generator/same_movement_day_gate_test.dart (OFF floor `> 0` with 5 measured placements)
- **status:** fixed: measured floors, OFF >= 5 and ON >= 977.

## Finding 5 — P3 — dead-code asymmetry (seat A)
- **file:line:** lib/shared/repositories/plan_engine/exercise_selector.dart:68 (legacy V3 `pick` and its helpers)
- **claim:** V3 `pick` dedups by exact name with no partner expansion; it has no caller (verified: only `pickV4`,
  `topUpDays`, `buildPinnedDays` are called from outside, and nothing in the file calls `pick`).
- **status:** fixed as documentation: `lib/shared/repositories/plan_engine/CLAUDE.md` states V3 `pick` is not covered
  and needs the expansion before any revival.

## Clean lenses (summary)
Seat A: writer_reader_drift (one writer, the importer `LINK`; readers `SameMovement.fromRows` and two mirrors; lowercase
at every soft set), guard mirrors (both directions, B-vs-A, top-up, L6, universal pool, missing / inactive partner, no
chains), performance (one O(n) map per call, four `getAll()` reads match the seam allowlist 18 -> 22). Seat B: the
migration header counts, the ON CONFLICT column list, the inline rollback against 173, `blast_radius.yaml`, the
importer and sandbox inputs, the nine rows against Decision 1, the v22 -> v23 upgrade (writes by id; no custom row
touched), and the shifted `sot_registry.yaml` ranges.

## Founder triage notes
None needed: no finding above P3.

## Tuning entry
- **2026-11-09** - blast-radius platform - 5 findings; 0 false_alarm; tuning: none (two seats split rule / data kept each brief small; seat B's "rebuild the record row and compare with the previous migration" is the shape to ask for when a generator emits a rollback).
