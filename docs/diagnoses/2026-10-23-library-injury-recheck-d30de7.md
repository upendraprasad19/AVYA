---
bug_id: d30de7
date: 2026-10-23
batch: library-injury-recheck
status: fixed
blast_radius: platform
symptom: >-
  102 of the 285 library rows loaded a joint with no matching
  injury_contraindications token, so the injury filter handed them to an injured
  user. The founder named the cases: a bicycle crunch, a V-up or a Russian twist
  to a lower-back user. The same hole covered Kettlebell Goblet Press, Lat
  Pulldown and Push Up for a shoulder, every curl and triceps row for an elbow,
  and the hip-abduction and hip-adduction machines for a hip. Batch 13-B had left
  28 of these untagged on purpose ("kept safe for variety"); the founder rejected
  that principle on 2026-10-23.
concept: exercise_injury_tags
sot_registry_entry: exercise_injury_tags
writers:
  - file: assets/data/exercise_library.json
    method: injury_contraindications on 102 rows (union, additions only, 146 tokens)
    line: 1
  - file: scripts/add_library_injury_tags_v14.js
    method: applies scripts/data/library_injury_additions_v14.json (idempotent, refuses removal and non-canonical tokens)
    line: 1
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion (13 to 14)
    line: 116
  - file: lib/shared/repositories/plan_engine/warmup_cooldown.dart
    method: _moveInjuries 'Push Up' now {wrist, shoulder}
    line: 30
  - file: lib/shared/repositories/plan_engine/injury_substitutes.dart
    method: _preferred shoulder list re-pointed, knee list trimmed, elbow key removed
    line: 30
readers:
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: queryV4 injury filter (attempts 1-4)
    line: 413
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: V3 injury filter in the selector
    line: 473
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: _isContraindicated (attempt 5 and repeat pins)
    line: 1456
  - file: lib/shared/repositories/plan_engine/warmup_cooldown.dart
    method_or_widget: WarmupCooldownSelector reads _moveInjuries (its own copy of the tags)
    line: 64
hive_key_prefix: exerciseBox
hive_key_formula: "exerciseBox[<id>]['injury_contraindications'] (re-seeded by SeedService v14 putAll)"
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: []
contract_test_path: test/contracts/injury_recheck_v14_contract_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked: []
proposed_fix: >-
  Tag per injury by movement pattern through a committed table
  (scripts/data/library_injury_additions_v14.json, 102 rows, 146 tokens), applied
  by an idempotent additions-only script. Bump the seed to 14 so existing installs
  receive the tags. Mirror the one changed warm-up move (Push Up) into
  WarmupCooldownSelector._moveInjuries and pin all 27 of its keys against the
  library. Re-verify every curated substitute against the new tags: Push Up,
  Dumbbell Bench Press, Lat Pulldown, Kettlebell Goblet Press, Leg Press and the
  whole elbow list became dead or unsafe, so the shoulder list takes three
  untagged names (Floor Press, Chest Squeeze Press, Machine High Row) and the
  elbow key is removed. Founder calls kept literally: Chin Up is elbow only, Push
  Up is wrist and shoulder, Decline Sit Up and Reverse Hyper keep lower_back.
regression_test_planned:
  - test/contracts/injury_recheck_v14_contract_test.dart
  - test/contracts/library_seed_v14_upgrade_behavioral_test.dart
  - test/plan_generator/injury_floor_sweep_test.dart
  - test/contracts/warmup_library_injury_mirror_test.dart
  - test/contracts/warmup_injury_filter_behavioral_test.dart
  - test/contracts/injury_undertag_13b_contract_test.dart
related_bugs:
  - f4c1e8  # Batch 13-B injury under-tagging (26 rows tagged, 2 deepened)
  - c2d5e8  # five safety-direction tags (v13), same class, same fix shape
  - e1a7c4  # Batch 13-A injury field missing on stub rows
  - a1f6c3  # injury filter non-functional
