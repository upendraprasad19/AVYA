---
branch: regen-wave-unit2
date: 2026-09-12
blast_radius: account
review_rounds: 9
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/9c7cbabe4d3d-review.md
---

# Plan-review record — OI-166 Unit 2 (account)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Account tier**, measured against the ACTUAL staged file list
(`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -` → `account`,
2026-09-11), and printed as `blast-radius=account` by `scripts/pre-commit.sh` on every green gate-loop
run of this tree. `lib/features/ai_coach/**` is `account` (`docs/blast_radius.yaml:235`);
`lib/core/services/workout_schedule_read_service.dart` falls to the `lib/core/services/**` default
(`:326`) — none of the higher-tier service globs match it. Not platform → `bpass: accepted` is NOT
required by the gate (`check_plan_review_record_exists.dart:833`); not catastrophic → no Hermes pass.

## B-pass: accepted

`docs/reviews/9c7cbabe4d3d-review.md` — one fresh context-blind agent, 6 findings (1 P0, 2 P1, 1 P2, 2 P3),
0 false alarms, every finding closed in-batch with a per-finding `status:` recorded in that file. Its
top-level `verdict: accepted` was set on the founder's explicit acceptance of the triage (2026-09-12, in
chat), per the code-review skill's contract (`.claude/skills/code-review/SKILL.md` §4) — not inferred by
the author. At account tier the field is advisory (`check_plan_review_record_exists.dart:833` requires it
only from platform up); it is recorded because it is true, and the anti-fabrication check (`:840-866`)
finds the line-anchored `verdict: accepted` it demands in the referenced file.

## Scope

OI-166 Unit 2 — the regeneration-window fix that Unit 1 (`docs/plan-reviews/regen-wave-alignment.md`)
explicitly did NOT ship: the AI-coach regen path never wrote `current_plan`, so the phase-arc strip
rendered a stale wave. Diagnose `d7f3b2`. Plan: `docs/audit/oi166-unit2-plan-v10.md`.

1. **`contentFlavorIndex(w) := (w-1) % 4`** — NEW static on `WorkoutScheduleReadService`, beside the
   Unit-1 `rawWeekNumberFor`. Cycles baseline/overreach/peak/deload past week 4 instead of freezing on
   the last week or indexing out of bounds.
2. **Writer B** (`generateAndScheduleFromDate`, Edit-Profile regen): loop bounds anchored to the phase's
   real `plan_start` (`regenStartWeek..lastWeek`, both `rawWeekNumberFor`-derived); a per-day upper bound
   against the STORED `plan_end`; the unconditional `current_plan` write replaced by a splice
   (preserve completed weeks, cycle the rest) gated on the write range being non-empty by a literal
   DATE comparison — not a week-bucket comparison, which diverges whenever `plan_end` is mid-week
   misaligned (the exact state `redoWeek4` on a non-Monday produces).
3. **Writer C** (`RegeneratePlanPlanner.plan()` + both `tool_dispatcher.dart` commit sites, the AI-coach
   `regeneratePlanBlock`/`switchGoal` tools): `effectiveWeek` replaces the request-relative `weekIdx+1`
   at all three stamp sites; `Phase` + a NULLABLE `regenStartWeek` threaded through the return record,
   the cache, two new getters and `clearCache`; both commit sites splice `current_plan` with the same
   formula as B. The explicit-`startDate` branch keeps its pre-fix behaviour byte-identical (null
   `regenStartWeek` → splice skipped; "repeat-last" content selection preserved).
4. **Behavioral test** `test/contracts/oi166_unit2_regen_content_cycling_behavioral_test.dart` — 11
   tests through the REAL two-phase contract (`plan()` → `cache()` → `ToolDispatcher.execute()`), not a
   hand-rolled splice; six mutations run and reverted (diagnose-doc `regression_test_planned`).

## Review history — nine rounds on the plan, then implementation, then a B-pass on the code

