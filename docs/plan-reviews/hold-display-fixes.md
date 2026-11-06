---
branch: hold-display-fixes
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/hold-display-fixes-bpass.md
---

# Plan review — hold-display-fixes (D1 + L1 + L3)

## What shipped

Two behavioral fixes plus the test that pins the property the hold feature rests on:

- **D1** — the Train deployment banner printed `DEPLOYMENT 01 · FOUNDATION · WK 4 OF 4` roughly 40px
  below the `HOLDING · Hn` pill, in the same scroll view. Now branched on `holdStatus.isHolding`; the
  holding arm drops the week counter, matching the rule `plan_header.dart` already applies (*"a hold
  week has no honest WK n OF m — it sits OUTSIDE the phase's m weeks"*). The non-holding arm is
  byte-identical, so the literal pinned by `phase_relative_week_label_test.dart` still matches.
- **L1** — `completedWeekNumbers()` now excludes `is_hold` rows. It maps date→week via
  `plan_start + 7k`, but a hold is not on that grid, so a completed hold day credited a ✓ to a
  padlocked PHASE II/III chip.
- **L3** — a behavioral test driving the REAL `WorkoutWriteService.markCompleted` on a hold row,
  asserting `is_hold`/`hold_ordinal` survive completion.

No migration, no Edge Function deploy, no schema change. `enable_hold_weeks` stays default OFF.

## How this batch was scoped — a ×2 review that did NOT converge, then a split

This record's `review_rounds: 2` refers to **two independent context-blind reviews of the
implementation plan, run before any code was written.** They examined a proposed **six**-fix batch and
returned **NOT CONVERGED with four P0s**. Per §4.12.1 — *"when successive reviews keep surfacing new
material issues, that is the signal the unit is too large: split it and ship the smallest converged
piece"* — the unit was split. This batch is the piece **both reviewers explicitly cleared**; Reviewer A
wrote of D1, *"the only fix I can fully clear."*

**What the reviews killed, and why it matters:**

- **P0 — my streak fix was arithmetically wrong.** I had designed it on `4 + ordinal`, assuming hold
  week *N* sits at `plan_start + 7×(3+N)`. It does not: `holdWeek()` uses
  `normalizeToMonday(nowWall())` (`workout_schedule_write_service.dart:248`), so a hold occupies the
  calendar week containing **today**. A user who lapses three weeks and returns gets H1 at
  `plan_start + 49` — date-week 8, ordinal 1. The fix would have read unmaterialized dates →
  `planned == 0` → **no streak increment and no `streaks` row at all**, silently, on the commonest real
  path — while passing every test I would have written, because I only exercised the contiguous case
  under time travel. This is now pinned as the LATE RETURN case in
  `hold_display_read_path_test.dart`, which asserts `weekStart == lateStart` while the date index is 8.
- **P0 — the coach/push design reintroduced drift `c9f4a2` had closed.** Projecting `4 + ordinal` into
  `user_progress.current_week` would have produced a snapshot saying week 4, a push saying week 6 and a
  chip saying H2 — three surfaces, three numbers — and would have manufactured exactly the number the
  shipped UI already ruled dishonest.
- **P0 — the Sunday push copy is wrong for a holder at any value**, so "no Edge Function redeploy
  needed" was false.
- **P0 — holds are unobservable**: the five `phase_1_day_29_*` events have zero consumers repo-wide, and
  because `founder_metrics_engagement()` counts `ai_coach_interactions` with no `channel` filter they
  *inflate* `ai_messages_today`.
- Plus: my "all six fixes are naturally ship-dark" claim was **false** (the proposed row→`WorkoutDayData`
  extraction depends on loop var `w` and would run for every user), I had conflated **two different
  `getWeek` methods** (`CurrentPlanData`'s indexed/capped one vs the read service's date-based unbounded
  one), and the reader inventory missed `telegram-bot/bot.py` and a second unguarded snapshot consumer
  in `ai-media-proxy`.

Everything not shipped here is recorded as **hard flip-on preconditions** in
`docs/ship_dark_pending_review.yaml` (`flip_on_blockers`, FOB-1…FOB-7). That is a gate, not a
deferral: `enable_hold_weeks` already cannot flip without its own full ×2 + `bpass: accepted`, and that
review must show every FOB closed. Closure ledger: `docs/audit/hold-display-fixes.closure.yaml`
(5/5 terminal).

## Ground-truth verification

- The P0 was **verified by the author against source** before acceptance, not taken on reviewer prose:
  `workout_schedule_write_service.dart:248` places the hold in today's week, and the two `getWeek`
  variants were confirmed distinct by symbol lookup.
- The date-week arithmetic for all three hold-start test cases (5 / 8 / 15 from `plan_start`) was
  hand-computed independently by the B-pass reviewer and matches.
- L1's blast radius was checked by enumerating callers: `completedWeekNumbers()` has exactly one
  production caller (`week_selector.dart:122`), and `HoldWeekInfo.isCompleted` is computed independently
  — so hold chips keep their ✓.
- Flag-OFF inertness was proven structurally, not asserted: only `holdWeek()` writes `is_hold`, and the
  flag-OFF path routes to `redoWeek4()`, which never does.

## B-pass

`docs/reviews/hold-display-fixes-bpass.md`, verdict **accepted**. Fresh context-blind Sonnet over the
staged diff. Two findings, both real, both fixed in-batch:

- **P0 — gate evasion by stale citation.** My closure ledger cited branch `hold-display-fixes` and
  review docs that did not exist, while the working branch was still `hold-display`. The keystone gate
  keys on **branch name**, so it would have resolved the PREVIOUS batch's `hold-display.md` — which
  carries `bpass: accepted` — and passed green on an artifact that never reviewed this diff. Fixed by
  renaming the branch and writing the records the citations promised. Not a code defect; a discipline
  artifact that would have silently disarmed the gate.
- **P2 — a test that overclaimed coverage.** The reviewer **reverted the fix and re-ran** to prove the
  "beyond maxWeek" case passes either way. Fixed by honest relabelling to `CHARACTERIZATION:` with a
  comment naming the two cases that genuinely fail without the fix — kept, because it documents why the
  pre-fix bug was intermittent.

## Provenance

Both defects fixed here were found by a **live walkthrough on `test7`** (2026-07-25) — flag flipped ON
via the new `/dev` Flags card, time-travelled to the day-29 wall, three holds taken, backend verified in
Postgres. D1 was visible to the eye; L1 came out of the ground-truth investigations that walkthrough
triggered. The automated suite was green throughout and would not have surfaced either.