recurrence: |
  Fifth instance of the under-tag class: the filter drops a row only when its
  list CONTAINS the user's token, so a missing tag is a silent pass, and each
  batch tagged only the rows in front of it (a1f6c3, e1a7c4, f4c1e8, c2d5e8).
  Known-good fix applied: additions only, tokens closed to InjuryVocab, a
  contract pin per changed row, a seed bump so the stale Hive box receives them.
  New this time: (1) the tag decision is made per injury by movement pattern
  instead of per row by feel, so the "kept safe" exemption list is gone; (2) the
  second table that copies the tags (_moveInjuries) is pinned key by key, not
  only for the three overlap names; (3) every curated substitute is checked
  against the new tags, because a substitute tagged for its own injury is dead;
  (4) the whole change is swept on the real generator (singles, pairs, repeat
  phase) for unsafe picks, unresolved names and empty days.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "assets/data/exercise_library.json 102 rows gain 146 tokens (proved: 0 removed, 0 other keys changed, 285 rows, 33 untagged); seed constant 14; _moveInjuries Push Up; injury_substitutes.dart; applier script is idempotent and refuses removal (run twice, byte-identical, --check round-trips). Tests: injury_recheck_v14_contract_test (A data, B real generator, C substitutes)." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "SeedService v14 re-seeds exerciseBox by id via putAll when the stored version is below 14; library_seed_v14_upgrade_behavioral_test puts a v13-shaped E005 row ['wrist'] at version 13, runs seedIfNeeded, and reads back ['shoulder','wrist'] and version 14 (first test to call seedIfNeeded; seed constant back to 13 reddens it). Stored PLANS are not rewritten: pre-launch, every account is a testing account (CLAUDE.md section 1); a regenerated plan gets the tags." }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "backups/live_schema_columns.json exercise_library has no injury_contraindications column, same as the c2d5e8 finding: the tags are not a cloud column." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud column carries the tags, so there is no row to backfill." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "Plan generation is local Dart; no Edge Function reads injury_contraindications." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Real PlanGenerator.generateV4, flag OFF, sweep AFTER: singles 1,728 runs 0 unsafe 0 unresolved 0 empty; pairs 1,440 runs 0 unsafe 0 unresolved 4 empty; repeat 432 runs 0 unsafe 0 unresolved 0 empty. Generator golden: 18 of 999 keys changed, all start with injury|. See the body for the before and after tables." }
impact_analysis: >-
  Safe direction only: an injured user loses options and the cascade
  substitutes. The cost is thinner days for injured users, measured below and
  owned by OI-401 (thin-day top-up). 102 rows change; 33 low-load and rehab rows
  stay untagged on purpose (kV14SafePool) and the contract test pins that
  nothing else is untagged. Uninjured users: the golden shows 0 of the 975
  non-injury keys changed and the scorecard shows 0 of 576 uninjured personas
  moved by this change.
---

# One hundred and two rows the injury filter could not see

## What was wrong

