---
bug_id: d30de7
date: 2026-10-23
batch: library-injury-recheck
status: fixed
blast_radius: platform
symptom: >-
  104 of the 285 library rows loaded a joint with no matching
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
    method: injury_contraindications on 104 rows (union, additions only, 148 tokens)
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
  (scripts/data/library_injury_additions_v14.json, 104 rows, 148 tokens), applied
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
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "assets/data/exercise_library.json 104 rows gain 148 tokens (proved against the v13 library: 0 removed, 0 other keys changed, 285 rows, 33 untagged); seed constant 14; _moveInjuries Push Up; injury_substitutes.dart; applier script is idempotent and refuses removal (run twice, byte-identical, --check round-trips). Tests: injury_recheck_v14_contract_test (A data, B real generator, C substitutes)." }
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
  - { tier: 12, name: client_server_contract, status: verified, evidence: "Real PlanGenerator.generateV4, flag OFF, five sweep blocks over 3, 4, 5 and 6 day plans (7,200 runs): 0 unsafe main, 0 unsafe warm/cool, 0 unresolved names in every block; empty days singles 0 and 1 (4/6-day), pairs 4 and 6, repeat 0. Generator golden: 18 of the 24 injury| keys changed, 0 of 975 others. See the body for the before and after tables." }
impact_analysis: >-
  Safe direction only: an injured user loses options and the cascade
  substitutes. The cost is thinner days for injured users, measured below and
  owned by OI-401 (thin-day top-up). 104 rows change; 33 low-load and rehab rows
  stay untagged on purpose (kV14SafePool) and the contract test pins that
  nothing else is untagged. Uninjured users: the golden shows 0 of the 975
  non-injury keys changed and the scorecard shows 0 of 576 uninjured personas
  moved by this change.
---

# One hundred and four rows the injury filter could not see

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
`scripts/data/library_injury_additions_v14.json`: 104 rows, 148 tokens
(shoulder 33, lower_back 26, elbow 22, wrist 19, hip 18, knee 12, hamstring 7, ankle 7, neck 4).
Additions only. The founder's calls, kept literally:

| call | result |
|---|---|
| Kettlebell Goblet Press | + shoulder |
| Lat Pulldown | + shoulder |
| "chinup is elbow" | Chin Up = elbow only (no shoulder) |
| hip machines (abduction, adduction) | + hip |
| Hollow Body Hold | + lower_back |
| "wrist and shoulders" | Push Up = wrist + shoulder |
| every push-up variant (B-pass F1, below) | Diamond Push Up and Incline Push Up + shoulder; all 11 push-up-named rows now carry shoulder |
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
users get), five blocks so each has its own timeout and wall time. All four day counts the product
offers are swept (the B-pass found 4 and 6 missing; they were added). BEFORE is the unmodified v13
library, MID is this change before the push-up reversal below, AFTER is the final change. The
columns are empty days / days under 3 exercises ("thin") / days with exactly one exercise.

| block | runs | BEFORE (v13) | MID | AFTER |
|---|---|---|---|---|
| singles, 3 and 5 days, phases 1 and 3 | 1,728 | 0 / 28 / 0 | 0 / 44 / 11 | **0 / 74 / 19** |
| singles, 4 and 6 days, phase 1 | 864 | 0 / 24 / 0 | 1 / 41 / 7 | **1 / 75 / 13** |
| pairs (15 pairs of knee, shoulder, lower_back, wrist, elbow, hip), 3 and 5 days | 1,440 | 2 / 219 / 51 | 4 / 399 / 157 | **4 / 531 / 197** |
| pairs, 4 and 6 days | 1,440 | 2 / 228 / 66 | 6 / 458 / 189 | **6 / 647 / 241** |
| repeat phase (pins from an uninjured phase 1), 3, 4, 5 and 6 days | 1,728 | 0 / 506 / 147 | not measured | **0 / 768 / 310** |

Safety holds in every block, every state: 0 unsafe main picks, 0 unsafe warm-up or cool-down
picks, 0 picks whose name is not a library row. Wall times of the final run, alone on the machine:
singles 2:25, singles 4/6 1:18, pairs 2:14, pairs 4/6 2:35, repeat 1:39 (about 10 minutes in all).
(MID's 3/5-day rows are from the first run of this change, which executed 11 test files in
parallel; the 4/6-day MID rows were measured separately on the earlier library.)

