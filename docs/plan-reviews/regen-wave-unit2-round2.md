# OI-166 Unit 2 — plan review round 2 (two context-blind reviewers)

**Date:** 2026-09-10 · **Plan:** `docs/audit/oi166-unit2-plan.md` (re-scoped 2026-09-10)
**Verdicts:** design reviewer **not-converged** · ground-truth reviewer **not-verified**

Two agents, no conversation context, read-only, dispatched concurrently on the hardened plan.
Round 1's mechanical findings were fixed BEFORE dispatch (§4.12.5), so nothing below is a repeat.

⚠ **Every finding recorded here as CONFIRMED was re-opened against source by the author.** Findings
relayed on a reviewer's word alone are marked `RELAYED — unverified`. Per
`feedback_audit_verifier_cannot_trust_own_subagent.md` a subagent citation is a hypothesis.

---

## The two verdicts are not in conflict — the input sets differ

The ground-truth reviewer wrote *"nothing found contradicts the plan's design — the anchor rule
… hold[s]"*. It was given 21 enumerated claims to verify, and **none of them asked whether
`plan_end − plan_start` is always 27 days**. It did not test the invariant; it confirmed the claims
it was handed. The design reviewer tested the invariant and it fails.

This is `feedback_green_check_input_set_width` at the review layer: a reviewer's verdict is only as
wide as the question it was given. Recording it because the two verdicts read as a contradiction
and are not one — and because the narrower reviewer sounded MORE reassuring.

---

## P0-1 — CONFIRMED BY AUTHOR — the window is not always 4 weeks, and the refutation was in the doc comment of the function the plan anchors on

The plan's §3 load-bearing claim: *"The window is `planStart..planEnd`, which is always exactly four
weeks because A writes it that way."*

**A is one of several `plan_end_date` writers.** `redoWeek4`
(`workout_schedule_write_service.dart:213-214`):

```dart
final newEnd = rollStart.add(const Duration(days: 6));
await MigratedKey.write(_planEndKey, newEnd.toIso8601String());
```

`rollStart = max(todayMidnight, planEnd + 1)` (`:187-189`), and **`_planStartKey` is never
written**. One tap → `planEnd − planStart` = 34 days; re-tappable, growing 7 days per tap.

It is LIVE, not ship-dark: `graduation_screen.dart:127` and the free keep-training action call it.

**The repo already states this, on `rawWeekNumberFor` itself** —
`workout_schedule_read_service.dart:1266-1268`:

> *`">4" is a real state (`redoWeek4` extends `plan_end` without moving `plan_start`) that clamping
> silently hides.`*

The plan cited that function as "already proven" and built §1 on it **without reading its
documentation**. Author error, not a reviewer nit.

**User-visible consequence of shipping it:** a free user who taps "Re-do Week 4" then edits their
profile gets a whole regenerated block at `rawWeekNumberFor(...).clamp(1,4)` = **4** → every row
stamped `deload`. The fix would have introduced that.

## P0-2 — CONFIRMED BY AUTHOR — the window can be EMPTY and both regen paths become silent no-ops

`today > plan_end` is a normal, reachable state — it is precisely what `isPhaseExpired()`
(`workout_schedule_read_service.dart:1411-1420`) and the plan-expired surface exist for.

§1's rule `writes := dates in [max(today, anchor) .. bound]` yields an **empty range** there. Edit
Profile would still overwrite `current_plan` while writing **zero rows** — blob and rows diverge and
the profile change silently does nothing. The coach tool advertises exactly this case
(`regeneratePlanBlock.ts`: *"refresh their plan after a long break"*).

The plan never uses the word "expired". §7 reasons only about rows *past* `plan_end`, never about
`today` being past it.

## P1-3 — CONFIRMED BY AUTHOR — the plan narrowed `weeks` and walked past `startDate`

`regeneratePlanBlock.ts:28-30` and `switchGoal.ts:17-19` both expose:

```ts
startDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional()
  .describe("Optional start date (YYYY-MM-DD). Defaults to today.")
```

That is **the exact re-basing semantic the unit exists to remove**, still in the contract. §5 step 4
narrows only `weeks`. Three resolutions exist (honour it → re-introduce the bug; ignore it → the
coach states a start date it does not use, a contract lie with no error path; remove it → a schema
break the plan does not budget). The plan picks none.

This is round 1's P0 recurring **in a second parameter, on files the author had open** — the
`feedback_mistake_guard_without_its_mirror` shape: the finding named a SITE (`weeks`), not the CLASS
(every parameter carrying anchor semantics).

## P1-4 / P1-5 / P1-6 — RELAYED, unverified by the author

- **P1-4** the preview is not a pure `map` (`regenerate_plan_planner.dart:248-268` appends only for
  `weekIdx == 0` and only on workout days), so a week-3 regen has no week-1 row and four live diff
  strings (`regenerate_plan_diff.dart:108`/`:138-139`, `switch_goal_diff.dart:153-154`/`:177-178`)
  would render wrong.
