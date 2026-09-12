# OI-166 Unit 2 — plan review round 3 (two context-blind reviewers)

**Date:** 2026-09-10 · **Plan:** `docs/audit/oi166-unit2-plan.md` (v3, re-planned after round 2)
**Verdicts:** design reviewer **not-converged** · ground-truth reviewer **not-verified**

⚠ **The v3 plan text no longer exists.** It was never committed, and I destroyed it on
2026-09-10 while adding a rejection banner — a Python `open(path, 'w')` truncated the file before
an encoding error aborted the write. `docs/audit/oi166-unit2-plan.md` now holds **v2** (the last
committed version) under a banner explaining this. **This record is therefore the only surviving
account of v3**, which is why its design is restated here: anchor `plan_start`, explicit
`weekCount = 4`, `nominalEnd = planStart + 27d`, `weekNumber = rawWeekNumberFor(date, planStart)`,
writes over `[max(today, planStart) .. nominalEnd]`. Since v3 is rejected, the loss costs nothing
forward-looking — but it is stated plainly rather than quietly repaired.

Third round on the third version of this plan. Both reviewers negative, independently, on
overlapping defects. Per §4.12.1 this is the signal the unit is the wrong shape — it is not an
invitation to a fourth version.

⚠ Findings marked **CONFIRMED** were re-opened against source by the author. Findings marked
**RELAYED** are recorded on the reviewer's word alone and are hypotheses per
`feedback_audit_verifier_cannot_trust_own_subagent.md`.

---

## The headline: v3's fix introduced a P0 that `main` does not have

**M1 — CONFIRMED, P0, data loss.** v3 bounds the *write* range at `nominalEnd = planStart + 27d`
while the caller's *delete* loop is bounded by `plan_end`
(`workout_schedule_read_service.dart:358-377`). When `plan_end > planStart + 27d` the regen deletes
rows it never rewrites.

Reachability was traced leg by leg, and **no leg carries an expiry gate**:

| Leg | File | Gate? |
|---|---|---|
| Train screen renders the unlock card | `screen.dart:376` | none |
| Card shows Thu–Sun of week 4, in-phase | `phase_unlock_card.dart:21-24` | in-phase only |
| Free keep-training action | `keep_training_phase1_action.dart` `runFreeTierRepeatWrite` | none |
| `redoWeek4` extends `plan_end` to `planStart + 34d` | `workout_schedule_write_service.dart:213-214` | none |

A regen the next day deletes `planStart + 25..34` and writes only `..27` — **7 empty days while
`plan_end` still claims they exist.** This is a regression created by the fix, in a state the
current code handles correctly.

## Defects the two reviewers found independently

| # | Finding | Status |
|---|---|---|
| M4 / F1 | `tool_dispatcher.dart:918` belongs to `_executePausePlan`, where `startDate` is **required**. Following v3 literally breaks `pausePlan` | **CONFIRMED** |
| M9 / F5 | `liftExerciseFromStash` **does not exist** — `git grep` in `lib/` returns 0. The real symbol is `_liftExercise` (`deload_evaluator.dart:294`), private and instance-level | **CONFIRMED** |
| M7 / F2 | The allowlist is **file-keyed**, so step 7's `permanent` entry would re-exempt callers A and B, not just the new builder | RELAYED |
| F3 | The plan budgets **4** hardcoded week strings; there are **6** | **CONFIRMED — see below** |
| F4 | OI-188's `progression_resolver` citations sit behind a **default-OFF** flag | **CONFIRMED — see below** |
| G1 | Deno tests would go red, invisibly (no Deno on this machine) | **CONFIRMED — see below** |
| G2 | Zero provider invalidations named, against a SoT concept declaring four | RELAYED |
| — | `platform` `requires:` is **four** items (`blast_radius.yaml:23-25`), not two as v3 stated | **CONFIRMED** |

**Ground-truth tally:** 112 claims checked — 6 wrong, 11 imprecise, 3 unverifiable.

### F3 — six week strings, not four (author's own round-2 record was the source of the 4)

Round 2's P1-4 cited four (`regenerate_plan_diff.dart:108`/`:138-139`,
`switch_goal_diff.dart:153-154`/`:177-178`). A grep of both files for `eek` returns six
user-facing strings:

```
regenerate_plan_diff.dart:108  '${plan.totalWeeks}-week plan'
regenerate_plan_diff.dart:126  'WEEK 1  ·  $replaceCount replace · $skipCount skip'   ← missed
regenerate_plan_diff.dart:139  'weeks 2-${plan.totalWeeks}'
switch_goal_diff.dart:153-154  'the next N week(s) regenerated.'
switch_goal_diff.dart:165      'NEW WEEK 1'                                           ← missed
switch_goal_diff.dart:178      'weeks 2-${plan.totalWeeks}'
```

Both missed strings are the **"WEEK 1" eyebrows** — the two that are most wrong for a mid-phase
regen, because they are the ones that state a week number outright. The round-2 pattern searched
for the phrases it expected; `feedback_green_check_input_set_width` in its purest form, in a
document written to record that very lesson.

