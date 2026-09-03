---
branch: techdebt-audit-sep02
date: 2026-09-03
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/db5584050b6b-review.md
---

# Plan-review record — tech-debt audit 2026-09-02, Slice A (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).
Platform-tier: the diff edits `supabase/functions/ai-proxy/index.ts` and
`supabase/functions/weekly-report/index.ts`, and those two files ALONE classify platform
(`git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart`). Not
catastrophic → no Hermes pass required.

## Scope

Two Edge Function fixes, both instances of *an unchecked or undelivered PostgREST result at a
gating decision*:

- **CODE-8 / diagnose `e4d1b7`** — `weekly-report`'s first-free-report gate read a count without
  destructuring `error`, so a failed query made `isFirstReport` true, the
  `!hasPro && !isFirstReport` gate did not fire, and a FREE user received an unbounded Gemini 2.5
  **Pro** report. Its sole writer also discarded its insert result, which would have held the count
  at 0 forever and left the gate permanently open.
- **CODE-6 / diagnose `f2b9d4`** — `ai-proxy`'s `checkPro()` lacked the
  `.order("end_date", {ascending:false}).limit(1)` its sibling query has, and there is no UNIQUE on
  `subscriptions(user_id)`, so two overlapping active rows (an ordinary renewal) made
  `maybeSingle()` synthesise PGRST116 and silently strip PRO from a paying customer. It also logged
  nothing, making the downgrade undiagnosable.

## Review rounds

**Round 1 (independent, context-blind)** — 3 BLOCKING, all verified against source and accepted:
1. CODE-7's root cause was wrong in the plan (its counter insert is malformed and has NEVER written
   a row — phantom columns plus an omitted NOT NULL). `await`-ing it would not have fixed it.
2. CODE-6 had a fixable cause the plan explicitly forbade fixing (the missing `.limit(1)`).
3. CODE-8's writer was unchecked too, in the same file.

**Round 2 (independent, context-blind, on the hardened plan)** — 4 BLOCKING, **three of them inside
round 1's own corrections**. The decisive one: correcting CODE-7's insert would introduce a NEW
channel value, and `rolling-context/index.ts:351` filters by `.neq("channel","app_event")` — a
denylist — so the rows would be embedded into `memory_embeddings` as conversation (reaching
ai-proxy's SYSTEM prompt) and then DELETED by the summarize cron, resetting the very counter the
rate limit reads. That reproduces the Hermes P1-E/P1-F incident of 2026-08-20 verbatim.

**Response — §4.12.1 SPLIT rather than a v4.** CODE-7 and the schema-gate extension (INFRA-14) were
moved out to **OI-162**, because CODE-7's blocker is the same complete `channel`-reader enumeration
that blocks OI-153. The slice was narrowed to CODE-6 + CODE-8, whose new boundary is mechanical
rather than thematic: *fixes that touch no channel vocabulary, no schema, and no new gate.*

**Confirmation round (independent, scoped to "is the narrowing sound?")** — verdict
`converged — safe to implement`, 1 blocking item: the plan BODY still instructed all four fixes
while its header said two had moved out. Fixed before any code was written.

## Ground truth verified

- Live prod (`dedsavbjuwgarrhphgnl`): `ai_coach_interactions` channel census — `weekly_report` is
  ABSENT, recorded as an OPEN question in `e4d1b7` tier 4 rather than assumed away.
- `backups/live_schema_columns.json`: all 8 insert columns present; the only NOT NULLs
  (`user_id`, `user_message`) are both supplied.
- No UNIQUE on `subscriptions(user_id)` — every migration grepped; only `razorpay_payment_id`.
- Full `bash scripts/pre-commit.sh` loop green (not a hand-picked subset — §4.12.5).
- **Mutation-proven (rule 21), three mutations applied ONE AT A TIME**, each confirmed to have
  landed via `grep -c` before running: restoring the pre-fix `isFirstReport` → 3 pass / 1 fail;
  restoring the discarded insert result → 3 pass / 1 fail; removing `.order().limit(1)` → 4 pass /
  1 fail. All restored → 9/9 green. The B-pass then independently mutated to the real pre-fix
  `HEAD` content of both files and measured 7 of 9 reddening.

## B-pass

`docs/reviews/db5584050b6b-review.md` — 3 findings, 0 P0, 0 false_alarm. Finding 1 (P1) fixed
in-batch: a `writers:` citation named a comment block in migration 052 rather than the two real
Edge Function writers, and no gate caught it because a prose `method:` makes
`check_sot_registry_parity` skip its symbol check. Finding 3 (P3) tracked as OI-161.

## `feature_flag` — platform's fourth requirement, addressed explicitly (B-pass Finding 2)

`docs/blast_radius.yaml:23-25` lists `feature_flag` among platform's `requires:`. This diff ships
none, and that is a deliberate judgment rather than an oversight:

**Both changes convert a fail-OPEN path to fail-CLOSED. A kill switch that reverts to the previous
behaviour would re-open the exact hole being closed** — it would restore "a failed count grants a
free user an unbounded Gemini 2.5 Pro report" and "a renewal silently strips PRO", on demand. A flag
whose OFF state is the vulnerability is not a safety mechanism; it is a second way to ship the bug.

The risk `feature_flag` exists to bound is *new behaviour misfiring on users*. Here the behavioural
delta is bounded and was proven, not asserted:
- `checkPro` is byte-identical for the 0-row and 1-row cases (`maybeSingle()` returns
  `{data:null,error:null}` for 0 rows either way); ONLY the ≥2-row case changes, and it changes from
  an error to picking the newest active row.
- The weekly-report gate's only new externally-visible outcome is a 403 `NOT_PRO` in a case that
  previously returned a report — the intended correction. Its one genuine cost, a PRO user denied
  when BOTH reads fail simultaneously, is stated in `e4d1b7`'s `impact_analysis` and is now
  attributable because both failures log.

Recorded here so a future auditor reads a decision rather than re-deriving an absence. This is NOT
a `tier: ship_dark_build` claim (§4.12.4) — that tier is for default-OFF flags and would require
exactly the kill switch argued against above; this record keeps the full `review_rounds: 2`.

## Not in this slice (terminal, not deferred)

- **OI-162** — the delete-account rate limit is inert in prod (its counter insert has never written
  a row) plus the schema gate's multi-line-map blind spot that hid it. Blocked on OI-153's
  channel-reader enumeration; shipping the obvious fix without it is the trap round 2 caught.
- **OI-153 / 154 / 155 / 156 / 157 / 158 / 159 / 160 / 161** — the remaining 80 audit findings, each
  with its evidence and its known traps.
- The audit's own `2026_09_02_audit_closures.yaml` is **not written yet**: Gate 40's closed==N
  invariant validates every closure file on every commit in the repo, so a half-filled ledger would
  block all work including the concurrent session's. It is written when the findings are terminal.