**The cost is thin days, and nearly all of them are shoulder.** Of the 74 thin days in the 3/5-day
singles block, 51 are shoulder and 16 wrist (hip 3, lower_back 4); in the 4/6-day block, 52 of 75
are shoulder and 23 wrist; in the repeat block shoulder is 390 of 768. A shoulder-injured user on
the bodyweight tier has NO safe horizontal press left, because every push-up variant loads the
shoulder, so the push day shrinks. That is the 13-B experience again, larger. The founder chose a
top-up fix (OI-401, its own plan and two reviews) over shipping thin days as they are.

### The empty days

| block | BEFORE | AFTER |
|---|---|---|
| singles 3/5 days | none | none (gate: exactly 0) |
| singles 4/6 days | none | shoulder, bodyweight, build_muscle, advanced, 4-day: Chest, shoulders, triceps (gate: at most 1) |
| pairs 3/5 days | knee+hip, knee+lower_back (3-day, week-2 leg day, bodyweight intermediate) | the same two, plus lower_back+hip at 3 and 5 days (gate: at most 4) |
| pairs 4/6 days | shoulder+elbow (Back, biceps), shoulder+wrist (Chest, shoulders, triceps), both bodyweight advanced 4-day | those two, plus knee+shoulder, shoulder+elbow (Chest, shoulders, triceps), shoulder+hip, shoulder+lower_back (gate: at most 6) |
| repeat | none | none (gate: exactly 0) |

The two new lower_back+hip leg days follow from one tag: Deficit Reverse Lunge (E228) went from
`[knee]` to `[hip, knee]` (a lunge loads the hip). The 4/6-day shoulder empties follow from the
shoulder tags on every press (the push-up reversal below changed thin counts, not these empties:
MID shows the same 1 and 6). Removing a tag to protect a gate would be the "kept safe" principle
the founder rejected, so no tag is removed. The founder was asked about the pairs ceiling and
answered "Ship, allow 4" on 2026-10-23 (the 3/5-day pairs block); the 4/6-day ceilings (1 and 6)
are the same decision applied to the blocks the B-pass added, with the same owner: OI-401 takes
every ceiling to 0.

### B-pass F1: the push-up variants (Ruling 2 reversed)

The first cut left Diamond Push Up (E020, `[elbow, wrist]`) and Incline Push Up (E102, `[wrist]`)
shoulder-free; plan Ruling 2 said "the founder named Push Up only; the extension was mine, and it
measured +30 thin days". The B-pass called that the P1 it is: it is the "kept safe for variety"
reasoning the founder rejected, applied by me to avoid thin days. A shoulder-injured bodyweight
user was handed Diamond Push Up right after Push Up was removed for loading the shoulder, while
E285 Elevated Diamond Push Up and Pike, Decline, Deficit and TRX push-ups were all shoulder-tagged.
Both rows now carry `shoulder`. The class check: every row in the pressing, pulling and
shoulder-isolation patterns without a shoulder tag was listed; the rest are the founder's own calls
(Chin Up), rows in the 33-row safe pool (Machine Chest Press, Floor Press, Chest Squeeze Press,
Svend Press, Sled Push, Face Pull, Band Pull Apart, Reverse Fly, Bodyweight Rear Delt Raise,
Machine High Row and the supported or machine rows), the barbell, T-bar, Meadows, Pendlay,
kettlebell and towel rows and the Rowing Machine (all lower_back-tagged), and Shrug (neck-tagged). A new test pins that all 11 push-up-named rows carry
shoulder. Cost, measured: thin days MID to AFTER singles 44 to 74, pairs 399 to 531.

### Generator golden

`RECORD_GENERATOR_GOLDEN=1`: 18 of the 24 `injury|` keys changed against the v13 golden on
origin/main, and 0 of the 975 others. The 18, all build_muscle, 4-day, intermediate, phases p1 and
p2:

```
injury|knee|full_gym
injury|lower_back|{bodyweight,home_dumbbells,basic_gym,full_gym}
injury|shoulder|{bodyweight,home_dumbbells,basic_gym,full_gym}
```

### Scorecard and the B1 report

`dart run test/plan_generator/generate_baseline.dart` rewrites both baseline files.

