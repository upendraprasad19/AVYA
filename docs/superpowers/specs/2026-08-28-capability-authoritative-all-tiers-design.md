# Capability becomes authoritative at every tier — design

**Board:** OI-144. **Closes:** the collect-but-ignore defect introduced by OI-89 Task 11.
**Blast radius:** `platform` — it changes what `queryV4` treats as authoritative for every user
of every tier, not only bodyweight.

**Precondition:** this design only makes sense *after* OI-89's equality flip. See §2.

---

## 1. The defect, stated once

`edit_profile_screen` offers a `home_dumbbells` user **13 chips** — `pull-up bar`, `kettlebell`,
`bench`, `barbell`, … — writes their answer to `userBox['profile']['equipment_owned']`, syncs it
to `user_profile.equipment_owned` (migration 124), and raises the **"Reschedule Workouts?"**
prompt when it changes (`computePlanChanged`).

The regenerated plan is byte-identical.

Two independent reasons, and BOTH must be removed or the fix does nothing:

1. `TrainingHistoryAnalyzer.resolveCapability` returns `null` for every tier above `bodyweight`
   (`training_history_analyzer.dart:~200`, decision 1 of OI-89), so `queryV4`'s capability filter
   is skipped entirely for gym-tier users.
2. Even with capability supplied, `queryV4`'s **tier block** (`exercise_repository.dart`, filter 3)
   independently drops any row whose `equipment_tier` list lacks the user's tier string. Chin Up
   is `[basic_gym, full_gym]`, so a `home_dumbbells` user never sees it however the capability set
   is computed. **Fixing only (1) changes nothing.**

Same family as `enable_equipment_exclusions`, whose flag comment calls this shape *"a live broken
promise, rather than an unshipped feature"*.

## 2. Why this is now safe, and would NOT have been three commits ago

`equipment_tier` used to carry information `equipment_needed` did not — the SoT registry
documented it as ADD-only with *"over-tags tolerated"*, i.e. a curated, deliberately imprecise
"reasonable at this tier" hint. Replacing it with a capability check would have silently discarded
that curation.

OI-89 flipped the invariant to **equality**: `equipment_tier == derive(equipment_needed)` for all
292 rows, asserted on both sides by `equipment_tier_consistency_test.dart`. The field is now a
pure function of `equipment_needed`.

**So the tier filter and the capability filter compute the same thing from the same data.** The
tier filter is redundant wherever capability is present, and removing it discards no curation
because there is none left to discard. This is the load-bearing argument for the whole design; if
the equality invariant is ever relaxed, this fix must be revisited.

## 3. The change

### 3.1 `resolveCapability` answers at every tier

Drop the `if (tier != 'bodyweight') return null;` early return. `null` retains exactly one
meaning: **the flag is off, or Hive could not be read** — i.e. *do not enforce*. It stops doubling
as "this tier is out of scope".

`effectiveItems(tier, owned, exclusions)` already handles every tier correctly and already
fails OPEN to all canonical tokens on an unknown tier.

### 3.2 `queryV4`: capability SUBSUMES the tier filter

```
if (capability != null) {
  // capability is authoritative; the tier block is skipped (see §2)
} else if (tierLower != null) {
  // legacy path, unchanged, byte-identical
}
```

Not "run both" — running both keeps the tier block as the binding constraint and the widening
never happens. This is the crux of the fix.

### 3.3 What each user actually experiences

| user | before | after |
|---|---|---|
| bodyweight, owns nothing | hard floor | **unchanged** |
| bodyweight, owns pull-up bar | already widened (decision 4) | **unchanged** |
| home_dumbbells, owns nothing | tier filter | same set, via capability |
| **home_dumbbells, owns pull-up bar** | **bar ignored** | **pull-ups unlocked** |
| full_gym, no exclusions | tier filter | same set (tier grants everything) |
| any gym tier, with exclusions | exclusions filter (2c) narrows | same, now also via capability |

The only behaviour that CHANGES is the row this bug is about. Everything else must be provably
identical — see §5.

## 4. What must NOT change, and why each is a real hazard

1. **Attempt-4 must keep dropping the tier while KEEPING capability.** Verified already correct at
   `exercise_selector.dart:1186-1192` — `equipmentTier` is not passed, `capability` is. If
   capability now subsumes the tier, attempt-4 becomes "relax nothing", which is a behaviour
   change to the cascade. **Open question O1 in §6.**
2. **`canPerform` fails CLOSED on an unreadable requirement.** Extending capability to every tier
   extends that failure mode to every tier. A community-synced row with a malformed
   `equipment_needed` is currently dropped only for bodyweight users; after this it is dropped for
   everyone. That is the correct direction (do not prescribe what we cannot verify) but it is a
   widening of a fail-closed path and must be stated, not discovered.