### G1 — the Deno breakage is bigger than reported, and none of it is visible locally

The reviewer said 4 tests. The census (`grep -n "weeks:\|startDate\|start_date"` over both test
files) says the count depends on which resolution v3 picks for round 2's still-open P1-3:

- **Narrowing `weeks` to max 4 alone reddens 3** — `regeneratePlanBlock_test.ts:114` (`weeks: 6`),
  `switchGoal_test.ts:17` and `:96` (`weeks: 8`).
- **Removing `startDate` reddens up to 5 more.** Certain: the two payload assertions
  (`regeneratePlanBlock_test.ts:98`, `switchGoal_test.ts:85`/`:100` assert `start_date` equals
  `null`/a date — the key would vanish). Inferred, not executed: the two malformed-`startDate`
  rejection tests (`regeneratePlanBlock_test.ts:83-89`, `switchGoal_test.ts:72-78`) flip to
  accepting, which depends on zod's unknown-key policy and **could not be run here**.

⚠ **There is no Deno on this machine** (CLAUDE.md §0), so `flutter analyze`, the 78 pre-commit
gates and pre-push are all blind to every one of these. First signal would be CI, after the push.

### F4 — OI-188 defect 3 cited ship-dark code, and the correction goes further than the citation

`progression_resolver.dart:307` (`beginnerLinear`) and `:318` (`reps >= hi`) are both inside
`_gradedSuggestion`, called only at `:189` under `if (graded)`, where
`graded = PlanEngineFlags.gradedProgressionEnabled` (`:61`) — **default false**
(`plan_engine_flags.dart:47-54`). `beginnerLinear` is not even computed unless `graded` (`:126`).

So *"beginners are on the unconditional ramp"* is **false in production**. What ships is the fixed
rule at `:203-215`: reps ≥10 → `base + 5.0` (lower) / `+2.5` (upper); ≥5 → hold; <5 → back off.

**Verifying that citation surfaced two facts that invert the defect**, neither of which any
reviewer raised:

1. **The ramp is per PHASE, not per session.** `ProgressionResolver.resolve()` has exactly one
   caller — `plan_generator.dart:235` — and returns `{}` for `phase <= 1`. Its output becomes
   `suggestedWeight`, applied identically to **every week** of the phase
   (`periodization_engine.dart:112-115`); the wave varies **sets and reps**, not weight
   (`_waveReps`, `:262`). So defect 3's *"back to full load in 3-4 weeks"* is wrong in mechanism.
   From a −50% cut, the plan's suggested weight recovers at **+2.5–5 kg per 4-week phase** —
   ~10 phases to undo a 100 kg → 50 kg cut. The hazard is the **opposite** of the one filed.
2. **The detraining decay never fires for a free user at all.** Both its call sites are closed to
   them: ⑦(a) lives inside `resolve()`, which returns `{}` for phase ≤ 1, and ⑦(b)
   (`train_provider.dart:1312`) is behind `sessionDetrainingCutEnabled`, **default OFF**. A free
   user is on phase 1 by definition (rule 6 / rule 19 gate `phases_2_to_12`), so the returning free
   user is prescribed **their exact pre-absence load, undecayed** — on top of the deload-week copy
   `redoWeek4` hands them.

Both corrections applied to OI-188 and to `docs/research/returning-user-reentry.md` §8.

---

## Author's read — do not re-plan

Three versions, three rounds, three negative verdicts from six independent reviewers. Round 2's own
record already invoked §4.12.1's split rule; v3 was that split, and it introduced a **P0 data-loss
regression that `main` does not have**. That is the strongest possible evidence that the unit is
still the wrong shape.

**The root cause is unchanged from round 2 and has now defeated three versions:** the plan keeps
modelling `plan_start_date` and `plan_end_date` as two ends of one 4-week window. They are not.
`plan_start` is the phase anchor; **`plan_end` is a mutable horizon** that `redoWeek4` and
`holdWeek` deliberately extend. v3 fixed the *anchor* half and left the *bound* half to a delete
loop keyed on the horizon — which is precisely how M1 was born.

**Recommendation: stop Unit 2. Take the APK on what is already merged.**

The genuinely converged slice — the pure builder called by nobody, C's Monday normalisation, and
the doc corrections — is real, but delivers **no user-visible value** and **does not fix OI-166**.
Shipping it would spend a full review-and-push cycle on invisible work.

**When OI-166 is re-opened, its first step is the thing three rounds have tripped over and no
version has modelled:** write down what the plan window actually *is* — `plan_start`, `plan_end`,
the delete range, and every extension path — as one explicit state model with the reachable states
enumerated. Every failure in all three versions is downstream of that document not existing.

**Author's pattern, stated plainly because it is the same one three times:** I reason confidently
about code I have not opened. Round 2's P0 was refuted by the doc comment of the function I called
"already proven". `liftExerciseFromStash` was invented in v1 and carried through three versions
unchecked. `tool_dispatcher.dart:918` was copied from a reviewer's prose into the plan without
opening the file. The fix is mechanical, not attitudinal: **open the file before the citation goes
in.**