- This change, measured fresh against fresh: v13 library to final library moves 12 of 606
  personas, 12 of the 30 injured and 0 of the 576 uninjured, all in the full_gym 4-day phase-1
  injury sub-sweep (lower_back 2, knee 3, shoulder 3, shoulder+knee 3, hip 1; overall -0.5 to
  -5.8). Aggregates: overall 86.2 to 86.1, coverage 94.6 to 94.5, balance 67.3 to 67.1, volume 69.2
  to 69.1, total fallback picks 2862 to 2864 (full_gym 52 to 54), unsafe plans 0, equipment
  violations 0. The ceilings are untouched.
- **The committed baseline was already stale, and the staleness is attributed.** Regenerated with
  the current engine, the library at `8ef89153` (the baseline's own commit) reproduces the
  committed baseline exactly (0 of 606 moved) and so does the library at `4514cf0c`; the library at
  `ad896b42` ("retire 7 duplicate rows into their twins", 2026-10-22) moves 165 personas, 164 of
  them uninjured: `volume` mean -1.53 on those 165 (all lower), `overall` -0.26, `coverage`,
  `balance` and `realism` unchanged. The gate only enforces `overall >= baseline - 0.05` and a
  fallback-pick ceiling, so a fall of 0.0 to 0.1 in the aggregate passed unseen. Refreshing the
  baseline here absorbs that older decline too, so it is recorded on the board as OI-404 rather
  than hidden in the refresh.
- `core_list_pool_report.md` (the ON path, dark): the hard counts stay 0. The multi-injury sweep
  reads emergencyAnyLevel 74 (was 54 on v13) and refilled 34 (was 22); the B1 flip criteria already
  require refilled to be 0, and Batch C is what removes the refills.

## Mutations (CLAUDE.md section 4.4 rule 21)

Each applied (confirmed with `grep -c` or a read-back), run, and restored (sha1 identical to the
pre-mutation file).

| mutation | tests that reddened |
|---|---|
| Push Up loses `shoulder` in the library | 7: v14 contract x3 (data, founder calls, real generator), 13-B safe-pool pin, seed test, mirror x2 |
| `_moveInjuries` Push Up reverted to `{wrist}` | 4: mirror x2, the U3 warm-up test, and the repeat sweep (`unsafe-warm/cool 160`, `shoulder: Push Up`) |
| seed constant 14 back to 13 | 1: the seed upgrade test |
| `Push Up` re-added to the shoulder substitutes | 2: the substitute-safety test and the shoulder-list pin |
| Diamond Push Up loses `shoulder` (B-pass F1) | 5: v14 contract x4 (table tokens, founder calls, push-up family, queryV4 drop) and the frozen row reference |
| the library rule removed from `docs/blast_radius.yaml` (B-pass F6) | 3 of the 4 blast-radius tests |

One assertion needed narrowing while building: "every list is sorted" had been written over all 285
rows, but the applier sorts only the rows it touches and 16 untouched rows (E229, E248, ...) keep
their v13 order, which the filter never reads. It now covers the table's rows; the canonical-token
check still covers every row.

## The B-pass (docs/reviews/library-injury-recheck-bpass.md)

One fresh read-only Sonnet reviewer, 0 P0, 1 P1, 5 P2. Every finding was checked by me against the
code or data before acting on it:

| finding | verdict | disposition |
|---|---|---|
| F1 P1 Diamond and Incline Push Up left shoulder-free | confirmed | tagged; Ruling 2 reversed; test added (above) |
| F2 P2 the sweep never asserts it scanned anything; repeat has no empty-day gate | confirmed | non-vacuity guard in every block, repeat gated at 0 empty |
| F3 P2 only 3 and 5 day plans swept (4 and 6 never; repeat only 4) | confirmed | two 4/6-day blocks added, repeat at 3 to 6 days, numbers above |
| F4 P2 the baseline refresh absorbs older uninjured drift (164 personas) | confirmed and attributed | OI-404, cause commit `ad896b42` |
| F5 P2 the coach injury-swap planner never reads the tags | confirmed (grep) | OI-403, outside this diff |
| F6 P2 library JSON classifies `feature` under `assets/**` | confirmed | `docs/blast_radius.yaml` gains two `account` rules and a test |

## What this does not fix

- Thin, one-exercise and empty days for injured users: OI-401 (top-up), blocked on this PR.
- The coach's `modify_workout_for_injury` swap ignores the tags: OI-403.
- The uninjured scorecard decline from retiring 7 duplicate rows: OI-404.
- The cardio finisher (WorkoutDay.finisher) takes no injuries and no screen shows it: OI-396.
- Stored plans keep their old picks until regenerated (pre-launch, testing accounts only).
