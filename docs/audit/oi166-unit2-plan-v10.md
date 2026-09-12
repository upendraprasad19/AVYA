# OI-166 Unit 2 (v10) — bound the write range by the SAME token the delete loop already uses

**Branch:** `regen-wave-unit2` · **v10, 2026-09-11**, after v1-v9 all failed review (9 rounds —
record: `docs/plan-reviews/regen-wave-unit2-round{1,2,3,4,5,6,7,8,9}.md`). Round 9's design reviewer
found ONE more real, unconditional P1: `contentFlavorIndex` (the shared-rule box's content-cycling
primitive) was called unqualified from THREE unrelated classes but never actually declared
anywhere — it existed only as this document's own pseudocode, `grep -rn "contentFlavorIndex" lib/`
returned zero hits. Fixed: declared as a new `static` method on `WorkoutScheduleReadService`
(beside `rawWeekNumberFor`), qualified at C's and `tool_dispatcher.dart`'s call sites, with the
needed import added at each. Round 9 also flagged (P2, not yet a confirmed broken line) that the
`current_plan` blob-splice logic — the one remaining piece of new logic still specified as prose,
never translated into exact Dart — was the same unclosed shape that had ALREADY produced real
compile bugs 3 rounds running on other symbols in this document; closed proactively by writing the
splice as concrete Dart for both B and C rather than waiting for round 10 to find it. Doing so
surfaced and fixed a self-contradiction in my own first-draft worked example (claimed a match to
the founder's decision-1 quote that the formula, correctly, did not produce). Round 9's ground-truth
reviewer verified 51 citations (50 exact, 1 cosmetic whitespace) and separately confirmed BOTH
syntax claims motivating round 8's fix (`rawWeekNumberFor` static / `getPlanStartDate()` instance)
against live precedent elsewhere in the codebase — but surfaced, outside its own citation-only
scope, that the qualifier fix alone still doesn't compile: `regenerate_plan_planner.dart` has ZERO
import of `workout_schedule_read_service.dart` at all. Fixed (this was applied mid-round-9, before
the design reviewer's own pass completed — independently re-verified by it afterward). All closed
below, v10. Round 8's design reviewer
found 3 P1 COMPILE-BLOCKING bugs, all self-inflicted in round 7's own fixes: C's new
`regenStartWeek` derivation called a cross-class static method unqualified (won't resolve); C's
widened `return` statement referenced `regenStartWeek` from OUTSIDE the loop scope where round 7's
own fix had declared it (Dart block-scoping — a `final` inside a `for` body doesn't survive past
its closing brace); B never received the mirror of the exact explicit-derivation fix C got (only
generic pseudocode, no concrete Dart line). None touch the core mechanism or reintroduce the round-7
P0 — all three are prose-to-code translation slips, not design flaws, and all three are
self-revealing at first compile (never reach a device). Round 8's ground-truth reviewer verified
44 citations (42 exact, 1 pre-existing 1-line drift unrelated to any round-7/8 fix, 1 whitespace
nit) — both fixed in place. All closed below, v9. Round 7's design reviewer
found a real P0 (B's day-loop had no per-day upper bound against `planEnd`, reachable via
`redoWeek4` misaligning it off the week grid) plus three P1 spec gaps (B's `planStart` read never
cited; C's `regenStartWeek` used before it was ever derived; C's new plumbing chain carried `phase`
but not the week number the splice needs) — all four closed below. Round 7's ground-truth reviewer
verified 33/36 citations exact, 2 within tolerance, 1 cosmetic — both trivial fixes already applied
in place before this version bump. Round 6's TWO reviewers both
returned on v6: ground-truth caught the `'week'`-fix-covered-1-of-3-sites gap (closed in place,
see round6.md); design reviewer, running on the same pre-fix v6 text, independently confirmed that
same gap AND found two more, both real: **(1) C's `current_plan` write had no specified file,
function, or insertion point anywhere in the document** — the splice algorithm existed in prose
with nothing to run it, the identical "described but not wired" shape round 5 found and closed for
B, recurring unaddressed for C's brand-new write; **(2) B's own `'week'` field (5 total stamp
sites in the file, 2 inside this fix's loop) was never addressed**, only C's was. Both closed below
— for C, a full 5-site plumbing chain (return record → cache → getter → both widget call sites →
both commit sites) mirroring the ALREADY-EXISTING `rawSchedules` caching pattern exactly, not a new
mechanism; for B, redefining what the existing loop variable MEANS so its two pre-existing
`'week'` stamps become correct with zero code changes at those sites, the same "fix the class, not
the site" resolution used for C's `_restEntry` gap. The core mechanism itself (write range bound to
`storedPlanEnd`) has now been independently confirmed sound by TWO consecutive rounds (5 and 6) —
not in question; what remained was specification completeness, now closed as far as two rounds of
adversarial reading can find.

**What changed from v7 (round 7 findings, design reviewer, verdict not-converged):** citation
accuracy was confirmed exact throughout (every one of round 6's new citations checked out), but four
real gaps survived into v7's OWN new material — closed below, v8:

1. **P0 — B's day-loop had no per-day upper bound.** `lastWeek := rawWeekNumberFor(storedPlanEnd,
   planStart)` rounds UP to a whole 7-day block, but the untouched inner day-loop only ever checked
   a LOWER bound (`date.isBefore(today)`). Whenever `(storedPlanEnd - planStart) mod 7 != 6` — i.e.
   `storedPlanEnd` isn't Sunday-aligned to `planStart`'s week grid — the final week's day-loop
   overshoots `storedPlanEnd` by up to 6 days. Reachable TODAY via the live default path
   (`redoWeek4`, `holdWeeksEnabled` OFF): `rollStart = todayMidnight.isAfter(planEnd) ? todayMidnight
   : planEnd.add(1)` (`workout_schedule_write_service.dart:187-189`) inherits whatever weekday
   `todayMidnight` happens to be when the plan is expired and the tap isn't the day right after
   `planEnd` — so `newEnd = rollStart + 6` (`:213`) need not land on a week boundary at all. Both of
   v7's own worked examples happened to be week-aligned, which is exactly why this survived two
   rounds. Independently re-derived and confirmed against source before accepting — see the fix
   below.
2. **P1 — B never cited where `planStart` is read from**, despite using it in three places. Fixed:
   it needs NO new Hive read — `generateAndScheduleFromDate` already computes both halves of it
   (`existingStart` at `:382`, `monday` at `:379`) for the existing `isFirstGeneration` branch.
3. **P1 — C's `effectiveWeek` formula referenced `regenStartWeek` as if already defined**; the only
   derivation anywhere in the document was the generic shared-rule pseudocode, never translated into
   an actual line in C's own section. Fixed: explicit derivation line added.
4. **P1 — C's new blob-splice write (closed structurally in v7 — the location is now fully
   specified) still had no way to obtain the WEEK NUMBER the splice formula needs.** The 5-site
   plumbing chain threaded `Phase phase` but not `regenStartWeek`. Fixed: widened to carry both,
   same shape, not a new mechanism.

(A fifth finding, a naming inconsistency between `contentFlavor`/`contentFlavorIndex`, was already
fixed in this document before round 7 was dispatched — the reviewer's citations for it (lines 95,
227-229, 288-289 using the old string-returning name) do not match the current text, confirmed by a
repo grep for the literal `contentFlavor(` returning zero hits in this file. Stale, not a v8 change.
Two nits — an imprecise "two lines above" distance claim, and a possible 6th import site if `Phase`
is ever explicitly typed at the commit site — fixed below too, both low-value but cheap.)

**What changed from v5:** round 5's ground-truth pass verified 24/24 citations and its design
pass independently re-derived the core arithmetic with its OWN numbers and confirmed it —
**the first round where the central mechanism itself was found sound.** What remained were five
completeness gaps, none requiring a new founder decision (each is a direct extension of the rule
already locked in — "bind everything to the same condition, never let two things diverge"):

1. **P0 — the "genuinely expired" case v5's own intro named but never revisited.** When today is
   past `storedPlanEnd` with no extension ever having happened, `writeRange` is correctly empty
   (no data loss — matches the also-empty delete range), but the `current_plan` blob was still
   being unconditionally refreshed, recreating round 2's P0-2 (blob says "regenerated", zero rows
   back it up). **Fix: gate the blob write on the SAME non-empty-range condition as the schedule
   rows** — if nothing is being written, nothing about `current_plan` changes either. This is not
   a new rule; it is v5's own principle applied to the one place it wasn't yet.
2. **P1 — B's actual `current_plan` write site (`:388`) was never cited**, so the splice design
   was described but not wired to real code. Fixed below with the exact citation.
3. **P1 — C's `'week'` field, which the codebase's own doc comment calls "the whole subject of
   OI-166"** (`workout_schedule_read_service.dart:1256-1263`, re-verified), was left stamped as a
   local block-relative counter. Fixed: reuse the SAME `regenStartWeek` already computed for
   content-flavor selection.
4. **P2 — C's explicit-`startDate` branch wasn't actually guarded.** Both real callers
   (`regenerate_plan_diff.dart:48`, `switch_goal_diff.dart:62`) do pass an explicit `startDate`
   through when the AI supplies one, and v5's substitution had no `startDate == null` gate. Fixed
   below.
5. **P2 — C had no `plan_start` read specified.** Fixed: one new read, explicit null-handling.

**On the missing kill-switch (round 5's P3 note):** deliberately not added. This is a bugfix for
confirmed-broken current behaviour (four rounds of verified P0s), not a new capability — shipping
it reduces risk relative to today, the opposite of the case a kill-switch protects against. Adding
one here would introduce its own review surface (exactly what round 2's F5 flag-semantics
self-contradiction cost) for no corresponding benefit. Stated explicitly rather than silently
dropped.

**Why v5 is not a fifth guess:** all four prior rounds failed because the write range and the
delete range could diverge whenever "today" fell outside the assumed 4-week window (extended via
`redoWeek4`/`holdWeek`, or genuinely expired). `holdWeek()` (`workout_schedule_write_service.dart:
236-270`) already solves the "don't cap the write position, use a modulo cadence for content" half
of this. **v5's own first draft tried to borrow its THIRD property too (extend `plan_end` to match
what was written) and that was WRONG** — caught by hand-checking the arithmetic against round 4's
exact scenario before dispatch (one `redoWeek4` tap: `storedPlanEnd = planStart+34`; regen at
`today = planStart+30` → a "natural 4-week block end" formula computed `planStart+55`, overshooting
by 21 days, writing an entire UNWANTED extra block nobody asked for). **The actual fix needs no
`plan_end` write at all**: bound the write range by the SAME token the delete loop already reads
(`storedPlanEnd`), so the two ranges can never diverge by construction — not because two
independently-computed formulas happen to agree.

## The borrowed mechanism, cited from `holdWeek` itself (two of its three properties)

1. **Never cap the write target to a fixed slot.** `holdWeek` computes `start =
   normalizeToMonday(nowWall())`, floored at `normalizeToMonday(planEnd + 1)` (`:249-255`) — always
   today's real position, however far past the nominal window that is.
2. **Content selection is a modulo cadence over an ordinal, not a clamp.** `:268`: `final deload = n
   % 4 == 0;` — cycles, never freezes at a fixed index once `n` exceeds 4.

(The third property — extending `plan_end` to match what was written — is intentionally NOT
borrowed; see above. Regenerate fills content inside an already-provisioned window; it does not
grow the window, so there is nothing for it to extend.)

## Why v5's content cadence differs from `holdWeek`'s (deliberate, not an inconsistency)

`holdWeek`'s cadence is mostly-peak/every-4th-deload — correct for **holding**: sustained intensity
training with periodic recovery, no new progression (no new goal/equipment/programming).
**Regenerate is fresh content** — a new `Phase` from `PlanGenerator`, potentially a new
goal/equipment. Per the founder's "match the calendar week" decision, the natural reading past week
4 is that each 4-week block repeats the full progressive wave from its own start:
`((realWeek - 1) % 4)` → baseline/overreach/peak/deload, cycling — not `holdWeek`'s peak-biased
cadence, which encodes "don't re-ramp," the opposite of what a fresh regen is for.

## The fix

**Shared rule (both B and C):**

```
regenStartWeek  := rawWeekNumberFor(today, planStart)          // UNCLAMPED — round 3/4's mistake was clamping this
writeRange      := [today .. storedPlanEnd]                     // storedPlanEnd = the EXACT SAME value the delete loop already bounds itself by — read once, passed to both, never recomputed. INVERTED (empty) when today > storedPlanEnd — the expired case, see below.
contentFlavorIndex(w) := (w - 1) % 4                            // w = 1-based real week number, cycles past 4. ONE function, returns the INDEX — phase.weekPlans[contentFlavorIndex(w)] is ALWAYS the (w-1)%4'th of [baseline, overreach, peak, deload] by construction (PeriodizationEngine); there is no separate string-returning variant — every use below indexes weekPlans directly, never compares a flavor name
blobWrite       := writeRange.isNotEmpty                        // gates current_plan too — see "genuinely expired" below
```

**Round 9 P1 — `contentFlavorIndex` is called from THREE unrelated classes (`WorkoutScheduleReadService`
in B, `RegeneratePlanPlanner` in C, and `ToolDispatcher` for the blob-splice write below) but was
never given a real declaration anywhere — only this pseudocode.** `grep -rn "contentFlavorIndex"
lib/` returns zero hits; every prior round's attention (5 through 9) was on `rawWeekNumberFor`, one
line above this in the same shared-rule box, and this sibling primitive was never given the same
treatment. It is pure arithmetic with zero dependencies, so it lives as a NEW `static` method
**on `WorkoutScheduleReadService`, immediately beside `rawWeekNumberFor` (`:1269`)** — the class
this document already establishes as home for "plan week arithmetic" primitives (its own doc
comment: *"Duplicated arithmetic is how the 'week' stamp drifts, which is the whole subject of
OI-166"*):
```dart
static int contentFlavorIndex(int w) => (w - 1) % 4;
```
Call-site consequence, per caller:
- **B** — no change to the call syntax already shown below (`contentFlavorIndex(week + 1)`):
  same-class call, `generateAndScheduleFromDate` is already a member of `WorkoutScheduleReadService`.
- **C** — every call becomes `WorkoutScheduleReadService.contentFlavorIndex(...)`, using the SAME
  import this plan's C section already adds for `rawWeekNumberFor`/`getPlanStartDate` — no second
  import needed.
- **`tool_dispatcher.dart`** (the blob-splice write, both B's and C's — see below) — this file
  currently has NO import of `workout_schedule_read_service.dart` at all (confirmed: its only
  schedule-related import, `workout_schedule_service.dart`, is a `@Deprecated` re-export shim whose
  `show`-scoped exports do not include `WorkoutScheduleReadService`). Add
  `import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';` and call
  `WorkoutScheduleReadService.contentFlavorIndex(...)` qualified, same pattern as C.

**No `plan_end` write, anywhere, by either B or C.** Regenerate's job is to refresh CONTENT inside
whatever window is already provisioned — by first-generation, by `redoWeek4`, or by `holdWeek` —
never to grow that window itself. Growing the window stays exclusively `redoWeek4`/`holdWeek`'s
job, unchanged. This is why the delete/write mismatch that killed v3 and v4 becomes STRUCTURALLY
impossible here: both loops are bounded by the identical `storedPlanEnd` value, read once, not by
two formulas that must independently agree.

Weeks strictly before `regenStartWeek` are never entered (matches the founder's "weeks completed,
not changed" rule, unchanged from v3/v4). When today is inside the ORIGINAL, unextended window,
`writeRange` is `[today..planStart+27]` — byte-compatible with the founder's original decision #1
example (week 3 regen, week 4 refreshed, nothing else changes). When today is inside a
`redoWeek4`-extended window (round 4's exact scenario: `today=planStart+30`,
`storedPlanEnd=planStart+34`), `writeRange` is `[planStart+30..planStart+34]` — the 5 days actually
provisioned, no more, no less. Hand-verified with a standalone script before this plan was written
(see the arithmetic check in the author's note at the end of this file).

**B** (`workout_schedule_read_service.dart`, `generateAndScheduleFromDate`): **the loop variable
`week` itself is redefined to START at `regenStartWeek - 1` instead of `0`, and its upper bound
becomes `lastWeek := rawWeekNumberFor(storedPlanEnd, planStart)` (the SAME primitive, applied
symmetrically to the other end of the range) instead of a hard `4`:**

```dart
final planStart = existingStart != null ? DateTime.parse(existingStart) : monday;
// NEW, but NOT a new Hive read — `existingStart` (`:382`) and `monday` (`:379`) are both
// ALREADY in scope from the pre-existing isFirstGeneration branch immediately above.
// Insert right after the existing `:382-387` block, before the `:388` write-site replacement below.
final regenStartWeek = rawWeekNumberFor(today, planStart);
final lastWeek = rawWeekNumberFor(planEnd, planStart);
// Round 8 P1: neither of these had an explicit Dart declaration anywhere in this document — only
// the generic shared-rule pseudocode near the top (`:= rawWeekNumberFor(...)`), which isn't code.
// C's mirror fix (below) needed an explicit CLASS-QUALIFIED call because `rawWeekNumberFor` lives
// on a different class than the one calling it; B needs NO qualifier — this loop's enclosing
// function is itself a member of WorkoutScheduleReadService, the class that declares
// `static rawWeekNumberFor` (`:1269`), so a same-class unqualified static call is valid Dart as-is.
```
```dart
for (int week = regenStartWeek - 1; week < lastWeek; week++) {
  final weekPlan = plan.weekPlans[contentFlavorIndex(week + 1)];   // was: week < plan.weekPlans.length ? plan.weekPlans[week] : plan.weekPlans.last
  final weekStart = planStart.add(Duration(days: week * 7));       // was: monday.add(...)
```
Everything else inside the loop is untouched — including, critically, the pre-existing
`'week': week + 1` stamps at `:473` and `:502` (5 total `'week':` sites in this file; the other
three — `:271`, `:303` in an earlier, untouched function, and `:414`'s literal `'week': 1` in the
"Joined later" backfill block — are out of scope). **Those two sites need ZERO code changes**: they
already read the loop variable `week`, which now correctly carries the real week number by
construction — the same "whole subject of OI-166" drift the codebase's doc comment names is closed
here for free, by redefining what the variable MEANS rather than patching each site that reads it.
Worked check: `regenStartWeek=3` (unextended mid-phase regen) → `lastWeek=4` → loop runs
`week=2,3` → stamps `'week': 3` and `'week': 4` — exactly the founder's original example. No
`plan_end` write added.

**Round 7 P0 — the inner day-loop also needs an upper bound, or it overshoots `planEnd`.**
`lastWeek := rawWeekNumberFor(planEnd, planStart)` (`planEnd` IS `storedPlanEnd` — the exact local
already read at `:358-360`) rounds UP to a whole 7-day block via integer division. The untouched
inner loop (`:442-517`, unchanged by anything above) iterates all 7 `dayOfWeek` values every time and
only ever checked a LOWER bound. Whenever `planEnd` isn't Sunday-aligned to `planStart`'s week grid
— i.e. `(planEnd.difference(planStart).inDays) % 7 != 6` — the final week's day-loop writes past
`planEnd` by up to 6 days. This is reachable TODAY through the live default path: `redoWeek4()`
(`holdWeeksEnabled` OFF, confirmed the default — `keep_training_phase1_action.dart:29-35`) sets
`rollStart = todayMidnight` whenever the plan is expired and `today` isn't exactly the day after the
old `planEnd` (`workout_schedule_write_service.dart:187-189`), and `todayMidnight` need not be a
Monday — so `newEnd = rollStart + 6` (`:213`) can land on any weekday. Worked example: `planStart=0`
(Monday), original `planEnd=27` (Sunday-aligned, `27%7==6`), plan expires, `redoWeek4` tapped on
`today=30` (a Wednesday) → `rollStart=30`, `newEnd=36` (`36%7==1`, NOT aligned). A later regen with
`regenStartWeek=5` → `lastWeek=6` runs `week=4,5`; `week=5` spans days 35-41, but `planEnd=36` — days
37-41 would be written past the recorded boundary without this fix. Fix: extend the existing
lower-bound skip (`:447`) to also check the upper bound, mirroring its exact shape:
```dart
if (date.isBefore(today) || date.isAfter(planEnd)) {   // was: if (date.isBefore(today)) {
  if (dayPattern.contains(dayOfWeek) && workoutDayIndex < weekPlan.workoutDays.length) {
    workoutDayIndex++;
  }
  continue;
}
```
Confirmed a no-op on every already-verified example: in the unextended case `planEnd=planStart+27`
is Sunday-aligned, so `weekStart+6` never exceeds it within the last iterated week; in round 4's
`redoWeek4` scenario `planEnd=planStart+34` is also Sunday-aligned (`34%7==6`) — both pass through
this check unchanged. The added clause only fires on a misaligned `planEnd`, which is exactly the
case v7's two worked examples didn't exercise. `date.isAfter(planEnd)` (strict) matches the delete
loop's own inclusive-of-`planEnd` semantics (`:362`, `!d.isAfter(planEnd)`) — the boundary day itself
is still written.

**The existing unconditional `current_plan` write at `:388`
(`await workoutBox.put(_planKey, plan.toMap());`) is REPLACED**, not left alongside the loop
change — this was v5's silent gap (round 5, P1): the splice design existed in prose but was never
wired to the real write site. **Round 9 P2: closed as concrete Dart, not left as prose** — the
"described but not wired" pattern has now cost 3 consecutive rounds (7, 8, 9) on OTHER symbols in
this exact document; this is the one remaining piece of new logic that hadn't been forced into
exact code yet:
```dart
if (writeRange.isNotEmpty) {   // was: unconditional `await workoutBox.put(_planKey, plan.toMap());`
  final existingBlob = workoutBox.get(_planKey);
  final existingWeekPlans =
      existingBlob is Map ? existingBlob['week_plans'] as List<dynamic>? : null;
  // regenStartWeek > 4 (extended/late regen): nothing in indices 0-3 is "still ahead of the
  // regen" — ALL 4 get fresh content. This is a real branch, not derivable from the general
  // formula alone (round 5's own hand-check of indices 1-5 already found this).
  final preserveBefore =
      regenStartWeek > 4 ? 0 : (regenStartWeek - 1).clamp(0, 3);
  final splicedWeekPlans = [
    for (var i = 0; i < 4; i++)
      i < preserveBefore && existingWeekPlans != null && i < existingWeekPlans.length
          ? Map<String, dynamic>.from(existingWeekPlans[i] as Map)
          : plan.weekPlans[contentFlavorIndex(i + 1)].toMap(),
  ];
  final splicedBlob = Map<String, dynamic>.from(plan.toMap())
    ..['week_plans'] = splicedWeekPlans;
  await workoutBox.put(_planKey, splicedBlob);
}
// when writeRange is empty (expired, see below): skip the write entirely, leave the prior blob
// exactly as it was.
```
Worked check, matched against the SAME schedule-row worked check already established above (not a
new scenario): `regenStartWeek=3` → `preserveBefore=2` → blob indices 0,1 preserved (weeks 1-2,
untouched — already-completed weeks, never entered by the schedule-row loop either), indices 2,3
fresh (weeks 3-4, regenerated) — this is the SAME split as the schedule-row loop's own worked check
above ("loop runs `week=2,3`" — 0-indexed weeks 2,3 = real weeks 3,4), by construction: both use
`regenStartWeek` as the same cutover point, so the blob and the rows can never disagree about which
weeks are "still ahead of the user" vs. "already behind them." (The founder's decision-1 quote
—"three weeks completed, last week regenerated"— describes the CALENDAR-week semantics this cutover
implements in general, not a claim that exactly 3 of the 4 blob indices are always preserved; how
many weeks are preserved depends entirely on which real week `regenStartWeek` is.)
`regenStartWeek=5` (an extension) → `preserveBefore=0` → all 4 indices fresh, matching the stated
degenerate case.

**C** (`regenerate_plan_planner.dart` + `tool_dispatcher.dart`): C currently has NO delete loop of
its own bounded by `plan_end` — it writes whatever `weeks` the caller asked for, from `start`
(today, absent an explicit `startDate`) forward, full stop (round 1's finding, still true, still
untouched by this plan). So C has no existing "storedPlanEnd" bound to reuse the way B does, and
this fix is narrower than B's in write-range terms — **but several things change, not one**
(numbered 0-3 below — item 0 is the round-9 import fix, added after the original "three things"
count was written):

0. **Round 9 P1 — new import, or neither call below resolves.** `regenerate_plan_planner.dart`'s
   current 6-line import block (`:1-6`) has ZERO reference to `workout_schedule_read_service.dart`
   or `WorkoutScheduleReadService` — confirmed by direct read. Round 8 fixed the CLASS-QUALIFIER on
   these two calls but neither round noticed the qualifier alone is insufficient without the type
   also being importable. Add:
   ```dart
   import 'package:icanbefitter/core/services/workout_schedule_read_service.dart';
   ```
   alongside the existing 6 imports. (Live precedent for this exact cross-class call shape, confirmed
   by round 9's ground-truth pass: `template_service.dart:122` already calls
   `WorkoutScheduleReadService.rawWeekNumberFor(date, planStart)` from a different class via this
   same import style.)
1. **New read + new derivation, BOTH at the top of `plan()`, alongside the existing profile read —
   BEFORE the outer `for (weekIdx...)` loop (`:211`), not inside it:**
   ```dart
   final planStart = WorkoutScheduleReadService.instance.getPlanStartDate();
   final regenStartWeek = (startDate == null && planStart != null)
       ? WorkoutScheduleReadService.rawWeekNumberFor(_today(), planStart)
       : 1;   // unused by effectiveWeek/weekPlan below when the guard is false (kept non-null
              // rather than int? to avoid threading nullability through two ternaries that
              // already re-check the same guard independently).
   ```
   `getPlanStartDate()` is an INSTANCE method (`.instance.`, confirmed unqualified elsewhere only
   from inside the class itself — `:822`, `:1036`); `rawWeekNumberFor` is `static` (`:1269`), so it
   takes the bare class name with NO `.instance` — the two calls are NOT interchangeable syntax.
   `getPlanStartDate()` can return `null` (a state that should not occur for an existing user
   regenerating, but is defensive) — when null, `regenStartWeek` falls back to the guard's `else`
   branch and **every item below falls back to today's unmodified v1-v4 behaviour** (`weekIdx`-based,
   unchanged), rather than throwing. **Round 8 P1 correction: `regenStartWeek` must be declared HERE,
   before the loop, never inside it** — it does not depend on `weekIdx` (only on `planStart` and
   `startDate`, both loop-invariant), and item 4 below's widened `return` statement (`:339`) needs to
   read it. A `final` declared inside the `for (weekIdx...)` loop's body goes out of scope the moment
   that loop closes (`:328`) — the ORIGINAL v8 text placed it "at the same scope as `weekPlan`" (i.e.
   inside the loop) and the widened return statement two rounds later would not have compiled. Also
   fixes an independent round-8 P1: `rawWeekNumberFor` is a member of `WorkoutScheduleReadService`,
   a DIFFERENT class from the one `plan()` lives in (`RegeneratePlanPlanner`) — the original v8 text
   called it unqualified, which only compiles for a same-class call (as B's mirror fix below
   legitimately is); C's call needs the explicit class-name qualifier.
2. **`effectiveWeek`/`weekPlan`, still computed at the SAME scope level they already sit at —
   `:215-217`, inside the outer `for (weekIdx...)` loop and BEFORE the inner `for (dayOfWeek...)`
   loop begins (`:227`)** — these two (unlike `regenStartWeek` above) DO depend on `weekIdx`, so they
   stay inside the loop, now referencing the outer-scope `regenStartWeek` from item 1. **GUARDED on
   `startDate == null`** (round 5 P2: v5 had no such guard, and both real callers —
   `regenerate_plan_diff.dart:48`, `switch_goal_diff.dart:62` — do pass an explicit `startDate`
   through when the AI supplies one, which is the untouched future-dated-block case):
   ```dart
   final effectiveWeek = (startDate == null && planStart != null)
       ? regenStartWeek + weekIdx
       : weekIdx + 1;                              // byte-identical to today when the guard is false
   final weekPlan = (startDate == null && planStart != null)
       ? phase.weekPlans[WorkoutScheduleReadService.contentFlavorIndex(effectiveWeek)]
       : (weekIdx < phase.weekPlans.length ? phase.weekPlans[weekIdx] : phase.weekPlans.last);
   ```
3. **`effectiveWeek` replaces `weekIdx + 1` at EVERY site that stamps it, not just one — round 6
   correction.** Round 5 flagged the `'week'` field as "the whole subject of OI-166" (codebase's
   own doc comment, `workout_schedule_read_service.dart:1256-1263`) and round 6's ground-truth
   pass caught that my first fix only replaced ONE of THREE writers.
   **Full census, verified by grep, `weekIdx + 1` appears at exactly three lines in this file:**
   `:278` (the workout-day row, direct `'week':` literal), and `:310` / `:321` — both calls into
   `_restEntry(dateStr, resolvedPhase, weekIdx + 1, dayOfWeek, weekPlan.weekCharacter)`, whose
   3rd positional parameter is named `week` and is stamped verbatim at `_restEntry`'s own `:352`
   (`_restEntry` itself needs no change — it is a pure formatter that stamps whatever `week` it is
   given; the three CALL SITES are the actual writers). **All three become `effectiveWeek`.**
   This is the `feedback_mistake_guard_without_its_mirror` shape exactly: a finding names a SITE,
   not the CLASS — round 5 named the field, and the first fix attempt fixed one occurrence of it.

**C's write range (`weeks`, from `start`) is completely unchanged** in every case — C still writes
exactly as many weeks as the caller asked for, no more, no less; it never had a "read too far past
what's provisioned and delete without replacing" problem in the first place, because C has no
delete-by-plan_end loop to diverge from, and `weeks.clamp(1, 12)` (`:143`) is always ≥1 — **C
structurally cannot produce an empty write range**, unlike B. `plan_end` is still never read or
written by C — no new writer, no SoT registry change needed for `plan_end`.

**C's `current_plan` write — round 6 finding (design reviewer): v6 described the splice ALGORITHM
but never named a single file, function, or line for it to run in — the exact "prose, not wired"
gap round 5 found and closed for B, recurring for C untouched.** `plan()` builds the `Phase`
object (`:190`, confirmed) and discards it after the loop — it is never part of `plan()`'s return
record, never cached, and the actual Hive write happens in a DIFFERENT file
(`tool_dispatcher.dart`) that has no way to obtain it. **Newly specified, mirroring the existing
`rawSchedules` caching pattern exactly (same shape, not a new mechanism):**

**Round 7 P1: the chain below originally threaded only `Phase phase`. The splice formula (see
"`current_plan` blob" below) also needs the WEEK NUMBER (`regenStartWeek`) to know where to start
splicing — nothing carried it to the commit site. Every step below now threads BOTH fields in
parallel; same shape, one extra field, not a new mechanism:**

1. `plan()`'s return record (`:135-136`, currently
   `Future<({RegeneratePlanResult plan, List<Map<String, dynamic>> rawSchedules})>`) widens to add
   `Phase phase` AND `int? regenStartWeek` (nullable — mirrors item 2's own `startDate`/`planStart`
   guard: undefined exactly when C's guard was false, i.e. explicit `startDate` or no `planStart`);
   its `return` statement (`:339`, currently `return (plan: result, rawSchedules: rawSchedules);`)
   becomes
   `return (plan: result, rawSchedules: rawSchedules, phase: phase, regenStartWeek: (startDate == null && planStart != null) ? regenStartWeek : null);`.
2. `cache()` (`:368-375`) gains TWO new parameters, `Phase phase` and `int? regenStartWeek`, stored
   into two NEW maps `_phaseCache[intentId] = phase;` and
   `_regenStartWeekCache[intentId] = regenStartWeek;` — same pattern as the existing
   `_cache`/`_rawScheduleCache` pair immediately above it, not a new mechanism.
3. Two new getters beside the existing two (`:377-380`):
   `Phase? getCachedPhase(String intentId) => _phaseCache[intentId];` and
   `int? getCachedRegenStartWeek(String intentId) => _regenStartWeekCache[intentId];`.
4. `clearCache()` (`:382-385`) adds `_phaseCache.remove(intentId);` AND
   `_regenStartWeekCache.remove(intentId);` alongside its existing two removals.
5. **Both real call sites of `.cache(...)` must pass BOTH new arguments** —
   `regenerate_plan_diff.dart:51-55` and `switch_goal_diff.dart:64-68`, both currently
   `RegeneratePlanPlanner.instance.cache(widget.intent.id, result.plan, result.rawSchedules);` —
   become
   `...cache(widget.intent.id, result.plan, result.rawSchedules, result.phase, result.regenStartWeek);`.
   Both already hold `result` from their own `.plan(...)` call earlier in the same method
   (`regenerate_plan_diff.dart:43`→`:51-55`; `switch_goal_diff.dart:59`→`:64-68`) — `result.phase`
   and `result.regenStartWeek` are both immediately available, no new read.

**Commit sites** (`tool_dispatcher.dart`): `_executeRegeneratePlanBlock` (`:828`) reads
`getCachedPhase(intent.id)` AND `getCachedRegenStartWeek(intent.id)` alongside its existing
`getCachedRawSchedules` read (`:842`), and inserts the blob splice-write immediately before its
`clearCache` call (`:882`) — after the existing row-write loop, gated on both being non-null (a
degenerate-input guard: `phase` missing should not occur on the Confirm path per the existing note
below; `regenStartWeek` null means the explicit-`startDate` or no-`planStart` branch, where C's
`current_plan` write is correctly skipped entirely — the pre-existing behaviour for that case,
unchanged). `_executeSwitchGoal` (`:959`) mirrors this exactly at its own `getCachedRawSchedules`
read (`:980`) and `clearCache` call (`:1038`).

**Round 9 P2: the splice, as concrete Dart** — same shared formula as B's (below), same
`WorkoutScheduleReadService` import this section already requires for `contentFlavorIndex`
(supersedes the old "6th import site, only if Phase is explicitly typed" hedge below — that
import is now needed regardless, for a different symbol; kept only as a note that a `Phase`-typed
local ALSO doesn't independently need a second new import, since `Phase` is already reachable
through the existing `regenerate_plan_planner.dart` import chain). `_planKey` is a PRIVATE
(`_`-prefixed) constant on `WorkoutScheduleReadService` — not visible outside that file — so this
code uses the literal string `'current_plan'` directly, matching how `HiveService.instance.
workoutBox` is already accessed elsewhere in `tool_dispatcher.dart` (e.g. `:450`, `:646`, `:762`,
`:849`):
```dart
final phase = getCachedPhase(intent.id);
final regenStartWeek = getCachedRegenStartWeek(intent.id);
if (phase != null && regenStartWeek != null) {
  final box = HiveService.instance.workoutBox;
  final existingBlob = box.get('current_plan');
  final existingWeekPlans =
      existingBlob is Map ? existingBlob['week_plans'] as List<dynamic>? : null;
  final preserveBefore =
      regenStartWeek > 4 ? 0 : (regenStartWeek - 1).clamp(0, 3);
  final splicedWeekPlans = [
    for (var i = 0; i < 4; i++)
      i < preserveBefore && existingWeekPlans != null && i < existingWeekPlans.length
          ? Map<String, dynamic>.from(existingWeekPlans[i] as Map)
          : phase.weekPlans[WorkoutScheduleReadService.contentFlavorIndex(i + 1)].toMap(),
  ];
  final splicedBlob = Map<String, dynamic>.from(phase.toMap())
    ..['week_plans'] = splicedWeekPlans;
  await box.put('current_plan', splicedBlob);
}
```
(`phase.toMap()`/`phase.weekPlans` — confirmed real on `Phase`, `lib/shared/repositories/
plan_engine/models.dart:24`+. `Map` here is untyped `dynamic`-keyed exactly as `existingBlob` reads
it — no explicit `Phase` type annotation is written anywhere in this snippet, so per the
already-reviewed hedge above, no import is needed FOR `Phase` specifically; the import this section
adds is solely for `WorkoutScheduleReadService.contentFlavorIndex`.)

**`current_plan` blob** (both B and C): splice, position-preserving over the FIRST 4 real weeks of
the phase only (`current_plan.week_plans` is always exactly 4 elements — unchanged shape), now given
as concrete Dart above for both B (inline in `generateAndScheduleFromDate`) and C (at the
`tool_dispatcher.dart` commit sites) — same shared formula, same `preserveBefore` cutover, applied
to each writer's own locally-available "fresh content" source (`plan.weekPlans` for B,
`phase.weekPlans` for C) and each writer's own already-established `regenStartWeek` value (B's own
local; C's `getCachedRegenStartWeek(intent.id)`, non-null per the commit-site gate above).

**The "genuinely expired" case (round 5's P0) — B ONLY, round 6's design pass correctly flagged
that the earlier "gated... for both B and C" wording overclaimed symmetry C cannot have (C's write
range is never empty, per above).** For B: when `today > storedPlanEnd` with no extension
(`writeRange` empty), BOTH the schedule-row loop AND the `current_plan` write are skipped — gated
on the identical `writeRange.isNotEmpty` condition. Nothing about the user's stale, expired plan
changes as a side effect of an Edit-Profile save. This does not "fix" the expired-user experience
(that is OI-188's territory — filed as OI-179, renumbered twice — not this unit's) — it just stops this unit from making it WORSE by
desynchronizing the blob from reality. `edit_profile_screen.dart:2019-2038` (confirmed, round 5)
has no expiry check before calling `generateAndScheduleFromDate` — this gate is the only thing
standing between that call and the round-2/round-5 P0-2 blob/rows-diverge state. For C: no
equivalent case exists, so no equivalent gate is needed — the degenerate inputs are a missing
cached `Phase` (should not occur on the Confirm path following a successful preview) OR a null
cached `regenStartWeek` (the explicit-`startDate`/no-`planStart` branch, where skipping the blob
write is the CORRECT existing behaviour, not a fallback for a should-not-happen case); either one
skips the blob write, but **round 8 P2: log a DISTINCT reason for each** (e.g.
`'regen_blob_skip_missing_phase'` vs `'regen_blob_skip_no_regen_start_week'`) rather than one shared
message — otherwise a future reader can't tell "the expected no-op on every explicit-startDate regen"
from "the Confirm-path invariant broke" from the log alone, matching the codebase's established
crash-safe pattern for a missing/malformed blob elsewhere in this same file.

## Explicitly out of scope (unchanged from v4, still holds)

- C's explicit-`startDate` branch (future-dated blocks) — untouched.
- C's `weeks` parameter and write range — entirely untouched, only its content-flavor selection
  changes.
- `redoWeek4` / `holdWeek` themselves — untouched; this plan doesn't change how the window gets
  extended, only how regen behaves once it has been.
- Converging B and C onto one shared `schedule_row_builder.dart` — `scripts/schedule_row_builder_
  gate_lib.dart:70-77` frames OI-166 Unit 2 as eventually landing there (both are currently
  `pendingUnit2` allowlist exemptions). This plan patches both files in place instead. Noted
  (round 7 FYI finding) as a deliberate scope decision, not an oversight — the allowlist exemptions
  are untouched by this plan and remain accurate afterward.

## Tests

- Pure: `contentFlavorIndex` for weeks 1-4 (unextended, byte-compatible), 5-8 (one `redoWeek4`
  extension, matches round 4's exact P0 scenario), and arbitrary large week numbers (repeated
  extensions).
- Behavioral (B), extended: regen via Edit Profile when `today` is inside a `redoWeek4`-extended
  window (the round-4 reproduction — `today=planStart+30`, `storedPlanEnd=planStart+34`) writes
  real rows through EXACTLY `storedPlanEnd`, no more, no fewer — zero empty days, EXACTLY 5 days
  (not 26, the v5-draft-1 bug caught before dispatch), the written row for `today` is stamped
  `'week': 5` (not `1` — the round-6 `_restEntry`-class finding's B counterpart: the loop-variable
  redefinition means the PRE-EXISTING `week + 1` stamp needs no separate code change, and this
  assertion is what proves that claim rather than just stating it), AND `current_plan.week_plans`
  reflects the spliced/cycled content (not v5's silent gap at `:388`).
- Behavioral (B), expired — **NEW, closes round 5's P0**: regen when `today > storedPlanEnd` with
  no extension writes ZERO schedule rows (already true pre-fix) AND leaves `current_plan`
  BYTE-IDENTICAL to its pre-regen value (was NOT true pre-fix — this is the regression test for
  round 5's finding).
- Behavioral (B), misaligned `planEnd` — **NEW, closes round 7's P0**: seed `planStart` on a Monday,
  set `planEnd` to a NON-Sunday-aligned date via the same arithmetic `redoWeek4` produces
  (`rollStart` on a non-Monday + 6), regen mid-extension. Assert NO schedule row is written for any
  date strictly after `planEnd` — the exact overshoot the fix closes. Without the per-day upper
  bound this reddens (rows exist past `planEnd`); with it, it passes.
- Mutate the new `date.isAfter(planEnd)` clause out (revert to the lower-bound-only check) once,
  confirm the new misaligned-`planEnd` behavioral test reddens.
- Behavioral (C): AI-coach `regeneratePlanBlock` at a late `regenStartWeek`, `startDate` omitted,
  writes `current_plan` with the correctly cycled flavor AND stamps `effectiveWeek` (not the prior
  local counter) on EVERY row type it produces — both a workout-day row AND a rest-day row in the
  same run (round 6's finding: `_restEntry`'s two call sites, not just the direct workout-day
  site) — while the schedule-row WRITE RANGE stays unchanged (still exactly `weeks` rows from
  `start`). Also asserts the FULL plumbing chain lands: `getCachedPhase(intent.id)` AND
  `getCachedRegenStartWeek(intent.id)` both return the same non-null values the cache received
  (round 8 nit: the two are cached in the same step and should be tested as a pair, not just
  `getCachedPhase` alone), and `current_plan` in Hive is non-null and spliced after the
  commit-site write — not just that the in-memory `Phase` was computed correctly.
- Behavioral (C), explicit `startDate` — **NEW, closes round 5's P2**: the SAME late-`regenStartWeek`
  state, but with an explicit `startDate` supplied, produces BYTE-IDENTICAL output to pre-fix C
  (content indexing and `'week'` stamping both fall through the guard, untouched) — the regression
  test proving the guard actually excludes this branch, not just that the plan says it should.
- Mutate `contentFlavorIndex`'s modulo back to a bare `w-1` (no `% 4`) once in each of
  B and C, confirm both late-week behavioral tests redden (content reverts to crashing/wrong).
- Mutate the `writeRange.isNotEmpty` blob-write gate to unconditional once, confirm the new expired
  behavioral test reddens (blob changes when it shouldn't) — proves the gate is load-bearing.

## SoT / registry impact

None for `plan_end` — no new writer, on either file, in this version. C's `current_plan` write is
new (per OI-166) and C's `'week'` stamp gains a second, guarded derivation path — update the
registry entry's writer list for both in the same commit, per §4.5.

## Blast radius

Touches the same two files as v4 (`lib/core/services/workout_schedule_read_service.dart`,
`lib/features/ai_coach/**`). No third file this time (`workout_schedule_write_service.dart` is
read for reference only — `holdWeek` is cited, not modified). **Measure against the real diff
before dispatching review** — do not assert a tier from memory.

## Author's note — the arithmetic check that caught v5-draft-1's bug, kept for the reviewer

```
# planStart = day 0. One redoWeek4 tap: rollStart = planEnd+1 = day 28, newEnd = day 34.
# today lands inside that extension, e.g. day 30 -> regenStartWeek = 30//7+1 = 5.
regenStartWeek = 30 // 7 + 1                          # = 5
blockIndex = (regenStartWeek - 1) // 4                # = 1
naturalBlockEnd = (blockIndex + 1) * 28 - 1           # = 55  <- WRONG, overshoots by 21 days
storedPlanEnd = 34                                    # what redoWeek4 ACTUALLY set
# v5-draft-1 would write 26 days; only 5 days are actually provisioned.
```

This is why the final design reads `storedPlanEnd` directly rather than deriving an end from
`planStart` via a block-count formula — any formula independent of the actual stored value is a
second source of truth that can (and did) drift from the first.
