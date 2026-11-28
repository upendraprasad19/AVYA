# Library Batch S1b-1: gym Hip slot gets gym kit, Goblet Squat off advanced (pool still OFF)

**Founder decisions, 2026-11-09** (after S1a merged as PR #235, board decision d12):
- (c) Goblet Squat: "go with your recommendation": take E038 back off `advanced`, so advanced basic and full gym Quads
  compound pools hold Back Squat, Front Squat and Bulgarian Split Squat (basic) or Leg Press (full).
- (e) Gym Hip slot: "Gym users, give them hip abduction machine." (no bodyweight Glute Kickback or Side Lying Hip
  Adduction for gym users in the Hip slot).
- Answered with no change in this batch: (a) E255 Towel Row stays `[]`; (f) Sliding Leg Curl stays the home_dumbbells
  hamstring curl; Front Delts bodyweight gap accepted. (b) E010 / E045 `suitable_for` widening is a cloud column
  (`backups/live_schema_columns.json`, `exercise_library.suitable_for`) and goes to S1b-2 with the twins, the
  same-movement rule, E053 and the one migration.

**Why split from S1b.** S1b as listed (9 new rows, a same-movement rule in both worlds, E053's retirement with media,
two `suitable_for` changes, one cloud migration with a live go) is the size Batch C2b had to split after two rounds
(§4.12.1). These two items need no cloud change and touch only the pool-ON world, so they ship first.

**Tier.** `ship_dark_build` (§4.12.4): the change is read only with `enable_core_list_pool` ON (default OFF);
`core_levels` is not a cloud column; OFF identity is proven by `generator_golden_test.dart` and
`scorecard_gate_test.dart` unchanged plus a byte-identical 2,304-plan OFF dump. One review round, B-pass, record.
Blast radius platform (`plan_engine/`, seed). `plan_generator.dart` untouched.

## Design

1. **Region rule (code, ON only).** `CoreListSelector.namesMuscle` (R3 (a), step 1A) compares a row's first-listed
   muscle with the slot's muscle. The Hip slot's muscle is `Hip`, a region; no row lists "Hip" first (E107 lists
   Abductors, G3667 / G0168 Adductors), so the like-for-like reduction never fired there and an equipped user kept the
   bodyweight rows. A table `_slotRegionMuscles = {hip: {abductors, adductors}}` makes those muscles name `Hip`.
   Exact match only (no prefix, no `Glutes (medius)`, no `Hip Flexors`). Scope: isolation slots outside the implement
   patterns for an implement user, i.e. only the Hip / hip_isolation slot.
2. **Data (core_levels only).**
   - E038 Goblet Squat `[beginner, intermediate, advanced]` -> `[beginner, intermediate]` (its pre-S1a value). E038
     leaves the S1 core-levels record (`scripts/data/library_s1_core_levels.json`) and Table A of
     `library_s1_core_levels_test.dart`; that test's "no fixture row outside Table A changed" then holds E038 at the
     fixture value. The library edit is that one array (the importer `--check` is byte-identical).
   - E107 Hip Abduction Machine `[advanced]` -> every level, and G0168 Cable Hip Adduction `[]` -> every level (source
     row; `library_batch_c_scope.js --write`, C1-C6 green). The first build put them at advanced only, as the founder's
     question was worded; the gate zero below then showed beginner and intermediate gym personas still getting E257 /
     G3667 in the Hip slot, and the ruling ("gym users") covers them. G0168 is my choice inside the ruling: basic_gym
     has cables but no machines (`EquipmentVocab.tierItems`). Full gym has E107 and G0168 (variant A takes the machine,
     variant B the cable row once A's pick is avoided). Reported to the founder. E107 is a kept row: its record entry's
     `after` becomes every level and the library row is set to it (the stage then reads it as `after`, a no-op).
3. **Seed v22** so installs at v21 get both rows (`library_seed_v22_upgrade_behavioral_test.dart`); the v16-v21 pins
   repointed, never loosened.

Home_dumbbells advanced users keep G3667 / E257 in the Hip slot (no implement row is core there; the founder approved
those rows for home users on 2026-11-08). **Glutes isolation slot (both S1b-1 reviewers, P2).** With E107 core at beginner, a full_gym beginner's Glutes /
hip_isolation pool (no like-for-like row there: E109 was core at intermediate up, E110 lists "Glutes (medius)") held
E107, E257, G3667, G0168 and E110, and E107 tied E257 on every key and won on id, so the machine took the Glutes slot.
Fix: E109 Glute Kickback (Cable) gains `beginner` (it is suitable for beginners; record entry `before [int, adv]` ->
`after` every level), so every gym Glutes isolation slot reduces to E109 at every level. This also answers what the
first build reported as open (bodyweight Glute Kickback in the gym beginner Glutes slot). The gate zero covers the
Glutes slot too and also fails a Glutes pick whose first-listed muscle is not Glutes.

**Accepted limits.** basic_gym's Hip slot is a one-row pool (G0168, an adductor row; basic_gym has no machines and the
library has no cables abduction row), so both variants repeat it (gate "B repeats A" +2.2 points); the splits hold one
Hip slot per day, so same-day dedup cannot push a second Hip slot to bodyweight today. A gym user who excludes cables
or machines falls back to the bodyweight rows, as before this batch (the reduction never empties a pool); the gate zero
skips such personas.

## Tests

- `test/contracts/core_list_like_for_like_data_test.dart`: two new recorded cells
  (`basic_gym|<level>|Hip` = [G0168]; `full_gym|<level>|Hip` = [E107, G0168], each level), the restated oracle gains the region,
  and a pin test (Abductors / Adductors name Hip; Glutes, Glutes (medius), Hip Flexors do not; Abductors does not name
  Glutes).
- `test/contracts/library_s1_core_levels_test.dart`: Table A without E038; E107, E109, G0168 at every level.
- `test/contracts/exercise_library_core_fields_contract_test.dart`: totals 128 / 154 / 128 -> 131 / 156 / 128.
- `test/contracts/library_seed_v22_upgrade_behavioral_test.dart`: v21 box upgrades, other rows unchanged, v22 box left
  alone.
- Gate zero (new, `core_list_pool_gate_test.dart`): no uninjured basic or full gym persona (gym kit not excluded) gets a
  bodyweight-only row in the Hip or Glutes hip_isolation slot, nor a Glutes pick whose first muscle is not Glutes.
- Repointed by the full suite: `library_seed_v21_upgrade_behavioral_test.dart` precondition 34 -> 35 changed rows (E109 joins);
  `library_batch_c_rows_contract_test.dart` count mutation now adds 1 to the real derived beginner count (the old
  literal 57 became the true value once G0168 went core at beginner, so the mutation stopped mutating).
- Mutations: the region rule removed (`_slotRegionMuscles` empty); G0168 back to `[]`; E038's advanced level back;
  seed constant back to 21. Each confirmed applied (`grep -c`) and its red count recorded in the diagnose doc.

## Results (measured 2026-11-09)

OFF: `generator_golden_test.dart` and `scorecard_gate_test.dart` green unchanged; the 2,304-plan OFF dump is
byte-identical to S1a's (`cmp`). Gate (`core_list_pool_gate_test.dart`) green with the new zero; the first build (E107 at
advanced only, G0168 at advanced only) was RED on it for beginner and intermediate gym personas, which is why both rows
went to every level.

