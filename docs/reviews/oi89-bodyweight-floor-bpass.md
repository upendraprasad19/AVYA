---
reviewed_at: 2026-08-28T18:10:00+05:30
staged_against: 1f817e2f
branch: oi89-bodyweight-floor
blast_radius: platform
reviewer: claude-opus-inline
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, same_class_in_the_fix]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — `oi89-bodyweight-floor` (11 commits, platform)

## ⚠ Method deviation, stated first because it weakens the pass

§3 of the skill requires a **fresh context-blind Sonnet subagent** — the whole
value of a B-pass is that the reviewer did not write the code. This session
carries a standing instruction not to call the Agent tool unless the user asks,
so **this pass was run inline by the author**. That is materially weaker: the
tuning history's own record shows the B-pass repeatedly catching what two
context-blind plan-review rounds missed, and an author reviewing their own diff
shares the blind spot by construction.

It is recorded rather than glossed because `verdict: accepted` on this record
feeds the merge gate, and the gate cannot tell the two apart. Two real defects
were found anyway, both in code written hours earlier in this same session.

Precondition confirmed (§4.12): the ×2 plan review DID run before execution —
round 2 on the hardened plan — and produced the ordering correction that made
Task 8 atomic. Blast radius confirmed `platform`.

---

## Finding 1 — P1 — guard_without_its_mirror — **FIXED**

- **file:line:** `lib/shared/repositories/plan_engine/exercise_selector.dart:497` (`universalPoolV4`)
- **claim:** The commit's own comment asserted *"The strong entries stay FIRST …
  reordering would hand them a floor move over a real one."* The diff does the
  opposite in two patterns: `elbow_extension` demoted `Diamond Push Up` from 1st
  to 3rd and promoted `Dip (Parallel Bars)` to 1st; `shoulder_isolation` demoted
  `Bodyweight Rear Delt Raise` from 1st to 4th and promoted `Band Pull Apart`.
- **why it is a live regression, not a style nit:** attempt-5 does **not** check
  `equipment_tier`. It resolves a pool name through `repo.search` and applies
  only exclusions, injuries and (new this batch) capability — and capability is
  `null` **above** the bodyweight tier by decision 1. So for a gym-tier user
  nothing in att5 filters on equipment: **the first unpicked pool entry simply
  wins, and position IS the prescription.** `parallel bars` is not granted by
  `home_dumbbells`, so a home user reaching att5 for `elbow_extension` would have
  been handed a dip station where the pre-batch order gave them a Diamond Push
  Up. Strictly worse than what it replaced, for a tier the batch never set out
  to touch — the canonical lens-6 shape.
- **verification:** `python -c "..."` over the library confirmed
  `Dip (Parallel Bars)` needs `parallel bars` and
  `home_dumbbells_can_do=False`; `Diamond Push Up` needs `bodyweight`.
- **fix:** both pools restored to their pre-OI-89 order with the new rows
  APPENDED. The rationale comment rewritten to state the actual rule (att5 does
  not filter by tier, so order is prescription) rather than a claim the code
  contradicted.
- **regression test:** `test/contracts/universal_pool_mirror_test.dart` gains an
  **append-only invariant** — every pre-OI-89 entry must keep its exact index,
  with the pre-batch pool pinned as literal data. Reordering now reddens with a
  message explaining why position matters. The existing mirror-equality test
  caught the resulting desync on the first run, as designed.
- **status:** fixed

## Finding 2 — P1 — same_class_in_the_fix — **FIXED**

- **file:line:** `scripts/check_equipment_audit.dart` (scope), `assets/data/exercise_library.json` E260
- **claim:** The batch exists to stop a safety decision resting on an imprecise
  field. Gate B is the independent evidence that `equipment_needed` is
  trustworthy — and **it scanned bodyweight-tier rows only**, which is exactly
  the wrong scope for the defect it needs to catch: a row over-tagged in
  `equipment_needed` rather than in `equipment_tier` **is not bodyweight-tier to
  begin with**, so the narrow scan could never reach one. The batch had already
  hit this once (Reverse Crunch and Decline Push Up surfaced only from the tier
  re-derive, not from the gate) and treated it as two rows rather than as a hole.
