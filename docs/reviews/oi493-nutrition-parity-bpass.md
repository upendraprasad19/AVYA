---
reviewed_at: 2026-11-12T16:30:00+05:30
staged_against: 93ec6cf0 (PR #251 head, CI green; three-dot diff origin/main...HEAD)
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 15
verdict: accepted
verdict_note: no P0/P1 in either seat; 5 P2 and 10 P3; every P2 fixed with a mutation-proven test; P3 fixed or closed with a reason
---

# Code Review (B-pass) - oi493-nutrition-parity (OI-493 Landing A)

Two fresh Sonnet seats on the CI-green head `93ec6cf0`, each with `docs/agent_brief_preamble.md` and an exhaustive
command list. Seat A (lenses 1-5, 7, 8) read code only through `git show HEAD:`. Seat B (lens 6) ran 27 mutants on nine
named files with backup / sha256 restore (tree clean afterwards). Diagnose `ec6f6c` holds the mutant tables.

## Seat A

### A1 — P2 — missing_input
- **file:line:** lib/features/ai_coach/services/coach_meal_log.dart `resolveCoachMealSlot`
- **claim:** "snack" / "Evening snack" fell to the clock rule (an evening snack under dinner); the deleted paths sent every unknown value to `snacks`.
- **status:** accepted, fixed: a value containing "snack" is `snacks`; test A1, mutant R1 red.

### A2 — P3 — writer_reader_drift (registry ranges)
- **claim:** `logMeal` ranges off by one, `_parse (case log_measurement)` and five reply-sanitizer single-line anchors stale (pre-existing, file touched).
- **status:** accepted, fixed: re-taken from the tree (`logMeal` 60-160, log_measurement 1606-1638, anchors 300/332/695/956/1036).

### A3 — P3 — function_exception_swallow
- **claim:** a calorie-less tag shows no card while the reply may say it was logged.
- **status:** no_change_needed: plan D4 and residuals (counted by `coach_food_tag_dropped_no_calories`, reopen if it appears in tester data); the write-claim rule already tells the coach a card comes first.

### A4 — P3 — missing_input
- **claim:** `date: null` (the field is nullable in the Gemini schema) is refused.
- **status:** accepted, fixed: `.nullish()`; Deno test, mutant S5 red.

### A5 — P3 — missing_input
- **claim:** the data export's `nutrition_logs_count` now counts the `recent_deletes` key.
- **status:** accepted, fixed: counts the exported rows; test A5, mutant R13 red.

### A6 — P3 — asserted_fixture_value (stale comment)
- **claim:** "caller passes IST DateTime" contradicts the contract.
- **status:** accepted, fixed: `logMeal` doc and step-2 comment reworded.

## Seat B

### B1 — P2 — guard_without_its_mirror
- **claim:** the tool's failure branch was untested (`if (false)` 0 red).
- **status:** accepted, fixed: a closed box makes `logMeal` fail; the tool answers failure, reports it, runs no badge check; mutants R2, R3 red.

### B2 — P2 — guard_without_its_mirror
- **claim:** "card slot = written slot" unpinned for a tag with no `meal_type` (only tested at 23:59:58, where the rule says snacks).
- **status:** accepted, fixed: tag at 07:30Z; mutant R4 red under Kolkata.

### B3 — P2 — guard_without_its_mirror
- **claim:** IST vs UTC "today" on the server unpinned.
- **status:** accepted, fixed: FakeTime at 01:30 IST; mutant S4 red.

### B4 — P2 — guard_without_its_mirror
- **claim:** three `hasFoodMeta` legs unpinned (meal_type, non-empty items, legacy `name`).
- **status:** accepted, fixed: four deleteLog cases; mutants R7-R9 red.

### B5 — P3 — guard_without_its_mirror
- **claim:** recent-list dedup case, tie order, blank names unpinned; a legacy flat row no longer appears.
- **status:** accepted, fixed for the three behaviours (R10-R12 red); the legacy flat row is no_change_needed (plan D9: such rows add nothing, stated).

### B6 — P3 — guard_without_its_mirror
- **claim:** badge on failure, negative calories, 0 g, weekly invalidation on failure unpinned.
- **status:** accepted, fixed for the first three (R3, R5, R6 red); invalidation-on-failure no_change_needed (an extra invalidation is harmless).

### B7 — P3 — guard_without_its_mirror
- **claim:** a zero payload total as override is pinned neither way.
- **status:** no_change_needed: Landing B (plan residual); seat A notes the server recomputes zero totals from the items.

### B8 — P3 — guard_without_its_mirror
- **claim:** the `food_name` guard is token-level.
- **status:** accepted: stated in the guard's header (deliberate).

### B9 — P3 — none
- **claim:** string fibre is pinned; a null `items[]` entry throws as before.
- **status:** no_change_needed.

## Founder triage notes
Self-triaged per §4.3 (platform tier, advisory verdict); every finding has a terminal status above.

## Tuning entry
- **2026-11-12** - blast-radius platform - 15 findings; 0 false_alarm; tuning: none. The mutation seat found five unpinned mirrors the author's 18 mutants missed (failure branches and the other legs of a compound predicate); for a new compound predicate, mutate EVERY leg, and for every success-path test write its failure twin.
