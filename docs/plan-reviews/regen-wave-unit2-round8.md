# OI-166 Unit 2 (v8) — plan review round 8

**Plan reviewed:** `docs/audit/oi166-unit2-plan-v8.md` (superseded in-place by v9 after this round,
same pattern as every prior round).

**Verdicts:** ground-truth reviewer **verified** (44 citations checked: 42 exact, 1 real-but-
pre-existing drift unrelated to any v7/v8 fix, 1 whitespace nit) · design reviewer **not-converged**
(3 P1 COMPILE-BLOCKING bugs, all self-inflicted in round 7's own fixes, plus 1 P2 diagnosability nit
and 1 minor test-coverage nit) — all closed in v9.

## The class of finding this round, stated up front

Every real finding this round was in the *translation of an already-decided design into exact Dart*
— not a new logic gap, not a data-loss risk, not a reachability question. All three P1s are the kind
of mistake that shows up at first `flutter analyze`/compile if code were actually being written
rather than specified in prose+snippets across several review rounds. This is categorically
different from round 7's P0 (a real, reachable runtime overshoot) and worlds apart from rounds 1-4
(the core mechanism itself was wrong). Stated explicitly because the round count alone doesn't
distinguish these — 8 rounds sounds identical whether round 8 found a design flaw or a missing
import.

## Design pass findings — all 3 P1s independently re-verified against source before accepting

**Finding 1: C's `regenStartWeek` derivation called `rawWeekNumberFor` unqualified.**
`rawWeekNumberFor` is `static` on `WorkoutScheduleReadService` (confirmed at
`workout_schedule_read_service.dart:1269-1270`); `regenerate_plan_planner.dart`'s `plan()` is a
member of a completely different class (`RegeneratePlanPlanner`) with no import of the read-service
file at all (confirmed via grep — zero hits across all four touched files). Round 7's fix wrote the
call unqualified, which does not compile. Fixed: `WorkoutScheduleReadService.rawWeekNumberFor(...)`.

**Finding 2: C's widened `return` statement referenced `regenStartWeek` from outside its scope.**
Confirmed by direct read: the outer `for (weekIdx...)` loop opens at `:211` and closes at `:328`;
round 7's fix declared `regenStartWeek` "at the same scope as `weekPlan`" — i.e. *inside* that loop,
at `:215-217`. The widened `return` statement is at `:339`, after the loop closes. A `final` declared
inside a `for` loop's body does not survive past its closing brace in Dart — this would read
"Undefined name 'regenStartWeek'" at compile time. Root cause: `regenStartWeek` doesn't actually
depend on `weekIdx` (only on `planStart` and `startDate`, both loop-invariant) — it never needed to
be inside the loop. Fixed: hoisted the derivation to before the loop, alongside the `planStart` read;
only `effectiveWeek`/`weekPlan` (which genuinely depend on `weekIdx`) stay inside it.

**Finding 3: B never received the mirror of the fix C got.** Round 7 gave C an explicit Dart
declaration line for `regenStartWeek` (closing round 7's own finding #3, "referenced before
derived"). B's for-loop header uses two equally bare identifiers, `regenStartWeek` and `lastWeek`,
with no equivalent concrete line anywhere in the document for B — only the generic shared-rule
pseudocode (`:=` notation, not Dart). Confirmed via grep of the plan text: every B-side occurrence of
either name is either that pseudocode or a bare use in the loop header. Fixed: added
`final regenStartWeek = rawWeekNumberFor(today, planStart); final lastWeek =
rawWeekNumberFor(planEnd, planStart);` right after the `planStart` derivation. Unlike C, B needs NO
class qualifier — the enclosing function is itself a member of `WorkoutScheduleReadService`, so a
same-class unqualified static call is valid as-is; this is exactly the asymmetry finding 1 turned on.

**Finding 4 (P2, non-blocking):** C's commit-site null-gate conflates two different null causes
(missing `Phase`, "should not occur" — vs. null `regenStartWeek`, the CORRECT outcome on an
explicit-startDate regen) behind one shared skip-and-log path, making them operationally
indistinguishable to a future reader. Fixed: specified distinct log reasons for each.

**Finding 5 (nit):** the C behavioral test bullet asserted `getCachedPhase` non-null post-cache but
not its now-parallel sibling `getCachedRegenStartWeek`, despite both being widened together in
round 7. Fixed: both now asserted as a pair.

## Ground-truth pass: clean, with 1 real pre-existing drift + 1 cosmetic nit

44 citations checked across 12 files, spanning all four of v8's changed sections plus a
self-consistency pass and spot-checks of pre-v7 citations. Both worked examples' arithmetic
independently re-derived and confirmed correct (the reviewer chose its OWN numbers for the P0 fix,
not the doc's `planStart=0,today=30` — separately verified with `planStart=100`, `redoWeek4` on
`today=140`, regen at `today2=143`, confirming a 2-day overshoot without the fix / zero with it).

The one real finding: `holdWeek()`'s "floored at `normalizeToMonday(planEnd+1)`" citation was
`:248-254`, but the actual reassignment is at `:255` (the cited range only reaches the `if`
condition guarding it) — correct range is `:249-255`. This is old text, present since v5/v6,
unrelated to any of round 7's or round 8's fixes — it survived 7 prior rounds because nobody had
re-verified this specific sub-citation until now. Fixed in place. Second nit: a quoted return type
dropped a space (`Map<String,dynamic>` vs. the real `Map<String, dynamic>`) — fixed.

Round 7's finding #5 (the `contentFlavor`/`contentFlavorIndex` naming inconsistency, already
confirmed stale by round 7's own ground-truth-equivalent check) was independently re-confirmed
absent by this round's reviewer too — a fresh grep of v8 found the sole `contentFlavor(` hit is
inside the prose describing the stale finding itself, not a real occurrence.

## What this round confirms

Nothing found this round touches the core `storedPlanEnd`-binding mechanism or reopens round 7's P0
(the day-loop upper-bound fix's own citations, arithmetic, and no-op-on-existing-examples property
were all independently re-verified clean). Every real finding was contained entirely within round
7's translation of already-decided logic into exact code — the mechanical layer, not the design
layer.

## Status

All 5 real findings + 2 citation nits closed in v9 (`docs/audit/oi166-unit2-plan-v9.md`). Per §4.12.1
and round 7's own stated escalation policy, this was reported to the founder rather than drafting v9
unilaterally — founder's call was to run this round (already done) and see the result; the result
is a clean class of finding (compile-mechanical, not structural) with a small, fully-closed fix set.
Recommend presenting this outcome to the founder as a genuine decision point: round 9 (to confirm the
v9 fixes compile-clean and introduce nothing new), or treat 8 rounds — with the last round's findings
being of a categorically easier class than every round before it — as sufficient and proceed to
actual implementation, where the code will be run through the real Dart compiler and test suite
regardless (which round 9 would only be simulating by hand).
