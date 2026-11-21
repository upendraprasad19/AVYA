---
branch: oi493-nutrition-parity
scope: OI-493 Landing A (coach-door meal parity). Every coach meal door writes through one CoachMealLog.write. The day and slot come from the instant the meal was reported (the server's intent createdAt, or the tag card's creation), with the slot by the screen's clock rule. The coach's parsed items are written with fibre, and the food tag writes the coach's own estimate instead of a database food or invented defaults. A coach meal no longer spends the client AI-text allowance, the server refuses a non-today date, and six readers of a never-written top-level food_name read the item names, with a source guard. Landing B (same meal twice adds an entry) has its own plan.
blast_radius: platform
review_rounds: 5
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/oi493-nutrition-parity-bpass.md
---

# Plan-review record: OI-493 Landing A

Plan: `docs/plans/oi493-nutrition-parity.md` (rev 5.1). Survey: a context-blind Sonnet agent (13 differences), every
key claim re-checked by the coordinator against the code before the plan. Founder decisions F1-F4 (2026-11-12) are in
the plan's section 0. Every round used context-blind Sonnet seats with `docs/agent_brief_preamble.md` prepended and an
exhaustive read-only command list; this is a prose plan with no draft diff, so the gate loop runs before the B-pass (§4.12.5).

## Round 1 (rev 1, one unit, two seats: A ground truth, B adversarial design)
Not converged: 9 P1 across the plan.
- B: the ICBF golden pins the ai-proxy prompt byte for byte; "first absent occurrence" key choice races without a lock;
  delete + UNDO overwrites a newer occurrence; midnight semantics wrong both ways; three more `food_name` readers.
- A: `_writeFoodLogFromIntent` has one caller (prelog removed 2026-05-31); `NlogKeyMigrator` recomputes a different
  (hashCode, UTC-date) key and keeps only the latest; `CoachMealLog.write` had no Ref for the invalidations it claimed;
  the golden collision; plus repoint lists, migration 129 (not 026), a path typo.
Outcome: SPLIT (§4.12.1). Landing A = coach-door parity; Landing B (`docs/plans/oi493b-duplicate-meals.md`, F4 and the
zero-override fallback, carrying every occurrence-key finding) follows after A merges.

## Round 2 (rev 2, Landing A, two seats)
Not converged: 6 P1.
- A: `createdAt` is a UTC-flagged server stamp and `inferMealSlot` reads the raw hour, so a 13:00 IST lunch would read as
  breakfast; the Deno size pin (2189) on the ON prompt; the recent-list relog read row totals.
- B: a wrong-day refusal at APPLY leaves a dead card after the coach said "queued" (move it server-side); the callback had
  no failure contract; the prompt edit drifted from the detector.
Outcome (rev 3, simplified): `.toLocal()` for the slot; server-side `.refine` on `date`; NO prompt change (golden, size
pin and write-claim rule untouched); no callback (badge check in a try/catch after success); relog as stored.

## Round 3 (rev 3, two seats)
No P0. One design P1 (B): the server checks `date` before the multi-second parse while `createdAt` is stamped after it,
so a client-side comparison refused a 23:59:58 meal. A: build mechanics (an existing Deno test file called NEW, a missed
repoint `food_log_notifier_to_nutrition_log_items_test.dart:188-200`, the guard allowlist missing the new file,
`PendingLogAction.createdAt` must be optional). Outcome (rev 4): client refusal removed; rune-safe name cut; tolerant
recent list; mechanics fixed.

## Round 4 (rev 4, one convergence seat)
Not converged: one P1. Rev 4's payload-date path would have fed a 00:00Z instant into the slot rule (a dated lunch as
breakfast). Two stale D5 sentences. Outcome (rev 5): the client ignores the payload date; one instant (`createdAt`) drives
day and slot; the server's check is the only date rule.

## Round 5 (rev 5, one convergence seat)
Converged: no P0/P1. One P2 fixed in place (rev 5.1): a P4 test sentence asserted lunch under Tokyo for 07:30Z; replaced
by the per-zone table (Kolkata lunch, Tokyo snacks, UTC breakfast, same IST day).

The rounds shrank from 9 P1 to 6 to 1 to 1 to 0, and three of the fixes were removals (prompt edit, callback, client date
rule), per the "remove the mechanism when rounds chase its symptoms" practice.

## Build and B-pass
Draft committed `0ed6722a` after the local gate loop (whole-project analyze 0 warnings, pre-commit gates, Deno tree);
synced with main (`93ec6cf0`); the full suite ran on CI for PR #251 (`land_pr --ci-only`: ci-green on `93ec6cf0`).
B-pass on that head, two fresh Sonnet seats (A read-only, lenses 1-5/7/8; B lens 6 by 27 mutants): no P0/P1, 5 P2 and
10 P3, all terminal in `docs/reviews/oi493-nutrition-parity-bpass.md` (verdict accepted). Fixes in `d5de6421`: snack
alias, `date: null`, export count, comments, registry ranges, and tests for five unpinned mirrors (15 new mutants red).