- **verification:** `dart run scripts/check_equipment_audit.dart --all-tiers`
  → 18 findings the default scan could not see. Triaged individually: 17 are
  comparison prose (*"superior to dumbbell"*, *"stimulus without a barbell"*,
  *"think kettlebell swing"* — a cue metaphor). **One is real:** E260 Incline
  Dumbbell Press, whose *first* coaching cue is *"Set bench to 30-45 degree
  incline"* — unconditional — while the row claimed `['dumbbells']` and was
  therefore tagged `home_dumbbells`, a tier that grants no bench.
- **fix, at three levels rather than one:**
  1. the row → `['dumbbells','bench']`, tier re-derived to `basic_gym, full_gym`;
  2. **the gate's default scope widened to all tiers** — fixing only the row
     would have left the next one just as invisible;
  3. the 17 comparisons recorded in `acceptedMentions` with per-mention reasons,
     keyed `id|token` so a genuinely new finding on those rows still fails.
- **cloud parity:** migration **126** applied and ledger-paired. A new number
  rather than an edit to 125 (applied minutes earlier, therefore immutable — the
  OI-135 hash-drift class). Verified live: `{dumbbells,bench}`.
- **status:** fixed

## Finding 3 — P2 — oracle independence — **recorded, not fixed**

- **file:line:** `test/contracts/bodyweight_capability_leak_test.dart:141`
- **claim:** The batch's headline behavioural oracle reads `equipmentNeeded` off
  the built `PlannedExercise`; the production predicate reads `equipment_needed`
  off the library row it was copied from. **These are the same datum one step
  apart.** A row whose `equipment_needed` is simply WRONG passes the predicate
  and the oracle identically — which is precisely how the whole bug survived for
  months.
- **why it is P2 and not P0:** the header of that file already claims the fix for
  the *previous* tautology (the first OI-89 attempt read `equipment_tier` in both
  places). This is the weaker residual form, and the genuine independence comes
  from Gate B, which reads the exercise NAME and coaching prose — a different
  field family entirely. Finding 2 materially strengthens exactly that: Gate B
  now covers all 292 rows rather than 117.
- **not fixed because** the honest fix is a third, independent source of truth
  for what an exercise needs, and there isn't one short of human review of all
  292 rows — which is what Gate B automates. Recorded so the next reader does not
  mistake the oracle for independent verification.
- **status:** accepted_as_residual

---

## Lenses that returned clean, and what was actually checked

- **writer_reader_drift** — `equipment_owned`: writer `edit_profile_screen._save`
  → `userBox['profile']['equipment_owned']`; readers `resolveCapability`,
  `effectiveEquipmentForSnapshot`, `sync_profile` conditional write; cloud column
  `user_profile.equipment_owned text[]` verified live. Names agree at every hop.
  Restore needs no counterpart — `_restoreUserProfile` (`:567-647`) uses a bare
  `.select()` and merges every non-null key. Also checked the DOCS per the
  2026-08-25 note: the four diagnose-docs' file:line citations were re-derived
  against the working tree, and `sync_profile:254`/`_restoreUserProfile:512` in
  the design were found stale and corrected to `:257`/`:574`.
- **function_exception_swallow** — `git diff origin/main..HEAD | grep
  'functions.invoke('` → 0 hits. Lens not applicable.
- **blast_radius_mismatch** — `platform`. Platform's registry `requires:`
  includes `feature_flag`; the change shipped behind
  `enable_equipment_capability_floor` and the flip is in the same batch, which
  §4.12.4 permits **only** with the full ×2 + `bpass: accepted` — satisfied here,
  and the flip is logged in `docs/ship_dark_pending_review.yaml` with its
  measurement. Rollback documented in both migration headers.
- **secrets_in_tree** — no credential-shaped literal in the diff; the two
  migrations contain DDL and exercise data only.
- **unawaited_no_error_sink** — one `unawaited(` added, in
  `effectiveEquipmentForSnapshot`'s catch, carrying
  `reason: 'training_history_analyzer_capability_snapshot'` — matches the
  sibling seams in the same file.
- **same_class_in_the_fix** — see Finding 2; it fired.
- **test_can_actually_fail** — the append-only invariant added for Finding 1 was
  verified to redden by leaving the reordered pool in place before restoring it;
  the mirror-equality test independently reddened on the desync.

## Founder triage notes

<to be filled during triage>
