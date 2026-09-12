> ⛔ **REJECTED — DO NOT IMPLEMENT. Round 4, not-converged, 2026-09-10.**
> Design reviewer found a confirmed P0: the write loop silently degrades to ZERO writes whenever
> today is at/past the phase's nominal 4-week boundary (clamp(1,4) always resolves to week 4,
> whose 7 days are then all `.isBefore(today)` and skipped) — while the UNCHANGED delete loop
> still deletes real rows across today..plan_end. Reachable via the live, ungated `redoWeek4`.
> Full record: `docs/plan-reviews/regen-wave-unit2-round4.md`.
>
> Fourth consecutive round, fourth new P0. Every version has assumed "today" falls inside the
> current phase's nominal 4 weeks and breaks the moment that fails — which `redoWeek4` and
> ordinary calendar expiry both make a live, reachable case. No v5 is planned; see the in-flight
> memory (`project_regen_alignment_brainstorm_inflight.md`) for the recommendation: write the
> plan-window state model FIRST, before any further code-level attempt.

# OI-166 Unit 2 (v4) — anchor regeneration to the phase's real start, not today

**Branch:** `regen-wave-unit2` · **v4, 2026-09-10**, after v1-v3 all failed review (3 rounds, 6
negative verdicts — record: `docs/plan-reviews/regen-wave-unit2-round{1,2,3}.md`).

**Why v4 is a different shape, not a fourth patch on the same design:** v1-v3 all tried to build
one shared schedule-row builder used by A/B/C and got tangled in `plan_end`'s mutable-horizon
semantics (`redoWeek4`/`holdWeek` deliberately extend it). v4 does not touch `plan_start_date` or
`plan_end_date` at all, and does not touch the delete-range logic anywhere. It fixes a narrower,
concretely-verified bug: **B and C both anchor their regeneration content to TODAY instead of to
the phase's real start date**, so the wave position (baseline/overreach/peak/deload) is wrong for
any regen that happens after week 1, and B additionally writes rows past the phase's real
boundary as a side effect.

## Founder decisions this plan implements (verbatim, this session)

1. *"the starting baseline will be the present date from which the phase is starting. If the user
   is in week three, [and he] regenerates the workout, then his phase one gets regenerated. His
   three weeks will be completed and not changed, but the last week will be regenerated."*
2. *"if the user wants to generate for phases, then yes, block it to four weeks with the floor as
   the signup date... If he's in phase two, that is phase two, starting date will be the starting
   date of the phase two."*
3. Asked directly whether a mid-phase regen should restart the difficulty ramp or match the
   calendar week: **"when a user regenerates a plan, he is matching the calendar week."**

## The bug, verified against source

**B** (`workout_schedule_read_service.dart`, `generateAndScheduleFromDate`, called from
Edit Profile): loop at `:435-439` (formatted across those lines; the `for` header is `:435`, the ternary `:436-438`, `weekStart` `:439`)

```dart
for (int week = 0; week < 4; week++) {
  final weekPlan = week < plan.weekPlans.length ? plan.weekPlans[week] : plan.weekPlans.last;
  final weekStart = monday.add(Duration(days: week * 7));
```