`queryV4` (`exercise_repository.dart:413`), the V3 filter (`exercise_selector.dart:473`) and
`_isContraindicated` (`:1456`) drop a row for an injured user only when its
`injury_contraindications` CONTAINS the user's token. An empty or short list reads as "safe", so
whether an injured user is protected is a property of the data, and every earlier batch tagged only
the rows it was looking at. Batch 13-B tagged 26 rows and deliberately left 28 untagged ("kept safe
for variety": the crunch and sit-up family and the hip machines). On 2026-10-23 the founder
rejected that principle: "We cannot give a bicycle crunch or a V-up or a Russian twist to a injured
user."

## The decision

Every row is tagged per injury by the movement it loads. The table is
`scripts/data/library_injury_additions_v14.json`: 102 rows, 146 tokens
(shoulder 31, lower_back 26, elbow 22, wrist 19, hip 18, knee 12, hamstring 7, ankle 7, neck 4).
Additions only. The founder's calls, kept literally:

| call | result |
|---|---|
| Kettlebell Goblet Press | + shoulder |
| Lat Pulldown | + shoulder |
| "chinup is elbow" | Chin Up = elbow only (no shoulder) |
| hip machines (abduction, adduction) | + hip |
| Hollow Body Hold | + lower_back |
| "wrist and shoulders" | Push Up = wrist + shoulder |
| every curl and triceps row | + elbow (30 rows in the elbow pattern pinned by the contract test) |
| Burpee, Mountain Climber | Burpee + knee, shoulder, wrist; Mountain Climber + shoulder, wrist |
| Decline Sit Up, Reverse Hyper | keep lower_back (CARVEOUT-E173-E127 closed: keep) |
| the three added shoulder substitutes | Floor Press, Chest Squeeze Press, Machine High Row |

33 rows stay untagged on purpose (`test/helpers/injury_safe_pool.dart`, `kV14SafePool`): low-load,
supported and rehab rows. The contract test pins that exactly those 33 are untagged and nothing
else is.

The exercise picker, swap and add sheets stay UNFILTERED by decision ("user should be able select,
add, swap all the exercises"): the filter governs what the GENERATOR picks.

## The second table

`WarmupCooldownSelector._moveInjuries` keeps its own copy of the tags for the warm-up and cool-down
moves (27 keys, every one a library row). Only Push Up changed: `{wrist}` to `{wrist, shoulder}`.
`warmup_library_injury_mirror_test` used to pin three overlap names; it now pins all 27 keys against
the library, and `warmup_injury_filter_behavioral_test` pins that a shoulder-injured user gets no
Push Up in a warm-up (with an uninjured positive control).

## The curated substitutes

`InjurySubstitutes._preferred` re-ranks candidates AFTER the filter. The new tags killed entries:
Push Up and Dumbbell Bench Press (shoulder), Lat Pulldown (shoulder), Kettlebell Goblet Press
(shoulder), Leg Press (knee + lower_back), and every elbow entry (the whole elbow pattern is
tagged elbow, so no same-pattern substitute remains and the key was removed). Before the three
additions the shoulder list was inert: 0 of 864 personas. After:

| injury | personas where the re-rank changes the plan (of 144 each) |
|---|---|
| shoulder | 60 |
| lower_back | 72 |
| wrist | 68 |
| knee | 22 |
| hip | 2 |
| elbow | 0 (no list, by construction) |
| total | 224 of 864 |

(A temporary probe file, deleted before the commit: 6 injuries x 4 tiers x 4 goals x 3 levels x
3/4/5 days, phase 1, flag `disable_injury_substitute_pref` set and deleted, ordered week-1 names
compared.) The shoulder stop condition in the plan ("shoulder count 0 means Ruling 3 failed") did
not trigger.

## Measured on the real generator

`test/plan_generator/injury_floor_sweep_test.dart`, `PlanGenerator.generateV4`, flag OFF (the path
users get). BEFORE is the unmodified v13 library; AFTER is this change. Wall times: the AFTER run
executed 11 test files in parallel on one machine, so its singles block (6:16) is slower than the
BEFORE run (2:49); a solo run of the singles block is about 3 minutes.

| block | runs | | empty days | thin (<3) | one-exercise | unsafe main | unsafe warm/cool | unresolved |
|---|---|---|---|---|---|---|---|---|
| singles (9 injuries, phases 1 and 3) | 1,728 | BEFORE | 0 | 28 | 0 | 0 | 0 | 0 |
| | | AFTER | 0 | 44 | 11 | 0 | 0 | 0 |
| pairs (15 pairs of knee, shoulder, lower_back, wrist, elbow, hip) | 1,440 | BEFORE | 2 | 219 | 51 | 0 | 0 | 0 |
| | | AFTER | 4 | 399 | 157 | 0 | 0 | 0 |
| repeat phase (pins from an uninjured phase 1) | 432 | BEFORE | 0 | 47 | 20 | 0 | 0 | 0 |
| | | AFTER | 0 | 109 | 32 | 0 | 0 | 0 |

Safety holds everywhere: 0 unsafe main picks, 0 unsafe warm-up or cool-down picks, 0 picks whose
name is not a library row.

**The cost is thin days.** A correct tag removes options, and for an injured user on a small
equipment tier the cascade can run out. That is the 13-B experience again, larger. The founder
chose a top-up fix (OI-401, its own plan and two reviews) over shipping the thin days as they are.

### The empty days in the pairs block

Four days are empty, all the week-2 ("B") leg day of a bodyweight build_muscle intermediate plan:

| pair | days | BEFORE |
|---|---|---|
| knee + hip | 3 | empty (unchanged) |
| knee + lower_back | 3 | empty (unchanged) |
| lower_back + hip | 3 | NEW: was not thin |
| lower_back + hip | 5 | NEW |

The two new ones follow from one tag: Deficit Reverse Lunge (E228) went from `[knee]` to
`[hip, knee]` (a lunge loads the hip). Removing that tag to protect a gate would be the "kept safe"
principle the founder rejected, so the tag stays. The pairs gate ceiling moves from the BEFORE
count (2) to the AFTER count (4): the founder was asked and answered "Ship, allow 4" on 2026-10-23.
OI-401 takes it to 0. A probe on both libraries (temporary file,
deleted) confirmed that the BEFORE two are the same two days.

### Generator golden

`RECORD_GENERATOR_GOLDEN=1`: 18 of 999 keys changed. The golden holds 24 `injury|` keys and 975
others; all 18 changed keys are injury keys and 0 of the 975 others changed. The 18, all
build_muscle, 4-day, intermediate, phases p1 and p2:

```
injury|knee|full_gym
injury|lower_back|{bodyweight,home_dumbbells,basic_gym,full_gym}
injury|shoulder|{bodyweight,home_dumbbells,basic_gym,full_gym}
```

### Scorecard and the B1 report

`dart run test/plan_generator/generate_baseline.dart` rewrites both baseline files.

- The committed baseline was ALREADY stale: regenerated on the unmodified v13 library it differs
  from the committed JSON in 165 of 606 personas (volume 69.6 committed against 69.2 fresh). It
  was last regenerated on 2026-08-28 and the library has changed since (7 duplicate rows retired,
  labels fixed, 136 coaching texts moved); the gate only has no-regression ceilings, so nothing
  noticed. This commit refreshes it, which clears that drift too.
- The valid comparison for THIS change is fresh v13 against fresh v14: 12 of 606 personas moved
  (12 of the 30 injured, 0 of the 576 uninjured), all in the full_gym 4-day phase-1 injury sub-sweep
  (lower_back 2, knee 3, shoulder 3, shoulder+knee 3, hip 1; overall -0.5 to -5.8).
- Aggregates (fresh v13 to fresh v14): overall 86.2 to 86.1, coverage 94.6 to 94.5, balance 67.3
  to 67.1, volume 69.2 to 69.1, total fallback picks 2862 to 2866 (full_gym 52 to 56). Unsafe plans
  0 and equipment violations 0 in both. The ceilings are untouched.
- `core_list_pool_report.md` (ON path, dark): the hard counts stay 0. The multi-injury sweep reads
  emergencyAnyLevel 64 (was 54) and refilled 24 (was 22); the B1 flip criteria already require
  refilled to be 0, and Batch C is what removes the refills.

## Mutations (CLAUDE.md section 4.4 rule 21)

Each applied (confirmed with `grep -c`), run, and restored (sha1 identical to the pre-mutation file).

| mutation | tests that reddened |
|---|---|
| Push Up loses `shoulder` in the library | 7: v14 contract x3 (data, founder calls, real generator), 13-B safe-pool pin, seed test, mirror x2 |
| `_moveInjuries` Push Up reverted to `{wrist}` | 4: mirror x2, the U3 warm-up test, and the repeat sweep (`unsafe-warm/cool 160`, `shoulder: Push Up`) |
| seed constant 14 back to 13 | 1: the seed upgrade test |
| `Push Up` re-added to the shoulder substitutes | 2: the substitute-safety test and the shoulder-list pin |

One assertion needed narrowing while building: "every list is sorted" had been written over all 285
rows, but the applier sorts only the rows it touches and 16 untouched rows (E229, E248, ...) keep
their v13 order, which the filter never reads. It now covers the table's rows; the canonical-token
check still covers every row.

## What this does not fix

- Thin and one-exercise days for injured users: OI-401 (top-up), blocked on this PR.
- The cardio finisher (WorkoutDay.finisher) takes no injuries and no screen shows it: OI-396.
- Stored plans keep their old picks until regenerated (pre-launch, testing accounts only).
