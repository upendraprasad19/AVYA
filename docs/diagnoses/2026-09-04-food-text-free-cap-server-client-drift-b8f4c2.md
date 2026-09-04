---
bug_id: b8f4c2
date: 2026-09-04
batch: food-text-limit-parity
status: fixed
blast_radius: platform
symptom: >
  The free AI food-text daily cap was declared 10/day by the client and by
  docs/architecture/business-rules.md, but the Postgres trigger that actually
  enforces it allowed 50/day. Any caller reaching ai-proxy directly rather than
  through the app got 5x the intended free allowance. In-app users never saw it,
  because the client blocks at 10 before the request is ever made — which is
  precisely why it survived four months undetected.
concept: food_text_analysis_daily_cap
sot_registry_entry: food_text_analysis_daily_cap
writers:
  - { file: supabase/migrations/127_food_text_free_cap_parity_10.sql, line: 65, method: enforce_food_text_daily_limit daily_cap assignment (live definition, FREE arm now 10) }
  - { file: supabase/migrations/113_fix_food_text_trigger_ist_boundary.sql, line: 38, method: prior definition — the drifted FREE arm of 50 that this migration replaces }
readers:
  - { file: lib/core/constants/app_constants.dart, line: 78, method: freeAiTextLogsPerDay — the client constant, always 10 }
  - { file: lib/core/services/usage_counter_service.dart, line: 127, method: _limit — returns 999999 for PRO, the client constant for free }
  - { file: lib/features/nutrition/widgets/food_logger_section.dart, line: 107, method: build — Log Food tab meter }
  - { file: lib/features/profile/screens/profile/subscription_section.dart, line: 174, method: build — free-tier rate-limit meter }
  - { file: supabase/functions/ai-proxy/index.ts, line: 84, method: FOOD_TEXT_FREE_DAILY_CAP — display-only, renders the 429 body; was an inline literal reporting 50 until the B-pass }
hive_key_prefix: "n/a — the counter is a row count on ai_coach_interactions, not a Hive key"
hive_key_formula: "n/a — no Hive surface for this concept"
sync_methods: []
restore_methods: []
cloud_table: ai_coach_interactions
cloud_columns: [user_id, channel, user_message, ai_response, model_used, tokens_used, created_at]
contract_test_path: test/contracts/ai_message_limit_parity_test.dart
ist_handling:
  - { file: supabase/migrations/127_food_text_free_cap_parity_10.sql, line: 74, method: IST day boundary carried VERBATIM from migration 113 — the fix for 7ad0d3; not re-derived }
provider_invalidations: "none — no client state changes; the client constant and every widget reading it are untouched"
telemetry_op_types: "none added — the trigger raises P0001 and ai-proxy already maps it to a 429 with a user-facing message"
cross_account_guard: "n/a — the trigger scopes its count by NEW.user_id, so one user's rows can never affect another's cap"
forbidden_patterns_checked: >
  No deferral euphemism. No Container(color:+decoration:). No client-side API
  key. No new SECURITY DEFINER function. No RLS relaxation. No new cloud column
  (so backups/live_schema_columns.json needs no regeneration). No inline isPro
  check added — the PRO branch stays inside the trigger where it already lived.
proposed_fix: >
  Migration 127 CREATE OR REPLACEs enforce_food_text_daily_limit with the FREE
  arm lowered 50 -> 10. PRO stays 200 (founder decision). Every other line of
  the function, including the IST day boundary, is byte-identical to migration
  113. The ai-proxy routing docstring is corrected from "50/day free" to
  "10/day free". The parity regression test is widened from the chat cap alone
  to cover food text and the vision ceiling.
regression_test_planned: >
  test/contracts/ai_message_limit_parity_test.dart — widened from 2 tests to 4.
  New: (1) client freeAiTextLogsPerDay must equal the trigger's FREE arm, with
  PRO pinned at 200 so the deliberate divergence stays a decision; (2) the
  vision ceiling must be >= proScanMealPerDay + proCartAuditorPerDay, so adding
  a third vision channel reddens the suite until the ceiling is raised. Caps are
  resolved from the HIGHEST-numbered migration defining each function, because
  CREATE OR REPLACE means only the last definition is live.
impact_analysis: >
  No user loses access they have today. All three client read sites block at 10,
  so no in-app user can reach an 11th food-text log; the change closes a
  direct-API bypass rather than removing a capability. Live prod exposure was
  low (the free tier has almost no traffic at pre-launch), but the bypass was
  real and unbounded per day. PRO is untouched at 200/day. Rollback is migration
  113's body, included commented at the foot of 127.
