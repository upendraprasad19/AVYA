---
bug_id: f7b2c4
date: 2026-08-28
batch: oi89-bodyweight-floor
status: fixed
blast_radius: platform
symptom: >-
  A bodyweight-tier user is prescribed Chin Up, Ab Wheel Rollout, Jump Rope, Box
  Jump, Dip (Parallel Bars), Medicine Ball Slam, TRX Row and Negative Pull Up,
  because library rows had their equipment distinctions destroyed by a
  normalizer that collapsed an 87-token vocabulary into 11, and equipment_tier
  was then derived from the collapsed values. Every one ships in the current APK.
concept: exercise_equipment_tier
sot_registry_entry: exercise_equipment_tier
writers:
  - file: assets/data/exercise_library.json
    method: equipment_needed + equipment_tier (292 rows)
    line: 1
  - file: lib/core/services/seed_service.dart
    method: _exerciseLibraryVersion (9 to 10)
    line: 89
readers:
  - file: lib/shared/repositories/exercise_repository.dart
    method_or_widget: queryV4 equipment filter
    line: 298
  - file: lib/shared/repositories/plan_engine/exercise_selector.dart
    method_or_widget: pickV4 / _cascadeFill
    line: 1
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: exercise_library
cloud_columns: [equipment_needed, equipment_tier]
contract_test_path: test/contracts/equipment_tier_consistency_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - pattern: "gains-only"
    absent: true
proposed_fix: >-
  Recover the 87 originals from the commit before the normalizer and re-map them
  through the expanded 24-token vocabulary; audit the bodyweight-tier rows against
  their own prose for the errors that predate the normalizer and so cannot be
  recovered from git; add the 12 rows the corrections leave the pattern pools
  short of; then re-derive equipment_tier from equipment_needed for every row and
  make that relation an equality, not a subset.
regression_test_planned:
  - test/contracts/equipment_tier_consistency_test.dart
  - test/contracts/exercise_library_schema_contract_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "seed_service _exerciseLibraryVersion 9 to 10; equipment_tier_consistency_test flipped from subset to equality and gained a per-pattern floor test; exercise_library_schema_contract_test pinned count 259 to 271; check_equipment_audit flipped strict with a 13-pair accept-list. universalPoolV4 + its mirror gained the bodyweight tails the retag made necessary. 55 green across the plan-generator and library suites; the 606-persona scorecard reports equipment-violating plans 201 -> 0, missing 0, unsafe 0." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "The library lives in exerciseBox. SeedService re-seeds only when storedVersion < _exerciseLibraryVersion, so without the 9 to 10 bump every existing install keeps the stale rows and the retag is inert for exactly the users who have the bug. The bump is the fix, not bookkeeping." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL. exercise_library.equipment_needed and equipment_tier already exist." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "The cloud exercise_library is a read-through mirror of the bundled asset and is re-seeded by migration, not by the client. Task 10 carries migration 125 to re-seed it; until that applies, the client reads its own bundled copy, which this commit corrects. Stated rather than assumed: no client read path consults the cloud table for equipment." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this commit." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function reads equipment_tier." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads the library." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy touched." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret involved." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service involved." }
  - { tier: 12, name: client_server_contract, status: not_applicable, evidence: "The library is bundled and read locally; no request carries equipment_tier." }
impact_analysis: >-
  This is the data half of OI-89 and it reaches every bodyweight user on every
  generated plan, because equipment_tier was the only field queryV4 filtered on.
  Chin Up is the clearest case: it needs a pull-up bar, it was tagged bodyweight,
  and it therefore shipped to users who told us they have nothing. Severity is
  bounded only by the user noticing and skipping — but the promise the tier makes
  is "no equipment needed", so every such pick is the app breaking its own word at
  the exact moment the user is trying to train. Sixteen rows leave the bodyweight
  tier here; the 12 new rows exist so that removal never empties a slot, which
  would have replaced a wrong-exercise bug with a missing-exercise one.
---

# The library forgot what its exercises need

## What was wrong

Three separate faults, stacked:

**1. A normalizer destroyed the vocabulary.** `scripts/normalize_equipment_library.dart`
(commit `632a10b8`) mapped 87 authored equipment tokens onto 11 canonical ones.
There was no token for a wall, a doorway, a chair, a towel, an ab wheel, a jump
rope, a plyo box, a medicine ball, parallel bars, a suspension trainer or battle
ropes — so every row needing one of those was mapped to the nearest survivor, and
the nearest survivor was usually `bodyweight`. Ab Wheel Rollout became a
bodyweight exercise. So did Jump Rope, Box Jump, Medicine Ball Slam, TRX Row and
Dip (Parallel Bars).

**2. `equipment_tier` was then derived from the collapsed values.** Batch 13-A
deepened `equipment_tier` from `equipment_needed`, and its recorded invariant was
`derive ⊆ equipment_tier` — under-tags banned, over-tags *"intentionally tolerated
this batch — a separate drop-side pass corrects them"*. That pass never came. So
a row that had lost its requirement gained the bodyweight tier and kept it.

