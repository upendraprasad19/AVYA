# Capability authoritative at every tier — implementation plan

**Spec:** `docs/superpowers/specs/2026-08-28-capability-authoritative-all-tiers-design.md`
**Board:** OI-144 · **Blast radius:** platform · **Flag:** rides the existing
`enable_equipment_capability_floor` (kill switch `disable_equipment_capability_floor`)

**Goal:** owning a pull-up bar unlocks pull-ups at any tier, so the Profile picker stops
collecting an answer the generator ignores.

---

## Review rounds

### Round 1 — two material findings, both verified against code

**R1-A (P0) — the harness cannot observe this fix.** `generator_matrix.dart` personas carry
`equipmentExclusions` and **no `equipmentOwned` field at all** (`:29`, `:38`, `:288`). Every one
of the 606 personas owns nothing, so with or without this change nothing widens and every number
is identical. Shipping on those numbers would be the §2.53 *green in every world* class — which
this batch already hit once, in the mirror.

**R1-B (P1) — a fail-OPEN path becomes reachable.** `EquipmentVocab.effectiveItems:347` returns
**every canonical token** for an unrecognised tier. That is unreachable from production today
*because* `resolveCapability` gates on `tier == 'bodyweight'` — the very gate §3.1 removes. After
the change, a corrupt `equipment_access` (say `'foo'`) yields capability = everything, the tier
filter is skipped, and the user is offered barbell work at attempt 1. `equipment_capability_test.dart:84`
pins the fail-open explicitly, so this is a deliberate contract, not an oversight — but the
reasoning that justified it no longer holds once the branch is reachable.

### Round 2 — on the hardened plan; both R1 fixes were wrong as first drafted

**R2-A — R1-A's obvious fix breaks the baseline again.** Adding owned personas to the matrix
changes the persona count, hence every aggregate, forcing a **third** re-baseline in one day. The
scorecard is a *no-regression* harness with a frozen baseline; it is the wrong instrument for
proving a new capability. **Correction:** leave the matrix alone — its job is to prove the
no-owned case is unchanged. Prove the widening in a dedicated `test/contracts/` behavioural test,
which is what rule 21 wants anyway (fails without the fix, passes with it).

**R2-B — R1-B's obvious fix changes a primitive's contract.** Making `effectiveItems` fail
*closed* on an unknown tier would redden `equipment_capability_test.dart:84` and change the
vocabulary primitive for every caller, including the AI-coach snapshot where fail-open is
defensible. **Correction:** put the policy in the PRODUCER. `resolveCapability` treats an
unrecognised tier as `bodyweight` — mirroring `equipmentAccessOf`'s existing fail-safe default —
and `effectiveItems` keeps its contract and its test.

**Verdict: converged.** Round 2 corrected round 1's corrections rather than surfacing new defect
classes, which is the §4.12.1 convergence signal. Not split.

⚠ **Method deviation:** both rounds were run inline by the author, not by fresh context-blind
subagents, because this session carries a standing instruction not to call the Agent tool unasked.
Materially weaker; recorded so the plan-review record does not overstate.

---

## Task 1 — the producer answers at every tier

**Files:** `lib/shared/repositories/plan_engine/training_history_analyzer.dart`

- [ ] Remove `if (tier != 'bodyweight') return null;` from `resolveCapability`.
- [ ] Add the R2-B guard: an unrecognised tier resolves to `bodyweight`, not to fail-open.
      `null` retains exactly ONE meaning — flag off, or Hive unreadable.
- [ ] Update the docstring: it currently states the bodyweight scoping as the design.

## Task 2 — capability subsumes the tier filter

**Files:** `lib/shared/repositories/exercise_repository.dart` (the ONE production read, `:315`)

- [ ] `if (capability != null) { /* authoritative */ } else if (tierLower != null) { …legacy… }`.
      **Not** both — running both keeps the tier block binding and nothing widens.
- [ ] Leave filter 2c (exclusions) alone and say why in a comment: it is a separately-flagged
      filter with its own kill switch (spec O3), and collapsing two independently-flagged filters
      removes a switch the founder may want.
- [ ] Correct the comments at `exercise_selector.dart:503` and `:699`, which assert that filtering
      keys on the tier.

## Task 3 — the oracle and the mirror, or the harness lies

**Files:** `test/plan_generator/plan_scorecard.dart`, `test/plan_generator/v4_diagnostic/query_v4_mirror.dart`

- [ ] `_equipmentViolations` keys on `equipment_tier` (`:248-261`) and OI-89 just promoted it to a
      hard `== 0`. Make it capability-aware, or a legitimately-unlocked Chin Up reports as a
      violation and the gate fails on correct behaviour.
- [ ] `query_v4_mirror` must take the same `else if`. A mirror that keeps running both filters
      measures the pre-fix world — §2.53 again.

## Task 4 — the behavioural test (R2-A: here, not in the matrix)

**Files:** `test/contracts/equipment_owned_widens_test.dart` (new)

- [ ] A `home_dumbbells` user owning `pull-up bar` receives pull-up-bar exercises;
      **the same user owning nothing does not.** Both halves, or it proves nothing.
- [ ] Drive the REAL `queryV4` and `ExerciseSelector.pickV4`, not the mirror.
- [ ] The oracle reads `equipment_needed` off the built `PlannedExercise` — never `equipment_tier`,
      which is the field under test.
- [ ] A `full_gym` user owning nothing gets a byte-identical candidate set to the legacy path
      (the §5 "unchanged for everyone else" claim, as evidence rather than argument).
- [ ] An unrecognised tier gets the BODYWEIGHT floor, not everything (R1-B/R2-B).
- [ ] The kill switch still yields `null` → legacy tier path intact.

## Task 5 — records

- [ ] Diagnose-doc (this is a `fix:` — OI-144 is a defect, not a feature).
- [ ] `docs/sot_registry.yaml`: `equipment_capability_floor` says the floor is bodyweight-scoped.
      That stops being true.
- [ ] `plan_engine/CLAUDE.md` + `profile/CLAUDE.md`: both now say owned widens at bodyweight only.
- [ ] Update `docs/plan-reviews/oi89-bodyweight-floor.md` — the branch grew past its converged
      scope, so the record must cover this work or it describes a diff that no longer exists.
- [ ] OI-144 → CLOSED with `closes-oi:`.
- [ ] Closure ledger gains the OI-144 entries.

## Task 6 — verify

- [ ] Full suite. The scorecard must be **unchanged** — that is the R2-A claim, and any movement
      means the no-owned path was not preserved.
- [ ] `flutter analyze lib test` clean.