touched_layers_checked:
  - { tier: 1, name: Client code, status: verified, evidence: "no client file changed; freeAiTextLogsPerDay was already 10 and is now the pinned side of the contract" }
  - { tier: 2, name: Hive, status: not_applicable, evidence: "the cap is a cloud row count; no Hive key participates" }
  - { tier: 3, name: Postgres schema, status: fixed_in_this_batch, evidence: "migration 127 CREATE OR REPLACE on enforce_food_text_daily_limit; no table or column changed, so live_schema_columns.json is unaffected" }
  - { tier: 4, name: Postgres data, status: not_applicable, evidence: "no rows read or written by the migration; only future daily_count evaluation changes" }
  - { tier: 5, name: Migrations applied, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json updated in this same commit, paired with the live apply per 4.5" }
  - { tier: 6, name: Edge Function code vs deploy, status: verified, evidence: "the only ai-proxy change is a routing-table docstring line; zero runtime effect, so no redeploy is required for correctness and the next deploy carries it" }
  - { tier: 7, name: Cron jobs, status: not_applicable, evidence: "no cron touches this trigger" }
  - { tier: 8, name: RLS policies, status: not_applicable, evidence: "trigger functions fire regardless of role EXECUTE grants; no policy changed" }
  - { tier: 9, name: Storage, status: not_applicable, evidence: "no storage surface" }
  - { tier: 10, name: Secrets, status: not_applicable, evidence: "no secret read or rotated" }
  - { tier: 11, name: External services, status: not_applicable, evidence: "Gemini call volume drops slightly for direct-API callers; no dashboard config changes" }
  - { tier: 12, name: Client to server contract, status: fixed_in_this_batch, evidence: "the contract IS the defect — client 10 vs server 50 is now 10 vs 10, pinned by the widened parity test" }
related_bugs: [f1a70c, 7ad0d3, c9e3b1]
recurrence: >
  Third instance of client-server limit drift on this codebase. f1a70c
  (2026-06-07) is the direct precedent: the client declared the free AI-coach
  cap as 15/day while ai-proxy enforced 10, so free users saw headroom then got
  429'd at message 11. Its fix shipped this very test file to pin client ==
  server — but pinned the CHAT pair only. Food text then drifted the same way in
  the opposite direction and stayed invisible for four months. The lesson is not
  "pin this number"; it is that a parity fix must pin EVERY pair of the class,
  and the test file must be the one obvious home so a new limit has nowhere else
  to go. 7ad0d3 is the sibling class on the same trigger family (UTC vs IST
  boundaries); c9e3b1 is the read-then-write race on the client-side counter.
---

# b8f4c2 — the free food-text cap said 10 in three places and 50 in the one that enforces it

## What was actually wrong

Several sources of truth describe the free food-text daily limit. These said 10:

- `lib/core/constants/app_constants.dart:78` — `freeAiTextLogsPerDay = 10`
- `docs/architecture/business-rules.md:17` — the FREE-tier row, "AI food text analysis — 10 text logs/day"
- the UI meters at `food_logger_section.dart:107` and `subscription_section.dart:174`

One said 50, and it was the only one that enforces anything:
`enforce_food_text_daily_limit`, whose live definition at the time was migration
113 (`daily_cap := CASE WHEN is_pro THEN 200 ELSE 50 END`).

⚠ **Corrected by the B-pass:** an earlier version of this doc cited
`business-rules.md:17` **and `:36`** as two confirmations of the free value.
Line 36 is in the **PRO** section, not the free one — so it was never evidence
for the free cap, and it was independently WRONG, documenting PRO at 10/day when
PRO is unlimited client-side with a 200/day server ceiling. Counting it as
corroboration is the input-set error this batch is about, committed inside the
writeup of that error. `:36` now reads "unlimited (server-side abuse ceiling
200/day)".

The client blocks at 10 before a request is made, so no in-app user could ever
observe the gap. It was reachable only by calling the Edge Function directly —
which is exactly the population a server-side cap exists to stop.

## Why it survived

`f1a70c` fixed this identical class in June and shipped
`test/contracts/ai_message_limit_parity_test.dart` so it "could not drift
again". That test pins one pair: `freeAiMessagesPerDay` against ai-proxy's
`FREE_DAILY_LIMIT`. Food text has the same shape and was never added.

The nominal coverage looked better than it was.
`test/contracts/food_text_analysis_daily_cap_test.dart` was titled
*"Source-grep contract for food_text_analysis 50/200/day server cap"* and
asserted **neither 50 nor 200** — only that a migration file exists and that
ai-proxy contains two strings. Lowering the cap to 10 left it green. A title
that claims more than its assertions deliver is worse than no test, because it
answers "is this covered?" wrongly. Its header now says what it actually does
and points at the parity test for values.

## The trap this batch walked into first

While planning, migration 111's vision cap (15) was read from source, reported
to the founder as a correction to an earlier claim of 20 — and was wrong.
Migration 114 had `CREATE OR REPLACE`d that function three weeks earlier and set
the cap to 20. **A migrations directory is append-only; the last definition
wins.** Reading one migration and citing its body is not verification, it is
sampling.

That is why the widened test resolves each cap through
`latestMigrationDefining()` — the highest-numbered migration that defines the
function — rather than a fixed path. The mistake is now structurally impossible
in this test.

## Mutation evidence (rule 21)

Four mutations, applied one at a time, each confirmed to have landed with
`grep -c` before running, all restored afterwards (7/7 green at rest).