**3. Some rows were wrong before the normalizer ever ran.** `Negative Pull Up`,
`Bench Dips`, `Doorframe Curl` and `Towel Row` were already `["Bodyweight"]` in
`632a10b8^`. Git cannot recover an error that predates the commit you are
recovering from — and each of those four is its movement pattern's only
core-satisfying row, so missing them would have left the pattern empty in exactly
the way this fix exists to prevent.

## What was done, and why in this order

**Restore (31 rows).** The 87 originals are recovered from `632a10b8^` and
re-mapped through the expanded 24-token vocabulary. The mapping is explicit and
recorded, not re-derived by re-running the normalizer — re-running it would
reproduce the collapse.

**Four ambiguous OR-compounds.** `§2`'s hand-mapping and `normalizeToken` disagree
on exactly four rows. Neither procedure is authoritative wholesale, and pretending
one is would get two of the four wrong:

| row | original | resolution | why |
|---|---|---|---|
| Copenhagen Plank | `Bench or Box` | `elevated surface` | **hand-mapping.** `normalizeToken` picks `plyo box`, which is a gym purchase; both authored alternatives are just "something to rest a foot on" |
| Handstand Hold | `Wall or Freestanding` | `wall` | **hand-mapping.** Behaviourally identical (`wall` is un-excludable) but honest |
| L-Sit Hold | `Parallel Bars or Floor` | `bodyweight` | **normalizeToken.** A floor L-sit is a real progression; the hand-mapping would lock a floor-doable move behind equipment |
| Lunge with Twist | `Bodyweight or Medicine Ball` | `bodyweight` | **normalizeToken.** The author wrote bodyweight as an alternative |

The rule underneath: `normalizeToken`'s most-accessible-wins implements *"the
author named an unequipped alternative, so honour it"*, which is right whenever
one side is genuinely unequipped. It cannot adjudicate between two **equipped**
alternatives, which is precisely what `Bench or Box` is.

**Audit (9 rows).** Gate B scans the bodyweight-tier rows' `name`,
`coaching_cues`, `common_mistakes`, `pro_tip` and `warmup_protocol` for equipment
the row does not declare — evidence from outside the field the predicate reads.
33 findings over 21 rows: 9 already fixed by the restore, 7 genuine corrections,
5 accepted as contrasts or progressions.

Two more (`Reverse Crunch`, `Decline Push Up`) surfaced only from the tier
re-derive, which showed them *leaving* a tier they belong in. Both needed `bench`
where they need `elevated surface` or nothing. **Gate B is structurally blind to
that shape** — it scans bodyweight-tier rows, and a row over-tagged in
`equipment_needed` is not bodyweight-tier to begin with. Widening the input set to
every row whose only kit is a bench found five, of which three (Hyperextension,
Reverse Hyper, Decline Sit Up) are genuine gym benches.

**Thirty-three new rows, in two waves with different jobs.**

**Wave 1 (E262–E273) — correctness.** The corrections empty pools, so this is not
a nice-to-have. Measured deficits, before:

| pattern | baseline | core |
|---|---|---|
| `vertical_pull` | **0** | **0** |
| `horizontal_pull` | 1 | **0** |
| `elbow_flexion` | 1 | **0** |
| `elbow_extension` | 1 | **0** |
| `shoulder_isolation` | 1 | 1 |
| `vertical_push` | 2 | 2 |

"baseline" is performable with the bodyweight tier's items; "core" is performable
with the **un-excludable** floor alone (`bodyweight` + `wall`), so a user who ticks
every Customize box still fills the slot. All eleven strength patterns now hold ≥3
baseline and ≥1 core, and the tier-consistency test asserts it so a future
correction cannot quietly empty one.

`horizontal_pull`'s core row is modelled on E261 Bodyweight Rear Delt Raise, which
was already a prone scapular movement needing nothing — no new equipment concept
and no product decision, just the same shape retargeted.

**Wave 2 (E274–E294) — depth, and it was not optional.** Wave 1 took six patterns
to exactly 3 baseline rows. That satisfies the floor invariant and *cannot build a
plan*: the generator dedups on `pickedNames` across the whole plan, so a 3-row
pool is exhausted inside one week. Measured with the capability floor ON, wave 1
alone left **331 empty slots**, every one at the bodyweight tier, in exactly the
six patterns it had taken to 3:

| pattern | wave-1 rows | empty slots |
|---|---|---|
| `shoulder_isolation` | 3 | 75 |
| `elbow_flexion` | 3 | 72 |
| `hip_dominant` | 3 | 66 |
| `horizontal_pull` | 3 | 57 |
| `elbow_extension` | 3 | 39 |
| `vertical_pull` | 3 | 22 |