Every round dispatched two context-blind reviewers: a design reviewer (mechanism) and a ground-truth
reviewer (every `file:line` citation re-derived against source). Per-round records:
`docs/plan-reviews/regen-wave-unit2-round{1..9}.md`. Plan versions v1-v3 are superseded; v2 is the
last committed early version (`docs/audit/oi166-unit2-plan.md`, banner explains v3's loss); v4 and v10
are committed; v5-v9 were edited in place into their successor.

| Round | Design | Ground-truth | What it found |
|---|---|---|---|
| 1 | not-converged | not-verified | P0: the shared builder as specified could not express what caller C already does |
| 2 | not-converged | not-verified | the load-bearing "window is always exactly four weeks" claim is FALSE (`redoWeek4` moves `plan_end`, not `plan_start`) |
| 3 | not-converged | not-verified | v3's own fix introduced a P0 `main` does not have (7 days deleted and never rewritten) — v3 rejected and the unit re-planned from the window model up (v4) |
| 4 | not-converged | not-verified (12/15 exact; caught a fabricated round-2 quote used to scope out C's explicit-`startDate` branch — corrected) | v4's P0 confirmed by hand, not on the reviewer's word |
| 5 | not-converged | **verified** (24/24) | **the core mechanism is sound for the first time** — bind the write range to the STORED `plan_end`, never a derived formula |
| 6 | not-converged | not-verified | C's `'week'` stamp only half-closed (1 of 4 sites); C's `current_plan` write had no specified LOCATION anywhere in the plan; B's own `'week'` sites never addressed |
| 7 | not-converged | **verified** (33/36 exact, rest within tolerance) | **real runtime P0**: B's day-loop had no per-day upper bound; reachable via a misaligned `plan_end`. Plus 3 P1 spec gaps |
| 8 | not-converged | **verified** (44: 42 exact) | 3 P1 compile-blockers, all inside round 7's own fixes (unqualified cross-class static; a `final` read outside its `for`-scope; B missing C's mirror) |
| 9 | not-converged | **verified** (51: 50 exact) | 1 more P1 of round 8's exact class on a new symbol (`contentFlavorIndex` called from 3 classes, declared nowhere) + the missing import; the `current_plan` splice written out as concrete Dart proactively |

**Why `verdict: converged` is an honest claim despite no round returning that word.** The design has
been stable since round 5 — rounds 7, 8 and 9 each independently re-confirmed the core mechanism and
every prior fix clean by re-derivation, and what they kept finding narrowed monotonically: a runtime
data bug (7), then symbol-resolution slips — a qualifier, a scope, a declaration, an import (8, 9) —
the class the Dart compiler catches mechanically on the first build. Round 9's own closing
recommendation said so and put the choice to the founder; the founder chose implementation over a
10th prose round (2026-09-11, "follow discipline"). Implementation then did what a 10th round could
not: `flutter analyze` + the real test harness caught the remaining slips, and the code — not the
prose — was reviewed by a fresh B-pass. Six further sub-defects were found across that chain and
every one is closed and mutation-proven in this same batch (diagnose `d7f3b2`, `concept:` items 1-6):

- **Sub-defects 1-3** (implementer, before any review): week-bucket-vs-date-range divergence on a
  misaligned `plan_end`; first-generation `planEnd` read from Hive before the horizon it will overwrite
  exists; commit-site qualifier/redeclaration discipline.
- **Sub-defect 4** (post-implementation self-verification, independent of the implementer's report):
  C's content-selection guard collapsed — an explicit-`startDate` call would have cycled instead of
  repeating the last week. Fixed, test widened `weeks:2 → 6`, mutation-proven.
- **Sub-defects 5-6** (the B-pass, after self-verification): writer C's splice lacked writer B's
  zero-rows gate (the round-5 P0, reopened for the sibling writer); three throw-prone casts
  inconsistent with this same blob's established crash-safe reader. Both fixed at every site, each
  with its own test and an orthogonal mutation proof.
- **B-pass Finding 1 (P0)** was a PROCESS failure, not a code one, and belongs in this record: sub-defect
  4's fix and its widened test had never been `git add`ed. Every `Read` and `flutter test` in the
  session had verified the working tree; the staged index — what would have been committed — still
  held the buggy form. Caught by the reviewer resetting to `git show :<path>` content before testing.
  Now staged; the skill's tuning history carries the lesson (lens 10).

## Residual, disclosed rather than implied-fixed

The phase-arc strip's "now" highlight (`getCurrentWeekNumber()`, clamped to `[1,4]`) does not cycle
even though content now does — past real week 4 it points at `week_plans[3]` regardless of the real
week's character. Pre-existing, belongs to the `hold_week_identity` concept (own tests, own explicit
"clamped 4 is honest for some consumers" invariant), out of scope for this unit. Tracked on OI-175
(`docs/audit/open_issues.md`) and in `d7f3b2`'s `impact_analysis`. B-pass Finding 2.

## What this record does NOT claim

- It does not close OI-166's WINDOW-ALIGNMENT half (OI-175) — `redoWeek4`/`holdWeek` were explicit
  out-of-scope. Only the content/labeling half and the never-written `current_plan` blob are closed.
- It does not claim the CI full suite has run — pre-commit is gates-only by design (ADR-0018); the
  behavioral file is 11/11 locally and lands in the pre-push ≥account suite and CI.