⚠ The whole set was RE-RUN after the helpers were extracted into
`test/helpers/migration_cap_reader.dart` — an earlier round proved the inline
version, and moving code invalidates the proof it carried. The re-run changed
one result, which is the point of re-running.

| Mutation | Confirmed applied | Result |
|---|---|---|
| Migration 127 FREE arm reverted 10 -> 50 (the exact pre-fix defect) | live-`ELSE 50` 1, live-`ELSE 10` 0 | **1 red** |
| Resolver `defs.last` -> `defs.first` | `defs.first` 1, `defs.last` 0 | **3 red** |
| `stripSqlComments` removed from the RESOLVER's `contains` | resolver call sites 1 -> 0 | **0 red — see below** |
| `stripSqlComments` removed from the CAP READERS | stripped body reads 2 -> 0 | **1 red** |

The second mutation reproduced this batch's own planning error verbatim: taking
the first migration yielded `Vision ceiling (10, 111_chat_vision_daily_cap_triggers.sql)`
— 10, not 15, because migration 111 defines BOTH cap functions and the chat cap
matches the regex first. A stale citation does not merely give you an old
number; it can hand you a number from an unrelated feature.

**The third mutation did not redden anything, and that is recorded rather than
hidden.** Comment-stripping inside the resolver's `contains('FUNCTION …')` test
is defensive only: today every migration that mentions one of these functions
also genuinely defines it, so stripping changes nothing. It guards a future
migration that merely *references* the function in prose — which would
otherwise be selected as the latest "definition" and then fail to parse. Real
protection, not currently exercised. Claiming a mutation-proof for it would
have been false.

The fourth is where stripping actually earns its place, and it was not the use
originally expected. Migration 127's own `Rollback strategy:` header quotes the
previous value (`ELSE 50`) at line 32, **above** the live `ELSE 10` at line 65
— so an unstripped `firstMatch` reads the rollback prose as the live cap.
Documenting the old value in a header makes the file self-trapping for any
naive grep.

## What the B-pass found — the first fix was the INSTANCE, not the class

The context-blind B-pass (`docs/reviews/9b3e688d-review.md`) reproduced all four
mutation results exactly and confirmed live prod state, then found **8 findings,
every one of them the same shape: the number was corrected where it is enforced
and left stale everywhere it is REPORTED or DOCUMENTED.**

- **P1 — `ai-proxy/index.ts` rendered the 429 body from an inline
  `isProUser ? 200 : 50`.** So after the trigger began enforcing 10, the error
  text still told callers "50/day" — misinforming *precisely* the direct-API
  population this cap exists to constrain, and doing it in the one message they
  actually see. Fixed by naming `FOOD_TEXT_FREE_DAILY_CAP` /
  `FOOD_TEXT_PRO_DAILY_CAP` (mirroring `FREE_DAILY_LIMIT`, which f1a70c already
  named and pinned for the chat cap) and pinning both to the live trigger arms.
- **P1 — two auto-loaded nested `CLAUDE.md` files still said "50/day free".**
  `supabase/functions/CLAUDE.md` and `lib/features/nutrition/CLAUDE.md` load into
  every future session working in those subtrees, so the stale number would have
  been fed back as authoritative context indefinitely. The reviewer noticed
  because they were injected into its own context during the review.
- **P2 ×2 —** a second stale comment 90 lines below the one that was fixed, and
  the `business-rules.md:36` citation error described above.
- **P3 ×3 —** this migration's header called itself the "FOURTH definition" when
  there are three (026 / 113 / 127); the vision test's "now it fires
  automatically" framing overstated what two hardcoded constant names can do;
  and `docs/architecture/{ai,functionality-flow}.md` both still said 50.

**Why the original grep missed all of it, stated plainly because it is the
fourth instance in one session:** the pre-commit check was
`grep -rn "50/day free\|200/day PRO\|50/day" test/ scripts/` — scoped to two
directories, on a repo-wide constant. It returned zero hits and was read as
"nothing else references this". The same defect that produced the bug produced
the incomplete fix, and only a reviewer with a different input set found it.

Every one of the eight is fixed in this batch. Two further mutations were run on
the new ai-proxy assertion, each confirmed applied first: setting
`FOOD_TEXT_FREE_DAILY_CAP = 50` reddens 1 test, and restoring the literal
`isProUser ? 200 : 50` reddens 1 test.

## What was deliberately NOT changed

- **PRO stays 200/day.** The client returns `999999` ("unlimited"). Founder
  decision 2026-09-04: 200 food logs in one IST day is an abuse ceiling, not a
  product limit. Pinned by the test so it stays a decision rather than becoming
  the next drift.
- **The vision ceiling stays 20.** PRO's advertised 10 + 10 lands exactly on it
  and free (3 + 1) is nowhere near. The gap was never the number — it was that
  raising it when a third channel is added lived only in intent. The new
  assertion is that trigger.
- **`ai-proxy` is not redeployed for this.** Its only change is one docstring
  line in the routing table; zero runtime effect.