Worst for advanced personas (147 of the 331), because `suitableFor` narrows the
pool further still. The target of 6–7 is not a guess: `horizontal_push` already
had 6 baseline rows and zero missing, `hip_isolation` 5 and zero. Five works,
three does not. Wave 2 takes all six to 6–7 and `missing` returns to **0**.

This is the failure mode the batch was built to avoid, and it was found by
measurement rather than by reasoning — the wave-1 invariant test was green the
whole time, because "≥3 baseline and ≥1 core" is a statement about the *library*
and the empty slots are a property of the *generator running over it*.

**Re-derive, and the invariant flip.** `equipment_tier` is recomputed from
`equipment_needed` for all 271 rows. 59 rows change; 16 leave the bodyweight tier.
The consistency test goes from `⊆` to `==`. That is the substantive change: a
subset assertion is what *permitted* Chin Up to sit in the bodyweight tier while
needing a pull-up bar, so the drop side is a hard failure now, and
`sot_registry.yaml`'s "over-tags tolerated" text is marked superseded rather than
left to contradict the code.

## The seed version is part of the fix, not bookkeeping

`SeedService` re-seeds only when `storedVersion < _exerciseLibraryVersion`.
Without the 9 → 10 bump, every existing install keeps the stale rows and the whole
correction is inert for precisely the users who have the bug.

## Why Gate B is warn-no-longer

It shipped `--warn-only` under §4.11 so each retag commit could see its own drift
without 33 pre-existing findings blocking every commit. This is the commit that
finished the correction, so it flips strict — as that plan said it would.

The residue is an `_accepted` map keyed on **(row id, implied token)**, never a
bare row id: a blanket row exemption would let a genuinely new finding on an
accepted row pass silently. Two of the twelve new rows tripped the gate on their
own prose; both were fixed by rewording the row rather than by adding an
exemption, which is the outcome an accept-list should be the last resort for.

## What the 606-persona scorecard says, including the part that got worse

The measurement harness runs the full persona matrix. Before this batch it was
also **blind to the capability flag** — it reported identical numbers with the
flag on and off, because `CascadeTracer` and `QueryV4Mirror` are mirrors of the
generator and neither modelled capability. A scorecard that is green in every
world measures nothing, so both mirrors now take the same `capability` set the
production selector does, and `generator_matrix` derives it per persona.

With that fixed, the honest before/after:

| metric | before | after |
|---|---|---|
| equipment-violating plans | 201 | **0** |
| equipment violations, all tiers | 528 | **0** |
| missing / `(none)` picks | 0 | **0** |
| unsafe plans | 0 | **0** |
| total fallback picks | 1184 | **2719** |
| mean overall score | 87.00 | **86.35** |

The last two got worse and the baseline was moved, so the reasoning has to be on
the record rather than in a commit message. The old 1184 was frozen against a
library that lied: the generator was satisfying attempt 1/2 with exercises the
user could not physically perform, which scores as *high target fidelity* and is
worth nothing. Refusing those picks means the cascade relaxes instead — more
generic, but performable. The composite `overall` includes a fidelity term, which
is why it moves with it.

What makes this a re-baseline rather than shipping the symptom: the same commit
**promotes the equipment gate from a `≤ 201` ceiling to a hard `== 0`**. The
baseline's own comment had read `// HARD invariant — expected 0` beside the value
201 since it was frozen. It is 0 now, and no amount of fallback tolerance can
satisfy the new gate. If fallbacks rise again while violations stay at 0, that is
a real regression and the ceiling still catches it.

⚠ The blast radius was wider than the bodyweight tier, and only the measurement
showed it: the re-derive removed **38 rows from `home_dumbbells`** and 16 from
`basic_gym`. Those tiers were propped up by the same over-tags — 10 of the 38
needed a pull-up bar. Every removal was verified correct by reading
`equipment_needed`.

## One thing measured and deliberately not fixed

All 12 new rows' `standard_swap` targets resolve to real exercise names. Checking
that surfaced **36 dangling `standard_swap` values across the pre-existing
library** — and then that **nothing in `lib/` reads the field at all**. It is
referenced only by the schema contract test (which checks the key exists) and two
Python tooling scripts under `test/plan_generator/`. So the 36 have no user
impact and no runtime path, and building a gate for a field production never
reads would be overhead for its own sake. Recorded here rather than fixed or
filed: if a later batch wires `standard_swap` into the swap sheet — a natural
enough feature — that is the batch that inherits 36 broken targets and owes the
check.

## Recurrence

`feedback_writer_reader_field_drift_recurring.md`, with a twist worth naming: the
writer here is a **migration script**, and it drifted from the readers by
destroying information rather than renaming it. A field-name drift gate sees
nothing — the field is still called `equipment_needed` and still holds a valid
canonical token. Only prose evidence from outside the field caught it, which is
why Gate B reads `name` and `coaching_cues` rather than the field the predicate
reads.
