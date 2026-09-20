---
branch: oi162-slice2-triggers
date: 2026-09-05
blast_radius: platform
review_rounds: 6
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/004af467034f-review.md
---

# Plan-review record — OI-162 slice 2, the three cap triggers (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `platform`, computed against the REAL migration file with content** — not against a
path. Slice 1's spec got that wrong and the §4.9 row it produced is why this one was written
first and classified second.

## Rounds

| Round | Verdict | Findings |
|---|---|---|
| 1 | NOT CONVERGED | 2 blocking, 5 major |
| 2 | NOT CONVERGED | 2 blocking, 5 major |
| 3 | NOT CONVERGED | 1 blocking, 2 major, 1 minor |
| 4 | NOT CONVERGED | 0 blocking, 1 major, 1 minor |
| 5 | NOT CONVERGED | 2 blocking, 1 minor |
| 6 | **CONVERGED** | 0 |

Every finding carries a written disposition in `docs/audit/oi162-slice2-plan.md` §9, one table
per round. Written down because slice 1's round-1 findings existed only in conversation, so a
later reviewer could not check the claim that they had been handled.

**Six rounds is more than §4.12.1's minimum of two, and the shape of the excess matters more
than the count.** §4.12.1 says that reviews which keep surfacing *new material issues* signal a
unit too large to review — split it. That is not what happened here:

- The slice's shape never changed across six rounds: three trigger bodies, one migration,
  server-side only.
- Design findings hit zero at round 4 and stayed there.
- Rounds 3 and 5 reopened items that were already understood. Round 3's blocker was a v3
  correction that REPLACED v2's fix instead of adding to it. Round 5's two blockers were not
  design defects at all — they were round-4 fixes written into the disposition table and never
  into the plan body, because a multi-edit script asserted before its single trailing write and
  silently discarded the earlier edits.

So the extra rounds measure the author's remediation quality, not the unit's size. Splitting
would have fixed nothing.

## What the review actually bought

Ranked by what would have shipped without it:

1. **A hard failure for every capped user.** Rounds 1-2 established that `consume_quota` is
   INVOKER-mode against an RLS-with-no-policy table, so any `authenticated` insert of a gated
   channel aborts with `42501` — the user's write fails, not merely their cap. Round 1
   reproduced it on a mirror table, and found the precondition is **live today**: the
   `ai_coach_interactions_insert_own` policy carries `with_check: auth.uid() = user_id` with no
   channel restriction. Accepted as self-limited, with the framing corrected; the alternative
   (restricting `channel` in the policy) is a catastrophic-tier RLS change and does not belong
   in a counter migration.
2. **Two parity tests that would have gone red on the merge.** `migration_cap_reader.dart`'s
   readers pin shapes migration 129 deletes.
3. **A latent bug in that same helper, unrelated to this slice.** Both readers matched over the
   WHOLE file, and migration 111 defines chat AND vision — so an unscoped read of 111 for vision
   returns the CHAT cap. Masked only because 114 and 127 happen to be single-function files.
   Now scoped to the function block.
4. **A guaranteed CI collision.** The behavioural test the spec first proposed would have driven
   the shared QA account's chat cap to exhaustion while `ai_proxy_test.dart` T15 asserts `200`
   for that same account, same job, same IST day.
5. **Behavioural coverage that already existed.** Withdrawing the QA-account test was right;
   withdrawing behavioural proof was not. `test/sql/oi46_daily_cap_triggers_live_verify.sql`
   already exercises these three triggers in a `BEGIN…ROLLBACK` with no Gemini cost — a §4.1.5
   miss on the exact trigger family. Extended rather than replaced.
6. **A verification command that could not see what it verified.** §1.4's writer grep was
   single-line, and these writers span two lines, so it silently dropped `ai-proxy:321/510/751`
   — the three gated writers that ARE the safety argument. 6 hits vs 14.

## Ground truth verified

Live `pg_get_functiondef` for all five functions; `pg_policies` on `ai_coach_interactions`;
`usage_counters` RLS state and row count; today's per-channel counts (chat 3, vision 0,
food_text 0); the live-definition chain 111 → 114 → 127; migration 129 as next free number;
`ai-proxy`'s three P0001 catch sites at `:338/:524/:765`; both client-side writers and all four
Edge Function writers; the seven stale citations in `supabase/functions/CLAUDE.md`.

## Mutation proofs (rule 21)

Six file-level, each confirmed APPLIED before its run — the third silently-unapplied mutation in
this repo's history was caught during this batch, when an anchor omitted a comment line and the
python assert's traceback was invisible behind a filtered grep.

| Mutation | Tests reddened |
|---|---|
| Vision ceiling reverted to `count(*)` over the pruned log | 4 |
| Chat P0001 base identifier renamed | 1 |
| Chat window re-anchored to bare UTC `date_trunc` | 1 |
| Vision short-circuit moved BELOW `consume_quota` | 1 |
| Two-line-shape gated writer added to `lib/` | 2 |
| Helper's post-129 `consume_quota` cap regex broken | 1 |

None was a compile error. Migration restored by `cp` from a pre-made copy and its sha256
re-verified (`1b0ffc94…`) — never `git checkout`, which rewrites CRLF and silently invalidates
the ledger hash while `git status` reads clean.

**Two more, run AFTER the apply:**

| Mutation | Tests reddened |
|---|---|
| Vision's shared budget split into a per-channel `quota_key`, live, inside `BEGIN…ROLLBACK` | 2 (both vision assertions) |
| A `const` holding a GATED channel added to `lib/` (indirection, post-B-pass hardening) | 2 |

The live one was mutated inside the harness's own transaction and rolled back; the function was
re-read afterwards to confirm restoration, and `usage_counters` was unchanged at 1 row / used=3.
Semantically wrong but valid SQL — deliberately not a compile error, per rule 21.

## B-pass

`docs/reviews/004af467034f-review.md` — **8 findings, 0 false alarms, all fixed in batch,
verdict accepted.**

⚠ **Two of the eight were P1 and neither was a code defect — both were MY OWN false verification
claims**, which is worth recording because the ×6 plan review did not catch either:

1. The diagnose-doc asserted migration 129 "carries the four-tag header". It carries two. The
   migration is applied and immutable, so the omission stands and the false claim was corrected
   instead. Discovered incidentally: **no gate checks those tags at all**, though
   `supabase/migrations/CLAUDE.md` states the pre-commit hook greps for them.
2. The plan claimed "zero stale live-definition citations remain" in `supabase/functions/CLAUDE.md`
   after step 4c. Its own published check returns 1. I had verified with a narrower private grep.

Both were caught by a context-blind reader running the command the document publishes rather than
trusting the sentence beside it. That is the cheapest reviewer behaviour there is, and it is the
one that found the two things six rounds of plan review missed.

The other six were real defects in guards this batch wrote to be careful — most notably a landmine
guard blind to `'channel': _channel` (a const) **in one of its own positive-control files**, and a
per-statement SQL exemption defeated three ways, now replaced by an enumerated allowlist.

