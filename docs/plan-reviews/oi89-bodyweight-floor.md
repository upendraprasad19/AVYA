---
branch: oi89-bodyweight-floor
date: 2026-08-28
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi89-bodyweight-floor-bpass.md
---

# Plan-review record — oi89-bodyweight-floor (platform)

Keystone record for the §4.12 merge gate.

**Platform, not `account` as the OI board estimated.** OI-89's own entry says
*"blast radius `account` … no migration, no schema"*. Both halves are now false:
the batch applied three migrations (124, 125, 126) and changed root `CLAUDE.md`,
which is path-pinned platform in `docs/blast_radius.yaml`. The board is corrected
in the same batch.

## What the branch is

`equipment_tier` was the only field the plan generator filtered on, and it is a
CURATION hint that the SoT registry itself documented as *"over-tags tolerated"*.
So Chin Up — which needs a pull-up bar — sat in the bodyweight tier and shipped
to users who told us they own nothing.

The batch replaces that with a capability model:
`effective = tierItems[tier] ∪ equipment_owned − equipment_exclusions`, and the
predicate `canPerform(equipment_needed, effective)` keyed on `equipment_needed`,
never on `equipment_tier`.

## Spec and plan

- Spec: `docs/superpowers/specs/2026-08-28-equipment-capability-design.md`
- Plan: `docs/superpowers/plans/2026-08-28-equipment-capability.md` (13 tasks)

## Review rounds

**Round 1** (context-blind, on the first plan) — material findings:

1. The four vocabulary structures (`canonicalTokens`, `_precedence`,
   `_chipLabels`, `_aliases`) move in lockstep or a token is silently DROPPED
   from an OR-compound, yielding `[]` = "no requirement" — the most permissive
   possible result. Produced Gate A.
2. `_exerciseLibraryVersion` must be bumped or the retag is inert for every
   existing install — live only for fresh ones.
3. The seam count was wrong. It went 5 → 7 → 10 → 11 across the rounds, which is
   a method failure rather than a counting one, and produced Gate B's sibling
   `check_exercise_seams.dart` pinning the inventory by count.

**Round 2** (on the HARDENED plan, per §4.12.1 — the corrections themselves can
introduce defects, and here they did):

1. **The round-1 ordering fix was itself wrong.** It flipped the flag ON before
   the retag, which leaves every bodyweight `vertical_pull` slot null:
   `universalPoolV4['vertical_pull']` was Pull Up / Chin Up / Inverted Row, all
   skipped after the retag. Fixed by making Task 8 **atomic** — data and new
   exercises in one commit.
2. **`vertical_pull` needs three new rows, not one.** The round-1 draft shipped
   only Prone Lat Pull, arguing the other two fail the un-excludable core — true
   but irrelevant to the ≥3 *baseline* assertion, which they satisfy.
3. **The scorecard cannot verify the flip.** It runs through a mirror that holds
   no `PlanEngineFlags` reference, so it is green in every world. Round 2
   directed verification to the Task 5 behavioural test instead. *(Execution
   later proved this understated: the mirror did not model capability at all —
   see "What execution found" below.)*

Verdict: **converged.** Round 2's findings were corrections to round 1's
corrections rather than new defect classes, which is the §4.12.1 convergence
signal; the unit was not split.

## Ground-truth verification

Every claim below was checked against the working tree or live prod, not against
subagent prose:

- `equipment_tier` over-tag: read in `docs/sot_registry.yaml` — the invariant
  literally reads *"over-tags tolerated (a separate later drop-side pass)"*. This
  batch is that pass; the text is marked superseded.
- Live schema before the change: `information_schema` confirmed
  `equipment_access` (text) and `equipment_exclusions` (ARRAY) present,
  `equipment_owned` absent.
- Live `exercise_library`: 259 rows, and **`equipment_tier` is NOT a cloud
  column** — only `equipment_needed` is. So the cloud never carried the tier
  over-tag, and what migration 125 fixes cloud-side is the DESTROYED
  `equipment_needed` values that `beat-my-coach:193` filters on.
- Migration numbering: 122 and 123 were already taken (122 by OI-98, applied
  2026-08-26 — two days after the design named it). Re-read from the ledger tail
  rather than trusted from the spec.
- Post-apply verification for all three migrations is recorded in
  `backups/applied_migrations.json` with the values observed.

## What EXECUTION found that neither review round did

Recorded because it is the honest lesson of this batch: the ×2 review converged
on a design that was still wrong in two measurable ways, and only running the
thing exposed them.

1. **The measurement harness was green in every world.** Round 2 said the
   scorecard "cannot read the flag". The truth was worse: `CascadeTracer` and
   `QueryV4Mirror` never modelled capability at all, so the harness reported
   **byte-identical numbers with the flag ON and OFF**. Found by toggling the
   flag and expecting movement. Both mirrors now take the same `capability` set
   production does.
2. **Three baseline rows per pattern satisfies the invariant and cannot build a
   plan.** The floor test went green while the generator left **331 empty
   slots** — `pickedNames` dedups across a whole plan, so a 3-row pool is
   exhausted inside one week. 21 further rows were needed, calibrated against
   the two patterns that already worked (6 rows / zero missing, 5 / zero).

Both are now bug-classes §2.53 and §2.54 in `.claude/skills/debugging/SKILL.md`.

## B-pass

`docs/reviews/oi89-bodyweight-floor-bpass.md` — 3 findings (2 P1 fixed, 1 P2
recorded as residual), 0 false alarms.

⚠ **The B-pass was run INLINE by the author, not by a fresh context-blind
subagent**, because this session carries a standing instruction not to call the
Agent tool unasked. This is a real weakening and the review file states it up
front. Both P1s were nonetheless code written hours earlier in the same session:
a `universalPoolV4` reorder that regressed `home_dumbbells` users while the
commit comment claimed no reorder had happened, and a gate whose scope excluded
the defect class it existed to catch.

## Outcome measured across 606 personas

| metric | before | after |
|---|---|---|
| equipment-violating plans | 201 | **0** |
| equipment violations, all tiers | 528 | **0** |
| missing / `(none)` picks | 0 | **0** |
| unsafe plans | 0 | **0** |
| total fallback picks | 1184 | 2719 |
| mean overall score | 87.00 | 86.35 |

The last two were **re-baselined**, which §4.2 discipline treats with suspicion,
so the reasoning is on the record in the gate test and diagnose `f7b2c4`: the old
numbers were frozen against a library that lied, so the generator was scoring
high target fidelity using exercises users cannot perform. What makes it a
re-baseline rather than shipping the symptom is that the same commit **promotes
the equipment gate from a `≤ 201` ceiling to a hard `== 0`** — the baseline's own
comment had read `// HARD invariant — expected 0` beside the value 201 since the
day it was frozen.

⚠ **Blast radius exceeded the bodyweight tier and only measurement showed it:**
re-deriving `equipment_tier` removed 38 rows from `home_dumbbells` (10 needed a
pull-up bar) and 16 from `basic_gym`. Every removal was verified correct against
`equipment_needed`. Those tiers' plans become more generic — a product
consequence surfaced to the founder, not a defect.

## Live prod applies

Three, each explicitly authorized in Task 0 and each verified after the fact:

- **124** `user_profile.equipment_owned text[]` — applied before the UI that
  writes it, deliberately (`user_repository.dart:721` upserts a spread and
  `_sanitize` does not whitelist, so a client carrying a key the DB lacks gets a
  PostgREST 400 that rejects the whole row).
- **125** `exercise_library` re-seed, 259 → 292 rows.
- **126** the single-row E260 correction from B-pass finding 2.