`monday = _normalizeToMonday(today)` (`:379`) — **today's week**, not the phase's start. So a
regen on real week 3 writes `week=0` (today's week) with `plan.weekPlans[0]` = **baseline**
content, and continues writing 4 fresh weeks from today — meaning it writes real weeks 3,4,5,6,
silently extending past the phase's real week-4 boundary while `plan_end` stays put.

**C** (`regenerate_plan_planner.dart`, `RegeneratePlanPlanner.plan()`, called by both
`regeneratePlanBlock` and `switchGoal` — confirmed same planner, `tool_dispatcher.dart:842`,
`:980`): `:144-146`

```dart
final start = startDate != null ? DateTime.parse(startDate) : _today();
```

then (`:211` is the `for (var weekIdx...)` loop header + comments; the actual ternary is `:215-217`): `weekPlan = weekIdx < phase.weekPlans.length ? phase.weekPlans[weekIdx] : ...`
with `weekStart = start.add(weekIdx * 7)`. Same defect: weekIdx=0 (today, when no explicit
`startDate`) always gets `phase.weekPlans[0]` = baseline, regardless of real wave position.

**C never writes `current_plan` at all** — confirmed by grep, zero hits for `_planKey` /
`current_plan` in `tool_dispatcher.dart` or `regenerate_plan_planner.dart`. This is OI-166's literal
symptom: the phase-arc strip reads a stale blob after any AI-coach regen.

## The fix

One rule, applied identically in both places: **anchor to `plan_start_date` (the real phase start,
read-only, never written by this fix), and only touch weeks from today's real wave-position
onward.**

```
currentWeek := rawWeekNumberFor(today, planStart).clamp(1, 4)   // Unit 1's own function, :1269
// weekIdx (0-based) into weekPlans is used DIRECTLY — weekPlans[i] is ALWAYS
// baseline/overreach/peak/deload at position i by construction
// (PeriodizationEngine._waveNames, fixed List.generate(4,...)); no re-indexing.
```

**B** (`:435-439`, per the precise breakdown above): change the loop bounds and anchor —
```dart
for (int week = currentWeek - 1; week < 4; week++) {
  final weekPlan = plan.weekPlans[week];                     // direct index, no offset
  final weekStart = planStart.add(Duration(days: week * 7));  // anchor to phase start, not `monday`
```
Weeks before `currentWeek` are never entered — the loop simply starts later. This also closes an
until-now-undiscovered second defect as a side effect: rows can no longer be written past the
phase's real 4-week boundary during a mid-phase regen, because the loop never runs past `week=3`.

**C** (`regenerate_plan_planner.dart`): **only when `startDate` is NOT supplied** (the
default/common regen case). **My own scoping call, not something round 2 already settled** —
round 2 actually flagged this exact parameter as unresolved (`round2.md:72-88`, three flawed
resolutions, none picked). The rationale: `startDate` explicit is a genuinely different, pre-existing
capability (a future-dated block — e.g. hotel-planner-style — not "continue my current plan"),
and the founder's decisions this session were specifically about the no-`startDate` case (resuming
today, mid-phase). That reading is left EXPLICIT here so the reviewer can weigh it directly, not
discover later it was borrowed authority that doesn't exist — see
`feedback_mistake_fabricated_citation_to_justify_scope.md` for why this note exists at all:
```dart
final planStart = getPlanStartDate();   // NEW read-only read; C writes neither key, still doesn't
final currentWeek = (startDate == null && planStart != null)
    ? rawWeekNumberFor(_today(), planStart).clamp(1, 4)
    : 1;                                                       // explicit startDate: unchanged behaviour
final start = startDate != null ? DateTime.parse(startDate) : planStart!.add(Duration(days: (currentWeek - 1) * 7));
```
then in the loop (`:215-217`, per the precise breakdown above), index by `(currentWeek - 1) + weekIdx` instead of `weekIdx`,
clamped to `phase.weekPlans.length - 1` for the existing beyond-4 repeat-last behaviour (untouched
for weeks 5-12 — that capability is not in scope here, per the founder's explicit go-ahead to leave
it as a separate future item).

`plan()`'s return record gains one field — `phase: Phase` (the object already built at `:190`,
currently discarded after the loop) — so callers can write `current_plan`.

**Both commit sites** (`tool_dispatcher.dart:842` `_executeRegeneratePlanBlock`, `:980`
`_executeSwitchGoal`) add, after the existing `upsertScheduled` loop: read the existing
`current_plan` blob, splice it with the freshly generated `phase.weekPlans` at index
`currentWeek - 1` onward (position-preserving — `spliced[i] = existing[i]` for `i < currentWeek-1`,
else `phase.weekPlans[i]`), write the result. Degenerate case (no existing blob, or `planStart`
null): write `phase.toMap()` unspliced, matching A's first-generation behaviour.

