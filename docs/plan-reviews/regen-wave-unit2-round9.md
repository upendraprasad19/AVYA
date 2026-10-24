# OI-166 Unit 2 (v9) — plan review round 9

**Plan reviewed:** `docs/audit/oi166-unit2-plan-v9.md` (superseded in-place by v10 after this round).

**Verdicts:** ground-truth reviewer **verified** (51 citations: 50 exact, 1 whitespace nit) but
surfaced a real finding outside its own citation-only scope · design reviewer **not-converged**
(1 more P1 compile-blocker of the exact same class as round 8's, on a different symbol, plus a P2
proactively closed as concrete Dart) — both closed in v10.

## The pattern holding across rounds 7-9

Every round since 7 has found real issues, but the SEVERITY class has been narrowing predictably:
round 7 found a runtime data bug; rounds 8 and 9 found compile-mechanical slips in translating
already-decided prose into exact Dart — the same failure mode recurring on a NEW symbol each time
(`rawWeekNumberFor`/`regenStartWeek` scoping in round 8; `contentFlavorIndex`'s declaration and the
missing import in round 9). This is worth naming explicitly: it means the underlying DESIGN has
been stable since round 5, and what's still shaking out is purely "did every symbol this design
introduced get a real declaration, a real import, and a real scope" — a checklist, not a rethink.

## Ground-truth pass: clean, but surfaced a real finding outside its own lane

51 citations checked, 50 exact, 1 cosmetic (`weeks.clamp(1,12)` quoted without the source's space —
fixed). Both syntax claims motivating round 8's fix were independently re-verified against LIVE
precedent elsewhere in the codebase, not just re-read: `rawWeekNumberFor` really is `static`
(confirmed a same-shape existing caller, `template_service.dart:122`,
`WorkoutScheduleReadService.rawWeekNumberFor(date, planStart)`, from a different class); confirmed
`template_service.dart:24` imports the file directly for that exact call — meaning **the fix this
whole document needed for its own new call was already a live, working pattern elsewhere in the
codebase the entire time.** `getPlanStartDate()` really is an instance method needing `.instance.`
(confirmed via `workout_schedule_service.dart:206` and two more live call sites).

The reviewer's task was narrowly "verify citations," but while checking those two syntax claims it
noticed the qualifier fix alone doesn't compile: `regenerate_plan_planner.dart`'s import block has
ZERO reference to `workout_schedule_read_service.dart`. This is the SAME class of bug round 8 found
(a cross-class call with nothing making the type/method resolvable) recurring on the IMPORT half of
the fix rather than the qualifier half — round 8 fixed how the call is WRITTEN, but nobody had yet
checked whether the file it's written in can even SEE the class being called. Fixed immediately
(mid-round, before the design reviewer's own pass returned) by adding the missing import, using the
exact style already established elsewhere in the codebase for this precise cross-class call.

## Design pass: one more real P1, same class, different symbol — plus a proactive P2 closure

**The P1:** `contentFlavorIndex` — the content-cycling arithmetic every use of `rawWeekNumberFor`
sits beside in the shared-rule pseudocode box — was called unqualified from THREE unrelated
classes (`WorkoutScheduleReadService` in B, `RegeneratePlanPlanner` in C, and — per the blob-splice
section — `ToolDispatcher` too) but was never given an actual declaration anywhere. Confirmed via
`grep -rn "contentFlavorIndex" lib/` → zero hits; the only 8 occurrences of the name anywhere in the
repo are in the plan document itself. Every round since 5 introduced or referenced this pseudocode
line without anyone asking "wait, is this actually declared somewhere?" — the same blind spot that
let round 8's `rawWeekNumberFor` bug survive 2 rounds, now caught on its very next sibling. Fixed:
declared as a new `static` method on `WorkoutScheduleReadService` (the class this document already
establishes as home for "plan week arithmetic," beside `rawWeekNumberFor`), with each caller
correctly qualified/unqualified per its own class relationship, and the needed import added at each
new call site (`RegeneratePlanPlanner` already needed the import for other reasons; `ToolDispatcher`
needed a genuinely new one).

**The P2, closed proactively rather than waiting for round 10:** the `current_plan` blob-splice
logic — for both B and C — was the one remaining piece of new logic in the entire document still
specified only as prose and a formula, never as literal Dart. Given this exact gap ("described but
not wired") had already produced real, confirmed compile bugs in rounds 7, 8, and now 9 on other
symbols, writing it out now rather than waiting for a reviewer to find the same shape a fourth time
seemed like the responsible move. Doing so surfaced and fixed a genuine self-contradiction in my
own first-draft worked example: I initially claimed the formula's output for `regenStartWeek=3`
matched the founder's "three weeks completed, last week regenerated" decision-1 quote, then in the
very same sentence described an outcome (week 3 ALSO regenerating) that contradicts that quote. The
formula itself was correct and consistent with the document's own long-established schedule-row
worked check; only my own explanatory prose was wrong. Caught and fixed before dispatch to any
reviewer — a self-check, not a finding attributed to round 9's agents.

## What this round confirms

Nothing found this round touches the core mechanism, round 7's P0 day-loop fix, or round 8's three
fixes — all independently re-confirmed clean by both round 9 reviewers via direct re-derivation, not
re-reading. The two new findings (the missing import, `contentFlavorIndex`'s non-existence) are both
in the SAME narrow category as round 8's: symbol resolution, not design correctness.

## Status

Both findings + the self-caught worked-example error closed in v10
(`docs/audit/oi166-unit2-plan-v10.md`). This is the 9th review round. The founder has now run two
consecutive rounds (8, 9) specifically to shake out this compile-mechanical class of error, and both
rounds found exactly one instance of it before returning to a genuinely narrow, closing state — no
new design-level material has surfaced since round 6. Recommend presenting the founder a direct
choice rather than further unilateral rounds: run round 10 (a diminishing-returns bet, given the
pattern), or proceed to actual implementation now, where the real Dart compiler and analyzer will
mechanically catch this exact class of error on the first attempt — which is, at this point, a
strictly faster and more reliable check than a 10th prose read-through for precisely the kind of
mistake still being found.
