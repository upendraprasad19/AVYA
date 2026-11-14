---
reviewed_at: 2026-11-15T01:20:00+05:30
staged_against: 638041b5 (committed diff 21db03c7..638041b5; PR #276)
blast_radius: platform
reviewer: claude-sonnet-via-skill (three fresh agents, no conversation context, one lens group each)
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 18
verdict: accepted
verdict_note: no P0 or P1; every P2 fixed in the follow-up commit except the food-type switch interaction, which is accepted, documented and pinned by a test; P3s fixed or accepted with reasons below
---

# Code Review (B-pass) — diet plan Unit 3b-2, the diet strategy in the coach manual and suggestMeal (`diet-strategy-3b2`, PR #276) at 638041b5

Three seats, each context-blind:
- seat A: writer/reader drift and blast radius (the snapshot keys the manual names, the column spellings, every prompt builder that bundles the manual, registry ranges);
- seat B: guards and their mirrors, missing input (counted in the real asset with a Python port of the handler: 1,444 rows, 152 queries per profile);
- seat C: tests that pass for the wrong reason, fixture values.

The coordinator re-checked each finding against the code before acting.

## Seat A

### A1 — P2 — the strategy note is missing on an empty answer
- **file:line:** `suggestMeal.ts` the `rows.length === 0` return vs the note push after it
- **claim:** a capped query that returns nothing tells the model to raise the calorie budget, never that the carb cap filtered.
- **status:** fixed: the note is pushed as soon as the cap is known, before every return; test "an empty capped answer still names the cap"; mutant E2 (the note moved back after the return) red.

### A2 — P2 — the food-type switch also drops the cap
- **claim:** `DISABLE_SUGGESTMEAL_STORED_FOOD_TYPE` routes to the verbatim pre-2b `legacyHandler`, which reads no profile and applies no cap, while the manual still tells the model the user is on keto.
- **status:** accepted and pinned (same as B1): that switch is the whole-tool rollback to before Unit 2b; adding the cap to the legacy path would break its "verbatim" property, and the manual has its own switch. Stated in the code comment, `supabase/functions/CLAUDE.md`, the naming row and OI-510; test "the food-type switch runs the verbatim pre-2b handler, which applies no strategy".

### A3 — P3 — registry wording for weekly-report
- **status:** fixed (the registry says weekly-report bundles the passage but never sends the key).

## Seat B

### B1 — P2 — = A2. Accepted, see A2.

### B2 — P2 — under a cap the top five are protein powders
- **claim:** the ranking is protein per 100 kcal, and supplement rows are the densest under 6 g: measured 752 of 760 veg keto top-five slots were supplements (99 %), against 63 % uncapped; paneer, tofu, eggs and nuts never reached the top five.
- **status:** fixed: under a cap the query also has `.neq("category", "supplements")` (the asset has no null category, so PostgREST's NULL rule drops nothing else) and the note says "protein powders left out"; Balanced is unchanged. Test rows: a soy isolate at 3 g carbs and 80 g protein is out under keto, in when uncapped; mutant E1 red.

### B3 — P2 — the strategy column read is coupled to the food-type read
- **claim:** one select for both columns, so if `diet_strategy` were unreadable every caller would drop to the vegan fail-safe, and the strategy kill switch would not help.
- **status:** fixed: the read selects `diet_preference, diet_strategy` only when the strategy can apply (PRO and the switch off); otherwise `diet_preference` alone, as before 3b-2. Test "the profile read selects diet_strategy only when the strategy can apply"; mutant E3 red.

### B4 — P3 — `ctx.isPro` is unreachable as false in production
- **status:** kept as defence in depth (suggestMeal is a `tier: "pro"` tool; the tool loop refuses a free caller first); a comment says so.

### B5 — P3 — an incomplete stored pack: the snapshot says balanced while the tool caps
- **status:** accepted: the client applies the strategy only to a complete pack (3a's stated limit, which onboarding never produces), and the tool's note names the cap to the model in that case.

### B6 — P3 — = A1. Fixed.

### B7 — P3 — no shared vector for the normaliser
- **status:** fixed: `_shared/testdata/diet_strategy_vocabulary.json` (15 rows), read by `_shared/diet_strategies_test.ts` and `test/core/diet_strategy_vocabulary_test.dart`; non-string inputs asserted on both sides; mutant E5 (no `toLowerCase`) red.

### B8 — P3 — vegan keto instructions contradict each other
- **status:** fixed: the passage says to plan low_carb plant meals "and say their carbs will be above the keto target".

## Seat C

### C1 — P2 — no fixture at a cap
- **status:** fixed: rows at 6, 6.1, 25 and 26 g; the low carb test reads the filter value and the candidate count; mutant E4 (`lte` -> `lt`) red.

### C2 — P2 — the read-error test cannot see the filters
- **status:** fixed: it captures the food calls (no `carbs_std` / `category` filter) and needs a non-empty answer.

### C3 — P2 — no direct test of `normalizeDietStrategy` — fixed (B7).

### C4 — P2 — the switch-combination test's expectation used the code's own `.replace`
- **status:** fixed: the strategy-only case also checks the length difference and that three passage lines are gone and SECTION 7 continues; mutant E6 (the switch works only with the food-type switch) red.

### C5 — P3 — "a separate field, below" dangles when the passage is removed
- **status:** fixed: both copies now name the key ("a separate field, snapshot.profile.diet_strategy").

### C6 — P3 — untested paths and vacuous loops
- **status:** fixed: cuisine indian with a cap, pescatarian keto (fish in, chicken out), length preconditions on every filter loop. Accepted: no 600-row fixture for "the cap applies before the limit"; that order is PostgREST's (filters before `limit`), the fake applies filters first too, and the asset never fills the 500-row limit under a cap (363 rows at 6 g).

### C7 — P3 — `withEnv` deleted instead of restoring
- **status:** fixed.

## Mutations

All against the four Deno test files, each applied once (count checked) and restored: D1–D12 (the original list, re-pointed at the changed lines) and E1–E6 (above): 18 of 18 red.

## Addendum (2026-11-15): two findings from the Unit 3b-3 B-pass, fixed on this branch

The 3b-3 B-pass (`docs/reviews/diet-strategy-3b3-bpass.md`, seat A) found two server-side gaps in this landing. They are fixed here, not on 3b-3, so the `weekly-report` and `ai-proxy` deploys from the merged `main` (before the 3b-3 go) carry them.

| 3b-3 finding | Sev | Finding | Fix |
|---|---|---|---|
| A2 | P2 | `weekly-report` shows the week's average carbs with no target and knows nothing of the strategy, so the model may tell a Keto user to eat more carbs | `_shared/diet_strategies.ts` `weeklyReportDietStrategyLine(raw, isPro)`: a Low carb / Keto line under the protein target (do not grade carbs or fat, never push carbs; calories and protein unchanged), empty for Balanced, unreadable or no PRO; the profile read selects `diet_strategy` (always: a conditional select string defeats supabase-js row typing, and migration 179 is live); the line is off with `DISABLE_DIET_STRATEGY_MANUAL_RULES`. Inert until 3b-3 (the column is NULL for every live row). Tests: `_shared/diet_strategies_test.ts` (behaviour), `weekly-report/index_test.ts` (wiring, comment-stripped). Mutants M1–M8 (the line empty for keto, no PRO check, PRO forced, switch ignored, line dropped, column dropped, switch read removed, line moved): 8 of 8 red |
| A1 | P3 | the manual comment and `supabase/functions/CLAUDE.md` said only the chat snapshot carries `profile.diet_strategy`; the daily snapshot push carries it too | reworded in both and in the registry: both carry it, no prompt builder reads a stored snapshot |
| D1 (fix review) | P2 | the weekly-report pins run with `--no-check` on the source text, so a deleted import stayed green | a test pins both imports (comment-stripped); mutants (each import deleted) 2 of 2 red. Accepted: the pins match the exact text, so a `deno fmt` reflow turns them red with correct code (loud, not a false green) |
| D6 (fix review) | P3 | the new registry range 206-217 stopped mid-statement | 206-218 (through `.single()`) |

## Founder triage notes

Not needed: no P0/P1, no product decision; dispositions above.

## Tuning entry
- **2026-11-15** - blast-radius platform - 18 findings (3 duplicates across seats); 0 false_alarm; tuning: a filter that changes WHICH rows survive needs a ranking check on the real table, not only a "rows under the cap" check: seat B ported the handler and counted the top five (99 % protein powders under keto), which no fixture without a supplement row could show.