## New pure helper (shared by B and C, one definition)

`lib/core/services/wave_position.dart` (new file, `account` tier — imported by both `core/services`
and `ai_coach`, no cross-tier import needed since `core/services` is already visible to
`ai_coach`):

```dart
/// The 0-indexed wave position into a freshly-generated Phase's 4 weekPlans
/// that a regen starting on [today] should use, given the phase's real
/// [planStart]. `weekPlans[i]` is always baseline/overreach/peak/deload at
/// position i by construction (PeriodizationEngine), so this returns an
/// ABSOLUTE index — callers use it directly, no further offset math.
int currentWaveWeekIndex(DateTime today, DateTime planStart) =>
    rawWeekNumberFor(today, planStart).clamp(1, 4) - 1;

/// Splices a freshly generated 4-element week_plans list into an existing
/// current_plan blob's week_plans, preserving indices before [fromIndex]
/// (already-completed weeks) and replacing [fromIndex..3] with the fresh
/// values at the SAME absolute index (position-aligned — matches the
/// calendar week, per founder decision "matching the calendar week").
/// Degenerate (existing missing/short): returns freshWeekPlans unchanged.
List<Map<String, dynamic>> spliceWeekPlans({
  required List<dynamic>? existingWeekPlans,
  required List<Map<String, dynamic>> freshWeekPlans,
  required int fromIndex,
}) {
  if (existingWeekPlans == null || existingWeekPlans.length < freshWeekPlans.length) {
    return freshWeekPlans;
  }
  return [
    for (var i = 0; i < freshWeekPlans.length; i++)
      i < fromIndex
          ? Map<String, dynamic>.from(existingWeekPlans[i] as Map)
          : freshWeekPlans[i],
  ];
}
```

## Explicitly out of scope (so no reviewer assumes silent overreach)

- `plan_start_date` / `plan_end_date` — never read for write, never written, by this fix.
- The delete-range logic in B (`:358-377`) — untouched.
- `redoWeek4` / `holdWeek` — untouched.
- C's `weeks` parameter beyond 4 (multi-phase forward planning) — untouched; existing repeat-last
  behaviour for weeks 5-12 continues exactly as today, just correctly anchored for weeks 1-4.
- C's explicit-`startDate` branch (future-dated blocks) — untouched, existing behaviour preserved.
- `scheduleTemplate` / hotel-planner / swap tools — not touched by this plan at all.

## Tests

- `test/core/services/wave_position_test.dart` (new, pure): `currentWaveWeekIndex` for weeks 1-4
  and clamp behaviour beyond 4; `spliceWeekPlans` for all four cases (`fromIndex=0` full overwrite,
  `fromIndex=3` single-week splice, existing null, existing short).
- Behavioral: a regen mid-phase (real week 3) via B produces a schedule row at that date carrying
  `week_character` = `'peak'` (not `'baseline'`), and writes no row past real week 4.
- Behavioral: the same via C (`regeneratePlanBlock`, no `startDate`) writes `current_plan` such
  that `currentWaveCharacters()[2]` (0-indexed week 3) = `'peak'`, and weeks 1-2 of the blob are
  byte-identical to what existed before the regen.
- Mutate `currentWeek - 1` → `0` in both call sites once, confirm both behavioral tests redden.

## Blast radius

Touches `lib/core/services/workout_schedule_read_service.dart` (account, per pre-push tier list)
and `lib/features/ai_coach/**` (also account per the same list) — **measure with
`blast_radius_from_diff.dart` against the real diff before dispatching review**, not asserted here
from memory (the exact mistake `part`-file/migration rows in CLAUDE.md §4.9 warn against).