- **P1-5** C's new `current_plan` write is a SECOND deload dual-write site; §6 binds only the deload
  evaluator.
- **P1-6** "byte-identical for B" is unachievable — the builder anchors differently by design, plus
  `finisher` / `generated_via` / `workout_name`-fallback all change B's row keys.
- ⚠ **Hold rows.** `holdWeek` stamps `week: 4 + n`, `is_hold`, `hold_ordinal`; the proposed
  `ScheduleRow` carries none of them, so a regen through the builder would erase hold identity —
  immediately before OI-60's flip. **Highest-value unverified claim; verify before any re-plan.**

---

## Ground-truth findings — citation layer

**CONFIRMED BY AUTHOR:**

| Claim | Plan said | Actual |
|---|---|---|
| B's Monday anchor | `:433` | **`:379`** — `:433` is `final dayPattern = …`. Off by 54 lines, on the defect the unit is built on |
| A's window writes | `:222-223` | **`:225-226`** (`:222-223` compute the locals) |
| week-5/6 quote | `:1177-1180` | **`:1181-1184`** |
| blast-radius elevator | `:328` | **`:61`** `supabase/functions/_shared/** → platform` wins first-match. **Tier `platform` is correct** — the reviewer re-ran the classifier |

Also off-by-small: claim 2 range stops one line before the `plan_end` write; claim 5 is `:574` not
`:575`; claim 11's non-normalisation comment is `:219-223`; claim 13's `:223` is the in-memory
assignment (Hive write `:224-228`) and the "Dual-write" label is at `:237`, not `:264`.

**13 of 21 claims verified exactly. 0 unverifiable.**

## Ground-truth findings — coverage (beyond the enumerated list)

- **F3 — CONFIRMED BY AUTHOR (commit-time blocker).** The plan never mentions
  `docs/sot_registry.yaml` (`grep` exit 1). Two gate-checked anchors would stale:
  `:2771` (`line: 325, fn: generateAndScheduleFromDate`) and `:7647-7649`
  (`line_range: 939-974, method: holdSnapshotBlock`, currently `:946`). Steps 3+5 rewrite ~85 net
  lines above both. `check_sot_registry_parity.dart:40` — *"Stale-line-range detection is an ERROR
  (not a warning)"*. The plan would hard-fail at commit on entries it never names.
- **F4 — CONFIRMED BY AUTHOR (§4.9's 2026-09-05 class).** `sot_registry.yaml:8103-8106`
  (`deload_decision_reason`) states the coach regen *"writes NO blob, so it is invisible to this
  guard by construction … filed as OI-166"*. **Step 4 makes C write the blob**, so the guard becomes
  live. `test/contracts/deload_reason_staleness_behavioral_test.dart` **exists** and is absent from
  §8. This is precisely *"repairing a broken enforcement breaks every test that was silently relying
  on it not enforcing"*.
- **F5 — CONFIRMED BY AUTHOR (self-contradiction in the plan).** The header declares the flag an
  opt-OUT kill switch defaulting to the fix live. So under `disable_shared_schedule_builder`,
  **OFF (default) = builder ACTIVE = corrected output**. §8 says *"Byte-identical per caller with the
  flag OFF"* — which is true only with the flag **ON**. Written as-is, the ship-dark test would be
  authored against the wrong branch.
- **F1 / F2 — RELAYED.** Two further inventory rot passages (`:38-41` hotel-planner D defects and
  the whole `:106-120` off-by-one section) describe pre-Unit-1 state; OI-170 is CLOSED. Step 0
  covered only `:144` and the two P3s.

---

## Author's read — SPLIT, per §4.12.1

Round 2 surfaced **new material design defects**, not citation errors: two P0s that invalidate §1's
anchor rule in live reachable states, plus an unaddressed live tool contract. Counting the five
pre-split rounds this is the sixth non-convergence. §4.12.1: *"split it and ship the smallest
converged piece, don't review the large thing a fifth time."*

**The root error is one sentence:** the plan treated `plan_start_date` and `plan_end_date` as two
ends of one 4-week phase window. They are not. `plan_start` is the phase anchor; `plan_end` is a
**mutable horizon** that `redoWeek4` and `holdWeek` deliberately extend. Conflating them is what
produced both P0s.

**Not converged — needs a founder decision before re-planning:** what a regeneration should do to
a user whose window has been EXTENDED (re-done week 4, or holding). That is a product question
about earned progress, not a code question, and it must be answered before the anchor/bound rule
can be redrawn.

**Separable and window-independent (candidate smallest piece):** C's Monday normalisation
(day-pattern stability), the pure builder itself shipped called-by-nobody, and the doc corrections.
⚠ **This slice does NOT fix OI-166's filed symptom** — and C's `current_plan` write, which would,
is NOT in it, because what you write into the blob depends on where the wave is anchored. Writing
a re-based wave would trade a stale phase-arc for a wrong one. Stated plainly rather than shipped
as a partial win.
