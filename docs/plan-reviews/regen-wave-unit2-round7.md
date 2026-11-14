# OI-166 Unit 2 (v7) — plan review round 7

**Plan reviewed:** `docs/audit/oi166-unit2-plan-v7.md` (superseded in-place by v8 after this round;
same pattern rounds 5 and 6 used).

**Verdicts:** ground-truth reviewer **verified** (33/36 citations exact, 2 within tolerance, 1
cosmetic labeling error — all three trivial, fixed in place before dispatch of this record) ·
design reviewer **not-converged** (1 P0, 3 P1 spec gaps, all real — closed in v8) · 1 finding
(naming inconsistency) confirmed **stale** — already fixed in v7 before the design reviewer was
dispatched, its citations don't match current text · 2 nits fixed cheaply · 1 FYI acknowledged.

## Ground-truth pass: clean, with 2 trivial fixes

Full report confirmed all 5 sites of C's plumbing chain, all of B's loop-redefinition citations,
the complete 5-occurrence census of `'week':` in `workout_schedule_read_service.dart`, and —
critically — a direct read of lines 430-510 confirming **no `week==0` conditional exists anywhere**
that the loop-variable redefinition could break. Two citation drifts fixed: the doc-comment
citation for "whole subject of OI-166" was inconsistent between two mentions in the same document
(`:1256-1262` vs `:1256-1263`) — both now `:1256-1263`; `_restEntry`'s `week` parameter was labeled
the "4th positional parameter" when it is the 3rd (`dayOfWeek` is 4th) — cosmetic, doesn't affect
the fix instructions since substitution is by name not position.

## Design pass: a real P0 survived two rounds because both worked examples happened to be week-aligned

**Finding 1 (P0, confirmed by direct source read before accepting):** `lastWeek :=
rawWeekNumberFor(planEnd, planStart)` rounds UP to a whole 7-day block via integer division, but
the untouched inner day-loop (`workout_schedule_read_service.dart:442-517`) only ever checked a
LOWER bound (`date.isBefore(today)`, `:447`) — confirmed by direct read, zero reference to
`planEnd` anywhere in that loop. Whenever `planEnd` isn't Sunday-aligned to `planStart`'s week grid,
the final week's day-loop overshoots `planEnd` by up to 6 days. Reachable TODAY: `redoWeek4()` is
the live default path (`holdWeeksEnabled` OFF, confirmed via `keep_training_phase1_action.dart:
29-35`), and its `rollStart = todayMidnight.isAfter(planEnd) ? todayMidnight : planEnd.add(1)`
(`workout_schedule_write_service.dart:187-189`, confirmed by direct read) inherits whatever weekday
`todayMidnight` happens to be whenever the plan is expired and the tap isn't exactly the day after
the old `planEnd` — so the new `planEnd = rollStart + 6` (`:213`) need not land on a week boundary.
Both of v7's own worked examples (unextended, and round 4's exact `redoWeek4` scenario) happened to
be Sunday-aligned by construction, which is exactly why this survived rounds 5 and 6. Fixed in v8
by extending the existing lower-bound skip to also check the upper bound, mirroring its exact shape
(`if (date.isBefore(today) || date.isAfter(planEnd))`) — confirmed a no-op on both pre-existing
worked examples, fires only on the misaligned case neither exercised.

**Findings 2-4 (P1, spec gaps):** B never cited where `planStart` is read from (fixed: no new Hive
read needed — `generateAndScheduleFromDate` already computes both halves of it for the existing
`isFirstGeneration` branch, confirmed by direct read of `:379-387`); C's `effectiveWeek` formula
referenced `regenStartWeek` before any line derived it (fixed: explicit derivation added); C's new
plumbing chain threaded `Phase phase` but not the week number the splice formula needs (fixed:
widened to carry both `phase` and `regenStartWeek` in parallel, same shape).

**Finding 5 (naming inconsistency) — STALE, not a v8 change.** The reviewer cited line 95 and the
Tests section using a string-returning `contentFlavor(w) := waveNames[(w-1)%4]`; a grep of the
actual v7 text for the literal `contentFlavor(` (excluding `contentFlavorIndex(`) returned zero
hits. This document was already fixed for this exact issue before round 7 was dispatched (see v7's
own header, "Naming inconsistency self-caught before round 7 dispatch"); the reviewer's subagent
evidently read a stale snapshot. Verified directly against the live file before dismissing — not
taken on the reviewer's word alone.

**Findings 6-7 (nits) + finding 8 (FYI):** an imprecise "two lines above" distance claim (fixed to
cite absolute line ranges instead of a relative distance); a possible 6th import site if `Phase` is
ever explicitly typed at a commit-site helper (noted defensively); `schedule_row_builder_gate_lib.
dart`'s framing of OI-166 Unit 2 as eventually converging onto a shared builder (acknowledged as a
deliberate scope decision in the "explicitly out of scope" section, not an oversight).

## What this round confirms, stated so it isn't lost under the findings

The core `storedPlanEnd`-binding mechanism itself was **not re-litigated this round** (per the
reviewer's own scope instructions — rounds 5/6 already confirmed it) and nothing found this round
touches it. Every finding was in v7's OWN new material (closing round 6's two gaps), not a
regression of anything earlier rounds already verified.

## Status

All four real findings closed in v8 (`docs/audit/oi166-unit2-plan-v8.md`). This is the first round
where the count of NEW real gaps (4, down from 5 in round 5 and 2 in round 6) plausibly reflects
genuine narrowing rather than a new failure mode — but per §4.12.1, three consecutive rounds each
finding *something* real is close to the line where the unit should be judged too large rather than
reviewed an eighth time. Recommendation: one more round. If round 8 finds only nits/stale citations
(no new P0/P1), treat as converged and proceed to implementation; if it finds another structural
gap, escalate to the founder with the round count rather than continuing unilaterally.
