# OI-166 Unit 2 (v4) — review round 4

**Plan:** `docs/audit/oi166-unit2-plan-v4.md` · **Verdicts:** design reviewer **not-converged**
(ground-truth reviewer confirmed 12/15 citations exact, found one self-caught fabricated
citation — corrected in the plan before the design review completed, see below).

## Self-caught before the design verdict landed

The ground-truth reviewer found the plan attributed an invented quote ("for cases other than
resuming today") to round 2's review to justify leaving C's explicit-`startDate` branch out of
scope. Round 2 actually flags that exact parameter as unresolved, not blessed as safe. Fixed in
the plan before dispatch of this record; memory:
`feedback_mistake_fabricated_citation_to_justify_scope.md`.

## The P0 — CONFIRMED, re-verified by hand, not taken on the reviewer's word

v4's premise: avoid v3's `plan_end`-mutable-horizon trap by leaving `plan_start`/`plan_end` and the
delete-range loop untouched, and instead correct only which of the 4 wave-position weeks gets
written. **The premise doesn't survive contact with a live case:**

1. `redoWeek4()` (live, ungated, free-tier — `workout_schedule_write_service.dart:213-214`) extends
   `plan_end` to `planStart+34` without moving `plan_start`.
2. Days later, "today" lands inside that extension (e.g. `planStart+30`). User edits their profile
   → `generateAndScheduleFromDate`.
3. Delete loop (`workout_schedule_read_service.dart:362-377`, unchanged by v4): deletes every
   non-completed row from `today` through the *stored* `plan_end` (`planStart+34`).
4. v4's write loop: `currentWeek = rawWeekNumberFor(today, planStart).clamp(1,4)` clamps to `4`.
   Loop becomes one iteration, `weekStart = planStart+21..27`. Every date in that range is
   `.isBefore(today)`, so the inner day-loop's `continue` (`:447-452`, re-verified by hand) fires
   for all 7 days — **zero writes**.

Net: real rows get deleted, nothing replaces them. Confirmed by direct re-read of both loops, not
taken on the design reviewer's prose.

A second, independent recurrence of the same class: even with NO `redoWeek4` extension, a
genuinely expired phase (`today > planStart+27`, the coach tool's own advertised "refresh after a
long break" case) hits the identical zero-write loop while `current_plan` is still overwritten
unconditionally — round 2's P0-2, unresolved a second time.

## The pattern across all four rounds

| Round | Design | What killed it |
|---|---|---|
| 1 | Shared builder, C given no `weeks` param | Can't express C's live 1-12 week capability |
| 2 (v2) | "Window is always exactly 4 weeks" | False — `redoWeek4` extends `plan_end` without moving `plan_start` |
| 3 (v3) | Explicit `weekCount=4`, `nominalEnd=planStart+27` | Write range ≠ delete range when `plan_end` is extended → 7 days deleted, never rewritten |
| 4 (v4) | Anchor to real phase position, don't touch `plan_end` at all | Same write≠delete mismatch, reached by a different route: clamping `currentWeek` to 4 silently degrades to a zero-write loop whenever today is at/past the nominal boundary |

**Every version assumes "today" falls within the current phase's nominal 4 weeks, and breaks —
either by writing the wrong content or by silently writing nothing — the moment that assumption
fails.** That failure is not an edge case: it is the live, reachable, ungated `redoWeek4` path, plus
ordinary calendar expiry.

## Verdict

Not converged. Fourth consecutive round with a new material P0. Per §4.12.1, this is well past the
point of splitting and shipping the smallest converged piece — there is no piece that converges
without first answering what "today is at/past the nominal boundary" means for a regen. No v5 is
being drafted; see the author's note in the in-flight memory for the recommendation.
