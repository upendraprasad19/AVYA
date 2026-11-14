---
reviewed_at: 2026-11-10T18:16:58+05:30
staged_against: generator-step1-1b staged tree (14 files) vs origin/main cc8286ad
blast_radius: platform
reviewer: two fresh context-blind Sonnet seats (adversarial B-pass; seat A the code and tests, seat B the documents against code and audit data)
lens_set: [guard_without_its_mirror, asserted_fixture_value, writer_reader_drift, missing_input, blast_radius_mismatch, secrets_in_tree]
findings_count: 4
verdict: accepted
---

# Code Review (B-pass) — Unit 1B-Q, the B leg day gets a quad compound (`generator-step1-1b`)

Two fresh, context-blind Sonnet seats reviewed the staged diff read-only. The commands they could run were listed
exhaustively: no `dart run scripts/*`, no database statement. Seat A ran `dart analyze` on the four staged Dart files
(clean) and `TZ=Asia/Kolkata flutter test test/contracts/variant_b_quads_behavioral_test.dart` (66 pass). It also
compared every kill-switch OFF list and the test's restated `_old3` / `_old4` / `_old5` lists against
`git show origin/main:` slot by slot. Seat B recomputed every number in the plan, ledger, diagnose and board from the
audit dumps with `python3 -I` and found them all equal. It also re-opened every line citation into the two changed
lib files.

**Verdict: accepted.** No P0 or P1. One P2 (a coverage note the test file already states) and three P3. All are
addressed in this batch.

## Finding 1 — P2 — asserted_fixture_value (seat A)
- **file:line:** test/contracts/variant_b_quads_behavioral_test.dart (live-world quad tests and group (g))
- **claim:** In the live world the 12 week-2 quad tests and the seven Calves / Core persona tests would also pass on
  the old lists. Only the shape tests and the pool-ON tests discriminate.
- **verification:** `grep -n "pass on the old lists\|do not detect a no-op" test/contracts/variant_b_quads_behavioral_test.dart`
- **status:** accepted, no code change. The file header (live-world quad tests are regression guards) and group (g)'s
  comment (round 3) say so. Reverting the feature reddens 28 tests (shape plus pool ON), and putting the Glutes slot
  back in fourth place reddens 13, so a regression of either part is caught. Group (g) runs in both worlds.

## Finding 2 — P3 — asserted_fixture_value (seat A)
- **file:line:** test/plan_generator/same_movement_day_gate_test.dart (floor `on ? 931 : 5`)
- **claim:** The floor equals the measured value, so a library change that moves it by one reddens the test.
- **verification:** `git diff --cached origin/main -- test/plan_generator/same_movement_day_gate_test.dart`
- **status:** false_alarm. A floor that must be re-measured on purpose is the gate's documented design, and the
  comment states the cause of the 977 -> 931 drop (N19 placements 1444 -> 1289).

## Finding 3 — P3 — writer_reader_drift, document hygiene (seat B)
- **file:line:** docs/audit/open_issues.md:7063
- **claim:** The OI-475 paragraph uses L1 / L2 / L3 without defining them on the board.
- **verification:** `grep -n "L1 = a slot-only change" docs/audit/open_issues.md`
- **status:** fixed. The paragraph now defines the three levels on first use. It also names the 14 ON Quads plans.

## Finding 4 — P3 — asserted_fixture_value, terminology (seat B)
- **file:line:** docs/diagnoses/2026-11-10-variant-b-leg-day-quad-compound-cf970c.md (`impact_analysis`)
- **claim:** "OFF" / "ON" (the core-list pool) next to "the kill-switch restores main" can be read as the
  kill-switch's sense.
- **verification:** `grep -n "Pool OFF\|Pool ON" docs/diagnoses/2026-11-10-variant-b-leg-day-quad-compound-cf970c.md`
- **status:** fixed. The text now says "Pool OFF (`enable_core_list_pool` off, live, every user today)" and "Pool ON (dark)".

## Checked clean (both seats)
- The kill-switch OFF branches are main's lists verbatim. `plan_generator.dart` is not in the diff. `selectV4` has one
  caller (`plan_generator.dart:168`) and reads the flag once, after the beginner early return.
- Slot readers: `pickV4` / `_pickCoreList` iterate `slotsB` in order. `VolumeFilter` is passed `baseline`. Only
  `ThinDayTopUp.anchors` reads priority. Nothing indexes slots by position. Author follow-up on seat A's one unread
  reader: `_patternForPick` (exercise_selector.dart:1501) maps a pick to the first slot whose muscle it names. On the B
  leg day the new Quads slot sits after Hamstrings and both Quads slots are knee_dominant, so a quad pick maps to the
  same pattern as before.
- Golden fixture: 242 of 998 keys differ from main's, all build_muscle 3/4/5-day or strength 3-day, with an equal key
  set. Beginner keys differ only where a non-full-body split applies.
- Library spellings behind the test oracles (Quads x111, Calves variants, Core / Abs / Obliques).
- Every number in plan section 2, the ledger, the diagnose and the board, including the one E292 plan new against
  main (`strength|3|advanced|home_dumbbells|30|1`).
- Line citations, the registry `line_range` shift, `ship_dark_pending_review.yaml:93`, blast radius (platform) and
  secrets (none).

## Founder triage notes
Self-triaged under the standing approval (board d7). All findings are fixed or answered in this batch.

## Tuning entry
- **2026-11-10** - blast-radius platform - 4 findings; 1 false_alarm; tuning: none. Splitting the seats into code / tests and documents-against-data held again. The data seat recomputed every published number from the audit dumps, which round 3 had already made the norm, and found no drift after the round-3 fixes. Worth keeping for any batch whose case rests on measured counts.
