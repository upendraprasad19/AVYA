---
branch: ai-table-truth
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/ai-table-truth-bpass.md
blast_radius: platform
open_issues: none-affected
date: 2026-07-28
---

# Plan review — `ai-table-truth`

Docs-only correction of the AI-architecture table in `supabase/functions/CLAUDE.md`
plus its propagated copy in `lib/features/nutrition/CLAUDE.md`. Platform tier because
`CLAUDE.md` is a platform-tier path in `docs/blast_radius.yaml` — not because the
change carries runtime risk. It touches no code, schema, Edge Function or workflow.

Two independent context-blind rounds ran (Haiku), each given only the files and told to
assume the change was wrong and report mismatches against source. **Both returned
material findings, and both findings were in my own work.** That is the reason this
record can honestly claim two rounds: they were real, and they changed the diff.

## Round 1 — refuted the correction's headline claim

The first commit (`a5b5eb00`) asserted:

> "There are only THREE LLM-calling Edge Functions … Everything else in
> `supabase/functions/` reaches no model."

**False.** Fifteen functions call `geminiChat`/`generateContent`. The sentence sat in
the exact paragraph written to stop a reader under-counting which functions touch a
model, so the fix reproduced — one level up — the defect it was fixing. Compounding it:
those 15 are precisely the set the OI-47 sanitiser had to cover, a list already derived
earlier in the same session. It was written from memory rather than re-derived.

Round 1's other 8 checks returned clean (model constants, call-site line numbers, the
`type` routing table, the 15/day caps, `weekly-recap-ready` having no LLM).

## Round 2 — run on the hardened text, caught two more

Per §4.12, round 2 reviews the POST-round-1 state because corrections introduce their
own defects. It found:

1. The replacement text said "twelve of the cron jobs in role 3" while pointing at a
   list that did not contain all twelve.
2. Role 3 listed `streak-guardian-daily`, `rolling-context-nightly` and
   `promote-community-item-daily` as function slugs. Those are pg_cron **job** names;
   the functions are `streak-guardian`, `rolling-context`, `promote-community-item`
   (`docs/operations/CRON_REGISTRY.md:26,38,39`).

While fixing (1) I first mis-filed `assess-body-composition`, `daily-snapshot` and
`future-prediction` as cron-dispatched. They carry no cron-auth gate and are
`verify_jwt=true`. Caught by checking the gate per function before the edit landed —
the third error of the same class in one change.

## Ground truth

Every claim in the final text was verified against source, not against prose:

- The 15-function set: `grep 'geminiChat|generateContent'` across all 41
  `supabase/functions/*/index.ts`.
- The 3 / 3 / 9 split: presence or absence of `isAuthorizedCronCall` per function — all
  9 cron functions have it, the other 6 have none.
- Model constants resolve in `_shared/gemini.ts:40-42`.
- Client call sites confirmed at `nutrition_provider.dart:733 / :1356 / :1445`.
- Function existence cross-checked against `list_edge_functions` on
  `dedsavbjuwgarrhphgnl`.

## Convergence

Converged. Round 2's findings were mechanical (a stale count, a name-class mix-up),
not a redesign, and the follow-on self-consistency B-pass found one further stale count
and nothing else. The unit is two markdown files; there is no smaller shippable piece
to split out per §4.12.1.

## Why the fix is the instruction, not the list

The corrected list is a snapshot and will rot the same way. The durable change is the
line telling the next reader to **derive this by grep, never maintain it by hand** —
because the table has now been wrong twice, both times from a hand-written list.