2,304-plan audit, pool ON, S1a -> S1b-1 (plans containing the row):

| row, tier, level | S1a | S1b-1 |
|---|---|---|
| Glute Kickback (bodyweight), basic_gym advanced | 93 | 0 |
| Glute Kickback (bodyweight), full_gym advanced | 21 | 0 |
| Side Lying Hip Adduction (bodyweight), basic_gym advanced | 24 | 0 |
| Cable Hip Adduction, basic_gym beginner / intermediate / advanced | 0 / 0 / 0 | 3 / 9 / 99 |
| Hip Abduction Machine, full_gym beginner / advanced | 0 / 84 | 64 / 84 |
| Cable Hip Adduction, full_gym advanced | 0 | 21 |
| Goblet Squat, basic_gym advanced | 33 | 0 |

Section 1 (ON): unloaded pick where a loaded row fits 548 -> 441; suitable 412 -> 431; lead lift 2+ sets under an
isolation 1,108 -> 1,090; every other row unchanged (zero-set weeks 284, iso-first 12, household 274).

Re-measured after the E109 fix (final tree; gate green with the Hip and Glutes zeros; golden and scorecard green; OFF
dump byte-identical again):

| row, tier, level | S1a | S1b-1 final |
|---|---|---|
| Glute Kickback (bodyweight), any gym tier and level (93 + 64 basic, 21 + 64 full) | 242 | 0 |
| Glute Kickback (Cable), basic / full gym beginner | 62 / 62 | 126 / 126 |
| Hip Abduction Machine, full_gym beginner (the Glutes-slot leak of the first build) | 0 | 0 |

Section 1 (ON) is the same as the first build: unloaded 548 -> 441, suitable 412 -> 431, lead-starved 1,108 -> 1,090.