3. **The scorecard oracle keys on `equipment_tier`** (`plan_scorecard.dart:248-261`). A
   legitimately-unlocked Chin Up for a `home_dumbbells` owner would be reported as an EQUIPMENT
   violation — and OI-89 just promoted that to a **hard `== 0`** gate. The oracle must become
   capability-aware in the same commit or the gate fails on correct behaviour.
4. **`generator_matrix` derives capability only for `bodyweight`** (added this batch). It must
   derive it at every tier or the 606-persona harness measures the old world — the exact
   "green in every world" class this batch already hit once (`debugging` §2.53).

## 5. How "unchanged for everyone else" gets proven, not asserted

A user who owns nothing must get a byte-identical plan. The claim is checkable:
`effectiveItems(tier, [], [])` is exactly `tierItems[tier]`, and a row passes the tier filter iff
its `equipment_tier` contains the tier, which after the equality flip is true iff
`equipment_needed ⊆ tierItems[tier]` — the capability predicate. The two filters are therefore
extensionally equal on the no-owned, no-exclusions case.

That is an argument, not evidence. The evidence is a test that runs the full 606-persona matrix
with `owned = []` and asserts the pick set is identical to the frozen baseline, plus the existing
scorecard gates holding at `equipment violations == 0` and `missing == 0`.

## 6. Open questions for the ×2 review

- **O1 — what should attempt-4 mean now?** If capability subsumes the tier, attempt-4's "drop the
  equipment tier" relaxes nothing. Options: (a) leave it — it becomes a no-op step, harmless but
  dead; (b) delete it and renumber the cascade — cleaner, but touches the cascade's shape and
  every trace/mirror that names the attempts; (c) have attempt-4 relax to the *tier's* items while
  keeping owned — incoherent, since that is what attempt-3 already produced. Recommend (a) with a
  comment, and file the deletion separately; do not renumber a cascade inside a fix for a
  different bug.
- **O2 — RESOLVED by enumeration, not left open.** Every `equipment_tier` reference in the repo
  was listed rather than recalled:
  - **Production reads of the FIELD AS DATA: exactly one** — `exercise_repository.dart:315`
    (`final tiers = e['equipment_tier'];`), inside `queryV4` filter 3. That is the whole
    production surface, and it is precisely what §3.2 changes.
  - The two `exercise_selector.dart` hits (`:503`, `:699`) are **comments**, as are the ones in
    `seed_service`, `equipment_vocab`, `equipment_capability` and `plan_engine_flags`. Several
    will need their wording revisited because they assert the tier is what filtering keys on.
  - **`supabase/functions/`: ZERO.** It is not a cloud column and no Edge Function reads it.
  - **Test-side readers, 6 files:** `plan_scorecard.dart` (the oracle — §4.3 hazard),
    `query_v4_mirror.dart` (the mirror — §4.4 hazard), `equipment_tier_consistency_test.dart`
    (asserts the equality invariant; unaffected and still valid),
    `v4_diagnostic_test.dart`, `v4_diagnostic/library_integrity.dart`,
    `community_equipment_normalize_behavioral_test.dart` — the last three need reading before
    implementation; they are not yet classified.
  This narrowness is the strongest argument that the change is tractable: **one production line
  moves.** Everything else is oracle, mirror and prose.
- **O3 — should the exclusions filter (2c) be folded into capability?** `effectiveItems` already
  subtracts exclusions, so 2c becomes redundant when capability is present. Removing it is
  tempting and out of scope: it is a *separate* flag (`disable_equipment_exclusions`) with its own
  kill switch, and collapsing two independently-flagged filters into one removes a kill switch
  the founder may want. Recommend explicitly leaving 2c alone and saying so in the code.
- **O4 — flag or no flag?** OI-89's floor shipped behind `enable_equipment_capability_floor`,
  now default ON with a `disable_` kill switch. This change rides that same flag rather than
  adding a second one — but that means the kill switch now disables *more* than it used to.
  Review should confirm that is acceptable, or require a distinct flag.

## 7. Not in scope

- Authoring more `home_dumbbells` exercises. The `vertical_pull` 100%-attempt-3 residual is
  **physics** — every compound vertical pull needs `cables`, `pull-up bar`, `bench` or `machines`
  — so content cannot close it. This fix closes it for users who own a bar, which is the honest
  remedy.
- Deleting attempt-4. See O1.
- Touching `plan_generator.dart`. Rule 14; the previous authorization was per-edit and does not
  carry.
